import 'dart:ui' show ImageFilter;
import 'dart:async';
import 'dart:math' as math;
import 'gestionar_planes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../core/supabase_client.dart';
import '../services/location_service.dart';
import '../services/tiendas_service.dart';
import '../services/productos_service.dart';
import '../services/currency_service.dart';
import 'package:provider/provider.dart';
import '../services/theme_provider.dart';
import '../core/app_colors.dart';

// Se añade 'hide supabase' para evitar el conflicto de nombres
// Asegúrate de que el import sea correcto y sin el "hide" que causaba el error anterior
import 'package:top_trading/widgets/product_detail_modal.dart';

import 'admin_panel_screen.dart';
import 'panel_vendedor_screen.dart';
import 'notifications_screen.dart';
import 'valorar_pedido_screen.dart';
import '../services/notificaciones_service.dart';

// ---------------------------------------------------------------------
// ESTILO VISUAL (paleta cálida coral + crema, tarjetas redondeadas,
// insignias tipo pill). Solo cambia apariencia: colores, formas,
// sombras y tipografía -- ninguna sección ni función se agregó o quitó.
// ---------------------------------------------------------------------
// Estos valores ahora viven en core/app_colors.dart (AppColors) para
// que toda la app los comparta -- se dejan estos alias para no tener
// que tocar las decenas de líneas de este archivo que ya los usan.
//
// FIX (paleta): _kCoral/_kCoralDark apuntaban a AppColors.coral (el
// naranja), pero según el propio app_colors.dart ese naranja es el
// "acento cálido VIP/premium/destacados", NO el color primario de
// marca -- el primario real de toda la app es el azul sistema
// (AppColors.primary). Por eso Home se veía "naranja feo" y
// desalineado del resto de las pantallas: apuntaban al color
// equivocado. _kGold sigue siendo el dorado exclusivo del sello VIP.
const _kCoral = AppColors.primary;
const _kCoralDark = AppColors.primaryDark;
const _kCream = AppColors.crema;
const _kInk = AppColors.ink;
const _kCardRadius = kCardRadius;
const _kGold = Color(0xFFD4AF37); // Sello "VIP" en todas las tarjetas de tienda

