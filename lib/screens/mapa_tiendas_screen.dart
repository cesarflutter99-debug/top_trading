// mapa_tiendas_screen.dart
//
// Mapa interactivo (OpenStreetMap vía flutter_map, sin API key).
// Revelado progresivo por zoom, como Google Maps:
//   - Zoom bajo (< _kZoomUmbral): puntos chicos, dorados si la tienda
//     es premium vigente, azules si es básica/gratis.
//   - Zoom alto (>= _kZoomUmbral): pin grande con el logo de la
//     tienda, más una etiqueta flotando arriba con el nombre y la
//     valoración.
// Al tocar cualquier pin (chico o grande) se abre un globito con el
// nombre y la valoración, con acceso directo a la tienda.
//
// Pide permiso de ubicación al abrir (igual que Home) para centrar el
// mapa en el usuario; si lo deniega, arranca centrado en La Habana.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'dart:ui' as ui show Path;
import '../core/app_colors.dart';
import '../services/location_service.dart';
import '../services/tiendas_service.dart';

// Centro por defecto: La Habana, Cuba.
const LatLng _kCentroLaHabana = LatLng(23.1136, -82.3666);
const double _kZoomUmbral = 14; // a partir de acá se revela el pin con nombre
const Color _kDorado = Color(0xFFD4AF37);

class MapaTiendasScreen extends StatefulWidget {
  const MapaTiendasScreen({super.key});

  @override
  State<MapaTiendasScreen> createState() => _MapaTiendasScreenState();
}

class _MapaTiendasScreenState extends State<MapaTiendasScreen> {
  final _tiendasService = TiendasService();
  final _locationService = LocationService();
  final MapController _mapController = MapController();

  late Future<List<Map<String, dynamic>>> _tiendasFuture;
  LatLng? _miUbicacion;
  bool _cargandoUbicacion = true;
  double _zoomActual = 12;
  Map<String, dynamic>? _tiendaSeleccionada;

