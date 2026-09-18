package com.example.top_trading

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        crearCanalNotificaciones()
    }

    private fun crearCanalNotificaciones() {
        // Canal de FCM (Android 8+). El id "notificaciones" coincide con
        // el que usa la Edge Function (channelId) y con el meta-data
        // default_notification_channel_id del AndroidManifest.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val canal = NotificationChannel(
                "notificaciones",
                "Notificaciones",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notificaciones de la app"
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(canal)
        }
    }
}