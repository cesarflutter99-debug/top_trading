// cache_offline_service.dart
//
// Cache PERSISTENTE de lectura (SharedPreferences + JSON) para el modo
// offline: catálogos, tiendas, productos y negocios que se cargaron con
// conexión siguen navegables sin ella -- incluso después de cerrar y
// reabrir la app. Patrón "read-through": los servicios intentan la red;
// si falla devuelven la última copia guardada; si tienen éxito refrescan
// el cache. Las imágenes ya las cachea cached_network_image por su
// cuenta en disco.
//
// Este cache es SOLO LECTURA de contenido público: nunca guarda nada
// que dependa del usuario (pedidos, favoritos, panel del vendedor) para
// no mostrar datos sensibles viejos.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheOfflineService {
  CacheOfflineService._();
  static final instance = CacheOfflineService._();

  static const _prefijo = 'cache_offline_v1_';

  /// Guarda (o refresca) una copia. Fire & forget: jamás propaga errores.
  Future<void> guardar(String clave, Object? datos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefijo$clave',
        jsonEncode({
          'guardado_en': DateTime.now().toIso8601String(),
          'datos': datos,
        }),
      );
    } catch (_) {}
  }

  Future<Object?> _leerEnvuelto(String clave) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefijo$clave');
      if (raw == null) return null;
      return (jsonDecode(raw) as Map<String, dynamic>)['datos'];
    } catch (_) {
      return null;
    }
  }

  /// Devuelve la lista cacheada (vacía si no hay nada).
  Future<List<Map<String, dynamic>>> leerLista(String clave) async {
    final datos = await _leerEnvuelto(clave);
    if (datos is List) {
      return List<Map<String, dynamic>>.from(
          datos.map((e) => Map<String, dynamic>.from(e as Map)));
    }
    return [];
  }

  /// Devuelve el objeto cacheado (null si no hay nada).
  Future<Map<String, dynamic>?> leerMapa(String clave) async {
    final datos = await _leerEnvuelto(clave);
    if (datos is Map) return Map<String, dynamic>.from(datos);
    return null;
  }

  /// Borra una entrada puntual del cache -- usado, por ejemplo, cuando
  /// se elimina un negocio/tienda para que no quede una copia "fantasma"
  /// navegable en modo offline después de borrado. Fire & forget, igual
  /// que guardar(): nunca debe romper el flujo que la llama.
  Future<void> eliminar(String clave) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefijo$clave');
    } catch (_) {}
  }
}
