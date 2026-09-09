// anuncios_state_service.dart
//
// Escucha en Realtime los anuncios creados por el usuario logueado
// (anuncios.creado_por = uid) para mantener la UI de "Mis anuncios" al
// día cuando el estado cambia desde fuera (el ADMIN aprueba, pausa o
// rechaza, o un anuncio editado se re-moderó).
//
// NOTA (cambio 2026-09): ANTES este servicio generaba la notificación
// con agregarLocal(). Ahora las notificaciones de estado de anuncio se
// insertan como fila REAL en la tabla `notificaciones` desde el trigger
// SQL notificar_estado_anuncio() (parche_notif_compras_tienda.sql), y
// llegan por el canal Realtime de NotificacionesService. Aquí solo
// refrescamos el estado en memoria -- no se genera ningún aviso local
// para evitar notificaciones duplicadas.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';

class AnunciosStateService extends ChangeNotifier {
  AnunciosStateService._();
  static final instance = AnunciosStateService._();

  RealtimeChannel? _canal;
  String? _uidEscuchado;

  /// Ya no se usa (las notificaciones de estado llegan por la tabla real).
  /// Se mantiene como no-op para no romper los call sites de las hojas
  /// "Mis anuncios"; se puede eliminar junto a esas llamadas más adelante.
  void marcarCambioPropio(String idAnuncio, String estadoEsperado) {}

  Future<void> iniciar() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    if (_uidEscuchado == uid && _canal != null) return;
    await limpiar();
    _uidEscuchado = uid;
    _canal = supabase
        .channel('mis-anuncios-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'anuncios',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'creado_por',
            value: uid,
          ),
          callback: (payload) {
            notifyListeners();
          },
        )
        .subscribe();
  }

  Future<void> limpiar() async {
    _canal?.unsubscribe();
    _canal = null;
    _uidEscuchado = null;
  }

  @override
  void dispose() {
    _canal?.unsubscribe();
    super.dispose();
  }
}
