// detalle_pedido_screen.dart
//
// Pantalla de detalle de un pedido con estilo FACTURA / recibo digital.
// Reemplaza al modal mostrarDetallePedido() en "Mis Pedidos" (comprador)
// y "Gestionar Ventas" (vendedor). Los dashboards siguen usando el modal
// viejo de analytics_widgets.dart, que no se toca.
//
// Uso:
//   Navigator.of(context).push(MaterialPageRoute(
//     builder: (_) => DetallePedidoScreen(pedido: p, esVendedor: false),
//   ));
//   // Devuelve true si el vendedor completó o rechazó el pedido
//   // (el llamador debe recargar su lista).
//
// DATOS QUE USA (columnas de `pedidos` que la app ya lee/escribe):
//   id_pedido, numero_pedido, id_tienda, id_comprador, detalle (jsonb),
//   total_usd, estado, creado_en, fecha_completado.
//
// DATOS OPCIONALES (si existen en el mapa del pedido se muestran, si no
// se omiten -- se leen de forma defensiva porque no se ve el SQL):
//   cancelado_en | fecha_cancelado, cancelado_por, motivo_cancelacion | motivo,
//   comprador_nombre, comprador_email, comprador_avatar (solo vista vendedor).
//
// REGLAS DE LA APP QUE RESPETA:
//   - El comprador NO puede cancelar ni editar (ver mis_pedidos_screen.dart):
//     solo existe la autocancelación a las 72 h.
//   - El vendedor puede "Rechazar" (fn_cancelar_pedido) o marcar "Vendido".
//   - Los precios se guardan en USD; el CUP es solo visual (CurrencyService).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/currency_service.dart';
import '../services/tiendas_service.dart';

enum _EstadoPedido { pendiente, completado, cancelado, otro }

_EstadoPedido _normalizarEstado(String? e) {
  switch (e) {
    case 'pendiente':
    case 'pending':
      return _EstadoPedido.pendiente;
    case 'completado':
      return _EstadoPedido.completado;
    case 'cancelado':
      return _EstadoPedido.cancelado;
    default:
      return _EstadoPedido.otro;
  }
}

const _kMeses = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
];

/// "12 abr 2025, 10:24 a. m." (hora local). Vacío si no hay fecha válida.
String _fmtFecha(dynamic iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso.toString())?.toLocal();
  if (d == null) return '';
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'a. m.' : 'p. m.';
  final min = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${_kMeses[d.month - 1]} ${d.year}, $h12:$min $ampm';
}

class _Extras {
  final Map<String, dynamic>? tienda;
  final Map<String, String> imagenes; // id_producto -> imagen_url
  final Map<String, dynamic>? valoracion;
  const _Extras({this.tienda, this.imagenes = const {}, this.valoracion});
}

class DetallePedidoScreen extends StatefulWidget {
  final Map<String, dynamic> pedido;

  /// true cuando lo abre el dueño de la tienda (Gestionar Ventas).
  final bool esVendedor;

  const DetallePedidoScreen({
    super.key,
    required this.pedido,
    this.esVendedor = false,
  });

  @override
  State<DetallePedidoScreen> createState() => _DetallePedidoScreenState();
}

class _DetallePedidoScreenState extends State<DetallePedidoScreen> {
  final _tiendasService = TiendasService();
  late Future<_Extras> _extras;
  Timer? _tick;
  bool _procesando = false;

  Map<String, dynamic> get _p => widget.pedido;
  _EstadoPedido get _estado => _normalizarEstado(_p['estado'] as String?);
  String get _idPedido => _p['id_pedido'].toString();
  String get _numero => '${_p['numero_pedido'] ?? ''}';
  double get _totalUsd => (_p['total_usd'] as num?)?.toDouble() ?? 0;

