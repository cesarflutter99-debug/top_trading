// pending_actions_queue.dart
//
// Cola de acciones que requieren red pero el usuario disparó offline.
// Persistida en SharedPreferences (JSON) -- sobrevive a que se cierre
// la app. Al recuperar conexión (ConnectivityService) se procesa
// sola. IMPORTANTE: nunca se aplican reglas de negocio (puntos,
// comisiones, límites de plan, stock) en el cliente -- solo se
// reintenta la llamada real contra Supabase; el server sigue siendo
// la única fuente de verdad. Si algo ya no aplica (pedido vencido,
// tienda borrada, etc.) se avisa con una notificación local, nunca se
// reintenta indefinidamente.
//
// EXCLUSIÓN DELIBERADA (2026-08): "Verificar Pago" / cambio de plan
// pago (ModalPagoPlan) NUNCA pasa por esta cola. Esa acción necesita
// validar el código de afiliado en vivo y abrir WhatsApp con el
// usuario presente y con el número de contacto actualizado -- encolarla
// significaría disparar WhatsApp solo, minutos u horas después al
// reconectar, sin el usuario esperándolo. modal_pago_plan.dart bloquea
// esa acción con un diálogo si no hay conexión, en vez de encolarla.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tiendas_service.dart';
import 'storage_service.dart';
import 'tienda_state_service.dart';
import 'afiliado_state_service.dart';
import 'notificaciones_service.dart';

class AccionPendiente {
  final String id;
  final String tipo;
  final Map<String, dynamic> datos;
  final DateTime creadaEn;

  AccionPendiente({
    required this.id,
    required this.tipo,
    required this.datos,
    required this.creadaEn,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'tipo': tipo,
        'datos': datos,
        'creadaEn': creadaEn.toIso8601String(),
      };

  factory AccionPendiente.fromJson(Map<String, dynamic> j) => AccionPendiente(
        id: j['id'] as String,
        tipo: j['tipo'] as String,
        datos: Map<String, dynamic>.from(j['datos'] as Map),
        creadaEn: DateTime.parse(j['creadaEn'] as String),
      );
}

class PendingActionsQueue extends ChangeNotifier {
  PendingActionsQueue._();
  static final instance = PendingActionsQueue._();

  static const _clave = 'cola_pendiente_v1';
  final _tiendasService = TiendasService();
  final _storageService = StorageService();

  final List<AccionPendiente> _cola = [];
  bool _procesando = false;

  List<AccionPendiente> get pendientes => List.unmodifiable(_cola);
  int get cantidad => _cola.length;

  bool tienePendiente(String tipo, String Function(Map) matchKey, String key) {
    return _cola.any((a) => a.tipo == tipo && matchKey(a.datos) == key);
  }

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_clave);
    if (raw == null) return;
    try {
      final lista = jsonDecode(raw) as List;
      _cola
        ..clear()
        ..addAll(lista.map((e) => AccionPendiente.fromJson(e)));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _guardar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _clave, jsonEncode(_cola.map((a) => a.toJson()).toList()));
  }

  Future<void> encolar(String tipo, Map<String, dynamic> datos) async {
    _cola.add(AccionPendiente(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      tipo: tipo,
      datos: datos,
      creadaEn: DateTime.now(),
    ));
    await _guardar();
    notifyListeners();
  }

  Future<void> procesarCola() async {
    if (_procesando || _cola.isEmpty) return;
    _procesando = true;
    for (final accion in List<AccionPendiente>.from(_cola)) {
      try {
        await _ejecutar(accion);
        _cola.remove(accion);
      } catch (e) {
        // Fallo real (no de red): reintentar no lo arreglaría --
        // se saca de la cola y se avisa.
        _cola.remove(accion);
        NotificacionesService.instance.agregarLocal(
          titulo: 'No se pudo completar una acción pendiente',
          mensaje: _mensajeError(accion, e),
        );
      }
      await _guardar();
      notifyListeners();
    }
    _procesando = false;
  }

  String _mensajeError(AccionPendiente a, Object e) {
    final base = switch (a.tipo) {
      'marcar_vendido' => 'No se pudo confirmar el pedido',
      'rechazar_pedido' => 'No se pudo rechazar el pedido',
      'crear_producto' =>
        'No se pudo publicar el producto "${a.datos['nombre']}"',
      'editar_tienda' => 'No se pudieron guardar los cambios de tu tienda',
      'solicitar_retiro' => 'No se pudo enviar tu solicitud de retiro',
      _ => 'No se pudo completar una acción',
    };
    return '$base. ${e.toString().replaceFirst('Exception: ', '')}';
  }

  Future<void> _ejecutar(AccionPendiente a) async {
    final d = a.datos;
    switch (a.tipo) {
      case 'marcar_vendido':
        await _tiendasService.marcarPedidoCompletado(d['idPedido'] as String);
        NotificacionesService.instance.agregarLocal(
          titulo: 'Venta confirmada ✅',
          mensaje:
              'El pedido #${d['numeroPedido'] ?? ''} ya quedó marcado como vendido.',
        );
        break;

      case 'rechazar_pedido':
        await _tiendasService.cancelarPedidoComoVendedor(
            d['idPedido'] as String,
            motivo: d['motivo'] as String?);
        NotificacionesService.instance.agregarLocal(
          titulo: 'Pedido rechazado',
          mensaje:
              'El pedido #${d['numeroPedido'] ?? ''} se rechazó y el stock se devolvió.',
        );
        break;

      case 'crear_producto':
        Future<String?> subir(String? path) async {
          if (path == null || !File(path).existsSync()) return null;
          return _storageService.subirFotoProducto(
              archivo: File(path), idTienda: d['idTienda'] as String);
        }

        final url = await subir(d['fotoPath'] as String?) ?? '';
        final url2 = await subir(d['fotoPath2'] as String?);
        final url3 = await subir(d['fotoPath3'] as String?);

        await _tiendasService.crearProducto(
          idTienda: d['idTienda'] as String,
          nombre: d['nombre'] as String,
          precioUsd: (d['precioUsd'] as num).toDouble(),
          imagenUrl: url,
          imagenUrl2: url2,
          imagenUrl3: url3,
          descripcion: d['descripcion'] as String?,
          cantidadDisponible: (d['cantidadDisponible'] as num?)?.toInt() ?? 1,
          categoria: d['categoria'] as String?,
        );
        NotificacionesService.instance.agregarLocal(
          titulo: 'Producto publicado ✅',
          mensaje: '"${d['nombre']}" ya está publicado en tu tienda.',
        );
        break;

      case 'editar_tienda':
        await _tiendasService.actualizarTienda(
          idTienda: d['idTienda'] as String,
          nombre: d['nombre'] as String,
          telefonoWhatsapp: d['telefonoWhatsapp'] as String,
          provincia: d['provincia'] as String,
          municipio: d['municipio'] as String,
          descripcion: d['descripcion'] as String?,
          categoria: d['categoria'] as String?,
        );
        await TiendaStateService.instance.refrescar();
        NotificacionesService.instance.agregarLocal(
          titulo: 'Tienda actualizada ✅',
          mensaje: 'Los datos de tu tienda ya se guardaron.',
        );
        break;

      case 'solicitar_retiro':
        await _tiendasService.solicitarRetiro(
          idAfiliado: d['idAfiliado'] as String,
          montoCup: (d['montoCup'] as num).toDouble(),
        );
        await AfiliadoStateService.instance.refrescar();
        NotificacionesService.instance.agregarLocal(
          titulo: 'Retiro solicitado ✅',
          mensaje: 'Tu solicitud de retiro ya se envió.',
        );
        break;
    }
  }
}
