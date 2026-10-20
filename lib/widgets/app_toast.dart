// app_toast.dart
//
// Aviso flotante ÚNICO para toda la app. Reemplaza a los SnackBar, que
// salían abajo y chocaban con los botones (carrito flotante, barra de
// navegación, etc.).
//
//   - Sale ARRIBA, debajo de la barra de estado.
//   - Con icono, letra en negrita y color según el tipo.
//   - Se adapta al modo claro/oscuro con AppColors.
//   - Si llega un aviso nuevo mientras hay uno visible, NO se apilan: el
//     aviso se actualiza en el mismo sitio con un pequeño "rebote" y se
//     reinicia el tiempo (ideal para "Agregado: Jabón · Llevas 3").
//   - Se puede cerrar tocándolo o deslizándolo hacia arriba.
//
// Uso:
//   AppToast.exito(context, 'Agregado: Jabón', subtitulo: 'Llevas 3 en tu carrito');
//   AppToast.error(context, 'No se pudo completar el pedido');
//   AppToast.aviso(context, 'Esta tienda no tiene ubicación registrada');
//   AppToast.info(context, 'Carrito vaciado');
//
// Para migrar un SnackBar viejo:
//   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('X')));
//   ->  AppToast.info(context, 'X');

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';

enum AppToastTipo { exito, error, aviso, info }

class _ToastDatos {
  final String mensaje;
  final String? subtitulo;
  final AppToastTipo tipo;
  const _ToastDatos({
    required this.mensaje,
    required this.tipo,
    this.subtitulo,
  });
}

class AppToast {
  AppToast._();

  static OverlayEntry? _entry;
  static ValueNotifier<_ToastDatos>? _notifier;
  static GlobalKey<_ToastHostState>? _key;
  static Timer? _timer;

  static void exito(BuildContext context, String mensaje,
          {String? subtitulo, Duration? duracion}) =>
      mostrar(context, mensaje,
          tipo: AppToastTipo.exito, subtitulo: subtitulo, duracion: duracion);

  static void error(BuildContext context, String mensaje,
          {String? subtitulo, Duration? duracion}) =>
      mostrar(context, mensaje,
          tipo: AppToastTipo.error,
          subtitulo: subtitulo,
          duracion: duracion ?? const Duration(milliseconds: 4200));

  static void aviso(BuildContext context, String mensaje,
          {String? subtitulo, Duration? duracion}) =>
      mostrar(context, mensaje,
          tipo: AppToastTipo.aviso,
          subtitulo: subtitulo,
          duracion: duracion ?? const Duration(milliseconds: 3200));

  static void info(BuildContext context, String mensaje,
          {String? subtitulo, Duration? duracion}) =>
      mostrar(context, mensaje,
          tipo: AppToastTipo.info, subtitulo: subtitulo, duracion: duracion);

  static void mostrar(
    BuildContext context,
    String mensaje, {
    AppToastTipo tipo = AppToastTipo.info,
    String? subtitulo,
    Duration? duracion,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _timer?.cancel();
    final datos =
        _ToastDatos(mensaje: mensaje, tipo: tipo, subtitulo: subtitulo);

    final entry = _entry;
    if (entry != null && _notifier != null) {
      // Ya hay un aviso visible: lo actualizamos en el mismo sitio.
      _notifier!.value = datos;
      _key?.currentState?.rebotar();
    } else {
      final notifier = ValueNotifier<_ToastDatos>(datos);
      final key = GlobalKey<_ToastHostState>();
      final nuevo = OverlayEntry(
        builder: (_) => _ToastHost(key: key, datos: notifier),
      );
      _notifier = notifier;
      _key = key;
      _entry = nuevo;
      overlay.insert(nuevo);
    }

    _timer = Timer(duracion ?? const Duration(milliseconds: 2600), ocultar);
  }

  static Future<void> ocultar() async {
    _timer?.cancel();
    final entry = _entry;
    final estado = _key?.currentState;
    if (entry == null) return;
    // Soltamos las referencias ya: si llega otro aviso mientras este se
    // cierra, nace uno nuevo sin pisar el que se está yendo.
    _entry = null;
    _notifier = null;
    _key = null;
    if (estado != null) {
      await estado.cerrar();
    }
    try {
      entry.remove();
    } catch (_) {}
  }
}

class _ToastHost extends StatefulWidget {
  final ValueNotifier<_ToastDatos> datos;
  const _ToastHost({super.key, required this.datos});

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost> with TickerProviderStateMixin {
  late final AnimationController _entrada = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final AnimationController _rebote = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _curva = CurvedAnimation(
    parent: _entrada,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<double> _escala = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.035), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.035, end: 1.0), weight: 60),
  ]).animate(CurvedAnimation(parent: _rebote, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    _entrada.forward();
  }

  void rebotar() {
    if (!mounted) return;
    _rebote.forward(from: 0);
  }

  Future<void> cerrar() async {
    if (!mounted) return;
    try {
      await _entrada.reverse();
    } catch (_) {}
  }

  @override
  void dispose() {
    _entrada.dispose();
    _rebote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 8;
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1.4),
          end: Offset.zero,
        ).animate(_curva),
        child: FadeTransition(
          opacity: _curva,
          child: ScaleTransition(
            scale: _escala,
            child: Material(
              type: MaterialType.transparency,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: AppToast.ocultar,
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) < -150) AppToast.ocultar();
                },
                child: ValueListenableBuilder<_ToastDatos>(
                  valueListenable: widget.datos,
                  builder: (context, datos, _) => _tarjeta(context, datos),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _colorDe(AppToastTipo tipo) {
    switch (tipo) {
      case AppToastTipo.exito:
        return AppColors.success;
      case AppToastTipo.error:
        return const Color(0xFFFF3B30);
      case AppToastTipo.aviso:
        return AppColors.warm;
      case AppToastTipo.info:
        return AppColors.primary;
    }
  }

  IconData _iconoDe(AppToastTipo tipo) {
    switch (tipo) {
      case AppToastTipo.exito:
        return Icons.check_rounded;
      case AppToastTipo.error:
        return Icons.error_outline_rounded;
      case AppToastTipo.aviso:
        return Icons.warning_amber_rounded;
      case AppToastTipo.info:
        return Icons.info_outline_rounded;
    }
  }

  Widget _tarjeta(BuildContext context, _ToastDatos d) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final color = _colorDe(d.tipo);
    final tinta = oscuro ? AppColors.inkDark : AppColors.inkLight;
    final tintaSec = oscuro ? const Color(0xFFD1D1D6) : const Color(0xFF636366);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      decoration: BoxDecoration(
        color: oscuro ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.45), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(oscuro ? 0.55 : 0.14),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(_iconoDe(d.tipo), color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.mensaje,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: tinta,
                    height: 1.25,
                  ),
                ),
                if (d.subtitulo != null && d.subtitulo!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    d.subtitulo!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: tintaSec,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
