// theme_provider.dart
//
// Faltaba esta clase: home_screen.dart ya tenía el switch de UI
// (Provider.of<ThemeProvider>...) pero la clase en sí nunca se creó,
// ni main.dart envolvía la app en un ChangeNotifierProvider. Sin esto,
// el switch no tenía a qué "provider" escuchar.

import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;

  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  void setDarkMode(bool valor) {
    if (_isDarkMode == valor) return;
    _isDarkMode = valor;
    notifyListeners();
  }
}
