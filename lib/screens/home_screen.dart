import 'dart:ui' show ImageFilter;
import 'dart:async';
import 'dart:math' as math;
import 'gestionar_planes_screen.dart';
import 'standalone_anuncio_screen.dart';
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
import '../services/tienda_state_service.dart';
import '../services/afiliado_state_service.dart';
import '../services/connectivity_service.dart';
import '../services/anuncios_service.dart';
import '../services/anuncios_state_service.dart';
import '../services/negocio_state_service.dart';
import '../core/app_colors.dart';

import 'package:top_trading/widgets/product_detail_modal.dart';
import 'package:top_trading/widgets/tarjeta_anuncio.dart';

import 'panel_vendedor_screen.dart';
import '../widgets/notification_bell.dart';
import 'valorar_pedido_screen.dart';
import '../services/notificaciones_service.dart';
import 'tasa_cambio_screen.dart';
import '../core/provincias_cuba.dart';

// ---------------------------------------------------------------------
// ESTILO VISUAL -- ver notas originales de paleta.
// ---------------------------------------------------------------------
const _kCoral = AppColors.primary;
const _kCoralDark = AppColors.primaryDark;
const _kCream = AppColors.crema;
const _kInk = AppColors.ink;
const _kCardRadius = kCardRadius;
const _kGold = Color(0xFFD4AF37);

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
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _tiendasService = TiendasService();
  final _productosService = ProductosService();
  final _locationService = LocationService();
  final _anunciosService = AnunciosService();
  double? _miLat;
  double? _miLon;

  // ANUNCIOS: dos futuros -- el del feed (se intercala cada 3 bloques de
  // tienda) y el del carrusel superior (solo admin). Se recargan con el
  // pull-to-refresh y TAMBIÉN cada vez que vuelves a la pestaña Inicio
  // (rotarAnuncios, llamada desde MainShellScreen) para que con muchas
  // tiendas/anuncios todos roten sin esperar el refresh manual.
  late Future<List<Anuncio>> _anunciosFeed;
  late Future<List<Anuncio>> _anunciosCarrusel;
  // CTA nativo "promociona tu negocio": se decide una vez por carga
  // (RPC cta_negocio_activo) y se pinta como banner ocasional.
  bool _ctaNegocio = false;

  void _cargarAnuncios() {
    if (!ConnectivityService.instance.online) {
      _anunciosFeed = Future.value(const []);
      _anunciosCarrusel = Future.value(const []);
      _ctaNegocio = false;
      return;
    }
    _anunciosFeed = _anunciosService.obtenerFeed(cantidad: 3);
    _anunciosCarrusel = _anunciosService.obtenerCarrusel(limite: 5);
    // Estado del negocio propio (para ocultar el CTA si ya registró
    // uno). El catch interno del servicio lo hace offline-safe.
    NegocioStateService.instance.refrescar();
    _anunciosService
        .ctaNegocioActivo()
        .then((v) {
          if (mounted) setState(() => _ctaNegocio = v);
        })
        .catchError((_) {});
  }

  /// Rotación de anuncios al volver a la pestaña Inicio (opción B).
  /// Público: lo invoca MainShellScreen vía GlobalKey cuando el usuario
  /// navega de vuelta a esta pestaña. Solo regenera los anuncios; el
  /// resto del contenido (carruseles, cercanas) NO se recarga.
  void rotarAnuncios() {
    _cargarAnuncios();
    if (mounted) setState(() {});
  }

  late Future<List<Map<String, dynamic>>> _premium;
  late Future<List<Map<String, dynamic>>> _trending;
  Future<List<Map<String, dynamic>>>? _productosCercanos;
  Future<List<Map<String, dynamic>>>? _tiendasCercanas;
  String? _errorUbicacion;

  final PageController _heroController = PageController();
  Timer? _heroAutoplayTimer;
  int _heroPaginaActual = 0;
  bool _heroAutoplayIniciado = false;

  _ModoCercanos _modo = _ModoCercanos.productos;

  bool _filtroDistanciaActivo = false;
  double _radioKm = 10;

  bool _filtroPrecioActivo = false;
  String? _categoriaSeleccionada;
  String? _provinciaSeleccionada;
  String? _municipioSeleccionado;
  final _precioMinCtrl = TextEditingController(text: '0');
  final _precioMaxCtrl = TextEditingController();

  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  final Map<String, Future<Map<String, dynamic>?>> _tiendaInfoCache = {};

  Future<Map<String, dynamic>?> _tiendaInfo(String idTienda) {
    return _tiendaInfoCache.putIfAbsent(
      idTienda,
      () =>
          _tiendasService.obtenerTiendaPorId(idTienda).catchError((_) => null),
    );
  }

  Map<String, dynamic>? get _miTienda => TiendaStateService.instance.miTienda;
  Map<String, dynamic>? get _miAfiliado =>
      AfiliadoStateService.instance.miAfiliado;
  bool get _cargandoRol =>
      TiendaStateService.instance.cargando ||
      AfiliadoStateService.instance.cargando;
  bool get _esVendedor => _miTienda != null;
  bool get _esPremium =>
      _miTienda != null &&
      (_miTienda!['plan'] as String? ?? 'basic') == 'premium';
  bool get _esAfiliado => _miAfiliado != null;

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
    _cargarAnuncios();
    _cargarCercanas();
    TiendaStateService.instance.cargar();
    AfiliadoStateService.instance.cargar();
    // Sesión restaurada en frío: sin esto los canales de notificaciones
    // y de "mis anuncios" nunca arrancan al reabrir la app ya logueado.
    if (supabase.auth.currentUser != null) {
      NotificacionesService.instance.iniciar();
      AnunciosStateService.instance.iniciar();
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _verificarAvisoDeValoracion());
  }

  Future<void> _verificarAvisoDeValoracion() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    if (!ConnectivityService.instance.online) return;

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
    if (idPedido == null) return;

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
    await Future.wait([
      TiendaStateService.instance.refrescar(),
      AfiliadoStateService.instance.refrescar(),
    ]);
  }

  Future<void> _cargarCercanas() async {
    setState(() {
      _errorUbicacion = null;
      _productosCercanos = null;
      _tiendasCercanas = null;
    });
    try {
      final pos = await _locationService.obtenerUbicacionActual();
      if (!mounted) return;
      _miLat = pos.latitude;
      _miLon = pos.longitude;

      final radio = _filtroDistanciaActivo ? _radioKm : 20000.0;
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

  Future<void> _cerrarSesion() async {
    try {
      await supabase.auth.signOut();
      NotificacionesService.instance.limpiar();
      AnunciosStateService.instance.limpiar();
      if (mounted) {
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

  void _abrirPreguntasFrecuentes() {
    showDialog(
      context: context,
      builder: (_) => const AlertDialog(
        title: Text('Preguntas frecuentes'),
        content: Text('Sección en construcción.'),
      ),
    );
  }

  Future<void> _abrirFiltro() async {
    _ModoCercanos modoTemp = _modo;
    bool distActivaTemp = _filtroDistanciaActivo;
    double radioTemp = _radioKm;
    bool precioActivoTemp = _filtroPrecioActivo;
    String? categoriaTemp = _categoriaSeleccionada;
    String? provinciaTemp = _provinciaSeleccionada;
    String? municipioTemp = _municipioSeleccionado;

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
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: categoriaTemp,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Categoría',
                      prefixIcon: Icon(Icons.category_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todas las categorías'),
                      ),
                      ...kCategoriasTienda.map(
                        (c) => DropdownMenuItem<String?>(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (v) => setModalState(() => categoriaTemp = v),
                  ),
                  const SizedBox(height: 16),
                  Text('Ubicación',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: provinciaTemp,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Provincia',
                      prefixIcon: Icon(Icons.location_city_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todas las provincias'),
                      ),
                      ...kProvinciasCuba.map(
                        (p) => DropdownMenuItem<String?>(
                          value: p,
                          child: Text(p, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (v) => setModalState(() {
                      provinciaTemp = v;
                      municipioTemp = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: municipioTemp,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Municipio',
                      prefixIcon: Icon(Icons.place_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todos los municipios'),
                      ),
                      if (provinciaTemp != null)
                        ...municipiosDe(provinciaTemp!).map(
                          (m) => DropdownMenuItem<String?>(
                            value: m,
                            child:
                                Text(m, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                    ],
                    onChanged: (v) =>
                        setModalState(() => municipioTemp = v),
                  ),
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
                              categoriaTemp = null;
                              provinciaTemp = null;
                              municipioTemp = null;
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
                                    _categoriaSeleccionada = categoriaTemp;
                                    _provinciaSeleccionada = provinciaTemp;
                                    _municipioSeleccionado = municipioTemp;
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

  /// "Ver todos" de los carruseles (Destacadas y Popular esta semana).
  /// FIX (2026-08): ahora es un widget con BUSCADOR -- filtra en vivo
  /// por nombre, municipio, provincia, categoría o descripción.
  void _abrirModalListaTiendas({
    required Future<List<Map<String, dynamic>>> future,
    required String titulo,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scrollController) => _ModalListaTiendas(
          future: future,
          titulo: titulo,
          scrollController: scrollController,
          miLat: _miLat,
          miLon: _miLon,
        ),
      ),
    );
  }

  void _abrirModalPremium() =>
      _abrirModalListaTiendas(future: _premium, titulo: 'Tiendas Destacadas');

  void _abrirModalTopSellers() =>
      _abrirModalListaTiendas(future: _trending, titulo: 'Popular esta semana');

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: TiendaStateService.instance,
      builder: (context, _) => AnimatedBuilder(
        animation: AfiliadoStateService.instance,
        builder: (context, __) => _buildScaffold(context),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      extendBodyBehindAppBar: true,
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

                // NUEVO: acceso directo a "Mis Pedidos" (historial de
                // compras del usuario) -- antes la ruta '/mis-pedidos'
                // existía en router.dart pero no estaba enlazada desde
                // ningún lado de la navegación.
                if (supabase.auth.currentUser != null)
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: const Text('Mis Pedidos'),
                    onTap: () {
                      Navigator.of(innerContext).pop();
                      context.push('/mis-pedidos');
                    },
                  ),

                if (!_cargandoRol) ...[
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
                  leading: Icon(Provider.of<ThemeProvider>(context).isDarkMode
                      ? Icons.dark_mode
                      : Icons.light_mode),
                  title: Text(Provider.of<ThemeProvider>(context).isDarkMode
                      ? "Modo Oscuro"
                      : "Modo Claro"),
                  trailing: Switch(
                    value: Provider.of<ThemeProvider>(context).isDarkMode,
                    onChanged: (value) {
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
                    Navigator.of(innerContext).pop();
                    _cerrarSesion();
                  },
                ),
              ],
            );
          },
        ),
      ),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(26)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AppBar(
              titleSpacing: 0,
              centerTitle: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: _kCoral.withOpacity(0.85),
              surfaceTintColor: Colors.transparent,
              shape: const RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(26)),
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
                // NUEVO: punto de estado online/oscuro -- verde con
                // wifi si hay conexión, rojo tachado si no. Toque
                // muestra un mensaje breve, no navega a ningún lado.
                AnimatedBuilder(
                  animation: ConnectivityService.instance,
                  builder: (context, _) {
                    final online = ConnectivityService.instance.online;
                    return Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Tooltip(
                        message: online
                            ? 'Conectado'
                            : 'Sin conexión -- viendo datos guardados',
                        child: Icon(
                          online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                          size: 20,
                          color: online ? Colors.white : Colors.amber.shade200,
                        ),
                      ),
                    );
                  },
                ),
                const NotificationBell(),
                IconButton(
                  icon: const Icon(Icons.currency_exchange_rounded),
                  tooltip: 'Tasa de Cambio',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const TasaCambioScreen()),
                    );
                  },
                ),
                const Padding(
                  padding: EdgeInsets.only(right: 12, left: 4),
                  child: Center(child: CurrencyToggle()),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _premium = _tiendasService.obtenerCarruselPremium();
            _trending = _tiendasService.obtenerCarruselTrending(limite: 10);
            _cargarAnuncios();
          });
          await _cargarCercanas();
          await _cargarRol();
        },
        child: ListView(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + kToolbarHeight,
            bottom: MediaQuery.of(context).padding.bottom + 96,
          ),
          children: [
            _seccionAnunciosAdmin(),
            _seccionFeaturedStoresHero(),
            _seccionTopSellers(),
            const SizedBox(height: 16),
            if (!_busquedaActiva) _bannerCtaNegocio(),
            const SizedBox(height: 16),
            if (!_busquedaActiva) _bannerCtaAnuncioIndependiente(),
            const SizedBox(height: 16),
            _feedProductosCercanos(),
          ],
        ),
      ),
    );
  }

  // ¿Hay búsqueda o filtros activos? Mismo criterio que oculta los
  // anuncios del grid: con intención de compra clara no estorbamos.
  bool get _busquedaActiva =>
      _busqueda.trim().isNotEmpty ||
      _filtroDistanciaActivo ||
      _filtroPrecioActivo ||
      _provinciaSeleccionada != null ||
      _municipioSeleccionado != null;

  Widget _bannerCtaNegocio() {
    if (!_ctaNegocio) return const SizedBox.shrink();
    // Si el usuario ya tiene un negocio (en revisión o aprobado), el
    // banner desaparece: no hay nada que registrar y evitaríamos que
    // cree duplicados.
    return AnimatedBuilder(
      animation: NegocioStateService.instance,
      builder: (context, _) {
        if (NegocioStateService.instance.tieneNegocio ||
            NegocioStateService.instance.cargando) {
          return const SizedBox.shrink();
        }
        return _bannerCtaNegocioContenido();
      },
    );
  }

  Widget _bannerCtaNegocioContenido() {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GestureDetector(
        onTap: () => context.push('/registrar-negocio'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.warm,
                const Color(0xFFD94800),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.warm.withOpacity(esOscuro ? 0.35 : 0.25),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(esOscuro ? 0.25 : 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  bottom: -30,
                  right: -20,
                  child: IgnorePointer(
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.10),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: -20,
                  right: 40,
                  child: IgnorePointer(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.06),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.20),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '🌟  PROMOCIONA TU NEGOCIO',
                            style: GoogleFonts.inter(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '¿Quieres darte a conocer?',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Promociona tu negocio, servicios, eventos, fiestas y mucho más',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            height: 1.3,
                            color: Colors.white.withOpacity(0.82),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.20),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Registrarme ahora',
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(Icons.arrow_forward_rounded,
                                  size: 11, color: Colors.white),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 14,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.20),
                    ),
                    child: const Icon(Icons.storefront_rounded,
                        size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bannerCtaAnuncioIndependiente() {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const StandaloneAnuncioScreen(),
            ),
          );
        },
        child: Container(
          height: 104,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF97316), Color(0xFFC2410C)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF97316).withOpacity(esOscuro ? 0.30 : 0.22),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('¿Quieres vender tu moto?',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5)),
                      const SizedBox(height: 4),
                      Text(
                        'Crea un anuncio y se lo mostramos a todo el mercado.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 11.5,
                            height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Crear',
                          style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5)),
                      const SizedBox(width: 3),
                      const Icon(Icons.arrow_forward_rounded,
                          size: 13, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ANUNCIOS ADMIN: carrusel superior (máx 5, rotación aleatoria del
  // backend). Si no hay anuncios aprobados, la sección desaparece
  // completa -- no deja hueco.
  Widget _seccionAnunciosAdmin() {    return FutureBuilder<List<Anuncio>>(
      future: _anunciosCarrusel,
      builder: (context, snapshot) {
        final anuncios = snapshot.data ?? const <Anuncio>[];
        if (anuncios.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            SizedBox(
              height: 150,
              child: PageView.builder(
                itemCount: anuncios.length,
                controller: PageController(viewportFraction: 0.94),
                itemBuilder: (context, i) =>
                    TarjetaCarruselAnuncio(anuncio: anuncios[i]),
              ),
            ),
            const SizedBox(height: 4),
          ],
        );
      },
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

            WidgetsBinding.instance.addPostFrameCallback((_) {
              _iniciarAutoplayHero(tiendas.length);
            });

            return AspectRatio(
              aspectRatio: 16 / 9,
              child: NotificationListener<ScrollNotification>(
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
        if (_categoriaSeleccionada != null) {
          productos = productos
              .where((p) => p['categoria'] == _categoriaSeleccionada)
              .toList();
        }
        if (_provinciaSeleccionada != null ||
            _municipioSeleccionado != null) {
          productos = productos.where(_coincideUbicacion).toList();
        }
        if (productos.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                _busqueda.isEmpty &&
                        _provinciaSeleccionada == null &&
                        _municipioSeleccionado == null
                    ? 'No hay productos cerca de ti todavía'
                    : 'Sin resultados para los filtros aplicados',
                style: GoogleFonts.inter(color: _colorTextoSecundario),
              ),
            ),
          );
        }
        final grupos = <String, List<Map<String, dynamic>>>{};
        for (final p in productos) {
          final idT = (p['id_tienda'] ?? '').toString();
          grupos.putIfAbsent(idT, () => []).add(p);
        }
        final entradas = grupos.entries.toList()
          ..sort((a, b) {
            final da = a.value
                .map((p) => (p['distancia_km'] as num?)?.toDouble() ?? 999999)
                .reduce(math.min);
            final db = b.value
                .map((p) => (p['distancia_km'] as num?)?.toDouble() ?? 999999)
                .reduce(math.min);
            return da.compareTo(db);
          });

        final bloques = entradas.map((entrada) {
            final idTienda = entrada.key;
            final productosTienda = entrada.value;
            final primero = productosTienda.first;
            final nombreTienda = primero['nombre_tienda'] as String? ?? '';
            final logoTienda = primero['logo_url'] as String?;
            final estrellasTienda =
                (primero['promedio_estrellas'] as num?)?.toDouble();
            final esPremium =
                (primero['plan'] as String? ?? '').toLowerCase() == 'premium';
            final distanciaMin = productosTienda
                .map((p) => (p['distancia_km'] as num?)?.toDouble())
                .whereType<double>()
                .fold<double?>(
                    null, (min, d) => min == null || d < min ? d : min);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headerGrupoTienda(
                  idTienda: idTienda,
                  nombreTiendaFallback: nombreTienda,
                  logoFallback: logoTienda,
                  estrellasFallback: estrellasTienda,
                  esPremiumFallback: esPremium,
                  distanciaMin: distanciaMin,
                ),
                SizedBox(
                  height: 176,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: productosTienda.length,
                    itemBuilder: (context, i) {
                      final p = productosTienda[i];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 108,
                            child: _tarjetaProducto(
                                p, (p['distancia_km'] as num?)?.toDouble()),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            }).toList();

        // ANUNCIOS: sin búsqueda ni filtros activos se intercala una
        // tarjeta cada 3 bloques de tienda (reglas FASE 0). Cuando el
        // usuario busca o filtra quiere resultados, no promociones.
        final buscando = _busqueda.trim().isNotEmpty ||
            _categoriaSeleccionada != null ||
            _filtroPrecioActivo;
        if (buscando) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: bloques,
          );
        }
        return FutureBuilder<List<Anuncio>>(
          future: _anunciosFeed,
          builder: (context, snapAds) {
            final anuncios = snapAds.data ?? const <Anuncio>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _intercalarAnuncios(bloques, anuncios),
            );
          },
        );
      },
    );
  }

  /// Intercalado: 1 TarjetaAnuncio cada 3 bloques de tienda completos,
  /// máximo 3 por sesión (la prioridad admin->negocio->producto y los
  /// cupos ya los resuelve la RPC en el backend).
  List<Widget> _intercalarAnuncios(
      List<Widget> bloques, List<Anuncio> anuncios) {
    if (anuncios.isEmpty) return bloques;
    final out = <Widget>[];
    var iAnuncio = 0;
    for (var i = 0; i < bloques.length; i++) {
      out.add(bloques[i]);
      if ((i + 1) % 3 == 0 && iAnuncio < anuncios.length && iAnuncio < 3) {
        out.add(TarjetaAnuncio(anuncio: anuncios[iAnuncio]));
        iAnuncio++;
      }
    }
    return out;
  }

  Widget _headerGrupoTienda({
    required String idTienda,
    required String nombreTiendaFallback,
    String? logoFallback,
    double? estrellasFallback,
    required bool esPremiumFallback,
    required double? distanciaMin,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 12, 8),
      child: GestureDetector(
        onTap: () => context.push('/tienda/$idTienda'),
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _tiendaInfo(idTienda),
          builder: (context, snapshot) {
            final tienda = snapshot.data;
            final nombreTienda =
                (tienda?['nombre'] as String?) ?? nombreTiendaFallback;
            final logoTienda = (tienda?['logo_url'] as String?) ?? logoFallback;
            final estrellasTienda =
                (tienda?['promedio_estrellas'] as num?)?.toDouble() ??
                    estrellasFallback;
            final esPremium = tienda != null
                ? (tienda['plan'] as String? ?? '').toLowerCase() == 'premium'
                : esPremiumFallback;

            return Row(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.all(esPremium ? 2 : 0),
                      decoration: esPremium
                          ? BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: _kGold, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: _kGold.withOpacity(0.45),
                                  blurRadius: 8,
                                  spreadRadius: 0.5,
                                ),
                              ],
                            )
                          : null,
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: _colorPlaceholder,
                        backgroundImage:
                            (logoTienda != null && logoTienda.isNotEmpty)
                                ? NetworkImage(logoTienda)
                                : null,
                        child: (logoTienda == null || logoTienda.isEmpty)
                            ? Icon(Icons.storefront_rounded,
                                color: _colorTextoSecundario, size: 22)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 12, color: Color(0xFFD4AF37)),
                        const SizedBox(width: 2),
                        Text(
                          estrellasTienda != null
                              ? estrellasTienda.toStringAsFixed(1)
                              : 'Nuevo',
                          style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: _colorTextoSecundario),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(nombreTienda,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: _colorTexto)),
                      if (distanciaMin != null) ...[
                        const SizedBox(height: 2),
                        Text('${distanciaMin.toStringAsFixed(1)} km',
                            style: GoogleFonts.inter(
                                fontSize: 11.5, color: _colorTextoSecundario)),
                      ],
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/tienda/$idTienda'),
                  child: const Text('Ver todo'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// ¿El resultado (producto o tienda) coincide con el filtro de
  /// provincia/municipio? Lee los campos de ubicación del propio
  /// registro. Tanto productos_cercanos como buscar_tiendas_cercanas
  /// incluyen los campos provincia/municipio de la tienda padre en cada
  /// fila del resultado.
  bool _coincideUbicacion(Map<String, dynamic> fila) {
    if (_provinciaSeleccionada == null && _municipioSeleccionado == null) {
      return true;
    }
    final provincia = (fila['provincia'] as String?)?.trim();
    final municipio = (fila['municipio'] as String?)?.trim();

    if (_provinciaSeleccionada != null &&
        (provincia == null || provincia.isEmpty)) {
      return false;
    }
    if (_provinciaSeleccionada != null && provincia != _provinciaSeleccionada) {
      return false;
    }
    if (_municipioSeleccionado != null &&
        (municipio == null || municipio.isEmpty)) {
      return false;
    }
    if (_municipioSeleccionado != null && municipio != _municipioSeleccionado) {
      return false;
    }
    return true;
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
        if (_categoriaSeleccionada != null) {
          tiendas = tiendas
              .where((t) => t['categoria'] == _categoriaSeleccionada)
              .toList();
        }
        if (_provinciaSeleccionada != null ||
            _municipioSeleccionado != null) {
          tiendas = tiendas.where(_coincideUbicacion).toList();
        }
        if (tiendas.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                _busqueda.isEmpty &&
                        _provinciaSeleccionada == null &&
                        _municipioSeleccionado == null
                    ? 'No hay tiendas cerca de ti todavía'
                    : 'Sin resultados para los filtros aplicados',
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
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 14, color: _kGold),
                      const SizedBox(width: 3),
                      Text(
                        t['promedio_estrellas'] != null
                            ? (t['promedio_estrellas'] as num)
                                .toStringAsFixed(1)
                            : 'Nuevo',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: _colorTextoSecundario),
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

  Widget _tarjetaProducto(Map<String, dynamic> p, double? distanciaKm) {
    return GestureDetector(
      onTap: () => showProductDetailModal(
          context: context,
          productId: p['id_producto'],
          distanciaKm: distanciaKm),
      child: Container(
        decoration: BoxDecoration(
          color: _colorSuperficie.withOpacity(_esOscuro ? 0.55 : 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withOpacity(_esOscuro ? 0.08 : 0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 88,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    p['imagen_url'] ?? '',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: _colorPlaceholder,
                      child: Icon(Icons.image_not_supported_outlined,
                          size: 18, color: _colorTextoSecundario),
                    ),
                  ),
                  if (distanciaKm != null)
                    Positioned(
                      top: 5,
                      left: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${distanciaKm.toStringAsFixed(1)}km',
                          style: GoogleFonts.inter(
                              fontSize: 8.5,
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['nombre'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: _colorTexto),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: PriceTag(
                          montoUsd: (p['precio_usd'] as num?)?.toDouble() ?? 0,
                          style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(3.5),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_kCoral, _kCoralDark],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add_rounded,
                            size: 11, color: Colors.white),
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
// Tarjeta hero de una tienda premium para el carrusel de arriba.
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
              Positioned(
                top: 16,
                right: 16,
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
                          Text(
                            t['promedio_estrellas'] != null
                                ? (t['promedio_estrellas'] as num)
                                    .toStringAsFixed(1)
                                : 'Nuevo',
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
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

/// Listado completo "Ver todos" de los carruseles del Home
/// (Tiendas Destacadas y Popular esta semana), con buscador en vivo.
class _ModalListaTiendas extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> future;
  final String titulo;
  final ScrollController scrollController;
  final double? miLat;
  final double? miLon;

  const _ModalListaTiendas({
    required this.future,
    required this.titulo,
    required this.scrollController,
    this.miLat,
    this.miLon,
  });

  @override
  State<_ModalListaTiendas> createState() => _ModalListaTiendasState();
}

class _ModalListaTiendasState extends State<_ModalListaTiendas> {
  String _busqueda = '';

  bool get _esOscuro => Theme.of(context).brightness == Brightness.dark;
  Color get _colorTexto => _esOscuro ? const Color(0xFFF5F5F4) : _kInk;
  Color get _colorTextoSecundario =>
      _esOscuro ? const Color(0xFFA8A29E) : Colors.black54;
  Color get _colorPlaceholder =>
      _esOscuro ? const Color(0xFF2A2A2A) : Colors.grey.shade100;

  /// Coincidencia por nombre, ubicación, categoría o descripción.
  bool _coincide(Map<String, dynamic> t) {
    if (_busqueda.trim().isEmpty) return true;
    final q = _busqueda.trim().toLowerCase();
    return [
      t['nombre'],
      t['municipio'],
      t['provincia'],
      t['categoria'],
      t['descripcion'],
    ].any((c) => c?.toString().toLowerCase().contains(q) ?? false);
  }

  double _distanciaKm(double lat1, double lon1, double lat2, double lon2) {
    // Haversine (misma fórmula que el RPC buscar_tiendas_cercanas)
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _rad(double grados) => grados * math.pi / 180;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: widget.future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final todas = snapshot.data ?? [];
        final tiendas =
            todas.where(_coincide).toList(growable: false);

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
              child: Text(widget.titulo,
                  style: GoogleFonts.inter(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: _colorTexto)),
            ),
            // Buscador
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _busqueda = v),
                style: GoogleFonts.inter(color: _colorTexto),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar tienda, lugar o categoría...',
                  hintStyle:
                      GoogleFonts.inter(color: _colorTextoSecundario),
                  prefixIcon:
                      const Icon(Icons.search, color: _kCoral),
                  filled: true,
                  fillColor: _colorPlaceholder,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: tiendas.isEmpty
                  ? Center(
                      child: Text(
                        _busqueda.isEmpty
                            ? 'Nada por aquí todavía'
                            : 'Sin resultados para "$_busqueda"',
                        style: GoogleFonts.inter(
                            color: _colorTextoSecundario),
                      ),
                    )
                  : ListView.builder(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      itemCount: tiendas.length,
                      itemBuilder: (context, i) {
                        final t = Map<String, dynamic>.from(tiendas[i]);
                        final tLat = (t['latitud'] as num?)?.toDouble();
                        final tLon = (t['longitud'] as num?)?.toDouble();
                        if (t['distancia_km'] == null &&
                            widget.miLat != null &&
                            widget.miLon != null &&
                            tLat != null &&
                            tLon != null) {
                          t['distancia_km'] = _distanciaKm(
                              widget.miLat!, widget.miLon!, tLat, tLon);
                        }
                        final distancia =
                            (t['distancia_km'] as num?)?.toDouble();
                        final esVip =
                            (t['plan'] as String? ?? '').toLowerCase() ==
                                'premium';

                        void irATienda() {
                          Navigator.of(context).pop();
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
                                    errorBuilder: (_, __, ___) => Container(
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
                                  fontWeight: FontWeight.w600,
                                  color: _colorTexto)),
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
                                  borderRadius: BorderRadius.circular(20)),
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
  }
}