// onboarding_slides_screen.dart
//
// Carrusel de bienvenida de la PRIMERA apertura tras la instalación
// (ruta /bienvenida, registrada en router.dart). Máximo 4 diapositivas
// con PageView, indicador de puntos, botón "Saltar" SIEMPRE visible y
// "Siguiente/Empezar" al final. Al terminar (o saltar) marca
// `onboarding_visto` en SharedPreferences y deja seguir a la app.
//
// 100% local: no consume datos ni red.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../services/onboarding_service.dart';

class OnboardingSlidesScreen extends StatefulWidget {
  const OnboardingSlidesScreen({super.key});

  @override
  State<OnboardingSlidesScreen> createState() => _OnboardingSlidesScreenState();
}

class _OnboardingSlidesScreenState extends State<OnboardingSlidesScreen> {
  final _pageCtrl = PageController();
  int _indice = 0;

  static const _slides = [
    _Slide(
      icono: Icons.storefront_rounded,
      titulo: 'Bienvenido a Al Lado',
      descripcion:
          'El mercado de La Habana en tu bolsillo: comprá y vendé '
          'localmente con conexiones reales.',
      color: AppColors.primary,
    ),
    _Slide(
      icono: Icons.verified_user_rounded,
      titulo: 'Compra con confianza',
      descripcion:
          'Tiendas verificadas, productos cerca de ti y conversión '
          'automática de precios USD/CUP según la tasa del día.',
      color: AppColors.success,
    ),
    _Slide(
      icono: Icons.sell_rounded,
      titulo: 'Vende y crece',
      descripcion:
          'Creá tu tienda en minutos, publicá productos, gestioná '
          'pedidos y promocioná tu negocio con anuncios.',
      color: AppColors.warm,
    ),
    _Slide(
      icono: Icons.rocket_launch_rounded,
      titulo: 'Listo para empezar',
      descripcion:
          'Navegá el mapa, guardá favoritos y recibí notificaciones. '
          'Iniciá sesión cuando quieras comprar o vender.',
      color: AppColors.primaryDark,
    ),
  ];

  bool get _esUltimo => _indice >= _slides.length - 1;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _avanzar() {
    if (_esUltimo) {
      _finalizar();
    } else {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _finalizar() async {
    await OnboardingService.instance.marcarVisto();
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final fondo = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: fondo,
      body: SafeArea(
        child: Column(
          children: [
            // Botón "Saltar" SIEMPRE visible (regla del diseño).
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: TextButton.icon(
                  onPressed: _finalizar,
                  icon: const Icon(Icons.skip_next_rounded, size: 20),
                  label: const Text('Saltar'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _indice = i),
                itemBuilder: (context, i) => _SlideWidget(slide: _slides[i]),
              ),
            ),
            // Indicador de puntos + navegación inferior.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (i) {
                      final activo = i == _indice;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: activo ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: activo
                              ? AppColors.primary
                              : AppColors.inkSecundarioLight.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      if (_indice > 0)
                        IconButton(
                          onPressed: () => _pageCtrl.previousPage(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                          ),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: FilledButton(
                            onPressed: _avanzar,
                            child: Text(
                              _esUltimo ? 'Empezar' : 'Siguiente',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Podés saltar y volver en "Preguntas frecuentes".',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: esOscuro
                          ? AppColors.inkSecundarioDark
                          : AppColors.inkSecundarioLight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final IconData icono;
  final String titulo;
  final String descripcion;
  final Color color;

  const _Slide({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.color,
  });
}

class _SlideWidget extends StatelessWidget {
  final _Slide slide;

  const _SlideWidget({required this.slide});

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final texto = esOscuro ? AppColors.inkDark : AppColors.inkLight;
    final secundario =
        esOscuro ? AppColors.inkSecundarioDark : AppColors.inkSecundarioLight;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [slide.color.withOpacity(0.25), slide.color.withOpacity(0.08)],
              ),
              border: Border.all(color: slide.color.withOpacity(0.2), width: 2),
            ),
            child: Icon(slide.icono, color: slide.color, size: 72),
          ),
          const SizedBox(height: 40),
          Text(
            slide.titulo,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: texto,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            slide.descripcion,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              height: 1.5,
              color: secundario,
            ),
          ),
        ],
      ),
    );
  }
}