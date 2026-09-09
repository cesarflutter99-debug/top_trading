// negocios_service.dart
//
// Cliente de la tabla `negocios` (barberías, talleres, joyerías...).
// RLS: cualquiera lee los estado='activo'; el dueño además los suyos.
// Toda consulta es tolerante a fallos -- si no hay red la mini-página
// muestra "no disponible" en vez de romper.

import 'package:flutter/foundation.dart';
import '../core/supabase_client.dart';
import 'cache_offline_service.dart';

class NegociosService {
  /// Mini-página completa de un negocio.
  Future<Map<String, dynamic>?> obtenerNegocio(String idNegocio) async {
    try {
      final res = await supabase
          .from('negocios')
          .select()
          .eq('id_negocio', idNegocio)
          .maybeSingle();
      if (res != null) {
        CacheOfflineService.instance.guardar('negocio_$idNegocio', res);
      }
      return res == null ? null : Map<String, dynamic>.from(res);
    } catch (e) {
      // OFFLINE: mostramos la última copia vista de este negocio
      debugPrint('obtenerNegocio falló (¿offline?): $e');
      return CacheOfflineService.instance.leerMapa('negocio_$idNegocio');
    }
  }

  /// Pines del mapa: solo activos con coordenadas.
  Future<List<Map<String, dynamic>>> obtenerNegociosParaMapa() async {
    try {
      final res = await supabase
          .from('negocios')
          .select('id_negocio, nombre, categoria, logo_url, latitud, longitud')
          .eq('estado', 'activo')
          .not('latitud', 'is', null)
          .not('longitud', 'is', null);
      final lista = List<Map<String, dynamic>>.from(res as List);
      CacheOfflineService.instance.guardar('negocios_mapa', lista);
      return lista;
    } catch (e) {
      debugPrint('obtenerNegociosParaMapa falló (¿offline?): $e');
      return CacheOfflineService.instance.leerLista('negocios_mapa');
    }
  }

  /// Registra el negocio del usuario. Siempre nace estado='pendiente':
  /// el admin lo aprueba desde su panel antes de que sea público.
  /// Devuelve el id_negocio creado (o lanza la excepción original).
  Future<String> crearNegocio({
    required String nombre,
    required String whatsapp,
    required double lat,
    required double lon,
    String? categoria,
    String? descripcion,
    String? logoUrl,
    String? portadaUrl,
    String? direccion,
    Object? horario, // jsonb ya serializado o Map
    Object? listaPrecios,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('SESION_REQUERIDA');

    final res = await supabase
        .from('negocios')
        .insert({
          'id_dueno': uid,
          'nombre': nombre,
          'whatsapp': whatsapp,
          'latitud': lat,
          'longitud': lon,
          if (categoria != null && categoria.isNotEmpty) 'categoria': categoria,
          if (descripcion != null && descripcion.isNotEmpty)
            'descripcion': descripcion,
          if (logoUrl != null && logoUrl.isNotEmpty) 'logo_url': logoUrl,
          if (portadaUrl != null && portadaUrl.isNotEmpty)
            'portada_url': portadaUrl,
          if (direccion != null && direccion.isNotEmpty) 'direccion': direccion,
          if (horario != null) 'horario': horario,
          if (listaPrecios != null) 'lista_precios': listaPrecios,
        })
        .select('id_negocio')
        .single();
    return res['id_negocio'] as String;
  }

  /// Reemplaza COMPLETO la lista de precios/servicios del negocio propio
  /// ({'nombre','precio'} por fila). RLS: solo el dueño puede actualizar
  /// su fila en negocios. Pasar null o lista vacía ELIMINA la lista.
  Future<void> actualizarListaPrecios(
      String idNegocio, Object? listaPrecios) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('SESION_REQUERIDA');
    await supabase.from('negocios').update({
      // jsonb acepta lista o null; el dueño es validado por RLS
      'lista_precios':
          (listaPrecios is List && listaPrecios.isEmpty) ? null : listaPrecios,
    }).eq('id_negocio', idNegocio);
    // Refrescamos el cache offline con el estado nuevo lo antes posible
    try {
      final actualizado =
          await supabase.from('negocios').select().eq('id_negocio', idNegocio).maybeSingle();
      if (actualizado != null) {
        CacheOfflineService.instance.guardar(
            'negocio_$idNegocio', Map<String, dynamic>.from(actualizado));
      }
    } catch (_) {}
  }
}
