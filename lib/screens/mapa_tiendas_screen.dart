// mapa_tiendas_screen.dart
//
// REDISEÑO (2026-09) -- estilo "Tiendas cerca de ti":
//   - Header propio (título + subtítulo + botón "Mi ubicación"), buscador
//     y chips de categoría. Ya no hay AppBar.
//   - Mapa OpenStreetMap (flutter_map, sin API key) con pines tipo gota
//     con el ícono de la categoría. Dorado = premium vigente, azul =
//     tienda normal, verde = negocio/evento.
//   - Botones flotantes sobre el mapa: ubicarme + capas (mostrar/ocultar
//     tiendas y negocios).
//   - Tarjeta flotante de la tienda seleccionada (tocarla abre el detalle).
//   - Panel inferior "Tiendas cercanas": carrusel horizontal ordenado por
//     distancia, "Ver todas" abre el listado completo.
//
// LÓGICA CONSERVADA: revelado de etiqueta por zoom (_kZoomUmbral), tiendas
// premium vigentes (_esVip), capa de negocios que abre /negocio/:id,
// detalle de tienda con botón "Ver tienda", permiso de ubicación con
// fallback a La Habana y el mapa NO se mueve solo (solo con "Ubicarme").
//
// FIXES / MEJORAS:
//   - Se quitó la suscripción a mapEventStream (nunca se cancelaba); el
//     zoom se sigue con MapOptions.onPositionChanged y solo se reconstruye
//     al cruzar el umbral.
//   - Se eliminó el overlay por píxeles (latLngToScreenPoint) de la foto
//     flotante: ahora la selección es una tarjeta fija, sin saltos.
//   - Los datos se cargan una vez en estado (antes un FutureBuilder
//     reconstruía el mapa entero).
//   - Atribución de OpenStreetMap propia y visible sobre el panel.
//
// REQUIERE (opcional pero recomendado) ampliar el select de
// TiendasService.obtenerTiendasParaMapa() con:
//   categoria, municipio, imagen_portada, total_valoraciones
// Sin eso la pantalla funciona, pero los chips de categoría no filtran y
// las tarjetas usan el logo como foto.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../services/location_service.dart';
import '../services/negocios_service.dart';
import '../services/tiendas_service.dart';

// Centro por defecto: La Habana, Cuba.
const LatLng _kCentroLaHabana = LatLng(23.1136, -82.3666);
const double _kZoomUmbral = 14; // a partir de acá se revela la etiqueta
const Color _kDorado = Color(0xFFD4AF37);

// Color identitario de los negocios/servicios en toda la app.
const Color _kVerdeNegocio = Color(0xFF0D9488);

// Alturas del panel inferior (sin contar el espacio de la barra de nav).
const double _kAltoPanelAbierto = 182;
const double _kAltoPanelCerrado = 60;

/// Ícono por categoría -- los valores deben coincidir con
/// kCategoriasTienda (tiendas_service.dart).
IconData _iconoCategoria(String? categoria) {
  switch (categoria) {
    case 'Ropa y Accesorios':
      return Icons.checkroom_rounded;
    case 'Calzado':
      return Icons.directions_walk_rounded;
    case 'Móviles y Laptops':
      return Icons.smartphone_rounded;
    case 'Electrodomésticos':
      return Icons.kitchen_rounded;
    case 'Hogar y Muebles':
      return Icons.chair_rounded;
    case 'Alimentos y Bebidas':
      return Icons.shopping_cart_rounded;
    case 'Belleza y Cuidado Personal':
      return Icons.spa_rounded;
    case 'Salud y Farmacia':
      return Icons.medical_services_rounded;
    case 'Deportes y Fitness':
      return Icons.fitness_center_rounded;
    case 'Ocio y Videojuegos':
      return Icons.sports_esports_rounded;
    case 'Juguetes y Niños':
      return Icons.toys_rounded;
    case 'Mascotas':
      return Icons.pets_rounded;
    case 'Vehículos y Repuestos':
      return Icons.build_rounded;
    case 'Transporte y Motor (vehículos completos)':
      return Icons.directions_car_rounded;
    case 'Ferretería y Construcción':
      return Icons.hardware_rounded;
    case 'Energía, Electricidad y Solar':
      return Icons.bolt_rounded;
    default:
      return Icons.storefront_rounded;
  }
}