  List<Map<String, dynamic>> get _items {
    final raw = _p['detalle'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _extras = _cargarExtras();
    // Cuenta regresiva: refresca cada minuto.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<_Extras> _cargarExtras() async {
    final idTienda = _p['id_tienda']?.toString();

    Map<String, dynamic>? tienda;
    if (idTienda != null) {
      try {
        tienda = await _tiendasService.obtenerTiendaPorId(idTienda);
      } catch (_) {}
    }
    if (tienda == null && _p['tiendas'] is Map) {
      tienda = Map<String, dynamic>.from(_p['tiendas'] as Map);
    }

    // El `detalle` no guarda la foto del producto: se consulta aparte.
    final imagenes = <String, String>{};
    final ids = _items.map((i) => i['id_producto']).whereType<String>().toList();
    if (ids.isNotEmpty) {
      try {
        final res = await supabase
            .from('productos')
            .select('id_producto, imagen_url')
            .inFilter('id_producto', ids);
        for (final r in (res as List)) {
          final url = r['imagen_url'] as String?;
          if (url != null && url.isNotEmpty) {
            imagenes[r['id_producto'] as String] = url;
          }
        }
      } catch (_) {}
    }

    Map<String, dynamic>? valoracion;
    if (!widget.esVendedor && _estado == _EstadoPedido.completado) {
      try {
        valoracion = await _tiendasService.obtenerValoracionDePedido(_idPedido);
      } catch (_) {}
    }

    return _Extras(tienda: tienda, imagenes: imagenes, valoracion: valoracion);
  }

  // ------------------------------------------------------------------
  // Colores adaptativos (mismo patrón que mi_perfil_screen.dart)
  // ------------------------------------------------------------------
  bool get _oscuro => Theme.of(context).brightness == Brightness.dark;
  Color get _texto => _oscuro ? const Color(0xFFF5F5F4) : AppColors.ink;
  Color get _textoSec =>
      _oscuro ? AppColors.inkSecundarioDark : AppColors.inkSecundarioLight;
  Color get _superficie => _oscuro
      ? AppColors.cardTransparentDark
      : AppColors.cardTransparentLight;
  Color get _borde =>
      (_oscuro ? AppColors.borderDark : AppColors.borderLight).withOpacity(0.6);

  Color _colorEstado(_EstadoPedido e) {
    switch (e) {
      case _EstadoPedido.pendiente:
        return const Color(0xFFFF9500);
      case _EstadoPedido.completado:
        return AppColors.success;
      case _EstadoPedido.cancelado:
        return const Color(0xFFFF3B30);
      case _EstadoPedido.otro:
        return AppColors.inkSecundarioLight;
    }
  }

  String _textoEstado(_EstadoPedido e) {
    switch (e) {
      case _EstadoPedido.pendiente:
        return 'Pendiente';
      case _EstadoPedido.completado:
        return 'Completado';
      case _EstadoPedido.cancelado:
        return 'Cancelado';
      case _EstadoPedido.otro:
        return '${_p['estado'] ?? ''}';
    }
  }

  IconData _iconoEstado(_EstadoPedido e) {
    switch (e) {
      case _EstadoPedido.pendiente:
        return Icons.schedule_rounded;
      case _EstadoPedido.completado:
        return Icons.check_circle_rounded;
      case _EstadoPedido.cancelado:
        return Icons.cancel_rounded;
      case _EstadoPedido.otro:
        return Icons.help_outline_rounded;
    }
  }

  // ------------------------------------------------------------------
  // Moneda: USD o CUP según el toggle global (CurrencyService)
  // ------------------------------------------------------------------
  String _money(double usd) {
    final cs = CurrencyService.instance;
    if (cs.moneda == Moneda.usd) return '\$${usd.toStringAsFixed(2)}';
    return '${(usd * (cs.tasa ?? 320)).toStringAsFixed(0)} CUP';
  }

  Duration? get _restante {
    if (_estado != _EstadoPedido.pendiente) return null;
    final creado = DateTime.tryParse('${_p['creado_en']}');
    if (creado == null) return null;
    final limite = creado.toLocal().add(const Duration(hours: 72));
    final r = limite.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  String _fmtRestante(Duration d) {
    if (d.inMinutes <= 0) return 'Por vencer';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}min restantes' : '${m}min restantes';
  }

  // ------------------------------------------------------------------
  // Acciones
  // ------------------------------------------------------------------
  void _compartir(Map<String, dynamic>? tienda) {
    final nombre = (tienda?['nombre'] as String?)?.trim();
    Share.share('Pedido #$_numero'
        '${nombre != null && nombre.isNotEmpty ? ' en $nombre' : ''} · '
        'Total \$${_totalUsd.toStringAsFixed(2)} USD');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _abrirWhatsapp(Map<String, dynamic>? tienda) async {
    final tel = (tienda?['telefono_whatsapp'] as String?)
        ?.replaceAll(RegExp(r'[^\d]'), '');
    if (tel == null || tel.isEmpty) {
      _snack('Esta tienda no tiene WhatsApp configurado');
      return;
    }
    final msg = Uri.encodeComponent('Hola, te escribo por mi pedido #$_numero.');
    try {
      await launchUrl(Uri.parse('https://wa.me/$tel?text=$msg'),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _snack('No se pudo abrir WhatsApp');
    }
  }

  Future<void> _comoLlegar(Map<String, dynamic>? tienda) async {
    final lat = (tienda?['latitud'] as num?)?.toDouble();
    final lon = (tienda?['longitud'] as num?)?.toDouble();
    if (lat == null || lon == null) {
      _snack('Esta tienda no tiene ubicación registrada');
      return;
    }
    await launchUrl(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _marcarVendido() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar venta'),
        content: const Text(
          '¿Confirmas que este pedido fue entregado y pagado? '
          'Se sumarán +15 puntos a tu tienda.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _procesando = true);
    try {
      final bajoStock = await _tiendasService.marcarPedidoCompletado(_idPedido);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Venta confirmada ✅ +15 puntos')),
      );
      if (bajoStock.isNotEmpty) {
        final nombres = bajoStock
            .map((p) => '${p['nombre']} (${p['cantidad_disponible']})')
            .join(', ');
        messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.red.shade600,
          content: Text('⚠️ Stock bajo: $nombres'),
          duration: const Duration(seconds: 4),
        ));
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _procesando = false);
        _snack('Error: $e');
      }
    }
  }

  Future<void> _rechazar() async {
    final motivoCtrl = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Rechazar pedido #$_numero?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'El stock reservado se devolverá automáticamente y se '
              'notificará al comprador.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Volver')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rechazar pedido'),
          ),
        ],
      ),
    );
    final motivo = motivoCtrl.text.trim();
    motivoCtrl.dispose();
    if (confirmar != true || !mounted) return;

    setState(() => _procesando = true);
    try {
      await _tiendasService.cancelarPedidoComoVendedor(
        _idPedido,
        motivo: motivo.isEmpty ? null : motivo,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido rechazado y stock devuelto')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _procesando = false);
        _snack('No se pudo rechazar el pedido: $e');
      }
    }
  }

  // ------------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Extras>(
      future: _extras,
      builder: (context, snap) {
        final extras = snap.data ??
            _Extras(
              tienda: _p['tiendas'] is Map
                  ? Map<String, dynamic>.from(_p['tiendas'] as Map)
                  : null,
            );
        return AnimatedBuilder(
          animation: CurrencyService.instance,
          builder: (context, _) => _scaffold(context, extras, snap.hasData),
        );
      },
    );
  }

  Widget _scaffold(BuildContext context, _Extras extras, bool cargado) {
    final barra = _barraAcciones(extras, cargado);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Pedido #$_numero'),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Center(child: CurrencyToggle()),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Compartir',
            onPressed: () => _compartir(extras.tienda),
          ),
        ],
      ),
      bottomNavigationBar: barra,
      body: AbsorbPointer(
        absorbing: _procesando,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _tarjetaCabecera(extras),
            const SizedBox(height: 12),
            _tarjetaFechas(),
            if (_datosComprador() != null) ...[
              const SizedBox(height: 12),
              _tarjetaComprador(_datosComprador()!),
            ],
            const SizedBox(height: 12),
            _tarjetaArticulos(extras),
            const SizedBox(height: 12),
            _tarjetaTotal(),
            if (extras.valoracion != null) ...[
              const SizedBox(height: 12),
              _tarjetaValoracion(extras.valoracion!),
            ],
            const SizedBox(height: 14),
            _notaPie(),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Piezas
  // ------------------------------------------------------------------
  Widget _tarjeta({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: _borde),
      ),
      child: child,
    );
  }

  Widget _tituloSeccion(IconData icono, String texto) {
    return Row(
      children: [
        Icon(icono, size: 18, color: _texto),
        const SizedBox(width: 8),
        Text(texto,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, fontSize: 14.5, color: _texto)),
      ],
    );
  }

  Widget _filaDato(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: _textoSec)),
          Flexible(
            child: Text(valor,
                textAlign: TextAlign.right,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w500, color: _texto)),
          ),
        ],
      ),
    );
  }

  // ---------- 1. Cabecera: tienda + número + estado + cuenta regresiva ----------
  Widget _tarjetaCabecera(_Extras extras) {
    final t = extras.tienda;
    final logo = t?['logo_url'] as String?;
    final nombre = (t?['nombre'] as String?) ?? 'Tienda';
    final ubicacion = [t?['municipio'], t?['provincia']]
        .where((e) => e != null && e.toString().isNotEmpty)
        .join(', ');
    final color = _colorEstado(_estado);
    final restante = _restante;
    final urgente = restante != null && restante.inHours < 12;
    final colorReloj = urgente ? const Color(0xFFFF3B30) : color;

    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage:
                    (logo != null && logo.isNotEmpty) ? NetworkImage(logo) : null,
                child: (logo == null || logo.isEmpty)
                    ? const Icon(Icons.storefront_rounded,
                        color: AppColors.primary)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: _texto)),
                    if (ubicacion.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.place_rounded, size: 14, color: _textoSec),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(ubicacion,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12.5, color: _textoSec)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('#$_numero',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 30,
                      color: _texto)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_iconoEstado(_estado), size: 15, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(_textoEstado(_estado),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
          if (restante != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorReloj.withOpacity(_oscuro ? 0.14 : 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorReloj.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 22, color: colorReloj),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_fmtRestante(restante),
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: colorReloj)),
                        Text('Se cancelará automáticamente en 72 h.',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11.5, color: colorReloj)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Contacto con la tienda: solo tiene sentido para el comprador.
          if (!widget.esVendedor) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _abrirWhatsapp(t),
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    label: const Text('WhatsApp'),
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _comoLlegar(t),
                    icon: const Icon(Icons.place_outlined, size: 18),
                    label: const Text('Cómo llegar'),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------- 2. Fechas ----------
  Widget _tarjetaFechas() {
    final creado = _fmtFecha(_p['creado_en']);
    final completado = _fmtFecha(_p['fecha_completado']);
    final cancelado = _fmtFecha(_p['cancelado_en'] ?? _p['fecha_cancelado']);
    final canceladoPor = _p['cancelado_por'] as String?;

    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion(Icons.calendar_today_rounded, 'Fechas'),
          _filaDato('Creado', creado.isEmpty ? '—' : creado),
          if (_estado == _EstadoPedido.completado && completado.isNotEmpty)
            _filaDato('Completado', completado),
          if (_estado == _EstadoPedido.cancelado) ...[
            if (cancelado.isNotEmpty) _filaDato('Cancelado', cancelado),
            if (canceladoPor != null && canceladoPor.isNotEmpty)
              _filaDato('Cancelado por',
                  canceladoPor == 'vendedor' ? 'La tienda' : 'El comprador'),
          ],
        ],
      ),
    );
  }

  // ---------- 3. Comprador ----------
  /// Comprador (vista comprador): la cuenta actual. Vista vendedor: solo
  /// si el mapa del pedido trae comprador_* (lo devuelven algunos RPC de
  /// analíticas, pero NO el select() de Gestionar Ventas).
  ({String nombre, String email, String? foto})? _datosComprador() {
    if (!widget.esVendedor) {
      final u = supabase.auth.currentUser;
      if (u == null) return null;
      final m = u.userMetadata;
      final nombre = (m?['full_name'] as String?) ??
          (m?['name'] as String?) ??
          (u.email?.split('@').first ?? 'Usuario');
      final foto = (m?['avatar_url_custom'] as String?) ??
          (m?['avatar_url'] as String?);
      return (nombre: nombre, email: u.email ?? '', foto: foto);
    }
    final email = _p['comprador_email'] as String?;
    final nombre = _p['comprador_nombre'] as String?;
    if ((email == null || email.isEmpty) &&
        (nombre == null || nombre.isEmpty)) {
      return null;
    }
    return (
      nombre: nombre ?? (email ?? '').split('@').first,
      email: email ?? '',
      foto: _p['comprador_avatar'] as String?,
    );
  }

  Widget _tarjetaComprador(({String nombre, String email, String? foto}) c) {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion(Icons.person_outline_rounded, 'Comprador'),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage: (c.foto != null && c.foto!.isNotEmpty)
                    ? NetworkImage(c.foto!)
                    : null,
                child: (c.foto == null || c.foto!.isEmpty)
                    ? const Icon(Icons.person, color: AppColors.primary)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: _texto)),
                    if (c.email.isNotEmpty)
                      Text(c.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5, color: _textoSec)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 4. Artículos ----------
  Widget _tarjetaArticulos(_Extras extras) {
    final items = _items;
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion(Icons.shopping_bag_outlined, 'Artículos del pedido'),
          const SizedBox(height: 6),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('No hay detalle de productos para este pedido',
                  style: GoogleFonts.plusJakartaSans(color: _textoSec)),
            )
          else
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) Divider(height: 1, color: _borde),
              _filaArticulo(items[i], extras),
            ],
        ],
      ),
    );
  }

  Widget _filaArticulo(Map<String, dynamic> item, _Extras extras) {
    final cantidad = (item['cantidad'] as num?)?.toInt() ?? 1;
    final precio = (item['precio_usd'] as num?)?.toDouble() ?? 0;
    final img = extras.imagenes[item['id_producto']];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 54,
              height: 54,
              color: AppColors.primary.withOpacity(0.08),
              child: img != null
                  ? Image.network(img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.image_not_supported_outlined,
                          size: 20,
                          color: AppColors.primary))
                  : const Icon(Icons.shopping_bag_outlined,
                      size: 22, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item['nombre'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: _texto)),
                const SizedBox(height: 2),
                Text('${cantidad}x · ${_money(precio)} c/u',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: _textoSec)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(_money(precio * cantidad),
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800, fontSize: 14, color: _texto)),
        ],
      ),
    );
  }

  // ---------- 5. Total ----------
  Widget _tarjetaTotal() {
    final cs = CurrencyService.instance;
    final tasa = cs.tasa;
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Total',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: _texto)),
              Text(_money(_totalUsd),
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 26,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tasa != null
                ? 'Tasa del día: 1 USD = ${tasa.toStringAsFixed(0)} CUP'
                : 'Tasa de referencia: 1 USD = 320 CUP',
            style:
                GoogleFonts.plusJakartaSans(fontSize: 12, color: _textoSec),
          ),
          Text('Los precios se guardan en USD.',
              style:
                  GoogleFonts.plusJakartaSans(fontSize: 12, color: _textoSec)),
        ],
      ),
    );
  }

  // ---------- 6. Valoración (si existe) ----------
  Widget _tarjetaValoracion(Map<String, dynamic> v) {
    final estrellas = (v['estrellas'] as num?)?.toInt() ?? 0;
    final comentario = (v['comentario'] as String?)?.trim();
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion(Icons.star_rounded, 'Valoración'),
          const SizedBox(height: 8),
          Row(
            children: List.generate(
              5,
              (i) => Icon(
                i < estrellas ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 20,
                color: i < estrellas
                    ? const Color(0xFFD4AF37)
                    : _textoSec.withOpacity(0.5),
              ),
            ),
          ),
          if (comentario != null && comentario.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(comentario,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, height: 1.4, color: _texto)),
          ],
        ],
      ),
    );
  }

  // ---------- 7. Pie: notas ----------
  Widget _notaPie() {
    final motivo =
        ((_p['motivo_cancelacion'] ?? _p['motivo']) as String?)?.trim();
    final notas = <String>[
      'El pago y la entrega se coordinan directamente con el vendedor por '
          'WhatsApp.',
      if (_estado == _EstadoPedido.cancelado && motivo != null && motivo.isNotEmpty)
        'Motivo de la cancelación: $motivo',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final n in notas)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: _textoSec),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(n,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5, height: 1.4, color: _textoSec)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---------- 8. Barra de acciones fija ----------
  Widget? _barraAcciones(_Extras extras, bool cargado) {
    Widget? contenido;

    if (widget.esVendedor && _estado == _EstadoPedido.pendiente) {
      contenido = Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _procesando ? null : _rechazar,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Rechazar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF3B30),
                side: const BorderSide(color: Color(0xFFFF3B30)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: _procesando ? null : _marcarVendido,
              icon: _procesando
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 18),
              label: const Text('Vendido'),
            ),
          ),
        ],
      );
    } else if (!widget.esVendedor &&
        _estado == _EstadoPedido.completado &&
        cargado &&
        extras.valoracion == null) {
      final idTienda = _p['id_tienda']?.toString();
      contenido = SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => context.push(idTienda != null
              ? '/valorar/$_idPedido?tienda=$idTienda'
              : '/valorar/$_idPedido'),
          icon: const Icon(Icons.star_rounded, size: 18),
          label: const Text('Valorar compra'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.warm),
        ),
      );
    }

    if (contenido == null) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: contenido,
      ),
    );
  }
}
