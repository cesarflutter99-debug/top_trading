import '../core/supabase_client.dart';

/// Encapsula todas las llamadas RPC/consultas relacionadas con tiendas,
/// productos y pedidos definidas en schema_top_trading.sql
class TiendasService {
  /// Carrusel de arriba: tiendas premium (validación manual del admin)
  Future<List<Map<String, dynamic>>> obtenerCarruselPremium() async {
    final res = await supabase.rpc('carrusel_premium');
    return List<Map<String, dynamic>>.from(res);
  }

  /// Carrusel de abajo: top trending semanal (automático, resetea lunes)
  Future<List<Map<String, dynamic>>> obtenerCarruselTrending(
      {int limite = 10}) async {
    final res = await supabase.rpc(
      'carrusel_top_trending',
      params: {'limite': limite},
    );
    return List<Map<String, dynamic>>.from(res);
  }

  /// Búsqueda geoespacial por proximidad (Haversine)
  Future<List<Map<String, dynamic>>> buscarTiendasCercanas({
    required double lat,
    required double lon,
    double radioKm = 10,
  }) async {
    final res = await supabase.rpc('buscar_tiendas_cercanas', params: {
      'lat_usuario': lat,
      'lon_usuario': lon,
      'radio_km': radioKm,
    });
    return List<Map<String, dynamic>>.from(res);
  }

  /// Crea un producto con su foto ya subida (imagenUrl).
  /// Si la tienda llegó al límite de su plan (20 basic / 50 premium),
  /// el trigger validar_limite_productos() lanza una excepción que
  /// hay que capturar en la UI.
  Future<void> crearProducto({
    required String idTienda,
    required String nombre,
    required double precioUsd,
    required String imagenUrl,
  }) async {
    await supabase.from('productos').insert({
      'id_tienda': idTienda,
      'nombre': nombre,
      'precio_usd': precioUsd,
      'imagen_url': imagenUrl,
    });
  }

  /// Elimina un producto puntual (usado tanto por el admin como,
  /// en el futuro, por el propio vendedor desde su panel).
  Future<void> eliminarProducto(String idProducto) async {
    await supabase.from('productos').delete().eq('id_producto', idProducto);
  }

  /// Crea la tienda del vendedor. Queda en estado 'pending' hasta que
  /// el admin la valide manualmente (Flujo 1 del documento maestro).
  Future<void> crearTienda({
    required String nombre,
    required String telefonoWhatsapp,
    required String provincia,
    required String municipio,
    required double lat,
    required double lon,
    required String plan,
  }) async {
    await supabase.from('tiendas').insert({
      'owner_id': supabase.auth.currentUser!.id,
      'nombre': nombre,
      'telefono_whatsapp': telefonoWhatsapp,
      'provincia': provincia,
      'municipio': municipio,
      'latitud': lat,
      'longitud': lon,
      'plan': plan,
      // estado queda 'pending' por defecto (definido en el esquema)
    });
  }

  /// Crea una tienda manualmente desde el panel de administrador
  /// (por ejemplo, para dar de alta un negocio que se registró fuera
  /// de la app). Queda 'active' de inmediato porque la crea el admin.
  ///
  /// NOTA: como 'owner_id' es NOT NULL en el esquema y esta tienda no
  /// tiene un vendedor real detrás todavía, se asigna temporalmente al
  /// propio admin que la crea. Si luego el negocio se suma como
  /// vendedor real, hay que reasignar 'owner_id' a su cuenta desde
  /// Supabase directamente (no hay UI para esto todavía).
  Future<void> crearTiendaManual({
    required String nombre,
    required String provincia,
    required String municipio,
    required String plan,
  }) async {
    await supabase.from('tiendas').insert({
      'owner_id': supabase.auth.currentUser!.id,
      'nombre': nombre,
      'provincia': provincia,
      'municipio': municipio,
      'plan': plan,
      'estado': 'active',
    });
  }

