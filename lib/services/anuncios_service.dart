// anuncios_service.dart
//
// Cliente del sistema de anuncios (ver sistema_anuncios_sql.sql en la
// raíz del proyecto). Las RPCs del backend devuelven cada anuncio como
// jsonb listo para pintar (incluye nombre/logo del destino), así que acá
// casi todo es parseo y tolerancia a fallos: si algo falla (ej. sin
// conexión) se devuelve lista vacía -- la app funciona igual, solo que
// sin promos, coherente con el resto del comportamiento offline.
//
// NUEVO (2026-09): ranuras de anuncio de TIENDA ya no salen solo del
// plan contratado -- ahora se suman las ranuras EXTRA compradas por
// separado (paquetes de anuncio independientes, tabla
// permisos_tienda_anuncios). Mismo patrón que ya existía para negocios
// (permisos_negocio / ranurasDeNegocio). Ver crearCompraPendienteTienda
// más abajo para el flujo de compra.
//
// NUEVO (2026-09, anuncios STANDALONE con pago real): antes un
// anuncio 'standalone' (sin tienda ni negocio) se aprobaba directo sin
// ninguna verificación de pago real -- cualquiera podía publicar sin
// comprar nada. Ahora existe la tabla permisos_usuario_anuncios
// (mismo patrón que permisos_negocio) que registra las ranuras
// REALMENTE compradas y aprobadas por el admin. El trigger
// anuncios_before_insert valida el cupo contra esa tabla igual que ya
// hace con tienda/negocio. Ver ranurasStandalone(),
// misPermisosStandalone(), crearCompraPendienteStandalone() y
// comprasPendientesStandalone() más abajo.

import 'package:flutter/foundation.dart';
import '../core/supabase_client.dart';
import 'storage_service.dart';

/// Tope de ranuras COMPRADAS por negocio (paquetes acumulados).
/// Debe coincidir con el `least(..., 5)` del trigger en Supabase
/// (parche_ranuras_acumulables.sql) -- si cambias uno, cambia el otro.
const int kMaxRanurasNegocio = 5;

/// Tope de ranuras EXTRA compradas por TIENDA (fuera de su plan).
/// Debe coincidir con el tope equivalente que se agregue al trigger
/// de anuncios de tienda en Supabase -- si cambias uno, cambia el otro.
const int kMaxRanurasExtraTienda = 5;

class Anuncio {
  final String idAnuncio;
  final String tipo; // 'admin' | 'negocio' | 'producto' | 'standalone'
  final String? titulo;
  final String? texto;
  final String? imagenUrl;
  final String? etiqueta;
  final String? idTienda;
  final String? idProducto;
  final String? idNegocio;
  final String? destinoNombre;
  final String? destinoImagen;
  final double? precioUsd;
  final String? whatsapp;

  const Anuncio({
    required this.idAnuncio,
    required this.tipo,
    this.titulo,
    this.texto,
    this.imagenUrl,
    this.etiqueta,
    this.idTienda,
    this.idProducto,
    this.idNegocio,
    this.destinoNombre,
    this.destinoImagen,
    this.precioUsd,
    this.whatsapp,
  });

  factory Anuncio.fromJson(Map<String, dynamic> j) => Anuncio(
        idAnuncio: (j['id_anuncio'] ?? '').toString(),
        tipo: (j['tipo'] ?? '').toString(),
        titulo: j['titulo'] as String?,
        texto: j['texto'] as String?,
        imagenUrl: j['imagen_url'] as String?,
        etiqueta: j['etiqueta'] as String?,
        idTienda: j['id_tienda'] as String?,
        idProducto: j['id_producto'] as String?,
        idNegocio: j['id_negocio'] as String?,
        destinoNombre: j['destino_nombre'] as String?,
        destinoImagen: j['destino_imagen'] as String?,
        precioUsd: (j['precio_usd'] as num?)?.toDouble(),
        whatsapp: j['whatsapp'] as String?,
      );

