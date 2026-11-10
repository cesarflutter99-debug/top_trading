// app_links_config.dart
//
// Configuración de los enlaces compartidos (App Links https).
//
// TODO(dominio): cuando tengas el dominio, cambia SOLO este valor por
// tu subdominio (ej. 'app.tudominio.com') y súbelo también a:
//   - AndroidManifest.xml  -> android:host (2 intents: tienda/anuncio/afiliado)
//   - assetlinks.json       -> host https://<subdominio>/.well-known/assetlinks.json
//   - Runner.entitlements   -> applinks:<subdominio>
//   - AASA (iOS)            -> https://<subdominio>/.well-known/apple-app-site-association
//
// Los links quedan así: https://<subdominio>/tienda/{id}[?producto={id}],
// https://<subdominio>/anuncio/{id}, https://<subdominio>/afiliado/{codigo}.
// Dominio de la página de descarga (Cloudflare Worker). Los enlaces
// compartidos usan este dominio para que, si la app está instalada,
// Android/iOS abra la app directamente (App Links / Universal Links);
// si no está instalada, se abre la página de descarga.
const String kDominioAppLinks = 'al-lado.elcesarrecord.workers.dev';

/// Link https a una tienda (opcionalmente a un producto dentro).
String kEnlaceTienda(String idTienda, [String? idProducto]) {
  final base = 'https://$kDominioAppLinks/tienda/$idTienda';
  if (idProducto == null || idProducto.isEmpty) return base;
  return '$base?producto=$idProducto';
}

/// Link https a un anuncio.
String kEnlaceAnuncio(String idAnuncio) =>
    'https://$kDominioAppLinks/anuncio/$idAnuncio';

/// Link https al código de afiliado.
String kEnlaceAfiliado(String codigo) =>
    'https://$kDominioAppLinks/afiliado/$codigo';