List<BoxShadow> get _kSoftShadow => [
      BoxShadow(
        color: _kCoral.withOpacity(0.10),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ];

enum _ModoCercanos { productos, tiendas }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _tiendasService = TiendasService();
  final _productosService = ProductosService();
  final _locationService = LocationService();
  // Guardada aparte de _cargarCercanas() para poder calcular distancia
  // también en la sección "Más Vendidos" (ver _distanciaKm más abajo).
  double? _miLat;
  double? _miLon;

  late Future<List<Map<String, dynamic>>> _premium;
  late Future<List<Map<String, dynamic>>> _trending;
  Future<List<Map<String, dynamic>>>? _productosCercanos;
  Future<List<Map<String, dynamic>>>? _tiendasCercanas;
  String? _errorUbicacion;

  // ---- Carrusel hero de tiendas premium (arriba del todo) ----
  final PageController _heroController = PageController();
  Timer? _heroAutoplayTimer;
  int _heroPaginaActual = 0;
  bool _heroAutoplayIniciado =
      false; // evita reiniciar el Timer en cada rebuild del FutureBuilder

  Map<String, dynamic>? _miTienda;
  bool _esAdmin = false;
  bool _cargandoRol = true;
  Map<String, dynamic>? _miAfiliado;

  // ---- Filtro / búsqueda del feed de cercanos ----
  _ModoCercanos _modo = _ModoCercanos.productos;

  bool _filtroDistanciaActivo = false;
  double _radioKm = 10;

  bool _filtroPrecioActivo = false;
  final _precioMinCtrl = TextEditingController(text: '0');
  final _precioMaxCtrl = TextEditingController();

  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  bool get _esVendedor => _miTienda != null;
  bool get _esPremium =>
      _miTienda != null &&
      (_miTienda!['plan'] as String? ?? 'basic') == 'premium';
  bool get _esAfiliado => _miAfiliado != null;

  // ---- Colores derivados del tema activo (claro/oscuro) ----
  // Estos SÍ cambian con el modo oscuro, a diferencia de _kCoral/_kInk/
  // _kCream que son la paleta de marca fija. Se usan para fondos de
  // tarjetas, texto y placeholders -- todo lo que antes estaba
  // hardcodeado en blanco/negro y por eso no respondía al toggle.
  bool get _esOscuro => Theme.of(context).brightness == Brightness.dark;
  Color get _colorFondo => Theme.of(context).scaffoldBackgroundColor;
  Color get _colorSuperficie => Theme.of(context).colorScheme.surface;
  Color get _colorTexto => _esOscuro ? const Color(0xFFF5F5F4) : _kInk;
  Color get _colorTextoSecundario =>
      _esOscuro ? const Color(0xFFA8A29E) : Colors.black54;
  Color get _colorPlaceholder =>
      _esOscuro ? const Color(0xFF2A2A2A) : Colors.grey.shade100;

  @override
  void initState() {
    super.initState();
    _premium = _tiendasService.obtenerCarruselPremium();
    _trending = _tiendasService.obtenerCarruselTrending(limite: 10);
    _cargarCercanas();
    _cargarRol();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _verificarAvisoDeValoracion());
  }

  /// Revisa si hay una notificación sin leer de tipo "valorar_servicio"
  /// (se crea automáticamente cuando el vendedor marca un pedido como
  /// completado -- ver notificar_pedido_completado() en SQL) y, si la
  /// hay, muestra un diálogo bloqueante pidiendo valorar la compra.
  /// Vuelve a aparecer cada vez que se abre Home hasta que el usuario
  /// elija "Valorar ahora" (que la marca como leída).
  Future<void> _verificarAvisoDeValoracion() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final notif = await supabase
        .from('notificaciones')
        .select()
        .eq('id_usuario', uid)
        .eq('tipo', 'valorar_servicio')
        .eq('leida', false)
        .order('creado_en')
        .limit(1)
        .maybeSingle();

    if (notif == null || !mounted) return;

    final data = notif['data'] as Map<String, dynamic>?;
    final idPedido = data?['id_pedido'] as String?;
    final idTienda = data?['id_tienda'] as String?;
    if (idPedido == null)
      return; // notificación mal formada, no bloqueamos al usuario

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(notif['titulo'] as String? ?? '¿Cómo fue tu compra?'),
        content: Text(notif['mensaje'] as String? ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Recuérdamelo más tarde'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await supabase.from('notificaciones').update({'leida': true}).eq(
                  'id_notificacion', notif['id_notificacion']);
              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ValorarPedidoScreen(
                    idPedido: idPedido,
                    idTienda: idTienda,
                  ),
                ),
              );
            },
            child: const Text('Valorar ahora'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _precioMinCtrl.dispose();
    _precioMaxCtrl.dispose();
    _busquedaCtrl.dispose();
    _heroAutoplayTimer?.cancel();
    _heroController.dispose();
    super.dispose();
  }

  // ---- Autoplay del carrusel hero: avanza de tienda cada 5s. Se
  // pausa mientras el usuario tiene el dedo encima (ver
  // NotificationListener<ScrollNotification> en _seccionFeaturedStoresHero)
  // y se reanuda al soltar. ----
  void _iniciarAutoplayHero(int cantidadTiendas) {
    if (_heroAutoplayIniciado || cantidadTiendas <= 1) return;
    _heroAutoplayIniciado = true;
    _reanudarAutoplayHero(cantidadTiendas);
  }

  void _reanudarAutoplayHero(int cantidadTiendas) {
    _heroAutoplayTimer?.cancel();
    if (cantidadTiendas <= 1) return;
    _heroAutoplayTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_heroController.hasClients) return;
      final siguiente = (_heroPaginaActual + 1) % cantidadTiendas;
      _heroController.animateToPage(
        siguiente,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _pausarAutoplayHero() {
    _heroAutoplayTimer?.cancel();
  }

  Future<void> _cargarRol() async {
    // FIX: antes esto era
    //   final tienda = await _tiendasService.obtenerMiTienda();
    //   final admin = await _tiendasService.esAdmin();
    // Si obtenerMiTienda() lanzaba una excepción por CUALQUIER motivo
    // (ej. quedó más de una fila con el mismo owner_id de pruebas
    // anteriores, y .maybeSingle() lanza si hay más de un resultado),
    // esAdmin() nunca se ejecutaba y _esAdmin se quedaba en false para
    // siempre -- el panel de admin desaparecía sin relación alguna con
    // si la cuenta era admin o no.
    //
    // Ahora cada chequeo es 100% independiente: ser admin no depende
    // en nada de si existe, falla, o se pudo cargar una tienda.
    bool admin = false;
    Map<String, dynamic>? tienda;
    Map<String, dynamic>? afiliado;

    try {
      admin = await _tiendasService.esAdmin();
    } catch (e) {
      debugPrint('Error verificando admin: $e');
    }

    try {
      tienda = await _tiendasService.obtenerMiTienda();
    } catch (e) {
      debugPrint('Error obteniendo tienda: $e');
    }

    try {
      afiliado = await _tiendasService.obtenerMiAfiliado();
    } catch (e) {
      debugPrint('Error obteniendo afiliado: $e');
    }

    if (mounted) {
      setState(() {
        _miTienda = tienda;
        _esAdmin = admin;
        _miAfiliado = afiliado;
        _cargandoRol = false;
      });
    }
  }

  Future<void> _cargarCercanas() async {
    setState(() {
      _errorUbicacion = null;
      _productosCercanos = null;
      _tiendasCercanas = null;
    });
    try {
      final pos = await _locationService.obtenerUbicacionActual();
      // FIX: verificamos `mounted` tras el await, igual que en _cargarRol.
      // Si el usuario navegó fuera de Home mientras se esperaba la
      // ubicación, llamar a setState aquí lanzaría una excepción.
      if (!mounted) return;
      _miLat = pos.latitude;
      _miLon = pos.longitude;

      final radio = _filtroDistanciaActivo ? _radioKm : 10.0;
      double? precioMin;
      double? precioMax;
      if (_filtroPrecioActivo && _modo == _ModoCercanos.productos) {
        precioMin = double.tryParse(_precioMinCtrl.text) ?? 0;
        precioMax = double.tryParse(_precioMaxCtrl.text);
      }

      setState(() {
        if (_modo == _ModoCercanos.productos) {
          _productosCercanos = _productosService.buscarProductosCercanos(
            lat: pos.latitude,
            lon: pos.longitude,
            radioKm: radio,
            precioMin: precioMin,
            precioMax: precioMax,
          );
        } else {
          _tiendasCercanas = _tiendasService.buscarTiendasCercanas(
            lat: pos.latitude,
            lon: pos.longitude,
            radioKm: radio,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorUbicacion = e.toString();
      });
    }
  }

  Future<bool> _onWillPop() async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Salir'),
            content: const Text('¿Desea salir de la aplicación?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('No')),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Sí')),
            ],
          ),
        ) ??
        false;
  }

  // FIX (logout no funcionaba): el ListTile llamaba a
  // _handleLogout(innerContext), y esta función hacía
  // Navigator.of(context).pop() (cerrar el drawer) usando ESE MISMO
  // context, y luego un `await` (signOut). El drawer se desmonta al
  // cerrarse, así que cuando el await terminaba, `innerContext.mounted`
  // ya era false y `context.go('/login')` nunca se ejecutaba.
  //
  // Ahora: el pop() del drawer se hace en el onTap (con innerContext,
  // que sí es válido en ese momento) y la lógica async usa el context/
  // mounted del propio State, que vive mientras HomeScreen exista.
  Future<void> _cerrarSesion() async {
    try {
      await supabase.auth.signOut();
      // Cierra el canal de Realtime y limpia la lista en memoria -- si
      // no, el próximo usuario que inicie sesión en este mismo
      // dispositivo podría ver por un instante las notificaciones del
      // anterior mientras se recarga.
      NotificacionesService.instance.limpiar();
      if (mounted) {
        // FIX: '/login' ya no existe (se fusionó con WelcomeScreen).
        // Ahora se redirige a '/', que es la ruta de WelcomeScreen.
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cerrar sesión: $e')),
        );
      }
    }
  }

  // FIX (doble pop): antes estas funciones volvían a hacer
  // Navigator.of(context).pop() aunque el drawer ya se había cerrado
  // desde el onTap del ListTile correspondiente. Eso terminaba
  // haciendo pop() sobre la propia pantalla HomeScreen (sacándola de
  // la pila, o lanzando un assertion si era la ruta raíz). Se quita
  // el pop duplicado: el cierre del drawer queda a cargo del onTap.
  void _abrirMiTienda() {
    if (_miTienda == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => PanelVendedorScreen(tienda: _miTienda!)),
    );
  }

  void _hacerVendedorPremium() {
    if (_miTienda == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GestionarPlanesScreen(tienda: _miTienda!),
      ),
    );
  }

  void _abrirAdmin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
    );
  }

  void _abrirPreguntasFrecuentes() {
    showDialog(
      context: context,
      builder: (_) => const AlertDialog(
        title: Text('Preguntas frecuentes'),
        content: Text('Sección en construcción.'),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // MODAL DE FILTROS (distancia, precio y modo Productos/Tiendas)
  // -----------------------------------------------------------------------
  Future<void> _abrirFiltro() async {
    _ModoCercanos modoTemp = _modo;
    bool distActivaTemp = _filtroDistanciaActivo;
    double radioTemp = _radioKm;
    bool precioActivoTemp = _filtroPrecioActivo;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final maxValido = double.tryParse(_precioMaxCtrl.text);
            final minValido = double.tryParse(_precioMinCtrl.text) ?? 0;
            final precioValido = !precioActivoTemp ||
                modoTemp != _ModoCercanos.productos ||
                (maxValido != null && maxValido > minValido && minValido >= 0);

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Filtrar búsqueda',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),

                  // Modo: Productos vs Tiendas
                  SegmentedButton<_ModoCercanos>(
                    segments: const [
                      ButtonSegment(
                        value: _ModoCercanos.productos,
                        label: Text('Productos'),
                        icon: Icon(Icons.shopping_bag_outlined),
                      ),
                      ButtonSegment(
                        value: _ModoCercanos.tiendas,
                        label: Text('Tiendas'),
                        icon: Icon(Icons.storefront_outlined),
                      ),
                    ],
                    selected: {modoTemp},
                    onSelectionChanged: (s) =>
                        setModalState(() => modoTemp = s.first),
                  ),
                  const SizedBox(height: 20),

                  // Filtro de distancia
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Filtrar por distancia'),
                    subtitle: Text(
                        'Radio de búsqueda: ${radioTemp.toStringAsFixed(0)} km'),
                    value: distActivaTemp,
                    onChanged: (v) => setModalState(() => distActivaTemp = v),
                  ),
                  if (distActivaTemp)
                    Slider(
                      value: radioTemp,
                      min: 1,
                      max: 100,
                      divisions: 99,
                      label: '${radioTemp.toStringAsFixed(0)} km',
                      onChanged: (v) => setModalState(() => radioTemp = v),
                    ),

                  // Filtro de precio (solo en modo Productos)
                  if (modoTemp == _ModoCercanos.productos) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Filtrar por precio'),
                      subtitle: const Text('Rango en USD'),
                      value: precioActivoTemp,
                      onChanged: (v) =>
                          setModalState(() => precioActivoTemp = v),
                    ),
                    if (precioActivoTemp) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _precioMinCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Mínimo',
                                prefixText: '\$ ',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => setModalState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _precioMaxCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Máximo',
                                prefixText: '\$ ',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => setModalState(() {}),
                            ),
                          ),
                        ],
                      ),
                      if (!precioValido)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'El máximo es obligatorio y debe ser mayor que el mínimo.',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                    ],
                  ],

                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setModalState(() {
                              distActivaTemp = false;
                              precioActivoTemp = false;
                              _precioMinCtrl.text = '0';
                              _precioMaxCtrl.clear();
                            });
                          },
                          child: const Text('Limpiar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: precioValido
                              ? () {
                                  setState(() {
                                    _modo = modoTemp;
                                    _filtroDistanciaActivo = distActivaTemp;
                                    _radioKm = radioTemp;
                                    _filtroPrecioActivo = precioActivoTemp;
                                  });
                                  Navigator.of(ctx).pop();
                                  _cargarCercanas();
                                }
                              : null,
                          child: const Text('Aplicar filtros'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // -----------------------------------------------------------------------
  // MODAL "VER TODAS" -- reutilizable para Destacadas/VIP y Más Vendidos.
  // Cada fila tiene tap completo + botón "Ver tienda" explícito: ambos
  // caminos llevan a la misma pantalla de tienda.
  // -----------------------------------------------------------------------
  Future<void> _abrirModalListaTiendas({
    required Future<List<Map<String, dynamic>>> future,
    required String titulo,
  }) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scrollController) {
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final tiendas = snapshot.data ?? [];
              return Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(titulo,
                        style: GoogleFonts.inter(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: _colorTexto)),
                  ),
                  Expanded(
                    child: tiendas.isEmpty
                        ? const Center(child: Text('Nada por aquí todavía'))
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            itemCount: tiendas.length,
                            itemBuilder: (context, i) {
                              final t = Map<String, dynamic>.from(tiendas[i]);
                              // Igual que en la sección "Popular esta semana":
                              // si el RPC no trae distancia_km ya calculada,
                              // la calculamos aquí mismo con la ubicación
                              // del usuario y la lat/lon de la tienda.
                              final tLat = (t['latitud'] as num?)?.toDouble();
                              final tLon = (t['longitud'] as num?)?.toDouble();
                              if (t['distancia_km'] == null &&
                                  _miLat != null &&
                                  _miLon != null &&
                                  tLat != null &&
                                  tLon != null) {
                                t['distancia_km'] =
                                    _distanciaKm(_miLat!, _miLon!, tLat, tLon);
                              }
                              final distancia =
                                  (t['distancia_km'] as num?)?.toDouble();
                              final esVip =
                                  (t['plan'] as String? ?? '').toLowerCase() ==
                                      'premium';

                              void irATienda() {
                                Navigator.of(ctx).pop();
                                context.push('/tienda/${t['id_tienda']}');
                              }

                              return ListTile(
                                onTap: irATienda,
                                leading: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    ClipOval(
                                      child: SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: Image.network(
                                          t['logo_url'] ?? '',
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              Container(
                                            color: _colorPlaceholder,
                                            child: Icon(Icons.storefront,
                                                size: 18,
                                                color: _colorTextoSecundario),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (esVip)
                                      Positioned(
                                        bottom: -2,
                                        right: -2,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            color: _kGold,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.star_rounded,
                                              size: 10, color: Colors.white),
                                        ),
                                      ),
                                  ],
                                ),
                                title: Text(t['nombre'] ?? '',
                                    style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  [
                                    if (t['municipio'] != null)
                                      '${t['municipio']}',
                                    if (distancia != null)
                                      '${distancia.toStringAsFixed(1)} km',
                                  ].join(' · '),
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: _colorTextoSecundario),
                                ),
                                trailing: TextButton(
                                  onPressed: irATienda,
                                  style: TextButton.styleFrom(
                                    backgroundColor: _kCoral.withOpacity(0.12),
                                    foregroundColor: _kCoralDark,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                  ),
                                  child: const Text('Ver tienda'),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _abrirModalPremium() =>
      _abrirModalListaTiendas(future: _premium, titulo: 'Tiendas Destacadas');

  Future<void> _abrirModalTopSellers() =>
      _abrirModalListaTiendas(future: _trending, titulo: 'Popular esta semana');

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: _colorFondo,
        drawer: Drawer(
          child: Builder(
            builder: (BuildContext innerContext) {
              final user = supabase.auth.currentUser;
              final avatarUrl = user?.userMetadata?['avatar_url'] as String?;
              final nombre = (user?.userMetadata?['full_name'] as String?) ??
                  (user?.userMetadata?['name'] as String?) ??
                  user?.email?.split('@').first ??
                  'Usuario';
              final email = user?.email ?? '';

              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  // ---------- Header: foto + nombre + email de Google ----------
                  // Tappable en vez de tener una fila "Mi Perfil" aparte --
                  // el chevron en la esquina es la pista visual de que se
                  // puede tocar para entrar al perfil.
                  InkWell(
                    onTap: () {
                      Navigator.of(innerContext).pop();
                      context.push('/mi-perfil');
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
                      decoration: const BoxDecoration(color: _kCoral),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 34,
                                backgroundColor: Colors.white,
                                backgroundImage:
                                    (avatarUrl != null && avatarUrl.isNotEmpty)
                                        ? NetworkImage(avatarUrl)
                                        : null,
                                child: (avatarUrl == null || avatarUrl.isEmpty)
                                    ? Text(
                                        nombre.isNotEmpty
                                            ? nombre[0].toUpperCase()
                                            : '?',
                                        style: GoogleFonts.inter(
                                            fontSize: 26,
                                            fontWeight: FontWeight.w800,
                                            color: _kCoral),
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              Text(nombre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800)),
                              if (email.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                        color: Colors.white.withOpacity(0.85),
                                        fontSize: 12.5)),
                              ],
                            ],
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.chevron_right_rounded,
                                  color: Colors.white, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (!_cargandoRol) ...[
                    ListTile(
                      leading: const Icon(Icons.map_rounded,
                          color: AppColors.primary),
                      title: Row(
                        children: [
                          const Text('Mapa'),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('NUEVO',
                                style: GoogleFonts.inter(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          ),
                        ],
                      ),
                      subtitle: const Text('Encuentra tiendas cerca de ti'),
                      onTap: () {
                        Navigator.of(innerContext).pop();
                        context.push('/mapa');
                      },
                    ),
                    if (_esAdmin)
                      ListTile(
                        leading: const Icon(Icons.admin_panel_settings,
                            color: Colors.deepPurple),
                        title: const Text('Panel de Admin'),
                        onTap: () {
                          Navigator.of(innerContext).pop();
                          _abrirAdmin();
                        },
                      ),
                    if (_esVendedor)
                      ListTile(
                        leading: const Icon(Icons.storefront_rounded),
                        title: const Text('Mi Tienda'),
                        subtitle: const Text('Gestionar productos y ventas'),
                        onTap: () {
                          Navigator.of(innerContext).pop();
                          _abrirMiTienda();
                        },
                      )
                    else
                      ListTile(
                        leading: const Icon(Icons.storefront),
                        title: const Text('Hacerte Vendedor'),
                        onTap: () {
                          Navigator.of(innerContext).pop();
                          context.push('/crear-tienda');
                        },
                      ),
                    if (_esAfiliado)
                      ListTile(
                        leading: const Icon(Icons.handshake_outlined,
                            color: Colors.teal),
                        title: const Text('Mi perfil de afiliado'),
                        subtitle: const Text('Saldo, comisiones y retiros'),
                        onTap: () {
                          Navigator.of(innerContext).pop();
                          context.push('/afiliados/perfil');
                        },
                      )
                    else
                      ListTile(
                        leading: const Icon(Icons.handshake_outlined),
                        title: const Text('Programa de afiliados'),
                        onTap: () {
                          Navigator.of(innerContext).pop();
                          context.push('/afiliados/registro');
                        },
                      ),
                    if (_esVendedor && !_esPremium)
                      ListTile(
                        leading: const Icon(Icons.workspace_premium_outlined,
                            color: Color(0xFFB8860B)),
                        title: const Text('Hacerte premium'),
                        onTap: () {
                          Navigator.of(innerContext).pop();
                          _hacerVendedorPremium();
                        },
                      ),
                    const Divider(),
                  ],
                  ListTile(
                    leading: const Icon(Icons.help_outline_rounded),
                    title: const Text('Preguntas frecuentes'),
                    onTap: () {
                      Navigator.of(innerContext).pop();
                      _abrirPreguntasFrecuentes();
                    },
                  ),
                  ListTile(
                    leading: Icon(
                        // Cambia el icono dependiendo del estado
                        Provider.of<ThemeProvider>(context).isDarkMode
                            ? Icons.dark_mode
                            : Icons.light_mode),
                    title: Text(Provider.of<ThemeProvider>(context).isDarkMode
                        ? "Modo Oscuro"
                        : "Modo Claro"),
                    trailing: Switch(
                      value: Provider.of<ThemeProvider>(context).isDarkMode,
                      onChanged: (value) {
                        // Aquí se invoca el cambio de tema
                        Provider.of<ThemeProvider>(context, listen: false)
                            .toggleTheme();
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Cerrar Sesión',
                        style: TextStyle(color: Colors.red)),
                    onTap: () {
                      // Cierra el drawer con el context del drawer (válido
                      // en este momento) y recién luego dispara la
                      // lógica async, que usa el context/mounted del State.
                      Navigator.of(innerContext).pop();
                      _cerrarSesion();
                    },
                  ),
                ],
              );
            },
          ),
        ),
        appBar: AppBar(
          titleSpacing: 0,
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: _kCoral,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
          title: Image.asset(
            'assets/logo.png',
            height: 40,
            errorBuilder: (context, error, stackTrace) => Text(
              'Al Lado',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
          ),
          actions: [
            AnimatedBuilder(
              animation: NotificacionesService.instance,
              builder: (context, _) {
                final noLeidas = NotificacionesService.instance.noLeidas;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined),
                      tooltip: 'Notificaciones',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        );
                      },
                    ),
                    if (noLeidas > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            noLeidas > 9 ? '9+' : '$noLeidas',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12, left: 4),
              child: Center(child: CurrencyToggle()),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _premium = _tiendasService.obtenerCarruselPremium();
              _trending = _tiendasService.obtenerCarruselTrending(limite: 10);
            });
            await _cargarCercanas();
            await _cargarRol();
          },
          child: ListView(
            children: [
              _seccionFeaturedStoresHero(),
              _seccionTopSellers(),
              const SizedBox(height: 8),
              _feedProductosCercanos(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seccionFeaturedStoresHero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tiendas Destacadas',
                  style: GoogleFonts.inter(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: _colorTexto)),
              TextButton(
                onPressed: _abrirModalPremium,
                style: TextButton.styleFrom(
                  foregroundColor: _kCoralDark,
                  textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
                child: const Text('Ver todas'),
              ),
            ],
          ),
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _premium,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AspectRatio(
                aspectRatio: 16 / 9,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              debugPrint('Error cargando carrusel premium: ${snapshot.error}');
              return const AspectRatio(
                aspectRatio: 16 / 9,
                child: Center(child: Text('No se pudo cargar')),
              );
            }
            final tiendas = snapshot.data ?? [];
            if (tiendas.isEmpty) {
              return const AspectRatio(
                aspectRatio: 16 / 9,
                child: Center(child: Text('Nada por aquí todavía')),
              );
            }

            // Arranca el autoplay una sola vez que ya sabemos cuántas
            // tiendas hay (después de este primer build, para no
            // llamar setState/animateToPage en medio de un build).
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _iniciarAutoplayHero(tiendas.length);
            });

            return AspectRatio(
              aspectRatio: 16 / 9,
              child: NotificationListener<ScrollNotification>(
                // Pausa el autoplay mientras el usuario arrastra a mano,
                // y lo reanuda al soltar -- así no "pelean" el gesto del
                // usuario y el avance automático.
                onNotification: (notif) {
                  if (notif is ScrollStartNotification &&
                      notif.dragDetails != null) {
                    _pausarAutoplayHero();
                  } else if (notif is ScrollEndNotification) {
                    _reanudarAutoplayHero(tiendas.length);
                  }
                  return false;
                },
                child: PageView.builder(
                  controller: _heroController,
                  itemCount: tiendas.length,
                  onPageChanged: (i) => setState(() => _heroPaginaActual = i),
                  itemBuilder: (context, i) {
                    final t = tiendas[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _HeroTiendaCard(
                        tienda: t,
                        tiendasService: _tiendasService,
                        esActiva: i == _heroPaginaActual,
                        onTap: () {
                          // TODO: acá va el modal de preview (foto,
                          // nombre, ubicación, estrellas + grilla de 3-4
                          // productos tocables) -- por ahora, mientras
                          // se construye ese paso, entra directo a la
                          // tienda para poder seguir probando el
                          // carrusel de punta a punta.
                          context.push('/tienda/${t['id_tienda']}');
                        },
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        // ---------- Indicador de puntos (qué tienda está activa) ----------
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _premium,
          builder: (context, snapshot) {
            final total = snapshot.data?.length ?? 0;
            if (total <= 1) return const SizedBox.shrink();
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(total, (i) {
                final activo = i == _heroPaginaActual;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: activo ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: activo ? _kCoral : _kCoral.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _seccionTopSellers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Popular esta semana',
                  style: GoogleFonts.inter(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: _colorTexto)),
              TextButton(
                onPressed: _abrirModalTopSellers,
                style: TextButton.styleFrom(
                  foregroundColor: _kCoralDark,
                  textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
                child: const Text('Ver todas'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 184,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _trending,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final tiendas = snapshot.data ?? [];
              if (tiendas.isEmpty) {
                return const Center(child: Text('Nada por aquí todavía'));
              }
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: tiendas.length,
                itemBuilder: (context, i) {
                  // El RPC de "más vendidos" no calcula distancia en el
                  // servidor (a diferencia de buscar_tiendas_cercanas,
                  // que sí la trae vía Haversine en SQL). Para no tocar
                  // el backend, la calculamos aquí mismo con la
                  // ubicación del usuario y la lat/lon que ya guarda
                  // cada tienda -- si falta cualquiera de esos datos,
                  // sencillamente no se agrega el chip de distancia.
                  final t = Map<String, dynamic>.from(tiendas[i]);
                  final tLat = (t['latitud'] as num?)?.toDouble();
                  final tLon = (t['longitud'] as num?)?.toDouble();
                  if (t['distancia_km'] == null &&
                      _miLat != null &&
                      _miLon != null &&
                      tLat != null &&
                      tLon != null) {
                    t['distancia_km'] =
                        _distanciaKm(_miLat!, _miLon!, tLat, tLon);
                  }
                  return SizedBox(
                    width: 148,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _tarjetaTienda(t),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // FEED DE CERCANOS: título + botón filtro + buscador + grid dual
  // -----------------------------------------------------------------------
  Widget _feedProductosCercanos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _modo == _ModoCercanos.productos
                    ? 'Productos Cercanos'
                    : 'Tiendas Cercanas',
                style: GoogleFonts.inter(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: _colorTexto),
              ),
              Container(
                decoration: BoxDecoration(
                  color: _kCoral.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.tune, size: 20, color: _kCoralDark),
                  tooltip: 'Filtrar',
                  onPressed: _abrirFiltro,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: _kSoftShadow,
            ),
            child: TextField(
              controller: _busquedaCtrl,
              onChanged: (v) => setState(() => _busqueda = v),
              style: GoogleFonts.inter(color: _colorTexto),
              decoration: InputDecoration(
                hintText: _modo == _ModoCercanos.productos
                    ? 'Buscar producto o tienda...'
                    : 'Buscar tienda...',
                hintStyle: GoogleFonts.inter(color: _colorTextoSecundario),
                prefixIcon: const Icon(Icons.search, color: _kCoral),
                suffixIcon: _busqueda.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _busquedaCtrl.clear();
                          _busqueda = '';
                        }),
                      ),
                filled: true,
                fillColor: _colorSuperficie,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_errorUbicacion != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_off_outlined, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No pudimos obtener tu ubicación. Activa el GPS para ver resultados cercanos.',
                      style: GoogleFonts.inter(fontSize: 12.5),
                    ),
                  ),
                  TextButton(
                    onPressed: _cargarCercanas,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          )
        else if (_modo == _ModoCercanos.productos)
          _gridProductos()
        else
          _gridTiendas(),
      ],
    );
  }

  Widget _gridProductos() {
    if (_productosCercanos == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _productosCercanos,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        var productos = snapshot.data ?? [];
        if (_busqueda.trim().isNotEmpty) {
          final q = _busqueda.trim().toLowerCase();
          productos = productos.where((p) {
            final nombre = (p['nombre'] ?? '').toString().toLowerCase();
            final tienda = (p['nombre_tienda'] ?? '').toString().toLowerCase();
            return nombre.contains(q) || tienda.contains(q);
          }).toList();
        }
        if (productos.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                _busqueda.isEmpty
                    ? 'No hay productos cerca de ti todavía'
                    : 'Sin resultados para "$_busqueda"',
                style: GoogleFonts.inter(color: _colorTextoSecundario),
              ),
            ),
          );
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.68,
          ),
          itemCount: productos.length,
          itemBuilder: (context, i) {
            final p = productos[i];
            return _tarjetaProducto(p, (p['distancia_km'] as num?)?.toDouble());
          },
        );
      },
    );
  }

  Widget _gridTiendas() {
    if (_tiendasCercanas == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _tiendasCercanas,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        var tiendas = snapshot.data ?? [];
        if (_busqueda.trim().isNotEmpty) {
          final q = _busqueda.trim().toLowerCase();
          tiendas = tiendas
              .where((t) =>
                  (t['nombre'] ?? '').toString().toLowerCase().contains(q))
              .toList();
        }
        if (tiendas.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                _busqueda.isEmpty
                    ? 'No hay tiendas cerca de ti todavía'
                    : 'Sin resultados para "$_busqueda"',
                style: GoogleFonts.inter(color: _colorTextoSecundario),
              ),
            ),
          );
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: tiendas.length,
          itemBuilder: (context, i) => _tarjetaTienda(tiendas[i]),
        );
      },
    );
  }

  /// Distancia en línea recta (km) entre dos coordenadas, fórmula de
  /// Haversine -- misma lógica que ya usa buscar_tiendas_cercanas en
  /// SQL, aquí en Dart porque el RPC de trending no la trae.
  double _distanciaKm(double lat1, double lon1, double lat2, double lon2) {
    const radioTierraKm = 6371.0;
    final dLat = _gradosARadianes(lat2 - lat1);
    final dLon = _gradosARadianes(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_gradosARadianes(lat1)) *
            math.cos(_gradosARadianes(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return radioTierraKm * c;
  }

  double _gradosARadianes(double grados) => grados * (math.pi / 180);

  Widget _tarjetaTienda(Map<String, dynamic> t) {
    final distancia = (t['distancia_km'] as num?)?.toDouble();
    final esVip = (t['plan'] as String? ?? '').toLowerCase() == 'premium';
    return GestureDetector(
      onTap: () => context.push('/tienda/${t['id_tienda']}'),
      child: Container(
        decoration: BoxDecoration(
          color: _colorSuperficie,
          borderRadius: BorderRadius.circular(_kCardRadius),
          boxShadow: _kSoftShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    t['logo_url'] ?? '',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: _colorPlaceholder,
                      child: Icon(Icons.storefront_outlined,
                          color: _colorTextoSecundario),
                    ),
                  ),
                  if (distancia != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _kCoral,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on,
                                size: 11, color: Colors.white),
                            const SizedBox(width: 3),
                            Text(
                              '${distancia.toStringAsFixed(1)} km',
                              style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (esVip)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: _kGold,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: _kSoftShadow,
                        ),
                        child: const Icon(Icons.star_rounded,
                            size: 13, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t['nombre'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: _colorTexto),
                  ),
                  if (t['promedio_estrellas'] != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: _kGold),
                        const SizedBox(width: 3),
                        Text(
                          '${(t['promedio_estrellas'] as num).toStringAsFixed(1)}',
                          style: GoogleFonts.inter(
                              fontSize: 11, color: _colorTextoSecundario),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaProducto(Map<String, dynamic> p, double? distanciaKm) {
    return GestureDetector(
      onTap: () => showProductDetailModal(
          context: context,
          productId: p['id_producto'],
          distanciaKm: distanciaKm),
      child: Container(
        decoration: BoxDecoration(
          color: _colorSuperficie,
          borderRadius: BorderRadius.circular(_kCardRadius),
          boxShadow: _kSoftShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    p['imagen_url'] ?? '',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: _colorPlaceholder,
                      child: Icon(Icons.image_not_supported_outlined,
                          color: _colorTextoSecundario),
                    ),
                  ),
                  if (distanciaKm != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _kCoral,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on,
                                size: 11, color: Colors.white),
                            const SizedBox(width: 3),
                            Text(
                              '${distanciaKm.toStringAsFixed(1)} km',
                              style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['nombre'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: _colorTexto),
                  ),
                  if ((p['nombre_tienda'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.storefront,
                            size: 11, color: _colorTextoSecundario),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            p['nombre_tienda'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                                fontSize: 11, color: _colorTextoSecundario),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: PriceTag(
                          montoUsd: (p['precio_usd'] as num?)?.toDouble() ?? 0,
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_kCoral, _kCoralDark],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add_rounded,
                            size: 16, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Tarjeta hero de una tienda premium para el carrusel de arriba de
// Home. Mientras esta tarjeta está "activa" (es la página visible del
// PageView), rota sola entre el logo de la tienda y las fotos de sus
// últimos productos disponibles -- un mini-carrusel dentro del
// carrusel grande, con crossfade. Se pausa cuando deja de ser la
// tienda activa, para no seguir corriendo un Timer por cada tarjeta
// fuera de pantalla.
// ---------------------------------------------------------------------
class _HeroTiendaCard extends StatefulWidget {
  final Map<String, dynamic> tienda;
  final TiendasService tiendasService;
  final bool esActiva;
  final VoidCallback onTap;

  const _HeroTiendaCard({
    required this.tienda,
    required this.tiendasService,
    required this.esActiva,
    required this.onTap,
  });

  @override
  State<_HeroTiendaCard> createState() => _HeroTiendaCardState();
}

class _HeroTiendaCardState extends State<_HeroTiendaCard> {
  late final Future<List<Map<String, dynamic>>> _productosFuture;
  Timer? _fotoTimer;
  int _fotoIndex = 0;

  @override
  void initState() {
    super.initState();
    _productosFuture = widget.tiendasService.obtenerProductosDestacadosDeTienda(
      widget.tienda['id_tienda'] as String,
    );
    if (widget.esActiva) _iniciarRotacionFotos();
  }

  @override
  void didUpdateWidget(covariant _HeroTiendaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.esActiva && !oldWidget.esActiva) {
      _iniciarRotacionFotos();
    } else if (!widget.esActiva && oldWidget.esActiva) {
      _fotoTimer?.cancel();
      if (mounted) setState(() => _fotoIndex = 0);
    }
  }

  void _iniciarRotacionFotos() {
    _fotoTimer?.cancel();
    _fotoTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() => _fotoIndex++);
    });
  }

  @override
  void dispose() {
    _fotoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tienda;
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kCardRadius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kCardRadius),
            // ---- Estilo "vidrio flotante": borde suave translúcido +
            // sombra grande y difusa (más pronunciada que _kSoftShadow,
            // que es para tarjetas chicas), para que se sienta como si
            // la tarjeta flotara sobre el fondo. ----
            border: Border.all(
              color: (esOscuro ? AppColors.borderDark : AppColors.borderLight)
                  .withOpacity(0.6),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(esOscuro ? 0.45 : 0.20),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
            ],
            color: Colors.grey.shade300,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ---- Foto de fondo: rota entre logo y productos ----
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _productosFuture,
                builder: (context, snapshot) {
                  final fotos = <String>[
                    if ((t['logo_url'] as String?)?.isNotEmpty ?? false)
                      t['logo_url'] as String,
                    ...((snapshot.data ?? [])
                        .map((p) => p['imagen_url'] as String?)
                        .whereType<String>()
                        .where((u) => u.isNotEmpty)),
                  ];
                  if (fotos.isEmpty) {
                    return Container(color: Colors.grey.shade300);
                  }
                  final url = fotos[_fotoIndex % fotos.length];
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: Image.network(
                      url,
                      key: ValueKey(url),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: Colors.grey.shade300),
                    ),
                  );
                },
              ),
              // ---- Degradado inferior + nombre/ubicación ----
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.5, 1],
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.80),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(18),
                alignment: Alignment.bottomLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t['nombre'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.place_rounded,
                            size: 14, color: Colors.white70),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${t['municipio'] ?? ''}, ${t['provincia'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                                fontSize: 13, color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // ---- Sello VIP (vidrio esmerilado real sobre la foto) ----
              Positioned(
                top: 16,
                left: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.28),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.4), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 15, color: _kGold),
                          const SizedBox(width: 4),
                          Text('TIENDA VIP',
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // ---- "Ver tienda" affordance, esquina inferior derecha ----
              Positioned(
                right: 16,
                bottom: 16,
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withOpacity(0.4), width: 1),
                      ),
                      child: const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