  /// Etiqueta legal fija por tipo -- solo se usa si el admin no puso
  /// una personalizada en la columna etiqueta.
  String get etiquetaFinal {
    if (etiqueta != null && etiqueta!.trim().isNotEmpty) return etiqueta!;
    switch (tipo) {
      case 'negocio':
        return 'Negocio Patrocinado';
      case 'producto':
        return 'Promoción Pagada';
      case 'standalone':
        return 'Anuncio Independiente';
      default:
        return 'Promoción del Marketplace';
    }
  }
}

class AnunciosService {
  /// Anuncios para intercalar en el feed (backend prioriza y rota:
  /// admin -> negocio -> producto, máximo de cupos server-side).
  /// Si se proveen [provincia] y/o [municipio], el RPC filtrará los anuncios
  /// solo de tiendas ubicadas en ese lugar, evitando que mezclen provincias
  /// (ej. un anuncio de Matanzas no aparezca en el feed de La Habana).
  Future<List<Anuncio>> obtenerFeed({
    int cantidad = 3,
    String? provincia,
    String? municipio,
  }) async {
    try {
      final res = await supabase.rpc(
        'obtener_anuncios_feed',
        params: {'p_cantidad': cantidad, 'provincia': provincia, 'municipio': municipio},
      );
      final filas = List<Map<String, dynamic>>.from(res as List);
      return filas
          .map((f) => Anuncio.fromJson(
              Map<String, dynamic>.from(f['anuncio'] as Map)))
          .toList();
    } catch (e) {
      debugPrint('obtener_anuncios_feed RPC falló (¿offline o schema?): $e');
      return _feedDirecto(cantidad);
    }
  }

