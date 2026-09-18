// productos_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class ProductosService {
  final _supabase = Supabase.instance.client;

  /// Busca productos cercanos al usuario.
  /// Si se proveen [provincia] y/o [municipio], filtra los resultados
  /// para que solo traiga productos de tiendas ubicadas en ese lugar.
  Future<List<Map<String, dynamic>>> buscarProductosCercanos({
    required double lat,
    required double lon,
    double radioKm = 5,
    double? precioMin,
    double? precioMax,
    int limite = 20,
    String? provincia,
    String? municipio,
  }) async {
    final params = {
      'lat_usuario': lat,
      'lon_usuario': lon,
      'radio_km': radioKm,
      'precio_min': precioMin,
      'precio_max': precioMax,
      'provincia': provincia,
      'municipio': municipio,
    };
    final data = await _supabase.rpc('productos_cercanos', params: params);
    return List<Map<String, dynamic>>.from(data).take(limite).toList();
  }

  /// Retorna productos de una tienda específica.
  Future<List<Map<String, dynamic>>> productosDeTienda(String idTienda) async {
    final data = await _supabase
        .from('productos')
        .select()
        .eq('id_tienda', idTienda)
        .eq('estado', 'activo')
        .order('nombre');
    return List<Map<String, dynamic>>.from(data);
  }
}
