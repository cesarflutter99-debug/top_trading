// anuncio_likes_service.dart
//
// Servicio para el sistema de "me gusta" del feed social de anuncios
// (ver anuncios_social_screen.dart). Requiere que exista la tabla
// `anuncio_likes` y la columna `anuncios.total_likes` -- ver
// sql/anuncio_likes.sql para el script de creación + triggers.
//
// AJUSTAR: si tu tabla `anuncios` usa otro nombre de columna PK
// distinto a `id_anuncio`, actualízalo en este archivo también.

import '../core/supabase_client.dart';

class AnuncioLikesService {
  /// true si el usuario actual ya le dio like a este anuncio.
  /// Con usuario invitado (sin sesión) siempre retorna false.
  Future<bool> yaLeDiLike(String idAnuncio) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    final res = await supabase
        .from('anuncio_likes')
        .select('id')
        .eq('id_anuncio', idAnuncio)
        .eq('id_usuario', uid)
        .maybeSingle();
    return res != null;
  }

  /// Da like. Lanza excepción si no hay sesión (el llamador debe
  /// haber verificado requireAuth() antes).
  Future<void> darLike(String idAnuncio) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('SESION_REQUERIDA');
    // El unique(id_anuncio, id_usuario) evita duplicados si el usuario
    // toca like dos veces muy rápido -- Postgres rechaza el segundo
    // insert con 23505, que ignoramos silenciosamente.
    try {
      await supabase.from('anuncio_likes').insert({
        'id_anuncio': idAnuncio,
        'id_usuario': uid,
      });
    } catch (e) {
      if (!e.toString().contains('23505')) rethrow;
    }
  }

  /// Quita el like del usuario actual.
  Future<void> quitarLike(String idAnuncio) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    await supabase
        .from('anuncio_likes')
        .delete()
        .eq('id_anuncio', idAnuncio)
        .eq('id_usuario', uid);
  }

  /// Alterna el estado de like. Devuelve el nuevo estado (true =
  /// ahora tiene like). Uso típico: actualizar el ícono al instante
  /// (optimista) ANTES de llamar esto, y revertir si lanza error.
  Future<bool> alternar(String idAnuncio, {required bool actualmenteConLike}) async {
    if (actualmenteConLike) {
      await quitarLike(idAnuncio);
      return false;
    } else {
      await darLike(idAnuncio);
      return true;
    }
  }

  /// Para pintar el feed completo de una sola vez: devuelve el set de
  /// ids de anuncio a los que el usuario actual ya les dio like, de
  /// entre la lista de ids visibles en pantalla. Evita 1 consulta por
  /// tarjeta.
  Future<Set<String>> misLikesDeLista(List<String> idsAnuncio) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || idsAnuncio.isEmpty) return {};
    final res = await supabase
        .from('anuncio_likes')
        .select('id_anuncio')
        .eq('id_usuario', uid)
        .inFilter('id_anuncio', idsAnuncio);
    return List<Map<String, dynamic>>.from(res)
        .map((r) => r['id_anuncio'] as String)
        .toSet();
  }
}
