// coach_marks_widget.dart
//
// Tour contextual "spotlight": oscurece (desenfoca visualmente) TODA la
// pantalla y va iluminando de a UNA las opciones reales de la interfaz,
// mostrando un cartelito con la explicación de cada una. Sin dependencias
// extra: la máscara con "agujero" se pinta con un CustomPainter.
//
// Cómo se usa:
//   CoachMarks.mostrar(context, titulo: 'Descubrí Al Lado', pasos: [
//     CoachStep(
//       titulo: 'Explorá el mapa',
//       descripcion: 'La pestaña Mapa te muestra las tiendas cerca tuyo...',
//       destino: rectDeLaOpcion,   // Rect en coordenadas globales
//     ),
//     ...
//   ]);
//
// Si un paso no tiene `destino`, se ilumina un foco central por defecto
// (para no romper la metáfora "desenfocar + opciones" en ningún paso).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';

/// Un paso del tour: la opción a iluminar (`destino`, en coordenadas
/// globales de pantalla) y el texto que aparece debajo.
class CoachStep {
  final String titulo;
  final String descripcion;
  final Rect? destino;

  const CoachStep({
    required this.titulo,
    required this.descripcion,
    this.destino,
  });
}

/// Muestra el tour completo como un overlay semitransparente encima de la
/// pantalla actual. Avanza tocando el fondo o el botón "Siguiente", y se
/// puede saltar siempre con "Saltar" (arriba a la derecha).
class CoachMarks {
  static Future<void> mostrar(
    BuildContext context, {
    required String titulo,
    required List<CoachStep> pasos,
  }) async {
    if (pasos.isEmpty) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => _OverlayTour(titulo: titulo, pasos: pasos),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }
}

class _OverlayTour extends StatefulWidget {
  final String titulo;
  final List<CoachStep> pasos;
  const _OverlayTour({required this.titulo, required this.pasos});

  @override
  State<_OverlayTour> createState() => _OverlayTourState();
}

class _OverlayTourState extends State<_OverlayTour> {
  int _paso = 0;

  CoachStep get _actual => widget.pasos[_paso];
  bool get _esUltimo => _paso == widget.pasos.length - 1;

  void _cerrar() => Navigator.of(context).pop();

  void _siguiente() {
    if (_esUltimo) {
      _cerrar();
      return;
    }
    setState(() => _paso++);
  }

  /// Rect (inflado un poco) de la opción destacada de este paso. Si el
  /// paso no trae destino, se ilumina un foco central de tamaño fijo.
  Rect _hueco(Size pantalla) {
    final base = _actual.destino;
    return (base ?? Rect.fromCenter(
      center: Offset(pantalla.width / 2, pantalla.height * 0.36),
      width: 320,
      height: 180,
    )).inflate(4);
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final pantalla = MediaQuery.sizeOf(context);

    return GestureDetector(
      // Tocar la zona oscurecida avanza al siguiente paso (type-showcase).
      behavior: HitTestBehavior.opaque,
      onTap: _siguiente,
      child: Stack(
        children: [
          // 1 - Máscara "desenfocada" con el agujero para la opción.
          Positioned.fill(
            child: CustomPaint(
              painter: _MascaraAgujero(
                pantalla: pantalla,
                hueco: _hueco(pantalla),
              ),
            ),
          ),

          // 2 - Anillo luminoso alrededor de la opción destacada.
          Positioned(
            left: _hueco(pantalla).left,
            top: _hueco(pantalla).top,
            width: _hueco(pantalla).width,
            height: _hueco(pantalla).height,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.primary, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.55),
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3 - Cartelito con el contenido del paso. Sus botones son
          // interactivos; el resto de la zona oscura avanza al tocar.
          Positioned(
            left: 16,
            right: 16,
            top: _posicionDelCartel(pantalla),
            child: _Cartel(
              titulo: widget.titulo,
              paso: _paso,
              total: widget.pasos.length,
              step: _actual,
              esOscuro: esOscuro,
            ),
          ),

          // 4 - Botón Saltar siempre visible (arriba a la derecha).
          Positioned(
            top: 16,
            right: 16,
            child: _BtnSaltar(onTap: _cerrar),
          ),
        ],
      ),
    );
  }

