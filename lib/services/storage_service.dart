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

  /// Borra la foto física del bucket (se usa junto con
  /// purgar_productos_inactivos() para liberar espacio)
  Future<void> borrarFoto(String imagenUrl) async {
    final path = imagenUrl.split('$_bucket/').last;
    await supabase.storage.from(_bucket).remove([path]);
  }
}
