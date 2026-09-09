// connectivity_service.dart
//
// Fuente única de verdad de "¿hay conexión ahora?". No basta con la
// interfaz de red (wifi conectado a un router sin internet reporta
// "conectado" igual) -- se hace un lookup real a un host. Al
// recuperar conexión dispara PendingActionsQueue.procesarCola() sola.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'pending_actions_queue.dart';

class ConnectivityService extends ChangeNotifier {
  ConnectivityService._();
  static final instance = ConnectivityService._();

  bool _online = true;
  bool get online => _online;

  StreamSubscription? _sub;
  Timer? _timer;

  void iniciar() {
    _verificar();
    _sub = Connectivity().onConnectivityChanged.listen((_) => _verificar());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _verificar());
  }

  Future<void> _verificar() async {
    bool nuevo;
    try {
      final r = await InternetAddress.lookup('supabase.co')
          .timeout(const Duration(seconds: 4));
      nuevo = r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      nuevo = false;
    }
    if (nuevo != _online) {
      _online = nuevo;
      notifyListeners();
      if (_online) PendingActionsQueue.instance.procesarCola();
    }
  }

  /// Chequeo puntual bajo demanda, antes de intentar una acción que
  /// requiere red (ej. al tocar "Completar Compra").
  Future<bool> chequearAhora() async {
    await _verificar();
    return _online;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