  /// Ubica el cartelito debajo del agujero; si no entra (hueco abajo),
  /// lo sube encima del mismo para que nunca quede cortado.
  double _posicionDelCartel(Size pantalla) {
    final hueco = _hueco(pantalla);
    const altoCartel = 240.0;
    final abajo = hueco.bottom + 20;
    final entraAbajo = abajo + altoCartel < pantalla.height - 16;
    if (entraAbajo) return abajo;
    final arriba = hueco.top - altoCartel - 20;
    if (arriba > 16) return arriba;
    return (pantalla.height - altoCartel) / 2;
  }
}

// --------------------------- Máscara ----------------------------------

/// Pinta la pantalla oscurecida con un agujero (recorte) sobre la opción.
class _MascaraAgujero extends CustomPainter {
  final Size pantalla;
  final Rect hueco;

  _MascaraAgujero({required this.pantalla, required this.hueco});

  @override
  void paint(Canvas canvas, Size size) {
    final todo = Path()..addRect(Offset.zero & pantalla);
    // El agujero es un rectángulo redondeado que se RESTA de la máscara
    // (like a "ventana" del foco).
    final ventana = Path()
      ..addRRect(
        RRect.fromRectAndRadius(hueco, const Radius.circular(24)),
      );
    final mascara = Path.combine(PathOperation.difference, todo, ventana);

    canvas.drawPath(
      mascara,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.72)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _MascaraAgujero old) =>
      old.hueco != hueco || old.pantalla != pantalla;
}

// --------------------------- Cartel -----------------------------------

class _Cartel extends StatelessWidget {
  final String titulo;
  final int paso;
  final int total;
  final CoachStep step;
  final bool esOscuro;

  const _Cartel({
    required this.titulo,
    required this.paso,
    required this.total,
    required this.step,
    required this.esOscuro,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOut,
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: Material(
        key: ValueKey(paso),
        color: esOscuro ? const Color(0xFF1E1E22) : Colors.white,
        elevation: 16,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${paso + 1}. ${step.titulo}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: esOscuro ? AppColors.inkDark : AppColors.inkLight,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                step.descripcion,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  height: 1.45,
                  color: esOscuro
                      ? AppColors.inkSecundarioDark
                      : AppColors.inkSecundarioLight,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (var i = 0; i < total; i++) ...[
                    _PuntoProgresso(activo: i == paso, esOscuro: esOscuro),
                    if (i < total - 1) const SizedBox(width: 6),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Saltar'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: () => _siguiente(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: Text(paso == total - 1 ? 'Entendido' : 'Siguiente'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _siguiente(BuildContext context) {
    if (paso == total - 1) {
      Navigator.of(context).pop();
    } else {
      // Avanza dentro del overlay: el estado del paso vive en el padre.
      final state = _tourState(context);
      state?._siguiente();
    }
  }
}

class _PuntoProgresso extends StatelessWidget {
  final bool activo;
  final bool esOscuro;
  const _PuntoProgresso({required this.activo, required this.esOscuro});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: activo ? 22 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: activo
            ? AppColors.primary
            : (esOscuro ? const Color(0xFF3A3A3F) : const Color(0xFFE1E1E6)),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// ------------------------ Botones flotantes ---------------------------

class _BtnSaltar extends StatelessWidget {
  final VoidCallback onTap;
  const _BtnSaltar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.skip_next_rounded, color: Colors.white, size: 18),
              SizedBox(width: 4),
              Text(
                'Saltar',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Helper para que el botón del cartelito pueda avanzar el paso (el
// botón vive en un subtree; el estado está en el overlay raíz).
_OverlayTourState? _tourState(BuildContext context) {
  return context.findAncestorStateOfType<_OverlayTourState>();
}