  /// Verifica si el usuario autenticado ya tiene una tienda creada,
  /// para saber si mandarlo al onboarding o directo a su panel.
  Future<Map<String, dynamic>?> obtenerMiTienda() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final res = await supabase
        .from('tiendas')
        .select()
        .eq('owner_id', userId)
        .maybeSingle();
    return res;
  }

  /// Crea un pedido (dispara el trigger anti-autoventa en el backend)
  Future<void> crearPedido({
    required String idTienda,
    required List<Map<String, dynamic>> detalle,
    required double totalUsd,
  }) async {
    await supabase.from('pedidos').insert({
      'id_tienda': idTienda,
      'id_comprador': supabase.auth.currentUser!.id,
      'detalle': detalle,
      'total_usd': totalUsd,
    });
  }

  /// El vendedor marca el pedido como completado (dispara +15 pts).
  ///
  /// FIX: antes solo se actualizaba 'estado', pero contarVentasDelMes()
  /// filtra por 'fecha_completado' >= inicio de mes. Sin poner esta
  /// fecha aquí mismo, el contador de "Vendidos este mes" siempre
  /// devolvía 0 (a menos que existiera un trigger en la base de datos
  /// que la llenara automáticamente, lo cual no está garantizado).
  Future<void> marcarPedidoCompletado(String idPedido) async {
    await supabase.from('pedidos').update({
      'estado': 'completado',
      'fecha_completado': DateTime.now().toIso8601String(),
    }).eq('id_pedido', idPedido);
  }

  /// Valora el pedido (dispara puntos por estrellas)
  Future<void> valorarPedido({
    required String idPedido,
    required String idTienda,
    required int estrellas,
    String? fotoUrl,
    String? comentario,
  }) async {
    await supabase.from('valoraciones').insert({
      'id_pedido': idPedido,
      'id_tienda': idTienda,
      'id_comprador': supabase.auth.currentUser!.id,
      'estrellas': estrellas,
      'foto_url': fotoUrl,
      'comentario': comentario,
    });
  }

  // ---------------------------------------------------------------------
  // PANEL DE ADMINISTRADOR
  // ---------------------------------------------------------------------

  /// Verifica si el usuario autenticado actual está en la tabla 'admins'.
  /// Se usa justo después del login (o al abrir la app con sesión
  /// guardada) para decidir si mandarlo al panel admin o al flujo
  /// normal de vendedor.
  Future<bool> esAdmin() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;

    final res = await supabase
        .from('admins')
        .select('id')
        .eq('user_id', userId)
        .maybeSingle();
    return res != null;
  }

  /// Lista todas las tiendas con estado 'pending' para revisión manual.
  Future<List<Map<String, dynamic>>> obtenerTiendasPendientes() async {
    final res = await supabase
        .from('tiendas')
        .select()
        .eq('estado', 'pending')
        .order('ultima_activacion', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Lista TODAS las tiendas (cualquier estado), para la pestaña
  /// "Tiendas y Productos" del panel de admin.
  Future<List<Map<String, dynamic>>> obtenerTodasLasTiendas() async {
    final res = await supabase
        .from('tiendas')
        .select()
        .order('nombre', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Aprueba una tienda: cambia su estado a 'active'.
  Future<void> aprobarTienda(String idTienda) async {
    await supabase
        .from('tiendas')
        .update({'estado': 'active'}).eq('id_tienda', idTienda);
  }

  /// Rechaza una tienda: cambia su estado a 'rechazada'.
  Future<void> rechazarTienda(String idTienda) async {
    await supabase
        .from('tiendas')
        .update({'estado': 'rechazada'}).eq('id_tienda', idTienda);
  }

  /// Elimina una tienda directamente desde el panel de admin
  /// (los productos se van con ella por ON DELETE CASCADE).
  Future<void> eliminarTiendaComoAdmin(String idTienda) async {
    await supabase.from('tiendas').delete().eq('id_tienda', idTienda);
  }

  /// Lista todos los números de WhatsApp configurados (activos e inactivos).
  Future<List<Map<String, dynamic>>> obtenerContactosWhatsapp() async {
    final res = await supabase
        .from('contactos_whatsapp')
        .select()
        .order('creado_en', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Devuelve el primer número activo, para usarlo en el flujo de
  /// verificación del onboarding y de gestionar_tienda_screen. Null
  /// si el admin no configuró ninguno.
  Future<String?> obtenerContactoWhatsappActivo() async {
    final res = await supabase
        .from('contactos_whatsapp')
        .select('telefono')
        .eq('activo', true)
        .order('creado_en', ascending: true)
        .limit(1)
        .maybeSingle();
    return res?['telefono'] as String?;
  }

  Future<void> agregarContactoWhatsapp({
    required String telefono,
    String? etiqueta,
  }) async {
    await supabase.from('contactos_whatsapp').insert({
      'telefono': telefono,
      'etiqueta': etiqueta,
      'activo': true,
    });
  }

  Future<void> actualizarActivoContactoWhatsapp({
    required String id,
    required bool activo,
  }) async {
    await supabase
        .from('contactos_whatsapp')
        .update({'activo': activo}).eq('id', id);
  }

  Future<void> eliminarContactoWhatsapp(String id) async {
    await supabase.from('contactos_whatsapp').delete().eq('id', id);
  }

  // ---------------------------------------------------------------------
  // PANEL DE VENDEDOR
  // ---------------------------------------------------------------------

  /// Lista todos los productos de una tienda (visibles y ocultos),
  /// para que el propio dueño (o el admin) los gestione.
  Future<List<Map<String, dynamic>>> obtenerProductosDeTienda(
      String idTienda) async {
    final res = await supabase
        .from('productos')
        .select()
        .eq('id_tienda', idTienda)
        .order('fecha_creacion', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Edita los datos básicos de la tienda del vendedor. No permite
  /// cambiar 'estado' -- eso solo lo hace el admin (aprobarTienda /
  /// rechazarTienda) -- ni 'plan', que se cambia desde
  /// gestionar_tienda_screen usando update directo a Supabase.
  Future<void> actualizarTienda({
    required String idTienda,
    required String nombre,
    required String telefonoWhatsapp,
    required String provincia,
    required String municipio,
  }) async {
    await supabase.from('tiendas').update({
      'nombre': nombre,
      'telefono_whatsapp': telefonoWhatsapp,
      'provincia': provincia,
      'municipio': municipio,
    }).eq('id_tienda', idTienda);
  }

  /// Actualiza la URL del logo/foto de perfil de la tienda.
  Future<void> actualizarLogoTienda({
    required String idTienda,
    required String logoUrl,
  }) async {
    await supabase
        .from('tiendas')
        .update({'logo_url': logoUrl}).eq('id_tienda', idTienda);
  }

  // ---------------------------------------------------------------------
  // GESTIONAR VENTAS
  // ---------------------------------------------------------------------

  /// Pedidos pendientes de confirmación de una tienda (solicitudes de
  /// venta que el vendedor todavía no marcó como completadas).
  Future<List<Map<String, dynamic>>> obtenerPedidosPendientes(
      String idTienda) async {
    final res = await supabase
        .from('pedidos')
        .select()
        .eq('id_tienda', idTienda)
        .eq('estado', 'pendiente')
        .order('fecha_creacion', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Cantidad de pedidos completados en el mes en curso (se reinicia
  /// automáticamente cada mes porque filtra por fecha_completado, que
  /// ahora se llena en marcarPedidoCompletado() -- ver fix arriba).
  Future<int> contarVentasDelMes(String idTienda) async {
    final inicioMes = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final res = await supabase
        .from('pedidos')
        .select('id_pedido')
        .eq('id_tienda', idTienda)
        .eq('estado', 'completado')
        .gte('fecha_completado', inicioMes.toIso8601String());
    return List.from(res).length;
  }
}
