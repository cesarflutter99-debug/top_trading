import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../core/supabase_client.dart';

/// Maneja la selección y subida de fotos de productos al bucket
/// público "productos" en Supabase Storage.
class StorageService {
  static const String _bucket = 'productos';
  final ImagePicker _picker = ImagePicker();

  /// Abre galería o cámara y devuelve el archivo elegido (o null si canceló)
  Future<File?> elegirFoto({bool desdeCamara = false}) async {
    final XFile? archivo = await _picker.pickImage(
      source: desdeCamara ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1280,
      imageQuality: 80, // comprime para no gastar datos móviles
    );
    if (archivo == null) return null;
    return File(archivo.path);
  }

  /// Sube la foto y devuelve la URL pública para guardar en
  /// productos.imagen_url
  Future<String> subirFotoProducto({
    required File archivo,
    required String idTienda,
  }) async {
    final nombreArchivo =
        '$idTienda/${DateTime.now().millisecondsSinceEpoch}.jpg';

    await supabase.storage.from(_bucket).upload(nombreArchivo, archivo);

    return supabase.storage.from(_bucket).getPublicUrl(nombreArchivo);
  }

  /// Sube el logo/foto de perfil de la tienda al bucket público "tiendas"
  /// y devuelve la URL pública para guardar en tiendas.logo_url.
  /// Requiere crear el bucket "tiendas" (público) en Supabase Storage.
  Future<String> subirLogoTienda({
    required File archivo,
    required String idTienda,
  }) async {
    final nombreArchivo =
        '$idTienda/logo_${DateTime.now().millisecondsSinceEpoch}.jpg';

    await supabase.storage.from('tiendas').upload(
          nombreArchivo,
          archivo,
          fileOptions: FileOptions(upsert: true),
        );

    return supabase.storage.from('tiendas').getPublicUrl(nombreArchivo);
  }

  /// Sube la foto de portada de la tienda al bucket público "tiendas"
  /// y devuelve la URL pública para guardar en tiendas.imagen_portada.
  Future<String> subirPortadaTienda({
    required File archivo,
    required String idTienda,
  }) async {
    final nombreArchivo =
        '$idTienda/portada_${DateTime.now().millisecondsSinceEpoch}.jpg';

    await supabase.storage.from('tiendas').upload(
          nombreArchivo,
          archivo,
          fileOptions: FileOptions(upsert: true),
        );

    return supabase.storage.from('tiendas').getPublicUrl(nombreArchivo);
  }

  /// Sube la foto del QR de pago (generado manualmente por el admin,
  /// ej. desde Transfermóvil/Enzona) al bucket público "planes" y
  /// devuelve la URL pública para guardar en planes.qr_url.
  /// Requiere crear el bucket "planes" (público) en Supabase Storage.
  Future<String> subirQrPlan({
    required File archivo,
    required String idPlan,
  }) async {
    final nombreArchivo =
        '$idPlan/qr_${DateTime.now().millisecondsSinceEpoch}.jpg';

    await supabase.storage.from('planes').upload(
          nombreArchivo,
          archivo,
          fileOptions: FileOptions(upsert: true),
        );

    return supabase.storage.from('planes').getPublicUrl(nombreArchivo);
  }

  /// Sube la foto opcional que el comprador adjunta al valorar un
  /// pedido, al bucket público "valoraciones", y devuelve la URL para
  /// guardar en valoraciones.foto_url.
  /// Requiere crear el bucket "valoraciones" (público) en Supabase Storage.
  Future<String> subirFotoValoracion({
    required File archivo,
    required String idPedido,
  }) async {
    final nombreArchivo =
        '$idPedido/${DateTime.now().millisecondsSinceEpoch}.jpg';

    await supabase.storage.from('valoraciones').upload(
          nombreArchivo,
          archivo,
          fileOptions: FileOptions(upsert: true),
        );

    return supabase.storage.from('valoraciones').getPublicUrl(nombreArchivo);
  }

  /// Borra todas las fotos de una tienda (logo, portada, productos) de
  /// Storage antes de eliminarla de la base de datos -- si no, los
  /// archivos quedan huérfanos ocupando espacio para siempre, ya que
  /// borrar la fila de `tiendas` no borra nada del bucket.
  /// No lanza excepción si algo falla acá: preferimos que la tienda se
  /// borre igual aunque la limpieza de Storage falle parcialmente.
  Future<void> borrarArchivosDeTienda(String idTienda) async {
    for (final bucket in ['tiendas', 'productos']) {
      try {
        final archivos =
            await supabase.storage.from(bucket).list(path: idTienda);
        if (archivos.isNotEmpty) {
          final rutas = archivos.map((a) => '$idTienda/${a.name}').toList();
          await supabase.storage.from(bucket).remove(rutas);
        }
      } catch (_) {
        // Continúa con el siguiente bucket aunque este falle.
      }
    }
  }

  /// Borra la foto física del bucket (se usa junto con
  /// purgar_productos_inactivos() para liberar espacio)
  Future<void> borrarFoto(String imagenUrl) async {
    final path = imagenUrl.split('$_bucket/').last;
    await supabase.storage.from(_bucket).remove([path]);
  }
}
