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
    String? descripcion,
    int cantidadDisponible = 1,
  }) async {
    await supabase.from('productos').insert({
      'id_tienda': idTienda,
      'nombre': nombre,
      'precio_usd': precioUsd,
      'imagen_url': imagenUrl,
      'descripcion': descripcion,
      'cantidad_disponible': cantidadDisponible,
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
  }) async {
    final data = <String, dynamic>{};
    if (nombre != null) data['nombre'] = nombre;
    if (precioUsd != null) data['precio_usd'] = precioUsd;
    if (imagenUrl != null) data['imagen_url'] = imagenUrl;
    if (descripcion != null) data['descripcion'] = descripcion;
    if (cantidadDisponible != null) {
      data['cantidad_disponible'] = cantidadDisponible;
    }
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
  /// detalle de una solicitud de cambio de plan en el panel de admin,
  /// ya que el RPC admin_solicitudes_plan_pendientes solo devuelve un
  /// resumen plano (tienda_nombre, plan_anterior/nuevo) y no trae la
  /// descripción ni el resto de los datos de contacto.
  Future<Map<String, dynamic>?> obtenerTiendaPorId(String idTienda) async {
    final res = await supabase
        .from('tiendas')
        .select()
        .eq('id_tienda', idTienda)
        .maybeSingle();
    return res;
  }

  /// Verifica si el usuario autenticado ya tiene una tienda creada,
  /// para saber si mandarlo al onboarding o directo a su panel.
  Future<Map<String, dynamic>?> obtenerMiTienda() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;

    // Se usa limit(1) en vez de maybeSingle() porque un usuario podría
    // llegar a tener más de una fila en 'tiendas' (pruebas, o un
    // reintento tras un rechazo); maybeSingle() lanza una excepción si
    // hay más de una fila, lo que dejaba "Mi Tienda" en blanco.
    final res = await supabase
        .from('tiendas')
        .select()
        .eq('owner_id', userId)
        .order('creado_en', ascending: false)
        .limit(1);
    final lista = List<Map<String, dynamic>>.from(res);
    return lista.isEmpty ? null : lista.first;
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
  }) async {
    await supabase.from('tiendas').update({
      'nombre': nombre,
      'telefono_whatsapp': telefonoWhatsapp,
      'provincia': provincia,
      'municipio': municipio,
      if (descripcion != null) 'descripcion': descripcion,
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

  /// Crea una solicitud de cambio de plan. Si viene con código de
  /// afiliado, valida primero que ESA tienda no haya usado YA ese
  /// código antes -- un código puede usarse en tiendas distintas,
  /// pero no dos veces en la misma tienda.
  Future<void> crearSolicitudCambioPlan({
    required String idTienda,
    required String idPlanSolicitado,
    required String planAnterior,
    String? idAfiliado,
    double? comisionUsd,
    String? codigoAfiliado,
  }) async {
    if (idAfiliado != null && codigoAfiliado != null) {
      final yaUsado = await supabase
          .from('usos_afiliado')
          .select('id')
          .eq('id_tienda', idTienda)
          .eq('codigo', codigoAfiliado)
          .maybeSingle();
      if (yaUsado != null) {
        throw Exception('Ya usaste este código. Consigue otro.');
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

  Future<Map<String, dynamic>?> obtenerInfoUsuario(String uid) async {
    final res = await supabase
        .from('usuarios')
        .select()
        .eq('id_usuario', uid)
        .maybeSingle();
    return res;
  }

  Future<void> crearAdmin({
    required String userId,
    required Map<String, dynamic> permisos,
  }) async {
    await supabase
        .from('admins')
        .insert({'user_id': userId, 'permisos': permisos});
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
    final estado = await validarCodigoAfiliadoParaTienda(codigo: codigo);
    return estado != 'invalido';
  }

  /// Validación completa para feedback en tiempo real en el modal de
  /// pago: distingue código inválido, código propio (no puedes
  /// referirte a ti mismo) y código ya usado antes por esta misma
  /// tienda. Devuelve uno de: 'valido', 'invalido', 'propio', 'usado'.
  ///
  /// Usa el RPC validar_codigo_afiliado (SECURITY DEFINER) en vez de
  /// consultar 'afiliados' directamente -- la política RLS de esa
  /// tabla solo deja leer la fila propia o si eres admin, así que
  /// cualquier código que no fuera el tuyo siempre salía "inválido".
  Future<String> validarCodigoAfiliadoParaTienda({
    required String codigo,
    String? idTienda,
  }) async {
    final res = await supabase.rpc('validar_codigo_afiliado', params: {
      'p_codigo': codigo,
      'p_id_tienda': idTienda,
    });
    return res as String;
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
  Future<String> crearTienda({
    required String nombre,
    required String telefonoWhatsapp,
    required String provincia,
    required String municipio,
    required double lat,
    required double lon,
    required String plan,
    String? codigoAfiliado,
  }) async {
    // Un usuario solo puede tener una tienda pending/active a la vez.
    // Si la anterior fue rechazada, puede reintentar (se borra la
    // rechazada y se crea una nueva limpia).
    final miTienda = await obtenerMiTienda();
    if (miTienda != null) {
      if (miTienda['estado'] == 'rechazada') {
        await supabase
            .from('tiendas')
            .delete()
            .eq('id_tienda', miTienda['id_tienda']);
      } else {
        throw Exception('Ya tienes una tienda registrada con esta cuenta.');
      }
    }

    final codigo = codigoAfiliado?.trim().toUpperCase();
    if (codigo != null && codigo.isNotEmpty) {
      final estado = await validarCodigoAfiliadoParaTienda(codigo: codigo);
      if (estado == 'invalido') {
        throw Exception('Código de afiliado no válido');
      }
      if (estado == 'propio') {
        throw Exception(
            'No se puede usar el propio código de afiliado del propietario de la tienda');
      }
      if (estado == 'usado') {
        throw Exception('Ya usaste este código. Consigue otro.');
      }
    }
    final res = await supabase
        .from('tiendas')
        .insert({
          'owner_id': supabase.auth.currentUser!.id,
          'nombre': nombre,
          'telefono_whatsapp': telefonoWhatsapp,
          'provincia': provincia,
          'municipio': municipio,
          'latitud': lat,
          'longitud': lon,
          'plan': plan,
          if (codigo != null && codigo.isNotEmpty) 'codigo_afiliado': codigo,
          // estado queda 'pending' por defecto (definido en el esquema)
        })
        .select('id_tienda')
        .single();
    return res['id_tienda'] as String;
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

  Future<void> activarPlanGratis({
    required String idTienda,
    required String idPlan,
  }) async {
    await supabase.from('tiendas').update(
        {'id_plan': idPlan, 'estado': 'active'}).eq('id_tienda', idTienda);
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

  Future<Map<String, dynamic>> registrarAfiliado({
    String? idUsuario,
    required String nombre,
    String? telefono,
    String? numeroTarjeta,
    String? codigo,
  }) async {
    final uid = idUsuario ?? supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('Debes iniciar sesión');
    final res = await supabase
        .from('afiliados')
        .insert({
          'user_id': uid,
          'nombre': nombre,
          'codigo': codigo ?? _generarCodigoAfiliado(nombre),
          'telefono': telefono,
          'numero_tarjeta': numeroTarjeta,
          'saldo_cup': 0,
          'activo': true,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(res);
  }

  String _generarCodigoAfiliado(String nombre) {
    final base = nombre.trim().isEmpty
        ? 'AF'
        : nombre.trim().toUpperCase().split(' ').first;
    final sufijo = supabase.auth.currentUser?.id.substring(0, 4) ?? '0000';
    return '$base-$sufijo';
  }

  Future<Map<String, dynamic>?> obtenerSolicitudPendienteDeTienda(
      String idTienda) async {
    final res = await supabase
        .from('solicitudes_cambio_plan')
        .select()
        .eq('id_tienda', idTienda)
        .eq('estado', 'pending')
        .order('created_at', ascending: false)
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

  Future<Map<String, dynamic>> afiliadoDashboardResumen(String uid) async {
    final res = await supabase
        .rpc('afiliado_dashboard_resumen', params: {'p_id_afiliado': uid});
    return Map<String, dynamic>.from(res.first);
  }

  Future<List<Map<String, dynamic>>> afiliadoComisiones(String uid) async {
    final res = await supabase
        .rpc('afiliado_comisiones', params: {'p_id_afiliado': uid});
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> afiliadoRetiros(String uid) async {
    final res =
        await supabase.rpc('afiliado_retiros', params: {'p_id_afiliado': uid});
    return List<Map<String, dynamic>>.from(res);
  }
}
