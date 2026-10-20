// terminos_gate.dart
//
// Gate de aceptación obligatoria de Términos y Condiciones. Se muestra
// antes de que el usuario pueda usar la app (incluso antes de iniciar
// sesión). Persiste la versión aceptada en SharedPreferences; si los
// términos cambian (kVersionTerminos), se vuelve a pedir aceptación.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/terminos_screen.dart';

class TerminosGate extends StatefulWidget {
  final Widget child;
  const TerminosGate({super.key, required this.child});

  @override
  State<TerminosGate> createState() => _TerminosGateState();
}

class _TerminosGateState extends State<TerminosGate> {
  bool _cargando = true;
  bool _aceptado = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString('terminos_version');
      if (mounted) {
        setState(() {
          _aceptado = v == kVersionTerminos;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aceptado = false;
          _cargando = false;
        });
      }
    }
  }

  Future<void> _aceptar() async {
    // Optimista: habilita el acceso de inmediato, sin esperar a disco.
    if (mounted) setState(() => _aceptado = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('terminos_version', kVersionTerminos);
    } catch (e) {
      debugPrint('TerminosGate persist falló: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_aceptado) return widget.child;
    return TerminosScreen(onAceptar: _aceptar);
  }
}
