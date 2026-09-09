// notificaciones_service.dart
//
// Servicio singleton (mismo patrón que CartService y CurrencyService)
// que mantiene la lista de notificaciones del usuario actual en
// memoria, sincronizada en tiempo real vía Supabase Realtime.
//
// NUEVO: agregarLocal() -- para avisos que nacen en el dispositivo
// (resultado de una acción offline que se acaba de sincronizar) y no
// existen como fila en la tabla `notificaciones`. Se insertan igual
// en la lista para que aparezcan en la campanita/pantalla de
// notificaciones, pero no se guardan en el servidor ni se marcan
// "leída" ahí -- son 100% locales a este dispositivo.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';

class NotificacionesService extends ChangeNotifier {
  static final NotificacionesService instance = NotificacionesService._();
  NotificacionesService._();

  final List<Map<String, dynamic>> _notificaciones = [];
  RealtimeChannel? _canal;
  String? _uidCargado;
  bool _cargando = false;

  List<Map<String, dynamic>> get notificaciones =>
      List.unmodifiable(_notificaciones);

  int get noLeidas =>
      _notificaciones.where((n) => n['leida'] == false).length;

  bool get cargando => _cargando;

  /// Llamar una sola vez, justo después de un login exitoso (o en el
  /// arranque de la app si ya hay sesión activa). Trae el historial y
  /// abre el canal Realtime para lo que llegue después.
  ///
  /// Idempotente: si ya estamos cargados y escuchando al mismo usuario,
  /// no se re-subscribe ni se recarga. Esto evita las notificaciones
  /// duplicadas que ocurrían cuando auth_guard y HomeScreen.initState
  /// llamaban iniciar() casi a la vez (dos canales Realtime activos
  /// entregando el mismo INSERT).
  Future<void> iniciar() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    if (_uidCargado == userId && _canal != null) return;

    await limpiar();
    _uidCargado = userId;
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
            final nuevo = payload.newRecord;
            final id = nuevo['id_notificacion']?.toString();
            // Anti-duplicado: si el mismo registro ya está en la lista
            // (p. ej. dos canales entregando el INSERT), no lo repito.
            if (id != null &&
                _notificaciones.any((n) =>
                    n['id_notificacion']?.toString() == id)) {
              return;
            }
            _notificaciones.insert(0, nuevo);
            notifyListeners();
          },
        )
        .subscribe();
  }

  /// Inserta un aviso 100% local (no viene de Supabase) -- usado por
  /// PendingActionsQueue para avisar el resultado de una acción que
  /// se ejecutó offline y recién se sincronizó. Nunca requiere red ni
  /// escribe en la tabla remota.
  void agregarLocal({
    required String titulo,
    required String mensaje,
    String tipo = 'local',
  }) {
    _notificaciones.insert(0, {
      'id_notificacion': 'local_${DateTime.now().microsecondsSinceEpoch}',
      'titulo': titulo,
      'mensaje': mensaje,
      'tipo': tipo,
      'leida': false,
      'data': null,
      'creado_en': DateTime.now().toIso8601String(),
      'local': true,
    });
    notifyListeners();
  }

  Future<void> marcarLeida(String idNotificacion) async {
    final i = _notificaciones
        .indexWhere((n) => n['id_notificacion'] == idNotificacion);
    if (i == -1 || _notificaciones[i]['leida'] == true) return;

    _notificaciones[i] = {..._notificaciones[i], 'leida': true};
    notifyListeners();

    // Los avisos locales (offline sincronizados) no existen en la
    // tabla remota -- no hay nada que actualizar en el servidor.
    if (_notificaciones[i]['local'] == true) return;

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
  Future<void> limpiar() async {
    _canal?.unsubscribe();
    _canal = null;
    _uidCargado = null;
    _notificaciones.clear();
    notifyListeners();
  }
}