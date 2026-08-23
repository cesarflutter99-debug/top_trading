import 'package:supabase_flutter/supabase_flutter.dart';

/// Credenciales del proyecto Supabase.

/// publicar la app. No subas estas claves a un repositorio público.
class SupabaseConfig {
  static const String url = 'https://azcdjfqqxptouweqejvk.supabase.co';
  static const String publishableKey =
      'sb_publishable_0T_rXE32v3OnOqZWC0BC4Q_9oGjlJQJ';
}

/// Acceso rápido al cliente en cualquier parte de la app:
/// final res = await supabase.from('tiendas').select();
final supabase = Supabase.instance.client;

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
}
