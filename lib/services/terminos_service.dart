// terminos_service.dart
//
// Controla la aceptación obligatoria de Términos y Condiciones.
// La bandera se precarga en main() para que el redirect de GoRouter
// decida de forma síncrona (sin parpadeos).
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/terminos_screen.dart';

class TerminosService {
  TerminosService._();
  static final instance = TerminosService._();

  static const _clave = 'terminos_version';

  bool _aceptado = false;

  bool get aceptado => _aceptado;

  Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _aceptado = prefs.getString(_clave) == kVersionTerminos;
    } catch (_) {
      _aceptado = false;
    }
  }

  Future<void> aceptar() async {
    _aceptado = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_clave, kVersionTerminos);
    } catch (_) {}
  }
}
