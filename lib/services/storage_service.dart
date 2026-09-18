// storage_service.dart
//
// MIGRACIÓN A IMAGEKIT.IO (2026-09): por límite de capacidad de
// Supabase Storage, todas las subidas ahora van a ImageKit en vez de
// los buckets de Supabase. La clase se llama IGUAL (StorageService) y
// todos los métodos tienen EXACTAMENTE la misma firma que antes -- por
// eso ningún otro archivo de la app necesitó cambiar un solo import.
//
// FLUJO DE CADA SUBIDA:
//   1. Comprimir localmente con flutter_image_compress (agresivo --
//      ver _PresetCompresion abajo) ANTES de mandar nada por la red.
//   2. Pedir token/expire/signature a la Edge Function imagekit-auth
//      (la Private Key nunca sale del servidor).
//   3. Subir el archivo comprimido directo a ImageKit vía multipart/
//      form-data (upload.imagekit.io) usando esas credenciales.
//   4. Devolver la URL pública que ImageKit responde.
//
// BORRADO: ImageKit borra por fileId, no por path -- por eso
// borrarArchivosDeTienda() delega en la Edge Function imagekit-delete,
// que lista y borra del lado del servidor (también requiere Private
// Key, por eso no se puede hacer directo desde el cliente).
//
// REQUISITOS (ver guía de migración):
//   - pubspec.yaml: flutter_image_compress, http, path_provider
//   - Edge Functions deployadas: imagekit-auth, imagekit-delete
//   - Secret IMAGEKIT_PRIVATE_KEY seteado en Supabase (NO en Flutter)

import 'dart:convert';
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../core/imagekit_config.dart';
import '../core/supabase_client.dart';

const String _kUploadUrl = 'https://upload.imagekit.io/api/v1/files/upload';

/// Presets de compresión -- "agresivo" a propósito según el uso real
/// de cada imagen en la UI. No tiene sentido guardar un logo de
/// tienda (se ve en círculos de 40-90px) al mismo tamaño que la
/// portada de una tienda (banner ancho).
class _PresetCompresion {
  final int maxLado; // lado mayor en píxeles, se mantiene el aspect ratio
  final int calidad; // 0-100, JPEG
  const _PresetCompresion({required this.maxLado, required this.calidad});

  // Fotos de producto: se ven en grillas/detalle -- necesitan algo
  // más de nitidez que un avatar, pero 1280px es de sobra para
  // cualquier pantalla de celular.
  static const producto = _PresetCompresion(maxLado: 1280, calidad: 62);

  // Portadas (tienda/negocio/perfil): banners anchos, algo más de
  // resolución que un avatar pero igual de agresivo en calidad.
  static const portada = _PresetCompresion(maxLado: 1280, calidad: 58);

  // Logos/avatares/QR: se muestran chicos -- preset MUY agresivo,
  // acá es donde más se ahorra almacenamiento.
  static const avatar = _PresetCompresion(maxLado: 500, calidad: 55);

  // Anuncios/valoraciones: tamaño intermedio, se muestran en tarjetas
  // medianas del feed.
  static const mediano = _PresetCompresion(maxLado: 900, calidad: 60);
}

class StorageService {
  final ImagePicker _picker = ImagePicker();

  /// Abre galería o cámara y devuelve el archivo elegido (o null si
  /// canceló). Misma firma que la versión anterior -- la compresión
  /// fuerte real ocurre después, en _comprimir(), así que acá no hace
  /// falta exprimir calidad, solo evitar archivos gigantes de entrada.
  Future<File?> elegirFoto({bool desdeCamara = false}) async {
    final XFile? archivo = await _picker.pickImage(
      source: desdeCamara ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 90,
    );
    if (archivo == null) return null;
    return File(archivo.path);
  }

  // ---------------------------------------------------------------
  // COMPRESIÓN
  // ---------------------------------------------------------------

  Future<File> _comprimir(File original, _PresetCompresion preset) async {
    final dir = await getTemporaryDirectory();
    final destino =
        '${dir.path}/ik_${DateTime.now().microsecondsSinceEpoch}.jpg';

    final resultado = await FlutterImageCompress.compressAndGetFile(
      original.absolute.path,
      destino,
      quality: preset.calidad,
      minWidth: preset.maxLado,
      minHeight: preset.maxLado,
      format: CompressFormat.jpeg,
      keepExif: false, // menos metadata = archivo más chico
    );

    if (resultado == null) {
      // Si la compresión falla por algún motivo (formato raro, etc.),
      // seguimos con el original antes que bloquear la subida.
      return original;
    }
    return File(resultado.path);
  }