  @override
  void initState() {
    super.initState();
    _tiendasFuture = _tiendasService.obtenerTiendasParaMapa();
    _pedirUbicacion();
    // Trackea el zoom en vivo para decidir si mostrar puntos chicos o
    // el pin grande con detalle, y reposiciona la foto flotante del
    // pin seleccionado cuando el mapa se mueve o hace zoom.
    _mapController.mapEventStream.listen((evento) {
      final nuevoZoom = evento.camera.zoom;
      if ((nuevoZoom - _zoomActual).abs() > 0.05) {
        setState(() => _zoomActual = nuevoZoom);
      } else if (_tiendaSeleccionada != null) {
        setState(() {});
      }
    });
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
      // GPS denegado/desactivado -- nos quedamos en La Habana, sin
      // bloquear el mapa por esto.
      if (mounted) setState(() => _cargandoUbicacion = false);
    }
  }

  /// Mueve el mapa a la ubicación actual del usuario. Si aún no hay una
  /// posición guardada, pide el permiso de ubicación y centra el mapa
  /// apenas la obtiene.
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

  bool _esVip(Map<String, dynamic> t) {
    if (t['plan'] != 'premium') return false;
    final expira = t['plan_expira_en'] as String?;
    if (expira == null) return true;
    final fecha = DateTime.tryParse(expira);
    return fecha == null || fecha.isAfter(DateTime.now());
  }

  void _alTocarPin(Map<String, dynamic> tienda) {
    setState(() {
      final id = tienda['id_tienda'] as String;
      // Tocar la misma otra vez la cierra; tocar otra la reemplaza.
      _tiendaSeleccionada =
          _tiendaSeleccionada?['id_tienda'] == id ? null : tienda;
    });
  }

  /// Abre el detalle completo de la tienda (foto grande, valoración y
  /// botón "Ver tienda") al tocar la tarjeta flotante del pin
  /// seleccionado.
  void _mostrarDetalleTienda(Map<String, dynamic> tienda) {
    final portada = tienda['imagen_portada'] as String?;
    final logo = tienda['logo_url'] as String?;
    final fotoPrincipal =
        (portada != null && portada.isNotEmpty) ? portada : logo;
    final estrellas = (tienda['promedio_estrellas'] as num?)?.toStringAsFixed(1);
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
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ---- Foto circular grande ----
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
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.primary.withOpacity(0.08),
                              child: const Icon(Icons.storefront_rounded,
                                  size: 34, color: AppColors.primary),
                            ),
                          )
                        : Container(
                            color: AppColors.primary.withOpacity(0.08),
                            child: const Icon(Icons.storefront_rounded,
                                size: 34, color: AppColors.primary),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(tienda['nombre'] ?? '',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 8),
                if (estrellas != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...List.generate(5, (i) {
                        final valor = double.tryParse(estrellas) ?? 0;
                        return Icon(
                          i < valor.round()
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 17,
                          color: _kDorado,
                        );
                      }),
                      const SizedBox(width: 6),
                      Text(
                        '($totalResenas reseñas)',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            color: AppColors.inkSecundarioLight),
                      ),
                    ],
                  )
                else
                  Text(
                    'Sin reseñas todavía',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        color: AppColors.inkSecundarioLight),
                  ),
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

  /// Construye la tarjeta circular flotante del pin seleccionado,
  /// posicionada en píxeles encima de la coordenada de la tienda
  /// (latLngToScreenPoint). El pin del mapa NO cambia al seleccionarse,
  /// así que no hay salto: la foto solo se superpone.
  Widget _construirTarjetaSeleccionada() {
    final tienda = _tiendaSeleccionada!;
    final punto = LatLng(
      (tienda['latitud'] as num).toDouble(),
      (tienda['longitud'] as num).toDouble(),
    );
    final pantalla = _mapController.camera.latLngToScreenPoint(punto);
    const ancho = 64.0;
    const alto = 64.0;
    // Centrada en el punto y levantada 4px sobre la punta del pin para
    // no taparlo del todo.
    return Positioned(
      left: pantalla.x - ancho / 2,
      top: pantalla.y - alto - 4,
      width: ancho,
      height: alto,
      child: _TarjetaSeleccionada(
        tienda: tienda,
        esVip: _esVip(tienda),
        onCerrar: () => setState(() => _tiendaSeleccionada = null),
        onVerTienda: () => _mostrarDetalleTienda(tienda),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detalleVisible = _zoomActual >= _kZoomUmbral;

    return Scaffold(
      appBar: AppBar(title: const Text('Tiendas cerca de ti')),
      body: Stack(
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _tiendasFuture,
            builder: (context, snapshot) {
              final tiendas = (snapshot.data ?? [])
                  .where((t) => t['latitud'] != null && t['longitud'] != null)
                  .toList();
              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _kCentroLaHabana,
                  initialZoom: 12,
                  minZoom: 5,
                  maxZoom: 18,
                  onTap: (_, __) =>
                      setState(() => _tiendaSeleccionada = null),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.top_trading.app',
                  ),
                  // Requisito de los términos de uso de OpenStreetMap:
                  // hay que atribuir la fuente de los tiles en el mapa.
                  RichAttributionWidget(
                    alignment: AttributionAlignment.bottomLeft,
                    attributions: [
                      TextSourceAttribution(
                        '© OpenStreetMap contributors',
                        onTap: () {},
                      ),
                    ],
                  ),
                  if (_miUbicacion != null)
                    MarkerLayer(markers: [
                      Marker(
                        point: _miUbicacion!,
                        width: 22,
                        height: 22,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ]),
                  // ---- Pines: chicos si el mapa está alejado, con
                  // nombre si está acercado. El pin nunca cambia de
                  // tamaño ni posición al seleccionarse (para que no
                  // salte): la foto del seleccionado se dibuja encima
                  // como overlay en píxeles (ver _TarjetaSeleccionada).
                  MarkerLayer(
                    markers: tiendas.map((t) {
                      final punto = LatLng(
                        (t['latitud'] as num).toDouble(),
                        (t['longitud'] as num).toDouble(),
                      );
                      if (detalleVisible) {
                        return Marker(
                          point: punto,
                          width: 112,
                          height: 74,
                          alignment: Alignment.bottomCenter,
                          child: _PinTiendaDetallado(
                            tienda: t,
                            esVip: _esVip(t),
                            onTap: () => _alTocarPin(t),
                          ),
                        );
                      }
                      return Marker(
                        point: punto,
                        width: 18,
                        height: 18,
                        alignment: Alignment.bottomCenter,
                        child: _PuntoChico(
                          esVip: _esVip(t),
                          onTap: () => _alTocarPin(t),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
          if (_tiendaSeleccionada != null) _construirTarjetaSeleccionada(),
          if (_cargandoUbicacion)
            const Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  height: 3,
                  width: 120,
                  child: LinearProgressIndicator(),
                ),
              ),
            ),
          Positioned(
            top: 16,
            right: 16,
            child: Material(
              color: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: _ubicarme,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.my_location_rounded,
                          color: AppColors.primary, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Ubicarme',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Punto chico para cuando el mapa está alejado -- dorado si la
/// tienda es premium vigente, azul primario si no.
class _PuntoChico extends StatelessWidget {
  final bool esVip;
  final VoidCallback onTap;

  const _PuntoChico({required this.esVip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = esVip ? _kDorado : AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 3,
                offset: const Offset(0, 1)),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta circular pequeña que flota encima del pin seleccionado,
/// posicionada por píxeles desde el State (no es un marker), así el pin
/// del mapa no cambia de tamaño ni de posición al seleccionarse.
class _TarjetaSeleccionada extends StatelessWidget {
  final Map<String, dynamic> tienda;
  final bool esVip;
  final VoidCallback onCerrar;
  final VoidCallback onVerTienda;

  const _TarjetaSeleccionada({
    required this.tienda,
    required this.esVip,
    required this.onCerrar,
    required this.onVerTienda,
  });

  @override
  Widget build(BuildContext context) {
    final color = esVip ? _kDorado : AppColors.primary;
    final portada = tienda['imagen_portada'] as String?;
    final logo = tienda['logo_url'] as String?;
    final foto = (portada != null && portada.isNotEmpty) ? portada : logo;

    return GestureDetector(
      onTap: onVerTienda,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ---- Foto circular pequeña ----
          Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2.5),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3)),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: ClipOval(
              child: (foto != null && foto.isNotEmpty)
                  ? Image.network(
                      foto,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: color.withOpacity(0.08),
                        child: Icon(Icons.storefront_rounded,
                            color: color, size: 26),
                      ),
                    )
                  : Container(
                      color: color.withOpacity(0.08),
                      child: Icon(Icons.storefront_rounded,
                          color: color, size: 26),
                    ),
            ),
          ),
          // ---- Botón cerrar ----
          Positioned(
            right: -4,
            top: -4,
            child: GestureDetector(
              onTap: onCerrar,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 1)),
                  ],
                ),
                child: Icon(Icons.close_rounded, size: 14, color: color),
              ),
            ),
          ),
          // ---- Punta apuntando al pin ----
          Positioned(
            bottom: -5,
            left: 0,
            right: 0,
            child: CustomPaint(
              painter: _FlechaPin(color: color),
              child: const SizedBox(width: 14, height: 7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dibuja una pequeña flecha triangular que conecta la tarjeta circular
/// con la punta del pin del mapa.
class _FlechaPin extends CustomPainter {
  final Color color;
  const _FlechaPin({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FlechaPin oldDelegate) =>
      oldDelegate.color != color;
}

/// Pin grande con el logo de la tienda + etiqueta de nombre/estrellas
/// flotando arriba, para cuando el mapa está acercado. Anclado por
/// abajo (alignment: bottomCenter en el Marker) para que la etiqueta
/// crezca hacia arriba sin desplazar la posición real del pin.
class _PinTiendaDetallado extends StatelessWidget {
  final Map<String, dynamic> tienda;
  final bool esVip;
  final VoidCallback onTap;

  const _PinTiendaDetallado({
    required this.tienda,
    required this.esVip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = esVip ? _kDorado : AppColors.primary;
    final estrellas =
        (tienda['promedio_estrellas'] as num?)?.toStringAsFixed(1);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // ---- Etiqueta: nombre + estrellas ----
          Container(
            constraints: const BoxConstraints(maxWidth: 108),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  tienda['nombre'] ?? '',
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
                      const Icon(Icons.star_rounded, size: 10, color: _kDorado),
                      const SizedBox(width: 2),
                      Text(estrellas,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 9.5,
                              height: 1.1,
                              color: AppColors.inkSecundarioLight)),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 1),
          // ---- Pin clásico estilo gota (Google Maps / Walmart) ----
          SizedBox(
            width: 30,
            height: 38,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.location_on,
                  size: 34,
                  color: color,
                  shadows: [
                    Shadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 3,
                        offset: const Offset(0, 1)),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.storefront_rounded, size: 10, color: color),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}