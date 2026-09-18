// Servicio de comentarios de anuncios (Marketplace).
// Los conteos se mantienen en la base (triggers del parche
// parche_comentarios_anuncios.sql) en anuncios.total_comentarios.

import 'package:supabase_flutter/supabase_flutter.dart';

class AnuncioComentariosService {
  final _supabase = Supabase.instance.client;

  /// Devuelve el nombre visible del usuario actual (para guardar en el
  /// comentario junto con su id).
  String get nombreUsuarioActual {
    final meta = _supabase.auth.currentUser?.userMetadata;
    final nombre = meta?['full_name'] ?? meta?['name'] ?? meta?['nombre'];
    if (nombre is String && nombre.trim().isNotEmpty) return nombre.trim();
    final email = _supabase.auth.currentUser?.email;
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'Usuario';
  }

  /// Comentarios de un anuncio, mas recientes primero.
  Future<List<Map<String, dynamic>>> comentariosDe(String idAnuncio) async {
    final res = await _supabase
        .from('anuncio_comentarios')
        .select()
        .eq('id_anuncio', idAnuncio)
        .order('creado_en', ascending: false)
        .limit(300);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Publica un comentario. Rechaza textos ofensivos antes de enviar.
  Future<void> agregarComentario(String idAnuncio, String texto) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      throw Exception('Necesitas iniciar sesi\u00f3n para comentar.');
    }
    await _supabase.from('anuncio_comentarios').insert({
      'id_anuncio': idAnuncio,
      'id_usuario': uid,
      'nombre_usuario': nombreUsuarioActual,
      'texto': texto.trim(),
    });
  }

  /// Elimina un comentario (solo si es del propio usuario).
  Future<void> eliminarComentario(String idComentario) async {
    await _supabase
        .from('anuncio_comentarios')
        .delete()
        .eq('id_comentario', idComentario);
  }
}