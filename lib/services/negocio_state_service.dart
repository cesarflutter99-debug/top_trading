// negocio_state_service.dart
//
// Fuente ÚNICA de verdad para "mi negocio" (el registro de servicios
// del usuario logueado -- barbería, taller, etc.). Mismo patrón que
// TiendaStateService/AfiliadoStateService: una sola copia en memoria,
// notificada a todas las pantallas, para que el CTA "Promociona tu
// negocio" del feed y de Mi Perfil reaccione al instante.
//
// Por qué existe: sin esto, un usuario con negocio ya registrado (en
// revisión o aprobado) seguía viendo el botón "Registrar mi negocio"
// y podía crear registros duplicados rompiendo el flujo. Ahora:
//   - Sin negocio  -> se muestra el CTA de registro.
//   - 'pendiente'  -> tarjeta ámbar "En revisión", sin botón de crear.
//   - 'activo'     -> tarjeta verde con acceso a la mini-página.
//   - rechazado/suspendido -> aviso con el motivo si existe.
//
// BONUS Realtime: escucha la tabla `negocios` filtrada por id_dueno,
// así cuando el ADMIN aprueba/rechaza desde su panel, el celular del
// dueño se actualiza solo (igual que hace TiendaStateService).

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';

class NegocioStateService extends ChangeNotifier {
  NegocioStateService._();
  static final NegocioStateService instance = NegocioStateService._();

  Map<String, dynamic>? _miNegocio;
  bool _cargando = true;
  RealtimeChannel? _canal;
  // Compras de paquetes del negocio: avisamos cuando el admin aprueba
  // (o rechaza) el pago -- el permiso nace solo por trigger.
  RealtimeChannel? _canalCompras;
  String? _uidEscuchado;

  Map<String, dynamic>? get miNegocio => _miNegocio;
  bool get cargando => _cargando;
  bool get tieneNegocio => _miNegocio != null;

  /// 'pendiente' | 'activo' | 'rechazado' | 'suspendido' | null
  String? get estado => _miNegocio?['estado'] as String?;

  Future<void> cargar() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      _miNegocio = null;
      _cargando = false;
      notifyListeners();
      return;
    }
    _cargando = true;
    notifyListeners();
    try {
      // El dueño puede ver sus negocios en cualquier estado (RLS).
      // Si algún día hay varios, nos quedamos con el más reciente.
      final res = await supabase
          .from('negocios')
          .select()
          .eq('id_dueno', uid)
          .order('creado_en', ascending: false)
          .limit(1);
      final lista = List<Map<String, dynamic>>.from(res as List);
      _miNegocio = lista.isEmpty ? null : lista.first;
    } catch (_) {
      // Offline u otro fallo: no mostramos nada en vez de truenar.
      _miNegocio ??= null;
    }
    _cargando = false;
    notifyListeners();
    _escucharCambiosRemotos(uid);
  }

  /// Alias explícito tras crear/editar el negocio.
  Future<void> refrescar() => cargar();

  void limpiar() {
    _miNegocio = null;
    _cargando = false;
    _canal?.unsubscribe();
    _canal = null;
    _canalCompras?.unsubscribe();
    _canalCompras = null;
    _uidEscuchado = null;
    notifyListeners();
  }

  void _escucharCambiosRemotos(String uid) {
    if (_uidEscuchado == uid && _canal != null) return;
    _canal?.unsubscribe();
    _uidEscuchado = uid;
    _canal = supabase
        .channel('mi-negocio-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'negocios',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id_dueno',
            value: uid,
          ),
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.delete) {
              limpiar();
            } else {
              cargar(); // el admin cambió estado -> recargar
            }
          },
        )
        .subscribe();

    // Compras de paquetes: al aprobarse el pago, el trigger crea el
    // permiso solo, y el trigger SQL notifica al dueño insertando una
    // fila real en `notificaciones` (parche_notif_compras_tienda.sql).
    // Ya NO generamos una notificación local aquí (habría quedado
    // duplicada con la real). El permiso se refleja al volver a cargar.
    _canalCompras?.unsubscribe();
    _canalCompras = null;
  }

  @override
  void dispose() {
    _canal?.unsubscribe();
    super.dispose();
  }
}
