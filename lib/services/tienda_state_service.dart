// tienda_state_service.dart
//
// Fuente ÚNICA de verdad para "mi tienda" (la del vendedor logueado).
// Antes cada pantalla (MainShellScreen, MiPerfilScreen, HomeScreen,
// PanelVendedorScreen...) guardaba su propia copia en un setState()
// local. Eso es lo que causaba que, al eliminar la tienda o cambiar
// de plan, unas pantallas se enteraran y otras no -- porque con
// IndexedStack (MainShellScreen) las pestañas viejas siguen montadas
// en memoria con datos obsoletos hasta reiniciar la app.
//
// A partir de ahora: TODA acción que cree, edite, cambie de plan o
// elimine la tienda del usuario debe terminar llamando a
// TiendaStateService.instance.refrescar() (o .limpiar() si se borró).
// Cualquier widget que envuelva su build en un
// AnimatedBuilder(animation: TiendaStateService.instance, ...) se
// entera al instante, sin reiniciar nada.
//
// BONUS: escucharCambios(uid) abre un canal de Realtime de Supabase
// escuchando la tabla `tiendas` filtrada por owner_id. Así, si el
// ADMIN aprueba la tienda o el plan desde su panel (una acción que
// ocurre fuera de este celular), el cambio también llega solo, sin
// que el usuario tenga que hacer nada.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import 'tiendas_service.dart';

class TiendaStateService extends ChangeNotifier {
  TiendaStateService._();
  static final TiendaStateService instance = TiendaStateService._();

  final _tiendasService = TiendasService();

  Map<String, dynamic>? _miTienda;
  bool _cargando = true;
  RealtimeChannel? _canal;
  String? _uidEscuchado;

  Map<String, dynamic>? get miTienda => _miTienda;
  bool get cargando => _cargando;
  bool get tieneTienda => _miTienda != null;

  /// Carga (o recarga) la tienda del usuario actual desde Supabase.
  /// Notifica a todos los listeners al terminar, tanto si encontró
  /// tienda como si no (para que el "Cargando..." desaparezca igual).
  Future<void> cargar() async {
    _cargando = true;
    notifyListeners();
    try {
      _miTienda = await _tiendasService.obtenerMiTienda();
    } catch (_) {
      _miTienda = null;
    }
    _cargando = false;
    notifyListeners();

    final uid = supabase.auth.currentUser?.id;
    if (uid != null) _escucharCambiosRemotos(uid);
  }

  /// Alias explícito para usar después de crear/editar/cambiar plan/
  /// eliminar -- deja claro en el código de la pantalla que se está
  /// forzando un refresco global, no solo local.
  Future<void> refrescar() => cargar();

  /// Actualiza campos puntuales en memoria sin ir a la red (útil justo
  /// después de subir un logo/portada, por ejemplo) y notifica ya.
  void actualizarLocal(Map<String, dynamic> datos) {
    if (_miTienda == null) return;
    _miTienda = {..._miTienda!, ...datos};
    notifyListeners();
  }

  /// Se llama INMEDIATAMENTE después de borrar la tienda en Supabase.
  /// No espera ningún roundtrip de red -- la UI reacciona en el mismo
  /// frame.
  void limpiar() {
    _miTienda = null;
    _cargando = false;
    _canal?.unsubscribe();
    _canal = null;
    _uidEscuchado = null;
    notifyListeners();
  }

  void _escucharCambiosRemotos(String uid) {
    if (_uidEscuchado == uid && _canal != null) return;
    _canal?.unsubscribe();
    _uidEscuchado = uid;
    _canal = supabase
        .channel('mi-tienda-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tiendas',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'owner_id',
            value: uid,
          ),
          callback: (payload) {
            // UPDATE (aprobación, cambio de plan) -> recargar.
            // DELETE (el admin la eliminó desde su panel) -> limpiar.
            if (payload.eventType == PostgresChangeEvent.delete) {
              limpiar();
            } else {
              cargar();
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _canal?.unsubscribe();
    super.dispose();
  }
}
