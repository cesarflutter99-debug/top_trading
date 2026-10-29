// afiliado_state_service.dart
//
// Fuente ÚNICA de verdad para "mi afiliado" (el perfil de afiliado del
// usuario logueado). Mismo patrón que TiendaStateService
// (tienda_state_service.dart) -- antes cada pantalla (HomeScreen,
// MiPerfilScreen, AfiliadoRegistroScreen, AfiliadoPerfilScreen...)
// guardaba su propia copia local con setState(), así que registrar,
// editar o dar de baja el perfil de afiliado en una pantalla no se
// reflejaba en las demás hasta cerrar y volver a abrir la app.
//
// A partir de ahora: TODA acción que registre, edite o dé de baja el
// afiliado del usuario debe terminar llamando a
// AfiliadoStateService.instance.refrescar() (o .limpiar() si se dio
// de baja). Cualquier widget que envuelva su build en un
// AnimatedBuilder(animation: AfiliadoStateService.instance, ...) se
// entera al instante, sin reiniciar nada.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import '../core/supabase_client.dart';
import 'tiendas_service.dart';

class AfiliadoStateService extends ChangeNotifier {
  AfiliadoStateService._();
  static final AfiliadoStateService instance = AfiliadoStateService._();

  final _tiendasService = TiendasService();

  Map<String, dynamic>? _miAfiliado;
  bool _cargando = true;

  Map<String, dynamic>? get miAfiliado => _miAfiliado;
  bool get cargando => _cargando;
  bool get esAfiliado => _miAfiliado != null;

  /// Carga (o recarga) el afiliado del usuario actual desde Supabase.
  /// Notifica a todos los listeners al terminar, tanto si encontró
  /// afiliado como si no (para que el "Cargando..." desaparezca igual).
  Future<void> cargar() async {
    _cargando = true;
    _notificarSeguro();
    try {
      if (supabase.auth.currentUser == null) {
        _miAfiliado = null;
      } else {
        _miAfiliado = await _tiendasService.obtenerMiAfiliado();
      }
    } catch (_) {
      _miAfiliado = null;
    }
    _cargando = false;
    _notificarSeguro();
  }

  /// Alias explícito para usar después de registrar/editar/dar de baja
  /// -- deja claro en el código de la pantalla que se está forzando un
  /// refresco global, no solo local.
  Future<void> refrescar() => cargar();

  /// Actualiza campos puntuales en memoria sin ir a la red (útil justo
  /// después de una edición optimista) y notifica ya.
  void actualizarLocal(Map<String, dynamic> datos) {
    if (_miAfiliado == null) return;
    _miAfiliado = {..._miAfiliado!, ...datos};
    _notificarSeguro();
  }

  /// Se llama INMEDIATAMENTE después de dar de baja al afiliado en
  /// Supabase (darDeBajaAfiliado). No espera ningún roundtrip de red --
  /// la UI reacciona en el mismo frame.
  void limpiar() {
    _miAfiliado = null;
    _cargando = false;
    _notificarSeguro();
  }

  /// Notifica a los listeners SIN romper la app si el aviso cae dentro
  /// de un build. Un ChangeNotifier que llama notifyListeners() durante
  /// la fase de build hace que el AnimatedBuilder que lo escucha
  /// llame setState() -> "setState() or markNeedsBuild() called during
  /// build". Pasa, por ejemplo, cuando cargar() se llama desde el
  /// initState de una pantalla que vive dentro de un IndexedStack.
  /// En ese caso el aviso se aplaza al siguiente frame.
  void _notificarSeguro() {
    final fase = SchedulerBinding.instance.schedulerPhase;
    if (fase == SchedulerPhase.persistentCallbacks ||
        fase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      notifyListeners();
    }
  }

}
