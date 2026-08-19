import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../core/supabase_client.dart';
import '../widgets/analytics_widgets.dart' show RangoAnalitica;

/// Categorías fijas de tienda -- usadas en el onboarding (crear
/// tienda), en "Gestionar Tienda" (editar categoría) y como filtro en
/// Home (feed de cercanos, modo Productos y Tiendas). Si se agrega o
/// renombra una categoría acá, hay que revisar también el filtro del
/// modal en home_screen.dart (usa estos mismos valores para comparar
/// contra la columna 'categoria' que devuelven los RPC de búsqueda).
const List<String> kCategoriasTienda = [
  'Ropa y Accesorios',
  'Calzado',
  'Móviles y Laptops',
  'Electrodomésticos',
  'Hogar y Muebles',
  'Alimentos y Bebidas',
  'Belleza y Cuidado Personal',
  'Salud y Farmacia',
  'Deportes y Fitness',
  'Ocio y Videojuegos',
  'Juguetes y Niños',
  'Mascotas',
  'Vehículos y Repuestos',
  'Transporte y Motor (vehículos completos)',
  'Ferretería y Construcción',
  'Energía, Electricidad y Solar',
  'Otros',
  'Variada',
];

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
    String? imagenUrl2,
    String? imagenUrl3,
    String? descripcion,
    int cantidadDisponible = 1,
    String? categoria,
  }) async {
    await supabase.from('productos').insert({
      'id_tienda': idTienda,
      'nombre': nombre,
      'precio_usd': precioUsd,
      'imagen_url': imagenUrl,
      if (imagenUrl2 != null) 'imagen_url_2': imagenUrl2,
      if (imagenUrl3 != null) 'imagen_url_3': imagenUrl3,
      'descripcion': descripcion,
      'cantidad_disponible': cantidadDisponible,
      if (categoria != null) 'categoria': categoria,
    });
  }

  /// Elimina un producto puntual (usado tanto por el admin como,
  /// en el futuro, por el propio vendedor desde su panel).
  Future<void> eliminarProducto(String idProducto) async {
    await supabase.from('productos').delete().eq('id_producto', idProducto);
  }

  /// Edita un producto existente. Solo actualiza los campos que
  /// vienen distintos de null (mismo patrón que actualizarTienda /
  /// actualizarPlan / actualizarAfiliado).
  Future<void> actualizarProducto({
    required String idProducto,
    String? nombre,
    double? precioUsd,
    String? imagenUrl,
    String? descripcion,
    int? cantidadDisponible,
    String? categoria,
  }) async {
    final data = <String, dynamic>{};
    if (nombre != null) data['nombre'] = nombre;
    if (precioUsd != null) data['precio_usd'] = precioUsd;
    if (imagenUrl != null) data['imagen_url'] = imagenUrl;
    if (descripcion != null) data['descripcion'] = descripcion;
    if (cantidadDisponible != null) {
      data['cantidad_disponible'] = cantidadDisponible;
    }
    if (categoria != null) data['categoria'] = categoria;
    if (data.isNotEmpty) {
      await supabase
          .from('productos')
          .update(data)
          .eq('id_producto', idProducto);
    }
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

  /// Trae los datos completos de una tienda por su id (nombre,
  /// descripción, ubicación, WhatsApp, etc.). Se usa en el modal de
  /// detalle de una solicitud de cambio de plan en el panel de admin
  /// y en el router para precargar la tienda antes de construir la
  /// pantalla correspondiente.
  Future<Map<String, dynamic>?> obtenerTiendaPorId(String idTienda) async {
    final res = await supabase
        .from('tiendas')
        .select()
        .eq('id_tienda', idTienda)
        .maybeSingle();
    return res;
  }

  /// Productos "destacados" de una tienda para vitrinas públicas (el
  /// mini-carrusel de fotos dentro del hero de Home, y el modal de
  /// preview al tocar una tienda). Solo lo que un comprador realmente
  /// podría comprar: visible y con stock.
  Future<List<Map<String, dynamic>>> obtenerProductosDestacadosDeTienda(
    String idTienda, {
    int limite = 4,
  }) async {
    final res = await supabase
        .from('productos')
        .select()
        .eq('id_tienda', idTienda)
        .eq('es_visible', true)
        .gt('cantidad_disponible', 0)
        .order('fecha_creacion', ascending: false)
        .limit(limite);
    return List<Map<String, dynamic>>.from(res);
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

  /// Igual que obtenerMiTienda(), pero para cualquier owner_id -- usado
  /// por el admin al ver "Información del vendedor" de otro usuario.
  Future<Map<String, dynamic>?> obtenerTiendaPorOwnerId(String ownerId) async {
    final res = await supabase
        .from('tiendas')
        .select()
        .eq('owner_id', ownerId)
        .maybeSingle();
    return res;
  }

  /// Crea un pedido (dispara el trigger anti-autoventa en el backend)
  Future<Map<String, dynamic>> crearPedido({
    required String idTienda,
    required List<Map<String, dynamic>> detalle,
    required double totalUsd,
  }) async {
    final res = await supabase
        .from('pedidos')
        .insert({
          'id_tienda': idTienda,
          'id_comprador': supabase.auth.currentUser!.id,
          'detalle': detalle,
          'total_usd': totalUsd,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(res);
  }

  /// El vendedor marca el pedido como completado (dispara +15 pts).
  /// También descuenta el stock vendido de cada producto -- antes esto
  /// no pasaba en ningún lado del flujo, así que el stock nunca bajaba
  /// aunque se vendiera. Devuelve la lista de productos que quedaron
  /// en 0 o por debajo de 10 unidades, para poder avisar al vendedor.
  ///
  /// FIX: antes solo se actualizaba 'estado', pero contarVentasDelMes()
  /// filtra por 'fecha_completado' >= inicio de mes. Sin poner esta
  /// fecha aquí mismo, el contador de "Vendidos este mes" siempre
  /// devolvía 0 (a menos que existiera un trigger en la base de datos
  /// que la llenara automáticamente, lo cual no está garantizado).
  Future<List<Map<String, dynamic>>> marcarPedidoCompletado(
      String idPedido) async {
    final pedido = await supabase
        .from('pedidos')
        .select('detalle')
        .eq('id_pedido', idPedido)
        .single();

    await supabase.from('pedidos').update({
      'estado': 'completado',
      'fecha_completado': DateTime.now().toIso8601String(),
    }).eq('id_pedido', idPedido);

    final detalle = (pedido['detalle'] as List?) ?? [];
    final productosBajoStock = <Map<String, dynamic>>[];

    for (final item in detalle) {
      final idProducto = item['id_producto'] as String?;
      final cantidadVendida = (item['cantidad'] as num?)?.toInt() ?? 0;
      if (idProducto == null || cantidadVendida <= 0) continue;

      final producto = await supabase
          .from('productos')
          .select('cantidad_disponible, nombre')
          .eq('id_producto', idProducto)
          .maybeSingle();
      if (producto == null) continue;

      final actual = (producto['cantidad_disponible'] as num?)?.toInt() ?? 0;
      final nuevo = actual - cantidadVendida;
      final nuevoClamp = nuevo < 0 ? 0 : nuevo;

      await supabase.from('productos').update(
          {'cantidad_disponible': nuevoClamp}).eq('id_producto', idProducto);

      if (nuevoClamp < 10) {
        productosBajoStock.add({
          'id_producto': idProducto,
          'nombre': producto['nombre'],
          'cantidad_disponible': nuevoClamp,
        });
      }
    }

    return productosBajoStock;
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

  /// Devuelve la fila de 'admins' (incluye 'permisos') para cualquier
  /// user_id -- usado por el admin al ver "Información del vendedor"
  /// de otro usuario, para saber si esa persona también es admin y con
  /// qué permisos.
  Future<Map<String, dynamic>?> obtenerPermisosAdmin(String userId) async {
    final res = await supabase
        .from('admins')
        .select()
        .eq('user_id', userId)
        .order('creado_en', ascending: false)
        .limit(1);
    final lista = List<Map<String, dynamic>>.from(res);
    return lista.isEmpty ? null : lista.first;
  }

  /// Quita a un usuario de la tabla 'admins' (le revoca el acceso).
  Future<void> eliminarAdmin(String userId) async {
    await supabase.from('admins').delete().eq('user_id', userId);
  }

  /// Tiendas activas con coordenadas, para pintar los pines del mapa
  /// interactivo. Solo trae lo que el pin/globito necesita mostrar --
  /// no todo el resto de columnas de 'tiendas'.
  Future<List<Map<String, dynamic>>> obtenerTiendasParaMapa() async {
    final res = await supabase
        .from('tiendas')
        .select(
            'id_tienda, nombre, logo_url, latitud, longitud, promedio_estrellas, plan, plan_expira_en')
        .eq('estado', 'active')
        .not('latitud', 'is', null)
        .not('longitud', 'is', null);
    return List<Map<String, dynamic>>.from(res);
  }

  // ---------------------------------------------------------------------
  // FAVORITOS (solo tiendas)
  // ---------------------------------------------------------------------

  Future<bool> esFavorito(String idTienda) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    final res = await supabase
        .from('favoritos')
        .select('id_tienda')
        .eq('id_usuario', uid)
        .eq('id_tienda', idTienda)
        .maybeSingle();
    return res != null;
  }

  Future<void> agregarFavorito(String idTienda) async {
    await supabase.from('favoritos').insert({
      'id_usuario': supabase.auth.currentUser!.id,
      'id_tienda': idTienda,
    });
  }

  Future<void> quitarFavorito(String idTienda) async {
    await supabase
        .from('favoritos')
        .delete()
        .eq('id_usuario', supabase.auth.currentUser!.id)
        .eq('id_tienda', idTienda);
  }

  /// Tiendas favoritas del usuario actual, con sus datos para mostrar
  /// en la pantalla de Favoritos (logo, nombre, valoración).
  Future<List<Map<String, dynamic>>> obtenerMisFavoritos() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return [];
    final res = await supabase
        .from('favoritos')
        .select(
            'id_tienda, fecha_guardado, tiendas(id_tienda, nombre, logo_url, promedio_estrellas, municipio, plan)')
        .eq('id_usuario', uid)
        .order('fecha_guardado', ascending: false);
    return List<Map<String, dynamic>>.from(res);
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

  /// Lista todos los afiliados (para el listado del panel de admin).
  /// La política RLS de 'afiliados' ya permite que un admin lea todas
  /// las filas (afiliados_lectura_propia_o_admin).
  Future<List<Map<String, dynamic>>> obtenerTodosLosAfiliados() async {
    final res = await supabase
        .from('afiliados')
        .select()
        .order('creado_en', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  /// Actualiza la URL de la foto de portada de la tienda.
  Future<void> actualizarPortadaTienda({
    required String idTienda,
    required String portadaUrl,
  }) async {
    await supabase
        .from('tiendas')
        .update({'imagen_portada': portadaUrl}).eq('id_tienda', idTienda);
  }

  /// Aprueba una tienda: cambia su estado a 'active' y, si se registró
  /// con un código de afiliado válido, acredita la comisión (10% del
  /// precio del plan) en este mismo momento -- no antes.
  Future<void> aprobarTienda(String idTienda, {double tasaCupUsd = 0}) async {
    await supabase.rpc('admin_aprobar_tienda', params: {
      'p_id_tienda': idTienda,
      'p_tasa_cup_usd': tasaCupUsd,
    });
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
    String? descripcion,
    String? categoria,
  }) async {
    await supabase.from('tiendas').update({
      'nombre': nombre,
      'telefono_whatsapp': telefonoWhatsapp,
      'provincia': provincia,
      'municipio': municipio,
      if (descripcion != null) 'descripcion': descripcion,
      if (categoria != null) 'categoria': categoria,
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
        .order('creado_en', ascending: true);
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

  /// Ventas totales (histórico, no solo del mes) de una tienda --
  /// para el modal de detalle de tienda del panel de admin.
  Future<Map<String, dynamic>> obtenerVentasTotalesTienda(
      String idTienda) async {
    final res = await supabase
        .from('pedidos')
        .select('total_usd')
        .eq('id_tienda', idTienda)
        .eq('estado', 'completado');
    final lista = List<Map<String, dynamic>>.from(res);
    final monto = lista.fold<double>(
        0, (acc, p) => acc + ((p['total_usd'] as num?)?.toDouble() ?? 0));
    return {'total_pedidos': lista.length, 'monto_total': monto};
  }

  /// Top productos más vendidos de una tienda específica (a diferencia
  /// de adminTopProductos(), que es global) -- suma las cantidades de
  /// cada línea de `pedidos.detalle` a través de todos los pedidos
  /// completados de esa tienda.
  Future<List<Map<String, dynamic>>> obtenerTopProductosTienda(String idTienda,
      {int limite = 3}) async {
    final res = await supabase
        .from('pedidos')
        .select('detalle')
        .eq('id_tienda', idTienda)
        .eq('estado', 'completado');
    final lista = List<Map<String, dynamic>>.from(res);
    final Map<String, int> conteo = {};
    for (final pedido in lista) {
      final detalle = pedido['detalle'];
      if (detalle is List) {
        for (final item in detalle) {
          final nombre = item['nombre'] as String? ?? 'Producto';
          final cantidad = (item['cantidad'] as num?)?.toInt() ?? 1;
          conteo[nombre] = (conteo[nombre] ?? 0) + cantidad;
        }
      }
    }
    final ordenado = conteo.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ordenado
        .take(limite)
        .map((e) => {'nombre': e.key, 'cantidad': e.value})
        .toList();
  }

  /// Lista completa de pedidos vendidos (completados) del mes actual,
  /// para la tarjeta "Ventas realizadas" en Gestionar Ventas -- a
  /// diferencia de contarVentasDelMes(), trae el detalle completo de
  /// cada pedido (productos, precios) para poder mostrarlo al tocar.
  Future<List<Map<String, dynamic>>> obtenerVentasDelMes(
      String idTienda) async {
    final inicioMes = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final res = await supabase
        .from('pedidos')
        .select()
        .eq('id_tienda', idTienda)
        .eq('estado', 'completado')
        .gte('fecha_completado', inicioMes.toIso8601String())
        .order('fecha_completado', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  // ---------------------------------------------------------------------
  // ADMIN - GESTIÓN DE PLANES Y SOLICITUDES
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>?> obtenerMiAdminInfo() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return null;
    final res =
        await supabase.from('admins').select().eq('user_id', uid).maybeSingle();
    return res;
  }

  Future<List<Map<String, dynamic>>> obtenerSolicitudesPendientes() async {
    final res = await supabase.rpc('admin_solicitudes_plan_pendientes');
    return List<Map<String, dynamic>>.from(res);
  }

  /// Chequeo interno compartido: ¿esta tienda ya usó este código de
  /// afiliado antes? Cubre las TRES formas en que pudo haberse usado:
  /// (a) en su registro original (tiendas.codigo_afiliado), (b) en una
  /// solicitud de cambio de plan previa que sigue pendiente o que ya
  /// fue aprobada, o (c) en un uso ya confirmado/acreditado
  /// (usos_afiliado). Regla de negocio: un código se usa una sola vez
  /// por tienda, sin importar si fue en el registro o en un upgrade.
  /// Reutilizado por validarCodigoAfiliadoParaTienda (validación en
  /// vivo mientras el usuario escribe) y por crearSolicitudCambioPlan
  /// (candado final del lado del servidor, por si alguien se salta la
  /// UI y llama al insert directo).
  Future<bool> _tiendaYaUsoCodigo(String idTienda, String codigo) async {
    final tienda = await supabase
        .from('tiendas')
        .select('codigo_afiliado')
        .eq('id_tienda', idTienda)
        .maybeSingle();
    if (tienda != null && tienda['codigo_afiliado'] == codigo) return true;

    final solicitudPrevia = await supabase
        .from('solicitudes_cambio_plan')
        .select('id_solicitud')
        .eq('id_tienda', idTienda)
        .eq('codigo_afiliado', codigo)
        .inFilter('estado', ['pendiente', 'aprobada']).maybeSingle();
    if (solicitudPrevia != null) return true;

    final usoConfirmado = await supabase
        .from('usos_afiliado')
        .select('id_uso')
        .eq('id_tienda', idTienda)
        .eq('codigo', codigo)
        .maybeSingle();
    return usoConfirmado != null;
  }

  /// Validación en vivo de un código de afiliado EN EL CONTEXTO de una
  /// tienda puntual (usado por ModalPagoPlan mientras el usuario
  /// escribe). Devuelve un mapa con 'estado' y 'id_afiliado':
  ///   - 'invalido': el código no existe o no está activo.
  ///   - 'propio':   el código pertenece a un afiliado que es dueño de
  ///                 esta misma tienda (no puede autoreferirse).
  ///   - 'usado':    esta tienda ya usó este código antes (ver
  ///                 _tiendaYaUsoCodigo).
  ///   - 'valido':   todo bien, se puede aplicar el 10% de descuento.
  Future<Map<String, dynamic>> validarCodigoAfiliadoParaTienda({
    required String codigo,
    required String? idTienda,
  }) async {
    final res = await supabase.rpc('validar_codigo_afiliado', params: {
      'p_codigo': codigo.trim().toUpperCase(),
      'p_id_tienda': idTienda,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// Crea una solicitud de cambio de plan. Si viene con código de
  /// afiliado, valida primero que ESA tienda no haya usado YA ese
  /// código antes -- un código puede usarse en tiendas distintas,
  /// pero no dos veces en la misma tienda. Este es el candado del
  /// lado del servidor; ModalPagoPlan ya valida esto en vivo con
  /// validarCodigoAfiliadoParaTienda, esto es la red de seguridad
  /// final antes de escribir en la base de datos.
  Future<void> crearSolicitudCambioPlan({
    required String idTienda,
    required String idPlanSolicitado,
    required String planAnterior,
    String? idAfiliado,
    double? comisionUsd,
    String? codigoAfiliado,
  }) async {
    if (codigoAfiliado != null && codigoAfiliado.isNotEmpty) {
      final codigoNormalizado = codigoAfiliado.trim().toUpperCase();
      final yaUsado = await _tiendaYaUsoCodigo(idTienda, codigoNormalizado);
      if (yaUsado) {
        throw Exception('Esta tienda ya usó el código "$codigoAfiliado" antes. '
            'Cada código solo se puede usar una vez por tienda.');
      }
    }

    await supabase.from('solicitudes_cambio_plan').insert({
      'id_tienda': idTienda,
      'id_plan_solicitado': idPlanSolicitado,
      'plan_anterior': planAnterior,
      'estado': 'pendiente',
      if (idAfiliado != null) 'id_afiliado': idAfiliado,
      if (comisionUsd != null) 'comision_usd': comisionUsd,
      if (codigoAfiliado != null) 'codigo_afiliado': codigoAfiliado,
    });
  }

  Future<void> aprobarSolicitudCambioPlan({
    required String idSolicitud,
    required String idTienda,
    required String codigoPlanNuevo,
    Map<String, dynamic>? usoAfiliado,
    double tasaCupUsd = 0,
  }) async {
    // FIX: la versión anterior hacía 3 operaciones sueltas (aprobar
    // solicitud, insertar en usos_afiliado, sumar saldo) sin
    // transacción -- si la segunda o tercera fallaban, quedaba la
    // solicitud marcada 'aprobada' pero sin acreditar nada. También
    // tenía 'aprobada'/femenino, que no coincide con lo que chequea el
    // resto de la app ('aprobado'). Ahora todo pasa junto en un RPC
    // atómico (admin_aprobar_solicitud_plan) -- o se aplica todo, o no
    // se aplica nada.
    await supabase.rpc('admin_aprobar_solicitud_plan', params: {
      'p_id_solicitud': idSolicitud,
      'p_id_tienda': idTienda,
      'p_codigo_plan': codigoPlanNuevo,
      'p_id_afiliado': usoAfiliado?['id_afiliado'],
      'p_codigo_afiliado': usoAfiliado?['codigo'],
      'p_comision_usd': usoAfiliado?['comision_usd'],
      'p_tasa_cup_usd': tasaCupUsd,
    });
  }

  Future<void> rechazarSolicitudCambioPlan(String idSolicitud) async {
    await supabase.from('solicitudes_cambio_plan').update({
      'estado': 'rechazada',
      'resuelto_en': DateTime.now().toIso8601String()
    }).eq('id_solicitud', idSolicitud);
  }

  // FIX: consultaba una tabla `usuarios` que no existe -- la identidad
  // vive en auth.users, que necesita el RPC SECURITY DEFINER de abajo
  // porque no se puede leer directo desde el cliente.
  Future<Map<String, dynamic>?> obtenerInfoUsuario(String uid) async {
    final res =
        await supabase.rpc('admin_info_usuario', params: {'p_user_id': uid});
    if (res is List) {
      return res.isNotEmpty ? Map<String, dynamic>.from(res.first) : null;
    }
    return res != null ? Map<String, dynamic>.from(res) : null;
  }

  /// Crea O actualiza un admin (upsert) -- es idempotente a propósito:
  /// si el usuario ya tenía una fila en 'admins' (por ejemplo, si el
  /// modal no detectó bien que ya era admin), esto actualiza sus
  /// permisos en vez de tronar con "duplicate key violates unique
  /// constraint admins_user_id_key".
  Future<void> crearAdmin({
    required String userId,
    required Map<String, dynamic> permisos,
  }) async {
    await supabase.from('admins').upsert(
      {'user_id': userId, 'permisos': permisos},
      onConflict: 'user_id',
    );
  }

  /// Actualiza los permisos de un admin que YA existe (a diferencia de
  /// crearAdmin(), que hace un INSERT). El modal de "Gestionar
  /// permisos" debe llamar a este método, no a crearAdmin(), o si no
  /// intenta insertar una fila duplicada cada vez que se edita.
  Future<void> actualizarPermisosAdmin({
    required String userId,
    required Map<String, dynamic> permisos,
  }) async {
    await supabase
        .from('admins')
        .update({'permisos': permisos}).eq('user_id', userId);
  }

  Future<List<Map<String, dynamic>>> obtenerTodosLosPlanes() async {
    final res = await supabase
        .from('planes')
        .select()
        .order('precio_usd', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> actualizarPlan({
    required String idPlan,
    String? nombre,
    String? codigo,
    double? precioUsd,
    int? limiteProductos,
    String? descripcion,
    String? numeroTarjeta,
    String? numeroTelefonoPago,
    String? qrUrl,
    bool? esGratis,
    int? duracionDias,
  }) async {
    final data = <String, dynamic>{};
    if (nombre != null) data['nombre'] = nombre;
    if (codigo != null) data['codigo'] = codigo;
    if (precioUsd != null) data['precio_usd'] = precioUsd;
    if (limiteProductos != null) data['limite_productos'] = limiteProductos;
    if (descripcion != null) data['descripcion'] = descripcion;
    if (numeroTarjeta != null) data['numero_tarjeta'] = numeroTarjeta;
    if (numeroTelefonoPago != null)
      data['numero_telefono_pago'] = numeroTelefonoPago;
    if (qrUrl != null) data['qr_url'] = qrUrl;
    if (esGratis != null) data['es_gratis'] = esGratis;
    if (duracionDias != null) data['duracion_dias'] = duracionDias;
    if (data.isNotEmpty) {
      await supabase.from('planes').update(data).eq('id_plan', idPlan);
    }
  }

  Future<void> crearPlan({
    required String nombre,
    required String codigo,
    required double precioUsd,
    required int limiteProductos,
    String? descripcion,
    String? numeroTarjeta,
    String? numeroTelefonoPago,
    String? qrUrl,
    bool? esGratis,
    int? duracionDias,
  }) async {
    await supabase.from('planes').insert({
      'nombre': nombre,
      'codigo': codigo,
      'precio_usd': precioUsd,
      'limite_productos': limiteProductos,
      'descripcion': descripcion,
      'numero_tarjeta': numeroTarjeta,
      'numero_telefono_pago': numeroTelefonoPago,
      'qr_url': qrUrl,
      'es_gratis': esGratis,
      'duracion_dias': duracionDias,
      'activo': true,
    });
  }

  Future<void> eliminarPlan(String idPlan) async {
    await supabase
        .from('planes')
        .update({'activo': false}).eq('id_plan', idPlan);
  }

  Future<void> reactivarPlan(String idPlan) async {
    await supabase
        .from('planes')
        .update({'activo': true}).eq('id_plan', idPlan);
  }

  Future<List<Map<String, dynamic>>> obtenerRetirosPendientes() async {
    final res = await supabase
        .from('retiros')
        .select(
            '*, afiliados(id_afiliado, nombre, codigo, saldo_cup, telefono, numero_tarjeta)')
        .eq('estado', 'pendiente')
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<Map<String, dynamic>?> buscarAfiliadoPorCodigo(String codigo) async {
    final res = await supabase
        .from('afiliados')
        .select()
        .eq('codigo', codigo)
        .maybeSingle();
    return res;
  }

  Future<List<Map<String, dynamic>>> obtenerUsosDeAfiliado(
      String idAfiliado) async {
    final res = await supabase
        .from('usos_afiliado')
        .select('*, tiendas(nombre)')
        .eq('id_afiliado', idAfiliado)
        .order('creado_en', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> marcarRetiroPagado({
    required String idRetiro,
    required String idAfiliado,
    required double montoCup,
  }) async {
    // FIX: antes esto solo actualizaba retiros.estado y nunca
    // descontaba afiliados.saldo_cup, aunque recibía idAfiliado y
    // montoCup como parámetros. Ahora usa un RPC atómico que hace
    // ambas cosas juntas (o ninguna si algo falla) y bloquea el
    // doble-procesamiento si el retiro ya no está 'pendiente'.
    await supabase.rpc('admin_marcar_retiro_pagado', params: {
      'p_id_retiro': idRetiro,
      'p_id_afiliado': idAfiliado,
      'p_monto': montoCup,
    });
  }

  // ---------------------------------------------------------------------
  // AFILIADO - PERFIL Y GESTIÓN
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>?> obtenerMiAfiliado() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return null;
    final res = await supabase
        .from('afiliados')
        .select()
        .eq('user_id', uid)
        .maybeSingle();
    return res;
  }

  /// Igual que obtenerMiAfiliado(), pero para cualquier user_id -- usado
  /// por el admin al ver "Información del vendedor" de otro usuario.
  Future<Map<String, dynamic>?> obtenerAfiliadoPorUserId(String userId) async {
    final res = await supabase
        .from('afiliados')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return res;
  }

  Future<List<Map<String, dynamic>>> obtenerRetirosDeAfiliado(
      String idAfiliado) async {
    final res = await supabase
        .from('retiros')
        .select()
        .eq('id_afiliado', idAfiliado)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> actualizarAfiliado({
    required String idAfiliado,
    String? nombre,
    String? telefono,
    String? numeroTarjeta,
    String? metodoPago,
    String? datosPago,
  }) async {
    final data = <String, dynamic>{};
    if (nombre != null) data['nombre'] = nombre;
    if (telefono != null) data['telefono'] = telefono;
    if (numeroTarjeta != null) data['numero_tarjeta'] = numeroTarjeta;
    if (metodoPago != null) data['metodo_pago'] = metodoPago;
    if (datosPago != null) data['datos_pago'] = datosPago;
    if (data.isNotEmpty) {
      await supabase
          .from('afiliados')
          .update(data)
          .eq('id_afiliado', idAfiliado);
    }
  }

  Future<double> obtenerRetiradoHoy(String idAfiliado) async {
    final hoy = DateTime.now();
    final inicioDia = DateTime(hoy.year, hoy.month, hoy.day);
    final res = await supabase
        .from('retiros')
        .select('monto_cup')
        .eq('id_afiliado', idAfiliado)
        .eq('estado', 'pagado')
        .gte('pagado_el', inicioDia.toIso8601String());
    return (res as List).fold<double>(
        0.0, (sum, r) => sum + (r['monto_cup'] as num).toDouble());
  }

  Future<void> solicitarRetiro({
    required String idAfiliado,
    required double montoCup,
  }) async {
    if (montoCup < 1000) {
      throw Exception('El monto mínimo para retirar es 1000 CUP.');
    }
    if (montoCup > 10000) {
      throw Exception('El monto máximo diario para retirar es 10,000 CUP.');
    }
    final afiliado = await supabase
        .from('afiliados')
        .select('saldo_cup')
        .eq('id_afiliado', idAfiliado)
        .maybeSingle();
    if (afiliado == null) {
      throw Exception('Afiliado no encontrado.');
    }
    final saldo = (afiliado['saldo_cup'] as num).toDouble();
    if (montoCup > saldo) {
      throw Exception(
          'No puedes retirar más de tu saldo actual (${saldo.toStringAsFixed(0)} CUP).');
    }
    final retiradoHoy = await obtenerRetiradoHoy(idAfiliado);
    final disponibleHoy = (10000 - retiradoHoy).clamp(0, 10000);
    if (montoCup > disponibleHoy) {
      throw Exception(
          'Solo puedes retirar hasta ${disponibleHoy.toStringAsFixed(0)} CUP hoy (ya retiraste ${retiradoHoy.toStringAsFixed(0)} CUP).');
    }
    await supabase.from('retiros').insert({
      'id_afiliado': idAfiliado,
      'monto_cup': montoCup,
      'estado': 'pendiente',
    });
  }

  // ---------------------------------------------------------------------
  // VALORACIONES
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>?> obtenerValoracionDePedido(
      String idPedido) async {
    final res = await supabase
        .from('valoraciones')
        .select()
        .eq('id_pedido', idPedido)
        .maybeSingle();
    return res;
  }

  // ---------------------------------------------------------------------
  // PLANES Y TIENDAS (ONBOARDING / PANEL VENDEDOR)
  // ---------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> obtenerPlanesActivos() async {
    final res = await supabase
        .from('planes')
        .select()
        .eq('activo', true)
        .order('precio_usd', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<bool> validarCodigoAfiliado(String codigo) async {
    final res = await supabase
        .from('afiliados')
        .select('id_afiliado')
        .eq('codigo', codigo)
        .eq('activo', true)
        .maybeSingle();
    return res != null;
  }

  /// Crea la tienda del vendedor. Queda en estado 'pending' hasta que
  /// el admin la valide manualmente (Flujo 1 del documento maestro).
  /// Usado por OnboardingTiendaScreen.
  ///
  /// FIX: antes esto acreditaba la comisión del afiliado de inmediato,
  /// al momento del registro -- sin esperar a que el admin valide la
  /// tienda. Se corrigió para que solo valide que el código existe (así
  /// el vendedor ve el error al toque si escribió mal) y lo guarde en
  /// la tienda; la comisión real se acredita recién en aprobarTienda(),
  /// cuando el admin activa la tienda -- igual que en el flujo de
  /// cambio de plan.
  /// Devuelve el id_tienda recién creado -- lo necesita el flujo de
  /// onboarding para navegar a /pago-plan justo después de registrar.
  Future<String> crearTienda({
    required String nombre,
    required String telefonoWhatsapp,
    required String provincia,
    required String municipio,
    required double lat,
    required double lon,
    required String plan,
    String? codigoAfiliado,
    String? categoria,
  }) async {
    final uid = supabase.auth.currentUser!.id;
    final codigo = codigoAfiliado?.trim().toUpperCase();
    if (codigo != null && codigo.isNotEmpty) {
      final afiliado = await supabase
          .from('afiliados')
          .select('id_afiliado')
          .eq('codigo', codigo)
          .eq('activo', true)
          .maybeSingle();
      if (afiliado == null) {
        throw Exception('Código de afiliado no válido');
      }
      // FIX: un código de afiliado solo puede usarse UNA vez por
      // cuenta (sin importar en qué tienda), incluso si esta tienda se
      // borra y crea otra. fn_puede_usar_codigo_afiliado consulta
      // cuentas_beneficios, que es permanente por diseño.
      final puedeUsarlo = await supabase.rpc(
        'fn_puede_usar_codigo_afiliado',
        params: {'p_user_id': uid, 'p_codigo': codigo},
      );
      if (puedeUsarlo != true) {
        throw Exception('Ya usaste este código de afiliado antes con esta cuenta');
      }
    }
    final res = await supabase
        .from('tiendas')
        .insert({
          'owner_id': uid,
          'nombre': nombre,
          'telefono_whatsapp': telefonoWhatsapp,
          'provincia': provincia,
          'municipio': municipio,
          'latitud': lat,
          'longitud': lon,
          'plan': plan,
          if (codigo != null && codigo.isNotEmpty) 'codigo_afiliado': codigo,
          if (categoria != null) 'categoria': categoria,
          // estado queda 'pending' por defecto (definido en el esquema)
        })
        .select('id_tienda')
        .single();

    if (codigo != null && codigo.isNotEmpty) {
      await supabase.rpc(
        'fn_registrar_uso_codigo_afiliado',
        params: {'p_user_id': uid, 'p_codigo': codigo},
      );
    }

    return res['id_tienda'] as String;
  }

  // ---------------------------------------------------------------------
  // PLAN GRATIS -- 14 días, una sola vez por cuenta (ver
  // cuentas_beneficios en SQL). A diferencia de crearTienda() de arriba,
  // esta activa la tienda de inmediato (sin pasar por 'pending' ni
  // esperar aprobación de admin), porque no hay pago que verificar.
  // ---------------------------------------------------------------------

  /// Consulta si esta cuenta todavía puede reclamar el plan gratis.
  /// Usado en el Paso 4 del stepper para deshabilitar esa opción en la
  /// UI si ya la usó antes (con esta tienda o con una anterior ya
  /// borrada -- el control es por cuenta, no por tienda).
  Future<bool> puedeUsarPlanGratis() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    final res = await supabase.rpc(
      'fn_puede_usar_plan_gratis',
      params: {'p_user_id': uid},
    );
    return res == true;
  }

  /// Consulta si esta cuenta ya usó un código de afiliado específico
  /// (sin importar en qué tienda). Usado para dar feedback temprano en
  /// el formulario, antes de intentar crear la tienda.
  Future<bool> puedeUsarCodigoAfiliado(String codigo) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    final res = await supabase.rpc(
      'fn_puede_usar_codigo_afiliado',
      params: {'p_user_id': uid, 'p_codigo': codigo.trim().toUpperCase()},
    );
    return res == true;
  }

  /// Crea la tienda con plan gratis y la activa de inmediato (visible
  /// ya en el marketplace, sin esperar aprobación ni pago).
  /// plan_expira_en queda en 14 días desde ahora; a partir de ahí
  /// revisar_vencimientos() (ya existente, corre cada hora) se encarga
  /// de notificar 5 y 3 días antes de vencer, y la Edge Function
  /// eliminar-tiendas-vencidas se encarga de borrar todo si nadie
  /// activó un plan de pago a tiempo.
  ///
  /// Lanza Exception si esta cuenta ya usó el plan gratis antes, o si
  /// el código de afiliado (si se pasó uno) ya fue usado por esta
  /// cuenta, o no existe -- toda la validación real ocurre del lado
  /// del servidor (crear_tienda_plan_gratis es SECURITY DEFINER), así
  /// que aunque se intente saltar la UI, no se puede abusar del plan
  /// gratis ni reusar códigos de afiliado.
  Future<String> crearTiendaConPlanGratis({
    required String nombre,
    required String telefonoWhatsapp,
    required String provincia,
    required String municipio,
    required double lat,
    required double lon,
    required String categoria,
    String? descripcion,
    String? codigoAfiliado,
  }) async {
    final codigo = codigoAfiliado?.trim().toUpperCase();
    try {
      final idTienda = await supabase.rpc('crear_tienda_plan_gratis', params: {
        'p_nombre': nombre,
        'p_telefono_whatsapp': telefonoWhatsapp,
        'p_provincia': provincia,
        'p_municipio': municipio,
        'p_lat': lat,
        'p_lon': lon,
        'p_categoria': categoria,
        'p_descripcion': descripcion,
        'p_codigo_afiliado': (codigo != null && codigo.isNotEmpty) ? codigo : null,
      });
      return idTienda as String;
    } on PostgrestException catch (e) {
      // El RPC lanza excepciones con mensaje amigable (ej. "Ya usaste
      // tu plan gratuito...") -- se propagan tal cual para que la UI
      // las muestre directo, sin traducir códigos de error.
      throw Exception(e.message);
    }
  }

  /// Crea una tienda usando el esquema de planes por id_plan/id_afiliado
  /// (variante alternativa, con id_usuario explícito y afiliado/logo).
  /// NOTA: renombrado desde 'crearTienda' porque Dart no permite dos
  /// métodos con el mismo nombre -- si en algún screen se usaba con este
  /// nombre y esquema, hay que actualizar esa llamada a
  /// 'crearTiendaConPlan'.
  Future<Map<String, dynamic>> crearTiendaConPlan({
    required String idUsuario,
    required String nombre,
    required String idPlan,
    String? idAfiliado,
    String? logoUrl,
    String? descripcion,
  }) async {
    final res = await supabase
        .from('tiendas')
        .insert({
          'id_usuario': idUsuario,
          'nombre': nombre,
          'id_plan': idPlan,
          'id_afiliado': idAfiliado,
          'logo_url': logoUrl,
          'descripcion': descripcion,
          'estado': 'pending',
        })
        .select()
        .single();
    return Map<String, dynamic>.from(res);
  }

  // FIX: intentaba actualizar tiendas.id_plan, columna que no existe
  // (la real es tiendas.plan, texto con el código del plan tipo
  // 'basic'/'premium'). Ahora traduce el uuid recibido a su código
  // antes de guardar.
  Future<void> activarPlanGratis({
    required String idTienda,
    required String idPlan,
  }) async {
    final plan = await supabase
        .from('planes')
        .select('codigo')
        .eq('id_plan', idPlan)
        .single();
    await supabase.from('tiendas').update(
        {'plan': plan['codigo'], 'estado': 'active'}).eq('id_tienda', idTienda);
  }

  Future<Map<String, dynamic>?> obtenerPlanPorCodigo(String codigo) async {
    final res = await supabase
        .from('planes')
        .select()
        .eq('codigo', codigo)
        .eq('activo', true)
        .maybeSingle();
    return res;
  }

  /// Registra un afiliado nuevo -- o, si esta cuenta de Google YA
  /// tuvo un perfil de afiliado antes (aunque esté dado de baja), lo
  /// reactiva conservando su código, saldo e historial intactos, en
  /// vez de crear un perfil nuevo. El código es permanente por cuenta,
  /// para siempre -- por eso nunca se genera uno nuevo en este caso.
  Future<Map<String, dynamic>> registrarAfiliado({
    String? idUsuario,
    required String nombre,
    String? telefono,
    String? numeroTarjeta,
  }) async {
    final uid = idUsuario ?? supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('Debes iniciar sesión');

    final existente = await supabase
        .from('afiliados')
        .select()
        .eq('user_id', uid)
        .maybeSingle();

    if (existente != null) {
      if (existente['activo'] == true) {
        throw Exception('Ya tienes un perfil de afiliado activo.');
      }
      final res = await supabase
          .from('afiliados')
          .update({
            'activo': true,
            'nombre': nombre,
            if (telefono != null) 'telefono': telefono,
            if (numeroTarjeta != null) 'numero_tarjeta': numeroTarjeta,
          })
          .eq('id_afiliado', existente['id_afiliado'])
          .select()
          .single();
      return Map<String, dynamic>.from(res);
    }

    final codigo = await _generarCodigoUnico();
    final res = await supabase
        .from('afiliados')
        .insert({
          'user_id': uid,
          'nombre': nombre,
          'codigo': codigo,
          'telefono': telefono,
          'numero_tarjeta': numeroTarjeta,
          'saldo_cup': 0,
          'activo': true,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(res);
  }

  /// Genera un código de afiliado de 6 caracteres (letras y números
  /// solamente, sin 0/O/1/I para evitar confusión visual), y verifica
  /// que no esté ya en uso antes de devolverlo.
  Future<String> _generarCodigoUnico() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    while (true) {
      final codigo =
          List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
      final existe = await supabase
          .from('afiliados')
          .select('id_afiliado')
          .eq('codigo', codigo)
          .maybeSingle();
      if (existe == null) return codigo;
    }
  }

  /// Da de baja (soft-delete) la cuenta de afiliado -- NUNCA se borra
  /// de la base de datos. Bloquea si hay un retiro pendiente de
  /// aprobación. El saldo, código e historial se conservan intactos
  /// para cuando la misma cuenta de Google se vuelva a registrar (ver
  /// registrarAfiliado()).
  Future<void> darDeBajaAfiliado(String idAfiliado) async {
    final retiroPendiente = await supabase
        .from('retiros')
        .select('id_afiliado')
        .eq('id_afiliado', idAfiliado)
        .eq('estado', 'pendiente')
        .maybeSingle();
    if (retiroPendiente != null) {
      throw Exception(
          'Tienes un retiro pendiente de aprobación. Espera a que se procese antes de eliminar tu cuenta.');
    }
    await supabase
        .from('afiliados')
        .update({'activo': false}).eq('id_afiliado', idAfiliado);
  }

  Future<Map<String, dynamic>?> obtenerSolicitudPendienteDeTienda(
      String idTienda) async {
    final res = await supabase
        .from('solicitudes_cambio_plan')
        .select()
        .eq('id_tienda', idTienda)
        .eq('estado', 'pendiente')
        .order('creado_en', ascending: false)
        .limit(1)
        .maybeSingle();
    return res;
  }

  // ---------------------------------------------------------------------
  // ANALYTICS - ADMIN
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> adminDashboardResumen() async {
    final res = await supabase.rpc('admin_dashboard_resumen');
    return Map<String, dynamic>.from(res.first);
  }

  Future<List<Map<String, dynamic>>> adminTopTiendasPorPedidos(
      {int limite = 10}) async {
    final res = await supabase
        .rpc('admin_top_tiendas_por_pedidos', params: {'limite': limite});
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> adminPedidosPendientes() async {
    final res = await supabase.rpc('admin_pedidos_pendientes');
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> adminTopProductos(
      {int limite = 10}) async {
    final res =
        await supabase.rpc('admin_top_productos', params: {'limite': limite});
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> adminTopAfiliados(
      {int limite = 10}) async {
    final res =
        await supabase.rpc('admin_top_afiliados', params: {'limite': limite});
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> adminIngresosPorMes() async {
    final res = await supabase.rpc('admin_ingresos_por_mes');
    return List<Map<String, dynamic>>.from(res);
  }

  // ---------------------------------------------------------------------
  // ANALYTICS - VENDEDOR
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> vendedorDashboardResumen(String idTienda) async {
    final res = await supabase
        .rpc('vendedor_dashboard_resumen', params: {'p_id_tienda': idTienda});
    return Map<String, dynamic>.from(res.first);
  }

  Future<List<Map<String, dynamic>>> vendedorPedidos(String idTienda,
      {String? estado}) async {
    final res = await supabase.rpc('vendedor_pedidos',
        params: {'p_id_tienda': idTienda, 'p_estado': estado});
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> vendedorProductosConVentas(
      String idTienda) async {
    final res = await supabase.rpc('vendedor_productos_con_ventas',
        params: {'p_id_tienda': idTienda});
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> vendedorValoraciones(
      String idTienda) async {
    final res = await supabase
        .rpc('vendedor_valoraciones', params: {'p_id_tienda': idTienda});
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> vendedorIngresosDiarios(
      String idTienda) async {
    final res = await supabase
        .rpc('vendedor_ingresos_diarios', params: {'p_id_tienda': idTienda});
    return List<Map<String, dynamic>>.from(res);
  }

  // ---------------------------------------------------------------------
  // ANALYTICS - COMPRADOR
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> compradorDashboardResumen(String uid) async {
    final res = await supabase
        .rpc('comprador_dashboard_resumen', params: {'p_id_comprador': uid});
    return Map<String, dynamic>.from(res.first);
  }

  Future<List<Map<String, dynamic>>> compradorPedidos(String uid) async {
    final res = await supabase
        .rpc('comprador_pedidos', params: {'p_id_comprador': uid});
    return List<Map<String, dynamic>>.from(res);
  }

  // ---------------------------------------------------------------------
  // ANALYTICS - AFILIADO
  // ---------------------------------------------------------------------

  /// Busca el id_afiliado real (clave primaria de 'afiliados') a partir
  /// del user_id de auth. Las tres funciones de abajo reciben `uid`
  /// (el id del usuario logueado) para no romper las pantallas que ya
  /// las llaman así, pero el RPC necesita el id_afiliado real -- son
  /// IDs distintos. Sin esta traducción, el RPC nunca encontraba la
  /// fila y el resumen/comisiones salían siempre vacíos.
  Future<String?> _idAfiliadoDeUid(String uid) async {
    final afiliado = await supabase
        .from('afiliados')
        .select('id_afiliado')
        .eq('user_id', uid)
        .maybeSingle();
    return afiliado?['id_afiliado'] as String?;
  }

  Future<Map<String, dynamic>> afiliadoDashboardResumen(String uid) async {
    final idAfiliado = await _idAfiliadoDeUid(uid);
    if (idAfiliado == null) return {};
    final res = await supabase.rpc('afiliado_dashboard_resumen',
        params: {'p_id_afiliado': idAfiliado});
    if (res is List) {
      return res.isNotEmpty ? Map<String, dynamic>.from(res.first) : {};
    }
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> afiliadoComisiones(String uid) async {
    final idAfiliado = await _idAfiliadoDeUid(uid);
    if (idAfiliado == null) return [];
    final res = await supabase
        .rpc('afiliado_comisiones', params: {'p_id_afiliado': idAfiliado});
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> afiliadoRetiros(String uid) async {
    final idAfiliado = await _idAfiliadoDeUid(uid);
    if (idAfiliado == null) return [];
    final res = await supabase
        .rpc('afiliado_retiros', params: {'p_id_afiliado': idAfiliado});
    return List<Map<String, dynamic>>.from(res);
  }

  // ---------------------------------------------------------------------
  // ANALYTICS - VENDEDOR, con rango de fechas (semana/mes/mes_calendario/
  // historico). Se agregan aparte de vendedorDashboardResumen/
  // vendedorPedidos/vendedorIngresosDiarios de arriba, por si algo más
  // todavía usa esos sin rango.
  // ---------------------------------------------------------------------

  String _rangoParam(RangoAnalitica rango) {
    switch (rango) {
      case RangoAnalitica.semana:
        return 'semana';
      case RangoAnalitica.mes:
        return 'mes';
      case RangoAnalitica.mesCalendario:
        return 'mes_calendario';
      case RangoAnalitica.historico:
        return 'historico';
    }
  }

  /// Ingresos, pedidos, ticket promedio y calificación del período, con
  /// % de variación vs. el período anterior equivalente.
  Future<Map<String, dynamic>> vendedorResumenPeriodo(
      String idTienda, RangoAnalitica rango) async {
    final res = await supabase.rpc('vendedor_resumen_periodo', params: {
      'p_id_tienda': idTienda,
      'p_rango': _rangoParam(rango),
    });
    if (res is List) {
      return res.isNotEmpty ? Map<String, dynamic>.from(res.first) : {};
    }
    return Map<String, dynamic>.from(res as Map);
  }

  /// Pedidos del período, con el campo `detalle` incluido para poder
  /// mostrar el desglose de productos al tocar uno.
  Future<List<Map<String, dynamic>>> vendedorPedidosPeriodo(
      String idTienda, RangoAnalitica rango) async {
    final res = await supabase.rpc('vendedor_pedidos_periodo', params: {
      'p_id_tienda': idTienda,
      'p_rango': _rangoParam(rango),
    });
    return List<Map<String, dynamic>>.from(res);
  }

  /// Ranking de productos del período: {nombre, precio_usd,
  /// veces_vendido, ingresos_generados} -- ya viene ordenado de más a
  /// menos vendido, el toggle "Menos vendidos" lo reordena en el cliente.
  Future<List<Map<String, dynamic>>> vendedorRankingProductosPeriodo(
      String idTienda, RangoAnalitica rango) async {
    final res =
        await supabase.rpc('vendedor_ranking_productos_periodo', params: {
      'p_id_tienda': idTienda,
      'p_rango': _rangoParam(rango),
    });
    return List<Map<String, dynamic>>.from(res);
  }

  /// Serie temporal de ingresos para la gráfica: {etiqueta, valor}.
  Future<List<Map<String, dynamic>>> vendedorIngresosSerie(
      String idTienda, RangoAnalitica rango) async {
    final res = await supabase.rpc('vendedor_ingresos_serie', params: {
      'p_id_tienda': idTienda,
      'p_rango': _rangoParam(rango),
    });
    return List<Map<String, dynamic>>.from(res);
  }

  // ---------------------------------------------------------------------
  // ANALYTICS - ADMIN, ingresos reales con rango de fechas
  // ---------------------------------------------------------------------

  /// Ingresos reales del admin (pagos de planes aprobados, con el 90%
  /// si hubo código de afiliado), con rango de fechas.
  Future<Map<String, dynamic>> adminIngresosPeriodo(
      RangoAnalitica rango) async {
    final res = await supabase.rpc('admin_ingresos_periodo', params: {
      'p_rango': _rangoParam(rango),
    });
    if (res is List) {
      return res.isNotEmpty ? Map<String, dynamic>.from(res.first) : {};
    }
    return Map<String, dynamic>.from(res as Map);
  }
}
