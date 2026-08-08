// notification_bell.dart
//
// Ícono de campana con badge de no-leídas, para poner en el AppBar de
// HomeScreen (o cualquier pantalla principal). Toca -> abre
// NotificationsScreen.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/notificaciones_service.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NotificacionesService.instance,
      builder: (context, _) {
        final noLeidas = NotificacionesService.instance.noLeidas;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Notificaciones',
              onPressed: () => context.push('/notificaciones'),
            ),
            if (noLeidas > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    noLeidas > 9 ? '9+' : '$noLeidas',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}