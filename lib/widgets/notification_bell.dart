// notification_bell.dart
//
// Ícono de campana con badge de no-leídas -- pieza ÚNICA para toda la
// app. Antes existían DOS implementaciones distintas: este widget (que
// nadie usaba en Home) y una copia inline dentro de home_screen.dart
// con su propio Stack/Positioned y Navigator.push() en vez de
// context.push() de go_router. Esa duplicación es la causa de:
//   1. El look inconsistente ("de palo") entre Home y el resto de la
//      app -- esta versión ahora sí usa AppColors + plusJakartaSans.
//   2. El choque visual con el ícono vecino (Tasa de Cambio) en el
//      AppBar de Home -- el badge quedaba muy pegado al borde del
//      IconButton siguiente. Se ajustó el offset y se le puso un
//      borde de contraste para que se distinga bien sin invadir el
//      área táctil del ícono de al lado.
//   3. Navegación mixta (Navigator.push vs context.push) que podía
//      dejar rutas "huérfanas" fuera del stack de go_router. Ahora
//      SIEMPRE usa context.push('/notificaciones').
//
// Uso: reemplaza cualquier IconButton/Stack de campana a mano por
// simplemente `const NotificationBell()`.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../services/notificaciones_service.dart';

class NotificationBell extends StatelessWidget {
  /// Color del ícono e badge-border. Si no se pasa, usa el color de
  /// IconTheme actual (blanco en el AppBar coral de Home, oscuro/claro
  /// según el tema en el resto de pantallas).
  final Color? iconColor;

  const NotificationBell({super.key, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final colorIcono = iconColor ?? IconTheme.of(context).color;

    return AnimatedBuilder(
      animation: NotificacionesService.instance,
      builder: (context, _) {
        final noLeidas = NotificacionesService.instance.noLeidas;
        return SizedBox(
          // Ancho fijo = mismo hitbox que cualquier otro IconButton del
          // AppBar, así el badge nunca se sale de su propia "celda" ni
          // invade el ícono vecino.
          width: 48,
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.notifications_outlined, color: colorIcono),
                tooltip: 'Notificaciones',
                onPressed: () => context.push('/notificaciones'),
              ),
              if (noLeidas > 0)
                Positioned(
                  // Ligeramente más adentro que antes (10/10 en vez de
                  // 6/6) para que el badge quede sobre el ícono y no
                  // sobre el padding compartido con el próximo botón.
                  top: 6,
                  right: 6,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      height: 17,
                      constraints: const BoxConstraints(minWidth: 17),
                      decoration: BoxDecoration(
                        color: AppColors.warm,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          // Borde de contraste: separa visualmente el
                          // badge del fondo del AppBar (coral o
                          // superficie oscura) para que no se "funda".
                          color: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? AppColors.backgroundDark
                              : Colors.white,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        noLeidas > 9 ? '9+' : '$noLeidas',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}