  /// Fallback del feed: consulta directa a la tabla. No reparte cupos ni
  /// hace la rotación "menos mostrados primero" del RPC, pero garantiza
  /// que el feed nunca se quede vacío por un error del RPC.
  Future<List<Anuncio>> _feedDirecto(int cantidad) async {
    try {
      final data = await supabase
          .from('anuncios')
          .select()
          .eq('estado', 'aprobado')
          .order('creado_en', ascending: false)
          .limit(cantidad.clamp(0, 50));
      return data
          .map((r) => Anuncio.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (e) {
      debugPrint('fallback de feed directo falló (¿offline?): $e');
      return [];
    }
  }

  /// Carrusel superior: solo tipo='admin', máx 5, rotación aleatoria.
  Future<List<Anuncio>> obtenerCarrusel({int limite = 5}) async {
    try {
      final res = await supabase.rpc(
        'obtener_anuncios_carrusel',
        params: {'p_limite': limite},
      );
      final filas = List<Map<String, dynamic>>.from(res as List);
      return filas
          .map((f) => Anuncio.fromJson(
              Map<String, dynamic>.from(f['anuncio'] as Map)))
          .toList();
    } catch (e) {
      debugPrint('obtener_anuncios_carrusel RPC falló (¿offline o schema?): $e');
      try {
        final data = await supabase
            .from('anuncios')
            .select()
            .eq('tipo', 'admin')
            .eq('estado', 'aprobado')
            .order('creado_en', ascending: false)
            .limit(limite.clamp(0, 50));
        return data
            .map((r) => Anuncio.fromJson(Map<String, dynamic>.from(r)))
            .toList();
      } catch (e2) {
        debugPrint('fallback de carrusel directo falló (¿offline?): $e2');
        return [];
      }
    }
  }

  /// Un anuncio específico por id (deep link de compartición). Lee la
  /// tabla `anuncios` directo: la RLS permite a cualquiera leer los
  /// aprobados/vigentes (misma regla que usa el feed). Devuelve null
  /// si no existe o no está visible para el público.
  Future<Map<String, dynamic>?> obtenerAnuncioPorId(String idAnuncio) async {
    try {
      final res = await supabase
          .from('anuncios')
          .select()
          .eq('id_anuncio', idAnuncio)
          .maybeSingle();
      return res;
    } catch (e) {
      debugPrint('obtenerAnuncioPorId falló (¿offline?): $e');
      return null;
    }
  }

  /// Métrica de clics -- los usuarios no pueden hacer UPDATE directo.
  void registrarClic(String idAnuncio) {
    supabase.rpc('anuncio_registrar_clic', params: {'p_id_anuncio': idAnuncio})
        .catchError((_) {});
  }

  /// ¿El CTA "¿Quieres promocionar tu negocio?" está encendido?
  /// Lee configuracion_app directamente (lectura pública por RLS).
  Future<bool> ctaNegocioActivo() async {
    try {
      final res = await supabase
          .from('configuracion_app')
          .select('valor')
          .eq('clave', 'anuncios')
          .maybeSingle();
      final valor = res?['valor'];
      if (valor is Map) {
        return (valor['cta_negocio_activo']?.toString() ?? 'true') == 'true';
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ¿El CTA "¿Quieres vender algo puntual?" (anuncio independiente)
  /// está encendido? Mismo patrón que ctaNegocioActivo() -- lee la
  /// misma fila de configuracion_app, otra clave dentro del jsonb.
  /// Si el admin no configuró nada, por defecto true (no bloquea el
  /// lanzamiento de la función por falta de config).
  Future<bool> ctaAnuncioIndependienteActivo() async {
    try {
      final res = await supabase
          .from('configuracion_app')
          .select('valor')
          .eq('clave', 'anuncios')
          .maybeSingle();
      final valor = res?['valor'];
      if (valor is Map) {
        return (valor['cta_standalone_activo']?.toString() ?? 'true') ==
            'true';
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // PAQUETES DE ANUNCIO (pago del negocio, la tienda o un usuario suelto)
  //
  // El negocio elige su primer paquete al registrarse; las cuentas
  // (tarjeta/QR) cuelgan de CADA paquete (paquetes_anuncio_cuentas_pago)
  // y el admin las edita desde su panel. El número de WhatsApp destino
  // también lo define el admin (configuracion_app -> whatsapp_pagos).
  // ------------------------------------------------------------------

  /// Paquetes activos ordenados por `orden`.
  Future<List<Map<String, dynamic>>> obtenerPaquetesActivos() async {
    try {
      final res = await supabase
          .from('paquetes_anuncio')
          .select()
          .eq('activo', true)
          .order('orden', ascending: true);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('obtenerPaquetesActivos falló (¿offline?): $e');
      return [];
    }
  }

  /// Cuentas de pago activas de UN paquete (MLC/CUP/Clásica + QR).
  Future<List<Map<String, dynamic>>> obtenerCuentasDePaquete(
      String idPaquete) async {
    try {
      final res = await supabase
          .from('paquetes_anuncio_cuentas_pago')
          .select()
          .eq('id_paquete', idPaquete)
          .eq('activo', true);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('obtenerCuentasDePaquete falló: $e');
      return [];
    }
  }

  /// Número de WhatsApp donde el admin recibe pagos/solicitudes de
  /// anuncios. Null si aún no lo configuró (la UI cae al contacto
  /// genérico de contactos_whatsapp).
  Future<String?> obtenerWhatsappPagos() async {
    try {
      final res = await supabase
          .from('configuracion_app')
          .select('valor')
          .eq('clave', 'anuncios')
          .maybeSingle();
      final valor = res?['valor'];
      if (valor is Map) return valor['whatsapp_pagos'] as String?;
      return null;
    } catch (e) {
      debugPrint('obtenerWhatsappPagos falló: $e');
      return null;
    }
  }

  /// Registra la compra pendiente del primer paquete DE NEGOCIO. Al
  /// aprobarla el admin, el trigger crea el permiso en
  /// permisos_negocio con su vigencia.
  Future<void> crearCompraPendiente({
    required String idNegocio,
    required String idPaquete,
    required String codigoRef,
  }) async {
    await supabase.from('compras_anuncio').insert({
      'id_negocio': idNegocio,
      'id_paquete': idPaquete,
      'estado': 'pendiente',
      'codigo_ref': codigoRef,
    });
  }

  /// Registra la compra pendiente de un paquete de RANURAS EXTRA para
  /// una TIENDA (independiente de su plan). Al aprobarla el admin, el
  /// trigger crea el permiso en permisos_tienda_anuncios.
  Future<void> crearCompraPendienteTienda({
    required String idTienda,
    required String idPaquete,
    required String codigoRef,
  }) async {
    await supabase.from('compras_anuncio').insert({
      'id_tienda': idTienda,
      'id_paquete': idPaquete,
      'estado': 'pendiente',
      'codigo_ref': codigoRef,
    });
  }

  /// NUEVO: registra la compra pendiente de un paquete de anuncio
  /// INDEPENDIENTE (standalone) ligado al USUARIO actual (sin tienda
  /// ni negocio). Al aprobarla el admin, el trigger
  /// fn_aprobar_compra_standalone crea el permiso en
  /// permisos_usuario_anuncios con su vigencia.
  Future<void> crearCompraPendienteStandalone({
    required String idPaquete,
    required String codigoRef,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('SESION_REQUERIDA');
    await supabase.from('compras_anuncio').insert({
      'id_comprador': uid,
      'id_paquete': idPaquete,
      'estado': 'pendiente',
      'codigo_ref': codigoRef,
    });
  }

  /// Compras de paquete de ranuras extra de ESTA tienda que aún
  /// esperan verificación del admin.
  Future<List<Map<String, dynamic>>> comprasPendientesDeTienda(
      String idTienda) async {
    try {
      final res = await supabase
          .from('compras_anuncio')
          .select()
          .eq('id_tienda', idTienda)
          .eq('estado', 'pendiente');
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('comprasPendientesDeTienda falló: $e');
      return [];
    }
  }

  /// Compras de paquete standalone del USUARIO actual que aún esperan
  /// verificación del admin -- para el banner "en revisión" de la
  /// pantalla de anuncio independiente / Mi Perfil.
  Future<List<Map<String, dynamic>>> comprasPendientesStandalone() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return [];
    try {
      final res = await supabase
          .from('compras_anuncio')
          .select()
          .eq('id_comprador', uid)
          .eq('estado', 'pendiente');
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('comprasPendientesStandalone falló: $e');
      return [];
    }
  }

  // ------------------------------------------------------------------
  // ANUNCIOS DE TIENDA (tipo='producto')
  // ------------------------------------------------------------------

  /// Ranuras EXTRA de la tienda por paquetes comprados aparte del plan
  /// (permisos_tienda_anuncios vigentes).
  Future<int> _ranurasExtraDeTienda(String idTienda) async {
    try {
      final res = await supabase
          .from('permisos_tienda_anuncios')
          .select('max_anuncios_extra')
          .eq('id_tienda', idTienda)
          .eq('activo', true)
          .gt('hasta', DateTime.now().toIso8601String());
      var total = 0;
      for (final p in (res as List)) {
        total += ((p['max_anuncios_extra'] as num?)?.toInt() ?? 0);
      }
      if (total > kMaxRanurasExtraTienda) total = kMaxRanurasExtraTienda;
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Ranuras de anuncio de la tienda: cuántas usa y cuántas permite en
  /// TOTAL (plan + extra).
  Future<({int usados, int max, int maxPlan, int maxExtra})> ranurasDeTienda(
      String idTienda) async {
    var usados = 0;
    var maxPlan = 0;
    try {
      final res = await supabase
          .from('anuncios')
          .select('id_anuncio')
          .eq('tipo', 'producto')
          .eq('id_tienda', idTienda)
          .eq('estado', 'aprobado');
      usados = (res as List).length;
    } catch (_) {}
    try {
      final res = await supabase
          .from('tiendas')
          .select('plan, planes:plan!inner(ranuras_anuncios)')
          .eq('id_tienda', idTienda)
          .maybeSingle();
      final planes = res?['planes'];
      if (planes is Map && planes['ranuras_anuncios'] != null) {
        maxPlan = (planes['ranuras_anuncios'] as num).toInt();
      }
    } catch (_) {}
    final maxExtra = await _ranurasExtraDeTienda(idTienda);
    return (
      usados: usados,
      max: maxPlan + maxExtra,
      maxPlan: maxPlan,
      maxExtra: maxExtra,
    );
  }

  /// Potencia un producto existente.
  Future<void> potenciarProducto({
    required String idTienda,
    required String idProducto,
    required String titulo,
    String? texto,
    String? imagenUrl,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('SESION_REQUERIDA');
    await supabase.from('anuncios').insert({
      'tipo': 'producto',
      'id_tienda': idTienda,
      'id_producto': idProducto,
      'titulo': titulo,
      if (texto != null && texto.isNotEmpty) 'texto': texto,
      if (imagenUrl != null && imagenUrl.isNotEmpty) 'imagen_url': imagenUrl,
      'creado_por': uid,
    });
  }

  /// Promo de tienda en pleno ("crear anuncio").
  Future<void> crearPromoTienda({
    required String idTienda,
    required String titulo,
    required String texto,
    String? imagenUrl,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('SESION_REQUERIDA');
    await supabase.from('anuncios').insert({
      'tipo': 'producto',
      'id_tienda': idTienda,
      'titulo': titulo,
      'texto': texto,
      if (imagenUrl != null && imagenUrl.isNotEmpty) 'imagen_url': imagenUrl,
      'creado_por': uid,
    });
  }

  /// Mis anuncios de producto/tienda (para el sheet de gestión).
  Future<List<Map<String, dynamic>>> misAnunciosDeTienda(
      String idTienda) async {
    try {
      final res = await supabase
          .from('anuncios')
          .select()
          .eq('tipo', 'producto')
          .eq('id_tienda', idTienda)
          .order('creado_en', ascending: false);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('misAnunciosDeTienda falló: $e');
      return [];
    }
  }

  // ------------------------------------------------------------------
  // ANUNCIOS DE NEGOCIO (tipo='negocio')
  // ------------------------------------------------------------------

  Future<({int usados, int max, DateTime? vigenteHasta})>
      ranurasDeNegocio(String idNegocio) async {
    var usados = 0;
    var max = 0;
    DateTime? vigenteHasta;
    try {
      final res = await supabase
          .from('anuncios')
          .select('id_anuncio')
          .eq('tipo', 'negocio')
          .eq('id_negocio', idNegocio)
          .inFilter('estado', ['pendiente', 'aprobado']);
      usados = (res as List).length;
    } catch (_) {}
    try {
      final res = await supabase
          .from('permisos_negocio')
          .select('max_anuncios, hasta')
          .eq('id_negocio', idNegocio)
          .eq('activo', true)
          .gt('hasta', DateTime.now().toIso8601String());
      for (final p in (res as List)) {
        final m = (p['max_anuncios'] as num?)?.toInt() ?? 0;
        max += m;
        final h = DateTime.tryParse(p['hasta'] as String? ?? '');
        if (h != null && (vigenteHasta == null || h.isAfter(vigenteHasta))) {
          vigenteHasta = h;
        }
      }
      if (max > kMaxRanurasNegocio) max = kMaxRanurasNegocio;
    } catch (_) {}
    return (usados: usados, max: max, vigenteHasta: vigenteHasta);
  }

  Future<void> crearPromoNegocio({
    required String idNegocio,
    required String titulo,
    required String texto,
    String? imagenUrl,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('SESION_REQUERIDA');
    await supabase.from('anuncios').insert({
      'tipo': 'negocio',
      'id_negocio': idNegocio,
      'titulo': titulo,
      'texto': texto,
      if (imagenUrl != null && imagenUrl.isNotEmpty) 'imagen_url': imagenUrl,
      'creado_por': uid,
    });
  }

  // ------------------------------------------------------------------
  // ANUNCIOS INDEPENDIENTES (tipo='standalone')
  //
  // NUEVO: ahora el cupo sale de permisos_usuario_anuncios (paquetes
  // REALMENTE comprados y aprobados por el admin) -- ya no hay
  // publicación libre sin verificación de pago.
  // ------------------------------------------------------------------

  /// Ranuras de anuncio INDEPENDIENTE del usuario actual: usadas
  /// (aprobadas) vs. máximo según la suma de sus permisos vigentes.
  Future<({int usados, int max, DateTime? vigenteHasta})>
      ranurasStandalone() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return (usados: 0, max: 0, vigenteHasta: null);
    var usados = 0;
    var max = 0;
    DateTime? vigenteHasta;
    try {
      final res = await supabase
          .from('anuncios')
          .select('id_anuncio')
          .eq('tipo', 'standalone')
          .eq('creado_por', uid)
          .eq('estado', 'aprobado');
      usados = (res as List).length;
    } catch (_) {}
    try {
      final res = await supabase
          .from('permisos_usuario_anuncios')
          .select('max_anuncios, hasta')
          .eq('id_usuario', uid)
          .eq('activo', true)
          .gt('hasta', DateTime.now().toIso8601String());
      for (final p in (res as List)) {
        max += ((p['max_anuncios'] as num?)?.toInt() ?? 0);
        final h = DateTime.tryParse(p['hasta'] as String? ?? '');
        if (h != null && (vigenteHasta == null || h.isAfter(vigenteHasta!))) {
          vigenteHasta = h;
        }
      }
    } catch (_) {}
    return (usados: usados, max: max, vigenteHasta: vigenteHasta);
  }

  /// Detalle de los permisos vigentes (paquetes comprados y aprobados)
  /// del usuario actual, con el nombre del paquete embebido -- para
  /// listarlos en la UI (Mi Perfil / pantalla de anuncio independiente).
  Future<List<Map<String, dynamic>>> misPermisosStandalone() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return [];
    try {
      final res = await supabase
          .from('permisos_usuario_anuncios')
          .select(
              'id_permiso, max_anuncios, hasta, paquetes_anuncio(nombre, duracion_dias)')
          .eq('id_usuario', uid)
          .eq('activo', true)
          .gt('hasta', DateTime.now().toIso8601String())
          .order('hasta', ascending: true);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('misPermisosStandalone falló: $e');
      return [];
    }
  }

  /// Cuántos anuncios independientes ACTIVOS consume hoy cada permiso
  /// (id_permiso -> cantidad), usando la misma regla del trigger
  /// anuncios_before_insert (solo cuenta estado='aprobado'). Sirve para
  /// mostrar "X de Y usados" por ranura en el selector al publicar.
  Future<Map<String, int>> usadosPorPermisoStandalone() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return const {};
    try {
      final res = await supabase
          .from('anuncios')
          .select('id_permiso_usuario')
          .eq('tipo', 'standalone')
          .eq('creado_por', uid)
          .eq('estado', 'aprobado');
      final conteo = <String, int>{};
      for (final f in List<Map<String, dynamic>>.from(res)) {
        final idPermiso = (f['id_permiso_usuario'] ?? '').toString();
        if (idPermiso.isEmpty) continue;
        conteo[idPermiso] = (conteo[idPermiso] ?? 0) + 1;
      }
      return conteo;
    } catch (e) {
      debugPrint('usadosPorPermisoStandalone falló: $e');
      return const {};
    }
  }
  /// El cupo y la vigencia los resuelve el trigger
  /// anuncios_before_insert contra permisos_usuario_anuncios -- si no
  /// hay ranuras vigentes en el permiso elegido, el insert lanza
  /// 'CUPO_ANUNCIOS'.
  Future<void> crearAnuncioStandalone({
    required String titulo,
    required String texto,
    String? imagenUrl,
    String? idPermiso,
    double? precioUsd,
    String? whatsapp,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('SESION_REQUERIDA');
    await supabase.from('anuncios').insert({
      'tipo': 'standalone',
      'titulo': titulo,
      'texto': texto,
      if (imagenUrl != null && imagenUrl.isNotEmpty) 'imagen_url': imagenUrl,
      if (idPermiso != null && idPermiso.isNotEmpty)
        'id_permiso_usuario': idPermiso,
      if (precioUsd != null) 'precio_usd': precioUsd,
      if (whatsapp != null && whatsapp.trim().isNotEmpty)
        'whatsapp': whatsapp.trim(),
      'creado_por': uid,
    });
  }

  /// Mis anuncios independientes (para listarlos/gestionarlos).
  Future<List<Map<String, dynamic>>> misAnunciosStandalone() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return [];
    try {
      final res = await supabase
          .from('anuncios')
          .select()
          .eq('tipo', 'standalone')
          .eq('creado_por', uid)
          .order('creado_en', ascending: false);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('misAnunciosStandalone falló: $e');
      return [];
    }
  }

  /// Mis anuncios de negocio (para el sheet de gestión).
  Future<List<Map<String, dynamic>>> misAnunciosDeNegocio(
      String idNegocio) async {
    try {
      final res = await supabase
          .from('anuncios')
          .select()
          .eq('tipo', 'negocio')
          .eq('id_negocio', idNegocio)
          .order('creado_en', ascending: false);
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('misAnunciosDeNegocio falló: $e');
      return [];
    }
  }

  // ------------------------------------------------------------------
  // ACCIONES COMUNES SOBRE UN ANUNCIO PROPIO (cualquier tipo)
  // ------------------------------------------------------------------

  Future<void> editarContenido({
    required String idAnuncio,
    required String titulo,
    required String texto,
    String? imagenUrl,
    double? precioUsd,
    String? whatsapp,
  }) async {
    final data = <String, dynamic>{
      'titulo': titulo,
      'texto': texto,
    };
    if (imagenUrl != null) data['imagen_url'] = imagenUrl;
    if (precioUsd != null) data['precio_usd'] = precioUsd;
    if (whatsapp != null && whatsapp.trim().isNotEmpty) {
      data['whatsapp'] = whatsapp.trim();
    }
    await supabase.from('anuncios').update(data).eq('id_anuncio', idAnuncio);
  }

  Future<void> pausarAnuncio(String idAnuncio) async {
    await supabase
        .from('anuncios')
        .update({'estado': 'pausado'}).eq('id_anuncio', idAnuncio);
  }

  Future<void> activarAnuncio(String idAnuncio) async {
    await supabase
        .from('anuncios')
        .update({'estado': 'aprobado'}).eq('id_anuncio', idAnuncio);
  }

  Future<void> eliminarAnuncio(String idAnuncio) async {
    String? url;
    try {
      final res = await supabase
          .from('anuncios')
          .select('imagen_url')
          .eq('id_anuncio', idAnuncio)
          .maybeSingle();
      url = (res?['imagen_url'] as String?)?.trim();
    } catch (_) {}

    await supabase.from('anuncios').delete().eq('id_anuncio', idAnuncio);

    // Limpieza de la foto SOLO si es una subida original de anuncio
    // (carpeta /anuncios/). Un anuncio "potenciado" reusa la foto del
    // PRODUCTO (carpeta /productos/) -- borrar esa rompería el producto.
    if (url == null || url.isEmpty) return;
    if (!Uri.parse(url).pathSegments.contains('anuncios')) return;

    // Red de seguridad: si otro anuncio (improbable) comparte la misma
    // URL, no la borramos.
    try {
      final enUso = await supabase
          .from('anuncios')
          .select('id_anuncio')
          .eq('imagen_url', url)
          .limit(1);
      if ((enUso as List).isNotEmpty) return;
    } catch (_) {
      return; // no pudimos verificar -> conservador, no borrar
    }

    try {
      await StorageService().borrarFoto(url);
    } catch (_) {}
  }

  /// Compras de paquete de este negocio que aún esperan verificación
  /// del admin (estado='pendiente').
  Future<List<Map<String, dynamic>>> comprasPendientesDeNegocio(
      String idNegocio) async {
    try {
      final res = await supabase
          .from('compras_anuncio')
          .select()
          .eq('id_negocio', idNegocio)
          .eq('estado', 'pendiente');
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('comprasPendientesDeNegocio falló: $e');
      return [];
    }
  }
}