  // ---------------------------------------------------------------
  // AUTENTICACIÓN (token/expire/signature vía Edge Function)
  // ---------------------------------------------------------------

  Future<Map<String, dynamic>> _pedirCredencialesFirma() async {
    final res = await supabase.functions.invoke('imagekit-auth');
    if (res.status != 200) {
      throw Exception('No se pudo autenticar contra ImageKit: ${res.data}');
    }
    return Map<String, dynamic>.from(res.data as Map);
  }

  // ---------------------------------------------------------------
  // SUBIDA GENÉRICA
  // ---------------------------------------------------------------

  Future<String> _subir({
    required File archivo,
    required String carpeta,
    required String nombreArchivo,
    required _PresetCompresion preset,
  }) async {
    final comprimido = await _comprimir(archivo, preset);
    final creds = await _pedirCredencialesFirma();

    final request = http.MultipartRequest('POST', Uri.parse(_kUploadUrl))
          ..fields['publicKey'] = ImageKitConfig.publicKey
          ..fields['signature'] = creds['signature'] as String
          ..fields['expire'] = '${creds['expire']}'
          ..fields['token'] = creds['token'] as String
          ..fields['fileName'] = nombreArchivo
          ..fields['folder'] = '/$carpeta'
          ..fields['useUniqueFileName'] = 'false'
          ..files
              .add(await http.MultipartFile.fromPath('file', comprimido.path));

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception(
          'Error al subir a ImageKit (${streamed.statusCode}): $body');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    final url = json['url'] as String?;
    if (url == null) {
      throw Exception('ImageKit no devolvió una URL válida: $body');
    }
    return url;
  }

  // ---------------------------------------------------------------
  // MÉTODOS PÚBLICOS -- misma firma que la versión Supabase Storage
  // ---------------------------------------------------------------

  /// Sube la foto y devuelve la URL pública para guardar en
  /// productos.imagen_url
  Future<String> subirFotoProducto({
    required File archivo,
    required String idTienda,
  }) {
    final nombre = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    return _subir(
      archivo: archivo,
      carpeta: 'productos/$idTienda',
      nombreArchivo: nombre,
      preset: _PresetCompresion.producto,
    );
  }