class MapaTiendasScreen extends StatefulWidget {
  const MapaTiendasScreen({super.key});

  @override
  State<MapaTiendasScreen> createState() => _MapaTiendasScreenState();
}

class _MapaTiendasScreenState extends State<MapaTiendasScreen> {
  final _tiendasService = TiendasService();
  final _negociosService = NegociosService();
  final _locationService = LocationService();
  final MapController _mapController = MapController();
  final TextEditingController _busquedaCtrl = TextEditingController();

  List<Map<String, dynamic>> _tiendas = [];
  List<Map<String, dynamic>> _negocios = [];
  bool _cargandoDatos = true;

  LatLng? _miUbicacion;
  bool _cargandoUbicacion = true;

  bool _detalleVisible = false; // zoom >= umbral
  String _busqueda = '';
  String? _categoria; // null = Todas
  bool _verTiendas = true;
  bool _verNegocios = true;
  bool _panelAbierto = true;
  Map<String, dynamic>? _seleccion;

  // -------------------------------------------------------------------
  // Colores adaptativos
  // -------------------------------------------------------------------
  bool get _esOscuro => Theme.of(context).brightness == Brightness.dark;
  Color get _texto => _esOscuro ? const Color(0xFFF5F5F4) : AppColors.ink;
  Color get _textoSec =>
      _esOscuro ? AppColors.inkSecundarioDark : AppColors.inkSecundarioLight;
  Color get _superficie =>
      _esOscuro ? AppColors.surfaceDark : AppColors.surfaceLight;
  Color get _borde =>
      (_esOscuro ? AppColors.borderDark : AppColors.borderLight)
          .withOpacity(0.8);

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _pedirUbicacion();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------
  // Datos
  // -------------------------------------------------------------------
  List<Map<String, dynamic>> _conCoordenadas(List<Map<String, dynamic>> l) =>
      l.where((m) => m['latitud'] != null && m['longitud'] != null).toList();

