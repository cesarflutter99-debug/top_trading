// tutorial_service.dart
//
// Tours contextuales (coach marks) con persistencia local.
//
// Cada tour tiene una clave booleana en SharedPreferences (p.ej.
// 'tour_home_v2'). Al/versionar la clave se puede relanzar un tour
// renovado sin tocar el resto.
//
// Reglas de disparo:
//   - NUNCA desde el initState de una pestaña que vive en un IndexedStack
//     (allí se construyen todas de una, aunque estén ocultas). El
//     MainShell dispara el tour cuando la pestaña pasa a estar VISIBLE.
//   - Cada tour se muestra UNA vez por version. El usuario puede
//     saltarlo en cualquier momento.

import 'package:shared_preferences/shared_preferences.dart';

class TutorialService {
  TutorialService._();
  static final instance = TutorialService._();

  // ------------------------------------------------------------------
  // Claves de cada tour (versionadas).
  // ------------------------------------------------------------------
  static const claveHome = 'tour_home_v2';
  static const claveMapa = 'tour_mapa_v1';
  static const claveAnuncios = 'tour_anuncios_v1';
  static const claveFavoritos = 'tour_favoritos_v1';
  static const claveMiTienda = 'tour_mi_tienda_v2';
  static const clavePerfil = 'tour_perfil_v1';
  static const claveAsistente = 'tour_asistente_v1';
  static const claveSoporte = 'tour_soporte_v1';
  static const claveCarrito = 'tour_carrito_v1';
  static const clavePedidos = 'tour_pedidos_v1';
  static const claveTienda = 'tour_tienda_v1';

  /// Tours pendientes por defecto, en orden de prioridad.
  List<String> get toursPredeterminados => const [claveHome, claveMapa];

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

  /// Borra todos los flags de tour (para probar los tours de nuevo).
  Future<void> reiniciarTodos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final clave in todasLasClaves) {
        await prefs.remove(clave);
      }
    } catch (_) {}
  }

  static const todasLasClaves = <String>[
    claveHome,
    claveMapa,
    claveAnuncios,
    claveFavoritos,
    claveMiTienda,
    clavePerfil,
    claveAsistente,
    claveSoporte,
    claveCarrito,
    clavePedidos,
    claveTienda,
  ];
}
