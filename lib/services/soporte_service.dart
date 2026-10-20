// soporte_service.dart
//
// Chat de soporte entre el usuario y el equipo de Al Lado.
// El usuario tiene un único chat abierto a la vez; los mensajes se
// sincronizan en tiempo real vía Realtime.
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';

class SoporteService {
  SoporteService._();
  static final instance = SoporteService._();

  /// Obtiene (o crea) el chat abierto del usuario actual.
  Future<String> obtenerOCrearChat() async {
    final uid = supabase.auth.currentUser!.id;
    final res = await supabase
        .from('soporte_chats')
        .select('id')
        .eq('id_usuario', uid)
        .eq('estado', 'abierto')
        .maybeSingle();
    if (res != null) return res['id'] as String;
    final ins = await supabase
        .from('soporte_chats')
        .insert({'id_usuario': uid})
        .select('id')
        .single();
    return ins['id'] as String;
  }

  Future<List<Map<String, dynamic>>> mensajes(String idChat) async {
    final res = await supabase
        .from('soporte_mensajes')
        .select()
        .eq('id_chat', idChat)
        .order('creado_en', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> enviar(String idChat, String contenido) async {
    final uid = supabase.auth.currentUser!.id;
    await supabase.from('soporte_mensajes').insert({
      'id_chat': idChat,
      'id_usuario': uid,
      'contenido': contenido,
      'es_admin': false,
    });
  }

  RealtimeChannel suscribir(String idChat, void Function() onChange) {
    final c = supabase.channel('soporte_$idChat');
    c.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'soporte_mensajes',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id_chat', value: idChat),
      callback: (_) => onChange(),
    );
    c.subscribe();
    return c;
  }
}
