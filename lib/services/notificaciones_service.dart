// notificaciones_service.dart
//
// Servicio singleton (mismo patrón que CartService y CurrencyService)
// que mantiene la lista de notificaciones del usuario actual en
// memoria, sincronizada en tiempo real vía Supabase Realtime.
//
// Se suscribe una sola vez (al hacer login) y notifica a toda la app
// cuando llega una notificación nueva, sin necesidad de refrescar
// manualmente ninguna pantalla.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';

class NotificacionesService extends ChangeNotifier {
  static final NotificacionesService instance = NotificacionesService._();
  NotificacionesService._();

  final List<Map<String, dynamic>> _notificaciones = [];
  RealtimeChannel? _canal;
  bool _cargando = false;

  List<Map<String, dynamic>> get notificaciones =>
      List.unmodifiable(_notificaciones);

  int get noLeidas =>
      _notificaciones.where((n) => n['leida'] == false).length;

  bool get cargando => _cargando;

  /// Llamar una sola vez, justo después de un login exitoso (o en el
  /// arranque de la app si ya hay sesión activa). Trae el historial y
  /// abre el canal Realtime para lo que llegue después.
  Future<void> iniciar() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    await _cargarHistorial(userId);
    _suscribirRealtime(userId);
  }

  Future<void> _cargarHistorial(String userId) async {
    _cargando = true;
    notifyListeners();
    try {
      final res = await supabase
          .from('notificaciones')
          .select()
          .eq('id_usuario', userId)
          .order('creado_en', ascending: false)
          .limit(100);
      _notificaciones
        ..clear()
        ..addAll(List<Map<String, dynamic>>.from(res));
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  void _suscribirRealtime(String userId) {
    _canal?.unsubscribe();
    _canal = supabase
        .channel('notificaciones_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notificaciones',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id_usuario',
            value: userId,
          ),
          callback: (payload) {
            _notificaciones.insert(0, payload.newRecord);
            notifyListeners();
          },
        )
        .subscribe();
  }

  Future<void> marcarLeida(String idNotificacion) async {
    final i = _notificaciones
        .indexWhere((n) => n['id_notificacion'] == idNotificacion);
    if (i == -1 || _notificaciones[i]['leida'] == true) return;

    // Optimista: se actualiza en memoria primero para que la UI
    // reaccione al instante, sin esperar la vuelta del servidor.
    _notificaciones[i] = {..._notificaciones[i], 'leida': true};
    notifyListeners();

    await supabase
        .from('notificaciones')
        .update({'leida': true}).eq('id_notificacion', idNotificacion);
  }

  Future<void> marcarTodasLeidas() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    for (var i = 0; i < _notificaciones.length; i++) {
      _notificaciones[i] = {..._notificaciones[i], 'leida': true};
    }
    notifyListeners();

    await supabase
        .from('notificaciones')
        .update({'leida': true})
        .eq('id_usuario', userId)
        .eq('leida', false);
  }

  /// Llamar al hacer logout, para no dejar el canal abierto escuchando
  /// datos de un usuario que ya cerró sesión.
  void limpiar() {
    _canal?.unsubscribe();
    _canal = null;
    _notificaciones.clear();
    notifyListeners();
  }
}