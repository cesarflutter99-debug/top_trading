// theme_provider.dart
//
// Estado del tema (claro/oscuro). El modo oscuro se PERSISTE con
// shared_preferences: al cambiar con toggleTheme()/setDarkMode() se
// guarda en disco al instante, y se restaura al volver a abrir la app.
// Antes esto era solo en memoria, por lo que el modo oscuro se perdía
// cada vez que salías de la app.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _claveTema = 'tema_oscuro';

  bool _isDarkMode = false;
  bool _cargado = false;

  bool get isDarkMode => _isDarkMode;
  bool get cargado => _cargado;

  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  /// Carga el tema guardado de la sesión anterior. Se llama una sola vez
  /// desde `main()` antes de `runApp` para evitar un flash de tema.
  Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool(_claveTema) ?? false;
    } catch (e) {
      _isDarkMode = false;
    }
    _cargado = true;
    notifyListeners();
  }

  Future<void> _persistir(bool valor) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_claveTema, valor);
    } catch (_) {
      // si falla el guardado, el tema sigue aplicado en esta sesión
    }
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    await _persistir(_isDarkMode);
  }

  Future<void> setDarkMode(bool valor) async {
    if (_isDarkMode == valor) return;
    _isDarkMode = valor;
    notifyListeners();
    await _persistir(valor);
  }
}