  Future<void> _cargarDatos() async {
    try {
      final r = await Future.wait([
        _tiendasService.obtenerTiendasParaMapa(),
        _negociosService.obtenerNegociosParaMapa(),
      ]);
      if (!mounted) return;
      setState(() {
        _tiendas = _conCoordenadas(r[0]);
        _negocios = _conCoordenadas(r[1]);
        _cargandoDatos = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoDatos = false);
    }
  }

  Future<void> _pedirUbicacion() async {
    try {
      final pos = await _locationService.obtenerUbicacionActual();
      if (!mounted) return;
      // Solo guardamos la posición; el mapa NO se mueve solo. Para
      // centrar el mapa en el usuario hay que tocar "Ubicarme".
      setState(() {
        _miUbicacion = LatLng(pos.latitude, pos.longitude);
        _cargandoUbicacion = false;
      });
    } catch (_) {
      // GPS denegado/desactivado -- nos quedamos en La Habana.
      if (mounted) setState(() => _cargandoUbicacion = false);
    }
  }

  /// Mueve el mapa a la ubicación del usuario; si aún no hay posición,
  /// la pide y centra apenas la obtiene.
  Future<void> _ubicarme() async {
    if (_miUbicacion != null) {
      _mapController.move(_miUbicacion!, 14);
      return;
    }
    setState(() => _cargandoUbicacion = true);
    try {
      final pos = await _locationService.obtenerUbicacionActual();
      if (!mounted) return;
      final ubicacion = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _miUbicacion = ubicacion;
        _cargandoUbicacion = false;
      });
      _mapController.move(ubicacion, 14);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargandoUbicacion = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo obtener tu ubicación: $e')),
      );
    }
  }

  // -------------------------------------------------------------------
  // Reglas de tienda
  // -------------------------------------------------------------------
  bool _esVip(Map<String, dynamic> t) {
    if (t['plan'] != 'premium') return false;
    final expira = t['plan_expira_en'] as String?;
    if (expira == null) return true;
    final fecha = DateTime.tryParse(expira);
    return fecha == null || fecha.isAfter(DateTime.now());
  }

  LatLng _punto(Map<String, dynamic> m) => LatLng(
        (m['latitud'] as num).toDouble(),
        (m['longitud'] as num).toDouble(),
      );

  double? _distanciaKm(Map<String, dynamic> t) {
    final mi = _miUbicacion;
    if (mi == null) return null;
    final p = _punto(t);
    return Geolocator.distanceBetween(
            mi.latitude, mi.longitude, p.latitude, p.longitude) /
        1000;
  }

  String? _estrellas(Map<String, dynamic> t) =>
      (t['promedio_estrellas'] as num?)?.toStringAsFixed(1);

  bool _coincideBusqueda(Map<String, dynamic> m) {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [m['nombre'], m['categoria'], m['municipio']]
        .any((c) => c?.toString().toLowerCase().contains(q) ?? false);
  }

  List<Map<String, dynamic>> get _tiendasVisibles {
    if (!_verTiendas) return [];
    return _tiendas
        .where((t) =>
            _coincideBusqueda(t) &&
            (_categoria == null || t['categoria'] == _categoria))
        .toList();
  }

  // Los negocios tienen categoría de texto libre, así que al elegir una
  // categoría de tienda se ocultan (no hay forma fiable de compararlas).
  List<Map<String, dynamic>> get _negociosVisibles {
    if (!_verNegocios || _categoria != null) return [];
    return _negocios.where(_coincideBusqueda).toList();
  }

  List<Map<String, dynamic>> _tiendasPorDistancia() {
    final lista = [..._tiendasVisibles];
    if (_miUbicacion != null) {
      lista.sort((a, b) => (_distanciaKm(a) ?? double.infinity)
          .compareTo(_distanciaKm(b) ?? double.infinity));
    }
    return lista;
  }

  // -------------------------------------------------------------------
  // Interacción
  // -------------------------------------------------------------------
  void _alCambiarPosicion(double? zoom) {
    if (zoom == null) return;
    final visible = zoom >= _kZoomUmbral;
    if (visible != _detalleVisible) setState(() => _detalleVisible = visible);
  }

  void _alTocarPin(Map<String, dynamic> tienda) {
    setState(() {
      final id = tienda['id_tienda'];
      // Tocar la misma otra vez la cierra; tocar otra la reemplaza.
      _seleccion = _seleccion?['id_tienda'] == id ? null : tienda;
    });
  }

  void _seleccionarYCentrar(Map<String, dynamic> tienda) {
    setState(() => _seleccion = tienda);
    _mapController.move(
      _punto(tienda),
      math.max(_mapController.camera.zoom, _kZoomUmbral),
    );
  }

  void _limpiarSeleccion() {
    FocusScope.of(context).unfocus();
    if (_seleccion != null) setState(() => _seleccion = null);
  }

  // -------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final inferior = MediaQuery.of(context).padding.bottom;
    // Espacio que ocupa la barra de navegación flotante del shell.
    final navEspacio = math.max(inferior, 8.0) + 68;
    final altoPanel =
        (_panelAbierto ? _kAltoPanelAbierto : _kAltoPanelCerrado) + navEspacio;

    final tiendas = _tiendasVisibles;
    final negocios = _negociosVisibles;
    final seleccion = _seleccion;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: Stack(
              children: [
                // ---------------- Mapa ----------------
                // Termina 28px DEBAJO del borde superior del panel para que
                // las esquinas redondeadas del panel muestren el mapa.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: altoPanel - 28,
                  child: _buildMapa(tiendas, negocios),
                ),
                if (_cargandoUbicacion || _cargandoDatos)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                // ---------------- Botones flotantes ----------------
                Positioned(
                  top: 12,
                  right: 12,
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _ubicarme,
                        child: _circuloFlotante(Icons.my_location_rounded),
                      ),
                      const SizedBox(height: 10),
                      PopupMenuButton<String>(
                        tooltip: 'Capas',
                        onSelected: (v) => setState(() {
                          if (v == 't') {
                            _verTiendas = !_verTiendas;
                          } else {
                            _verNegocios = !_verNegocios;
                          }
                          _seleccion = null;
                        }),
                        itemBuilder: (_) => [
                          CheckedPopupMenuItem(
                              value: 't',
                              checked: _verTiendas,
                              child: const Text('Tiendas')),
                          CheckedPopupMenuItem(
                              value: 'n',
                              checked: _verNegocios,
                              child: const Text('Negocios y eventos')),
                        ],
                        child: _circuloFlotante(Icons.layers_rounded),
                      ),
                    ],
                  ),
                ),
                // ---------------- Atribución OSM (obligatoria) ----------------
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  right: 12,
                  bottom: altoPanel + 6,
                  child: GestureDetector(
                    onTap: () => launchUrl(
                      Uri.parse('https://www.openstreetmap.org/copyright'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: _superficie.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('© OpenStreetMap contributors',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 9, color: _textoSec)),
                    ),
                  ),
                ),
                // ---------------- Tarjeta de la seleccionada ----------------
                if (seleccion != null)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    left: 16,
                    right: 16,
                    bottom: altoPanel + 30,
                    child: _tarjetaSeleccionada(seleccion),
                  ),
                // ---------------- Panel inferior ----------------
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildPanel(altoPanel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Header: título, buscador y chips
  // -------------------------------------------------------------------
  Widget _buildHeader(BuildContext context) {
    final fondo = Theme.of(context).scaffoldBackgroundColor;
    final tinte = Color.alphaBlend(
        AppColors.primary.withOpacity(_esOscuro ? 0.14 : 0.10), fondo);
    final tituloColor = _esOscuro ? const Color(0xFFF5F5F4) : const Color(0xFF12305F);

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 10, 16, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tinte, fondo],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (context.canPop())
                Padding(
                  padding: const EdgeInsets.only(right: 4, top: 2),
                  child: GestureDetector(
                    onTap: () => context.pop(),
                    child: Icon(Icons.arrow_back_rounded, color: tituloColor),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tiendas cerca de ti',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: tituloColor)),
                    const SizedBox(height: 2),
                    Text(
                      'Encuentra las tiendas más cercanas\ny compra lo que necesitas.',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5, height: 1.35, color: _textoSec),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _pillMiUbicacion(),
            ],
          ),
          const SizedBox(height: 14),
          _buildBuscador(),
          const SizedBox(height: 12),
          _buildChips(),
        ],
      ),
    );
  }

  Widget _pillMiUbicacion() {
    return Material(
      color: _superficie,
      elevation: 3,
      shadowColor: AppColors.primary.withOpacity(0.25),
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: _ubicarme,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.my_location_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 6),
              Text('Mi ubicación',
                  style: GoogleFonts.plusJakartaSans(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBuscador() {
    return Container(
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(_esOscuro ? 0.0 : 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: _busquedaCtrl,
        onChanged: (v) => setState(() {
          _busqueda = v;
          _seleccion = null;
        }),
        style: GoogleFonts.plusJakartaSans(color: _texto, fontSize: 14),
        decoration: InputDecoration(
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: 'Buscar tiendas, negocios...',
          hintStyle:
              GoogleFonts.plusJakartaSans(color: _textoSec, fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
          suffixIcon: _busqueda.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => setState(() {
                    _busquedaCtrl.clear();
                    _busqueda = '';
                    _seleccion = null;
                  }),
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildChips() {
    final categorias = <String?>[null, ...kCategoriasTienda];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categorias.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = categorias[i];
          final activo = cat == _categoria;
          return GestureDetector(
            onTap: () => setState(() {
              _categoria = cat;
              _seleccion = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: activo ? AppColors.primary : _superficie,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: activo ? AppColors.primary : _borde),
                boxShadow: activo
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    cat == null
                        ? Icons.storefront_rounded
                        : _iconoCategoria(cat),
                    size: 18,
                    color: activo ? Colors.white : AppColors.primary,
                  ),
                  const SizedBox(width: 7),
                  Text(cat ?? 'Todas',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: activo ? Colors.white : _textoSec)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------
  // Mapa y marcadores
  // -------------------------------------------------------------------
  Widget _buildMapa(
    List<Map<String, dynamic>> tiendas,
    List<Map<String, dynamic>> negocios,
  ) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _kCentroLaHabana,
        initialZoom: 12,
        minZoom: 5,
        maxZoom: 18,
        onTap: (_, __) => _limpiarSeleccion(),
        onPositionChanged: (camera, _) {
          final double? zoom = camera.zoom;
          _alCambiarPosicion(zoom);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.top_trading.app',
        ),
        if (_miUbicacion != null)
          MarkerLayer(markers: [
            Marker(
              point: _miUbicacion!,
              width: 56,
              height: 56,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.16),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ),
          ]),
        MarkerLayer(markers: _marcadores(tiendas, negocios)),
      ],
    );
  }

  Marker _marcador(LatLng punto, Widget pin) {
    final conEtiqueta = _detalleVisible;
    return Marker(
      point: punto,
      width: conEtiqueta ? 112 : 42,
      height: conEtiqueta ? 90 : 42,
      // La punta de la gota queda justo sobre la coordenada.
      alignment: Alignment.topCenter,
      child: pin,
    );
  }

  List<Marker> _marcadores(
    List<Map<String, dynamic>> tiendas,
    List<Map<String, dynamic>> negocios,
  ) {
    final conEtiqueta = _detalleVisible;
    final marcadores = <Marker>[];

    // Negocios primero (quedan debajo de las tiendas).
    for (final n in negocios) {
      marcadores.add(_marcador(
        _punto(n),
        _PinMapa(
          color: _kVerdeNegocio,
          icono: Icons.content_cut_rounded,
          nombre: n['nombre']?.toString() ?? '',
          subtitulo: n['categoria']?.toString(),
          estrellas: null,
          conEtiqueta: conEtiqueta,
          seleccionado: false,
          // Su mini-página ya ES el detalle: van directo.
          onTap: () => context.push('/negocio/${n['id_negocio']}'),
        ),
      ));
    }

    // Tiendas; la seleccionada va al final para quedar encima.
    final idSel = _seleccion?['id_tienda'];
    final ordenadas = [
      ...tiendas.where((t) => t['id_tienda'] != idSel),
      ...tiendas.where((t) => t['id_tienda'] == idSel),
    ];
    for (final t in ordenadas) {
      marcadores.add(_marcador(
        _punto(t),
        _PinMapa(
          color: _esVip(t) ? _kDorado : AppColors.primary,
          icono: _iconoCategoria(t['categoria'] as String?),
          nombre: t['nombre']?.toString() ?? '',
          estrellas: _estrellas(t),
          conEtiqueta: conEtiqueta,
          seleccionado: t['id_tienda'] == idSel,
          onTap: () => _alTocarPin(t),
        ),
      ));
    }
    return marcadores;
  }

  Widget _circuloFlotante(IconData icono) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _superficie,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_esOscuro ? 0.4 : 0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icono, color: AppColors.primary, size: 22),
    );
  }

  // -------------------------------------------------------------------
  // Tarjeta flotante de la tienda seleccionada
  // -------------------------------------------------------------------
  Widget _tarjetaSeleccionada(Map<String, dynamic> t) {
    final color = _esVip(t) ? _kDorado : AppColors.primary;
    final dist = _distanciaKm(t);
    final estrellas = _estrellas(t);
    final detalle = [
      if (dist != null) 'A ${dist.toStringAsFixed(1)} km',
      if (estrellas != null) '★ $estrellas',
      if ((t['municipio'] ?? '').toString().isNotEmpty) '${t['municipio']}',
    ].join(' · ');

    return Material(
      color: _superficie,
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.25),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _mostrarDetalleTienda(t),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Row(
            children: [
              _badgeCategoria(t, color, 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t['nombre']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: _texto)),
                    if (detalle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(detalle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5, color: _textoSec)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: _textoSec),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badgeCategoria(Map<String, dynamic> t, Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Icon(_iconoCategoria(t['categoria'] as String?),
          color: Colors.white, size: size * 0.5),
    );
  }

  // -------------------------------------------------------------------
  // Panel inferior "Tiendas cercanas"
  // -------------------------------------------------------------------
  Widget _buildPanel(double altoPanel) {
    final cercanas = _tiendasPorDistancia();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      height: altoPanel,
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_esOscuro ? 0.5 : 0.10),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      // El scroll deshabilitado solo evita el overflow mientras se anima.
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _panelAbierto = !_panelAbierto),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _borde,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 10, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tiendas cercanas',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _texto)),
                  TextButton(
                    onPressed:
                        cercanas.isEmpty ? null : () => _abrirListaCompleta(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Ver todas',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700, fontSize: 12.5)),
                        const Icon(Icons.chevron_right_rounded, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 112,
              child: cercanas.isEmpty
                  ? Center(
                      child: Text(
                        _cargandoDatos
                            ? 'Cargando tiendas...'
                            : 'No encontramos tiendas con ese filtro',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, color: _textoSec),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: math.min(cercanas.length, 12),
                      itemBuilder: (context, i) =>
                          _tarjetaCercana(cercanas[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaCercana(Map<String, dynamic> t) {
    final color = _esVip(t) ? _kDorado : AppColors.primary;
    final portada = t['imagen_portada'] as String?;
    final logo = t['logo_url'] as String?;
    final foto = (portada != null && portada.isNotEmpty) ? portada : logo;
    final dist = _distanciaKm(t);
    final estrellas = _estrellas(t);
    final resenas = (t['total_valoraciones'] as num?)?.toInt();
    final categoria = (t['categoria'] ?? t['municipio'] ?? '').toString();
    final seleccionada = _seleccion?['id_tienda'] == t['id_tienda'];

    return Container(
      width: 262,
      margin: const EdgeInsets.only(right: 10),
      child: Material(
        color: _esOscuro ? const Color(0xFF2C2C2E) : const Color(0xFFF6F9FE),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _seleccionarYCentrar(t),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: seleccionada ? color : _borde,
                width: seleccionada ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 86,
                  height: double.infinity,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: (foto != null && foto.isNotEmpty)
                              ? Image.network(foto,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _fotoVacia(color))
                              : _fotoVacia(color),
                        ),
                      ),
                      Positioned(
                        left: -2,
                        bottom: -2,
                        child: _badgeCategoria(t, color, 30),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(t['nombre']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: _texto)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 14, color: _kDorado),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              estrellas == null
                                  ? 'Nuevo'
                                  : '$estrellas${resenas != null ? ' ($resenas)' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: _textoSec),
                            ),
                          ),
                        ],
                      ),
                      if (categoria.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(categoria,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11, color: _textoSec)),
                      ],
                      if (dist != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.near_me_rounded,
                                size: 12, color: color),
                            const SizedBox(width: 3),
                            Text('${dist.toStringAsFixed(1)} km',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: color)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _mostrarDetalleTienda(t),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.chevron_right_rounded, color: _textoSec),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fotoVacia(Color color) => Container(
        color: color.withOpacity(0.10),
        alignment: Alignment.center,
        child: Icon(Icons.storefront_rounded, color: color, size: 28),
      );

  // -------------------------------------------------------------------
  // "Ver todas": listado completo ordenado por distancia
  // -------------------------------------------------------------------
  void _abrirListaCompleta() {
    final lista = _tiendasPorDistancia();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Tiendas cercanas (${lista.length})',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: lista.length,
                itemBuilder: (context, i) {
                  final t = lista[i];
                  final color = _esVip(t) ? _kDorado : AppColors.primary;
                  final dist = _distanciaKm(t);
                  final logo = t['logo_url'] as String?;
                  final sub = [
                    if ((t['categoria'] ?? '').toString().isNotEmpty)
                      '${t['categoria']}',
                    if (dist != null) '${dist.toStringAsFixed(1)} km',
                  ].join(' · ');
                  return ListTile(
                    onTap: () {
                      Navigator.pop(ctx);
                      _seleccionarYCentrar(t);
                    },
                    leading: CircleAvatar(
                      backgroundColor: color.withOpacity(0.12),
                      backgroundImage: (logo != null && logo.isNotEmpty)
                          ? NetworkImage(logo)
                          : null,
                      child: (logo == null || logo.isEmpty)
                          ? Icon(_iconoCategoria(t['categoria'] as String?),
                              color: color)
                          : null,
                    ),
                    title: Text(t['nombre']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700)),
                    subtitle: sub.isEmpty
                        ? null
                        : Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 15, color: _kDorado),
                        const SizedBox(width: 2),
                        Text(_estrellas(t) ?? 'Nuevo',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Detalle de tienda (foto grande, valoración y botón "Ver tienda")
  // -------------------------------------------------------------------
  void _mostrarDetalleTienda(Map<String, dynamic> tienda) {
    final portada = tienda['imagen_portada'] as String?;
    final logo = tienda['logo_url'] as String?;
    final fotoPrincipal =
        (portada != null && portada.isNotEmpty) ? portada : logo;
    final estrellasTxt = _estrellas(tienda);
    final totalResenas = tienda['total_valoraciones'] ?? 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
        child: Material(
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          elevation: 10,
          color: _superficie,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.25), width: 2),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: ClipOval(
                    child: (fotoPrincipal != null && fotoPrincipal.isNotEmpty)
                        ? Image.network(
                            fotoPrincipal,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _fotoVacia(
                                AppColors.primary),
                          )
                        : _fotoVacia(AppColors.primary),
                  ),
                ),
                const SizedBox(height: 14),
                Text(tienda['nombre'] ?? '',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: _texto)),
                const SizedBox(height: 8),
                if (estrellasTxt != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...List.generate(5, (i) {
                        final valor = double.tryParse(estrellasTxt) ?? 0;
                        return Icon(
                          i < valor.round()
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 17,
                          color: _kDorado,
                        );
                      }),
                      const SizedBox(width: 6),
                      Text('($totalResenas reseñas)',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5, color: _textoSec)),
                    ],
                  )
                else
                  Text('Sin reseñas todavía',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5, color: _textoSec)),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/tienda/${tienda['id_tienda']}');
                    },
                    icon: const Icon(Icons.storefront_outlined, size: 18),
                    label: const Text('Ver tienda'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pin tipo gota con el ícono de la categoría. Con zoom alto muestra una
/// etiqueta (nombre + estrellas o categoría) encima. Se ancla por abajo
/// (la punta de la gota es la coordenada real) y al seleccionarse solo
/// escala -- nunca cambia el tamaño del Marker, así que no salta.
class _PinMapa extends StatelessWidget {
  final Color color;
  final IconData icono;
  final String nombre;
  final String? subtitulo;
  final String? estrellas;
  final bool conEtiqueta;
  final bool seleccionado;
  final VoidCallback onTap;

  const _PinMapa({
    required this.color,
    required this.icono,
    required this.nombre,
    required this.estrellas,
    required this.conEtiqueta,
    required this.seleccionado,
    required this.onTap,
    this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    final tam = conEtiqueta ? 46.0 : 40.0;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: seleccionado ? 1.18 : 1,
        alignment: Alignment.bottomCenter,
        duration: const Duration(milliseconds: 150),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (conEtiqueta) ...[
              Container(
                constraints: const BoxConstraints(maxWidth: 108),
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withOpacity(0.4)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 3,
                        offset: const Offset(0, 1)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          color: AppColors.inkLight),
                    ),
                    if (estrellas != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 10, color: _kDorado),
                          const SizedBox(width: 2),
                          Text(estrellas!,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 9.5,
                                  height: 1.1,
                                  color: AppColors.inkSecundarioLight)),
                        ],
                      )
                    else if (subtitulo != null && subtitulo!.isNotEmpty)
                      Text(
                        subtitulo!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 9.5,
                            height: 1.1,
                            color: AppColors.inkSecundarioLight),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
            ],
            SizedBox(
              width: tam,
              height: tam,
              child: Stack(
                children: [
                  Icon(
                    Icons.location_on,
                    size: tam,
                    color: color,
                    shadows: [
                      Shadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 1)),
                    ],
                  ),
                  Positioned(
                    top: tam * 0.15,
                    left: tam * 0.28,
                    child: Container(
                      width: tam * 0.44,
                      height: tam * 0.44,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icono, size: tam * 0.28, color: color),
                    ),
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
