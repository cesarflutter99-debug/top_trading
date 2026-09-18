// deep_link_service.dart
//
// Navegación entrante por deep link. Acepta DOS formatos:
//
//   A) Esquema custom (redirige por compatibilidad):
//      io.supabase.toptrading://tienda/{id}?producto={id}   -> /tienda/{id}
//      io.supabase.toptrading://anuncio/{id}                -> /anuncio/{id}
//      io.supabase.toptrading://afiliado/{codigo}           -> /afiliado/{codigo}
//
//   B) App Links https (los que se comparten; clicables en cualquier app):
//      https://<kDominioAppLinks>/tienda/{id}[?producto={id}]
//      https://<kDominioAppLinks>/anuncio/{id}
//      https://<kDominioAppLinks>/afiliado/{codigo}
//
// Usa AppLinks directamente. Es un SINGLETON por plataforma: la misma
// instancia que ya usa supabase_flutter para el callback de login, así
// que agregar aquí un listener no interfiere -- supabase filtra los
// links que no son de auth y nosotros filtramos los que no son de
// navegación (login-callback se ignora acá).
//
// Importante: la escucha comienza al arrancar la app (main.dart) para
// capturar tanto el link que la abrió (cold start) como los que llegan
// con la app en primer plano.

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import '../router.dart';

class DeepLinkService {
  static final DeepLinkService instance = DeepLinkService._();
  DeepLinkService._();

  bool _iniciado = false;

  void iniciar() {
    if (_iniciado) return;
    _iniciado = true;
    // En mobile, el link inicial también llega por este stream (así lo
    // hacen las llamadas "getInitialLink" de supabase en web; en móvil
    // no hace falta leerlo aparte).
    AppLinks().uriLinkStream.listen(_procesar, onError: (Object e, StackTrace st) {
      debugPrint('error escuchando deep links: $e');
    });
  }

  void _procesar(Uri uri) {
    if (uri.scheme == 'https') {
      _procesarHttps(uri);
      return;
    }
    if (uri.scheme != 'io.supabase.toptrading') return;
    final host = uri.host;
    final segmento = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    if (segmento.isEmpty) return;

    switch (host) {
      case 'tienda':
        final producto = uri.queryParameters['producto'];
        router.go(producto != null && producto.isNotEmpty
            ? '/tienda/$segmento?producto=$producto'
            : '/tienda/$segmento');
      case 'anuncio':
        router.go('/anuncio/$segmento');
      case 'afiliado':
        router.go('/afiliado/$segmento');
    }
    debugPrint('deep link procesado: $uri');
  }

  /// App Links https: https://<dominio>/anuncio/{id} etc.
  void _procesarHttps(Uri uri) {
    final segmentos = uri.pathSegments;
    if (segmentos.length < 2) return;
    final ruta = segmentos[0];
    final id = segmentos[1];
    if (id.isEmpty) return;

    switch (ruta) {
      case 'tienda':
        final producto = uri.queryParameters['producto'];
        router.go(producto != null && producto.isNotEmpty
            ? '/tienda/$id?producto=$producto'
            : '/tienda/$id');
      case 'anuncio':
        router.go('/anuncio/$id');
      case 'afiliado':
        router.go('/afiliado/$id');
    }
    debugPrint('app link procesado: $uri');
  }
}