  /// Sube el logo/foto de perfil de la tienda y devuelve la URL
  /// pública para guardar en tiendas.logo_url.
  Future<String> subirLogoTienda({
    required File archivo,
    required String idTienda,
  }) {
    final nombre = 'logo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return _subir(
      archivo: archivo,
      carpeta: 'tiendas/$idTienda',
      nombreArchivo: nombre,
      preset: _PresetCompresion.avatar,
    );
  }

  /// Sube la foto de portada de la tienda y devuelve la URL pública
  /// para guardar en tiendas.imagen_portada.
  Future<String> subirPortadaTienda({
    required File archivo,
    required String idTienda,
  }) {
    final nombre = 'portada_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return _subir(
      archivo: archivo,
      carpeta: 'tiendas/$idTienda',
      nombreArchivo: nombre,
      preset: _PresetCompresion.portada,
    );
  }

  /// Sube la foto del QR de pago y devuelve la URL pública para
  /// guardar en planes.qr_url.
  Future<String> subirQrPlan({
    required File archivo,
    required String idPlan,
  }) {
    final nombre = 'qr_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return _subir(
      archivo: archivo,
      carpeta: 'planes/$idPlan',
      nombreArchivo: nombre,
      preset: _PresetCompresion.avatar,
    );
  }

  /// Sube la foto de perfil personal del usuario y devuelve la URL
  /// pública. Se guarda en auth.users (user_metadata), no en tabla.
  Future<String> subirFotoPerfil({
    required File archivo,
    required String uid,
  }) {
    final nombre = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return _subir(
      archivo: archivo,
      carpeta: 'perfiles/$uid',
      nombreArchivo: nombre,
      preset: _PresetCompresion.avatar,
    );
  }

  /// Sube el logo del NEGOCIO (barbería, taller...) y devuelve la URL
  /// pública.
  Future<String> subirLogoNegocio({
    required File archivo,
    required String uid,
  }) {
    final nombre = 'logo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return _subir(
      archivo: archivo,
      carpeta: 'negocios/$uid',
      nombreArchivo: nombre,
      preset: _PresetCompresion.avatar,
    );
  }

  /// Sube la portada del negocio y devuelve la URL pública.
  Future<String> subirPortadaNegocio({
    required File archivo,
    required String uid,
  }) {
    final nombre = 'portada_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return _subir(
      archivo: archivo,
      carpeta: 'negocios/$uid',
      nombreArchivo: nombre,
      preset: _PresetCompresion.portada,
    );
  }

  /// Sube la imagen de un ANUNCIO (promo de tienda/negocio) y
  /// devuelve la URL pública.
  Future<String> subirImagenAnuncio({
    required File archivo,
    required String uid,
  }) {
    final nombre = 'anuncio_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return _subir(
      archivo: archivo,
      carpeta: 'anuncios/$uid',
      nombreArchivo: nombre,
      preset: _PresetCompresion.mediano,
    );
  }

  /// Sube la foto de portada del perfil personal (fondo del header de
  /// "Mi Perfil").
  Future<String> subirPortadaPerfil({
    required File archivo,
    required String uid,
  }) {
    final nombre = 'portada_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return _subir(
      archivo: archivo,
      carpeta: 'perfiles/$uid',
      nombreArchivo: nombre,
      preset: _PresetCompresion.portada,
    );
  }

  /// Sube la foto opcional que el comprador adjunta al valorar un
  /// pedido y devuelve la URL para guardar en valoraciones.foto_url.
  Future<String> subirFotoValoracion({
    required File archivo,
    required String idPedido,
  }) {
    final nombre = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    return _subir(
      archivo: archivo,
      carpeta: 'valoraciones/$idPedido',
      nombreArchivo: nombre,
      preset: _PresetCompresion.mediano,
    );
  }

  // ---------------------------------------------------------------
  // BORRADO -- vía Edge Function imagekit-delete (necesita Private
  // Key, por eso no se puede hacer directo desde el cliente).
  // ---------------------------------------------------------------

  /// Borra todas las fotos de una tienda (logo, portada, productos)
  /// antes de eliminarla de la base de datos -- si no, los archivos
  /// quedan huérfanos ocupando espacio para siempre. No lanza
  /// excepción si algo falla acá: preferimos que la tienda se borre
  /// igual aunque la limpieza en ImageKit falle parcialmente.
  Future<void> borrarArchivosDeTienda(String idTienda) async {
    for (final carpeta in ['tiendas/$idTienda', 'productos/$idTienda']) {
      try {
        await supabase.functions.invoke(
          'imagekit-delete',
          body: {'folder': carpeta},
        );
      } catch (_) {
        // Continúa con la siguiente carpeta aunque esta falle.
      }
    }
  }

  /// Borra la foto física del archivo EXACTO indicado por su URL.
  /// Antes esta operación borraba TODA la carpeta que contiene la URL
  /// (peligroso: las fotos de un producto comparten carpeta con las de
  /// los demás productos de la tienda). Ahora la Edge Function
  /// imagekit-delete acepta {file: ".../foto.jpg"} y la API la borra
  /// por ruta completa. No lanza si falla: se prefiere seguir.
  Future<void> borrarFoto(String imagenUrl) async {
    final uri = Uri.parse(imagenUrl);
    final segmentos = uri.pathSegments;
    if (segmentos.isEmpty) return;
    final ruta = '/' + segmentos.join('/');
    try {
      await supabase.functions.invoke(
        'imagekit-delete',
        body: {'file': ruta},
      );
    } catch (_) {}
  }

  /// Borra todas las fotos de un NEGOCIO (logo, portada) antes de
  /// eliminarlo de la base de datos -- si no, los archivos quedan
  /// huérfanos. No lanza excepción si algo falla acá.
  Future<void> borrarArchivosDeNegocio(String idNegocio) async {
    try {
      await supabase.functions.invoke(
        'imagekit-delete',
        body: {'folder': 'negocios/$idNegocio'},
      );
    } catch (_) {}
  }
}
