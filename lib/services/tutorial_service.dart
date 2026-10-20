// tutorial_service.dart
//
// Servicio de tours contextuales (coach marks) con persistencia local.
// Cada pantalla tiene una clave booleana en SharedPreferences
// (p.ej. 'tour_home_v1', 'tour_mi_tienda_v1') que impide que un tour
// se repita: el tour se muestra UNA vez, y al cerrarse se marca visto.
//
// Regla de visibilidad: los tours NUNCA se disparan desde el initState
// de una pestaña que viva dentro de un IndexedStack (allí todas las
// pestañas se construyen de una, aunque estén ocultas). El MainShell
// los dispara únicamente cuando la pestaña pasa a estar VISIBLE.

import 'package:shared_preferences/shared_preferences.dart';

class TutorialService {
  TutorialService._();
  static final instance = TutorialService._();

  /// Claves de los tours de la Fase 1. Versionar la clave (v1) permite
  /// re-lanzar un tour renovado en el futuro sin tocar el resto.
  static const claveHome = 'tour_home_v1';
  static const claveMiTienda = 'tour_mi_tienda_v1';

  /// Tours pendientes por defecto, en orden de prioridad. Útil para
  /// saber qué tour corresponde disparar cuando una pestaña se vuelve
  /// visible.
  List<String> get toursPredeterminados =>
      const [claveMiTienda, claveHome];

  Future<bool> _leer(String clave) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(clave) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// ¿El tour de esta clave ya se mostró alguna vez?
  Future<bool> yaVisto(String clave) => _leer(clave);

  /// Marca el tour como visto (no volverá a mostrarse).
  Future<void> marcarVisto(String clave) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(clave, true);
    } catch (_) {}
  }

  /// ¿Hay tours pendientes según el orden predeterminado?
  Future<bool> hayPendientes() async {
    for (final clave in toursPredeterminados) {
      if (!await _leer(clave)) return true;
    }
    return false;
  }
}