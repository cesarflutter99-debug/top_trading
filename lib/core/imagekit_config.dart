// imagekit_config.dart
//
// Solo credenciales PÚBLICAS de ImageKit -- son seguras de tener en
// el código de la app porque, sin la private key, no sirven para
// subir ni borrar nada (necesitan la firma que genera la Edge
// Function imagekit-auth). La private key NUNCA va en este archivo:
// vive como secret en Supabase (IMAGEKIT_PRIVATE_KEY).
class ImageKitConfig {
  static const String publicKey = 'public_wG1ciMQ8PcexrPOCNU9F7Dl3SIs=';
  static const String urlEndpoint = 'https://ik.imagekit.io/alLado';
}
