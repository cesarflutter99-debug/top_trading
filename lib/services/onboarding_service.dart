// onboarding_service.dart
//
// Controla el onboarding de bienvenida (slides de la primera apertura
// tras la instalación). La bandera `onboarding_visto` se guarda en
// SharedPreferences para que el carrusel aparezca una sola vez.
//
// Se carga UNA vez en main() antes de runApp(): el redirect de
// GoRouter lee `interface.viso` de forma síncrona en cada navegación
// sin esperas ni "flash" de la pantalla equivocada.

import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  OnboardingService._();
  static final instance = OnboardingService._();

  static const _claveVisto = 'onboarding_visto';

  bool _visto = false;

  /// Acceso síncrono para el redirect de GoRouter (ya precargado).
  bool get visto => _visto;

  /// Carga el estado guardado (llamar en arranque, antes de runApp).
  Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _visto = prefs.getBool(_claveVisto) ?? false;
    } catch (_) {
      _visto = false;
    }
  }

  /// Marca el onboarding como visto (lo llaman Saltar y Empezar).
  Future<void> marcarVisto() async {
    _visto = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_claveVisto, true);
    } catch (_) {}
  }
}