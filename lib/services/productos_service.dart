// productos_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class ProductosService {
  final _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> buscarProductosCercanos({
    required double lat,
    required double lon,
    double radioKm = 5,
    double? precioMin,
    double? precioMax,
    int limite = 20,
  }) async {
    final data = await _supabase.rpc('productos_cercanos', params: {
      'lat_usuario': lat,
      'lon_usuario': lon,
      'radio_km': radioKm,
      'precio_min': precioMin,
      'precio_max': precioMax,
    });
    return List<Map<String, dynamic>>.from(data).take(limite).toList();
  }
}
