// tour_runner.dart
//
// Helper para lanzar un tour contextual la PRIMERA vez que el usuario
// llega a una pantalla.
//
// Uso tipico (dentro de una pantalla, cuando ya se ve):
//
//   _tourMostrado = await TourRunner.mostrarSiNoVisto(
//     context,
//     clave: TutorialService.claveMiPerfil,
//     titulo: 'Tu perfil',
//     pasos: const [...],
//   );
//
// El tour NUNCA se dispara desde el initState de una pestaña que vive
// dentro de un IndexedStack: hay que llamarlo cuando la pestaña ya es
// visible (por ejemplo, en un addPostFrameCallback o al entrar a la
// pantalla con un push).
import 'package:flutter/material.dart';
import '../services/tutorial_service.dart';
import 'coach_marks_widget.dart';

class TourRunner {
  TourRunner._();

  /// Flag global para evitar que dos tours se abran al mismo tiempo
  /// (p. ej. al cambiar de pestaña rápido en MainShell).
  static bool _abierto = false;
  static bool get abierto => _abierto;

  /// Muestra el tour si el usuario no lo ha visto todavia.
  /// Devuelve true si se mostró (para no volver a intentarlo).
  static Future<bool> mostrarSiNoVisto(
    BuildContext context, {
    required String clave,
    required String titulo,
    required List<CoachStep> pasos,
  }) async {
    if (pasos.isEmpty) return false;
    if (!context.mounted) return false;
    if (_abierto) return false;
    if (await TutorialService.instance.yaVisto(clave)) return false;
    if (!context.mounted) return false;
    _abierto = true;
    try {
      await CoachMarks.mostrar(context, titulo: titulo, pasos: pasos);
    } finally {
      _abierto = false;
    }
    await TutorialService.instance.marcarVisto(clave);
    return true;
  }
}
