// coach_marks_widget.dart
//
// Tour contextual "spotlight": oscurece la pantalla y va iluminando de
// a UNA las opciones reales de la interfaz, mostrando un cartelito con la
// explicacion de cada una. Sin dependencias extra: la mascara con
// "agujero" se pinta con un CustomPainter.
//
// PRECISION: el foco se resuelve en el MOMENTO de pintar cada paso
// (no se calcula una vez al abrir el tour). Por eso el rect sale del
// RenderBox real del widget anclado -> el circulo cae EXACTAMENTE sobre
// el boton, sin desfases. Ver widgets/tour_anchor.dart.
//
// Como se usa:
//   CoachMarks.mostrar(context, titulo: 'Descubri Al Lado', pasos: [
//     CoachStep(
//       titulo: 'Explora el mapa',
//       descripcion: '...',
//       ancla: TourAnclas.navMapa,
//     ),
//     ...
//   ]);
//
// Si un paso no tiene 'ancla' ni 'destino', se ilumina un foco central
// por defecto (para no romper la metafora en ningun paso).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import 'tour_anchor.dart';

/// Un paso del tour: la opcion a iluminar y el texto que aparece.
///
/// - [ancla]: id de un TourAnchor. Se resuelve en vivo -> preciso.
/// - [destino]: rect absoluto (para casos sin anchor).
/// - [padding]: margen extra alrededor del foco (px).
/// - [radio]: radio del hueco. null = se calcula segun el alto del foco.
class CoachStep {
  final String titulo;
  final String descripcion;
  final String? ancla;
  final Rect? destino;
  final double padding;
  final double? radio;

  const CoachStep({
    required this.titulo,
    required this.descripcion,
    this.ancla,
    this.destino,
    this.padding = 6,
    this.radio,
  });
}

/// Muestra el tour completo como un overlay semitransparente encima de la
/// pantalla actual. Avanza tocando el fondo o el boton "Siguiente", y se
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
        barrierColor: Colors.transparent,
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

  /// Radio del hueco: circular si el foco es pequeño (iconos), con
  /// esquinas suaves si es un area grande (tarjetas, campos).
  double _radioDelFoco(Rect foco) {
    final r = _actual.radio;
    if (r != null) return r;
    final menor = foco.width < foco.height ? foco.width : foco.height;
    return (menor / 2).clamp(10, 22);
  }

  /// Rect (en coordenadas de pantalla) del foco de ESTE paso, resuelto
  /// en vivo desde el anchor.
  Rect _foco(Size pantalla) {
    final paso = _actual;
    if (paso.ancla != null) {
      final r = TourRegistro.rectDe(paso.ancla!, padding: paso.padding);
      if (r != null) return r;
    }
    final fijo = paso.destino;
    if (fijo != null) return fijo.inflate(paso.padding);
    return Rect.fromCenter(
      center: Offset(pantalla.width / 2, pantalla.height * 0.4),
      width: 300,
      height: 160,
    );
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final pantalla = MediaQuery.sizeOf(context);
    final foco = _foco(pantalla);
    final radio = _radioDelFoco(foco);

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
                hueco: foco,
                radio: radio,
              ),
            ),
          ),

          // 2 - Anillo luminoso alrededor de la opción destacada.
          Positioned(
            left: foco.left,
            top: foco.top,
            width: foco.width,
            height: foco.height,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(radio),
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
            top: _posicionDelCartel(pantalla, foco),
            child: _Cartel(
              titulo: widget.titulo,
              paso: _paso,
              total: widget.pasos.length,
              step: _actual,
              esOscuro: esOscuro,
              onSiguiente: _siguiente,
              onSaltar: _cerrar,
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

  /// Ubica el cartelito: debajo del foco si cabe; si no, encima; si
  /// tampoco, al lado (para foci que están en un borde).
  double _posicionDelCartel(Size pantalla, Rect foco) {
    const altoCartel = 250.0;
    const margen = 20.0;

    final abajo = foco.bottom + margen;
    if (abajo + altoCartel <= pantalla.height - 16) return abajo;

    final arriba = foco.top - altoCartel - margen;
    if (arriba >= 16) return arriba;

    // Sin espacio vertical: lo pegamos arriba del todo.
    return 16;
  }
}

// --------------------------- Máscara ----------------------------------

/// Pinta la pantalla oscurecida con un agujero (recorte) sobre la opción.
class _MascaraAgujero extends CustomPainter {
  final Size pantalla;
  final Rect hueco;
  final double radio;

  _MascaraAgujero({
    required this.pantalla,
    required this.hueco,
    required this.radio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final todo = Path()..addRect(Offset.zero & pantalla);
    // El agujero es un rectángulo redondeado que se RESTA de la máscara
    // (like a "ventana" del foco).
    final ventana = Path()
      ..addRRect(
        RRect.fromRectAndRadius(hueco, Radius.circular(radio)),
      );
    final mascara = Path.combine(PathOperation.difference, todo, ventana);

    canvas.drawPath(
      mascara,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.74)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _MascaraAgujero old) =>
      old.hueco != hueco ||
      old.pantalla != pantalla ||
      old.radio != radio;
}

// --------------------------- Cartel -----------------------------------

class _Cartel extends StatelessWidget {
  final String titulo;
  final int paso;
  final int total;
  final CoachStep step;
  final bool esOscuro;
  final VoidCallback onSiguiente;
  final VoidCallback onSaltar;

  const _Cartel({
    required this.titulo,
    required this.paso,
    required this.total,
    required this.step,
    required this.esOscuro,
    required this.onSiguiente,
    required this.onSaltar,
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      titulo,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  Text(
                    '${paso + 1}/$total',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: esOscuro
                          ? AppColors.inkSecundarioDark
                          : AppColors.inkSecundarioLight,
                    ),
                  ),
                ],
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
                    onPressed: onSaltar,
                    child: const Text('Saltar'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: onSiguiente,
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
