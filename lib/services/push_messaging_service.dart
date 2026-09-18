// push_messaging_service.dart
//
// Push FCM (Firebase Cloud Messaging) -- llega a la app aunque esté
// cerrada o en background. Se SUMA a las notificaciones in-app que ya
// entrega NotificacionesService vía Supabase Realtime:
//
//   - app ABIERTA (foreground):  el push se recibe por onMessage y se
//     re-envía hacia NotificacionesService para que la campanita/pantalla
//     lo muestren igual (no duplica: la fila ya llegó por Realtime, y si
//     por alguna razón no llegó, este aviso la pinta igual).
//   - app CERRADA/background: FCM muestra la notificación del sistema
//     con el logo de la app; al tocarla se abre la pantalla de
//     notificaciones.
//
// El token del dispositivo se guarda en la tabla `dispositivos` para que
// la Edge Function `notificar-push` (Supabase) pueda enviarle. Solo se
// registra cuando hay sesión; se borra al hacer logout.
//
// NOTA: requiere que exista `android/app/google-services.json` (Android)
// descargado de Firebase Console, y el servicio de background handler
// registrado en main.dart con Firebase.initializeApp().

import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/supabase_client.dart';
import '../router.dart';
import 'notificaciones_service.dart';

/// Handler de notificaciones cuando la app está CERRADA o en
/// background (proceso vivo). Solo puede tocar datos remotos o agendar
/// trabajo; aquí no dibujamos nada: el sistema ya muestra la
/// notificación. Esta función top-level es obligatoria y el kernel la
/// registra antes de arrancar la UI.
@pragma('vm:entry-point')
Future<void> pushManejadorDeFondo(RemoteMessage mensaje) async {
  // Nada que hacer en background: la notificación del sistema la pinta
  // FCM solo. Si en el futuro querés guardar algo aquí (ej. cache del
  // payload), hágalo acá.
}

class PushMessagingService {
  static final PushMessagingService instance = PushMessagingService._();
  PushMessagingService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Notificación local en primer plano (heads-up). No puede decidirse
  /// presentando en foreground el push de FCM: depende del dispositivo
  /// y en varios (Samsung, Pixel, Android 12-15) Play Services "delega"
  /// y los mensajes solo llegan con la app cerrada. Por eso, cuando un
  /// push llega con la app ABIERTA, lo mostramos nosotros con este
  /// plugin en el canal "notificaciones" (importancia alta) -- igual que
  /// el ejemplo oficial de flutterfire.
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static final AndroidNotificationChannel _canal = const AndroidNotificationChannel(
    'notificaciones', // mismo id del canal nativo (MainActivity) y el
    'Notificaciones', // channelId que usa la Edge Function
    description: 'Notificaciones de la app',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    enableLights: true,
  );
  static int _idsLocales = 0;

  bool _inicializado = false;

  /// Llama una sola vez en main(), después de Firebase.initializeApp().
  Future<void> inicializar() async {
    if (_inicializado) return;
    _inicializado = true;

    // Permisos: Android 13+ y iOS piden explícitamente.
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Canal de Android para que la notificación del sistema muestre el
    // logo de la app (la app crea el canal al arrancar). El id
    // "notificaciones" lo elige la Edge Function (channelId) y coincide
    // con el meta-data default_notification_channel_id del manifest.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Backend local para presentar el heads-up cuando la app está en
    // primer plano (ver doc de _local arriba).
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('launch_background'),
      ),
      onDidReceiveNotificationResponse: (resp) {
        // Tocar el heads-up de foreground lleva a la campanita.
        if (resp.payload == 'notificaciones') router.go('/notificaciones');
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_canal);

    // Notificaciones que llegan con la app en primer plano.
    FirebaseMessaging.onMessage.listen(_enForeground);

    // App abierta y el usuario toca la notificación.
    FirebaseMessaging.onMessageOpenedApp.listen(_alTocar);

    // App arrancada desde una notificación (la app estaba cerrada).
    final inicial = await _messaging.getInitialMessage();
    if (inicial != null) _alTocar(inicial);
  }

  /// Registra este dispositivo para recibir push del usuario SÍ el token
  /// cambió (cambia al reinstalar / borrar datos / rotar por seguridad).
  /// Guardamos el token en `dispositivos` (upsert por token: un mismo
  /// dispositivo puede re-loguarse con otra cuenta y debe actualizar su
  /// dueño).
  Future<void> registrarToken() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final token = await _messaging.getToken();
      if (token == null) return;

      await supabase.from('dispositivos').upsert(
            {
              'token': token,
              'user_id': user.id,
              'plataforma': Platform.isIOS ? 'ios' : 'android',
            },
            onConflict: 'token',
          );
    } catch (e) {
      // Si falla (sin red al arrancar, por ejemplo) no rompemos el
      // login; el siguiente registro de token lo reintenta.
      debugPrint('registrarToken falló: $e');
    }
  }

  /// Al cerrar sesión: borra el token de este dispositivo para que no
  /// reciba más push de una cuenta que ya no es la local.
  Future<void> limpiarToken() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      await supabase
          .from('dispositivos')
          .delete()
          .eq('token', token);
    } catch (_) {
      // Silencioso: el logout no debe romperse por un fallo acá.
    }
  }

  void _enForeground(RemoteMessage mensaje) {
    final data = mensaje.data;
    final titulo = mensaje.notification?.title ?? (data['titulo'] as String? ?? 'Nueva notificación');
    final cuerpo = mensaje.notification?.body ?? (data['mensaje'] as String? ?? '');
    final tipo = (data['tipo'] as String? ?? 'general');
    final dataStr = (data['data'] as String?)?.isNotEmpty == true ? data['data'] : null;

    // 1. In-app (campanita) - anti-duplicado
    NotificacionesService.instance.agregarPush(
      titulo: titulo,
      mensaje: cuerpo,
      tipo: tipo,
      data: dataStr,
    );

    // 2. Heads-up del sistema (visible aunque estés en la app)
    _presentarLocal(titulo: titulo, mensaje: cuerpo);
  }

  Future<void> _presentarLocal({
    required String titulo,
    required String mensaje,
  }) async {
    try {
      _idsLocales = (_idsLocales + 1) & 0x7FFFFFFF;

      // Asegurar que el canal existe (idempotente, fuerza heads-up en Android 12+)
      final androidImpl = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(_canal);

      await _local.show(
        id: _idsLocales,
        title: titulo,
        body: mensaje,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'notificaciones',
            'Notificaciones',
            channelDescription: 'Notificaciones de la app',
            importance: Importance.max,
            priority: Priority.high,
            icon: 'launch_background',
            visibility: NotificationVisibility.public,
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'notificaciones',
      );
    } catch (e) {
      debugPrint('_presentarLocal falló: $e');
    }
  }

  void _alTocar(RemoteMessage mensaje) {
    // El usuario tocó la notificación: vamos a la pantalla de
    // notificaciones. Usamos el router global (definido en router.dart)
    // para no depender de un BuildContext vivo -- el push puede
    // aterrizar justo cuando la app arranca.
    debugPrint('Push tocado: ${mensaje.notification?.title}');
    router.go('/notificaciones');
  }
}