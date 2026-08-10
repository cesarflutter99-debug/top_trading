// mapa_tiendas_screen.dart
//
// Mapa interactivo (OpenStreetMap vía flutter_map, sin API key) con un
// pin por cada tienda activa. Cada pin muestra el logo de la tienda
// (o un ícono genérico si no tiene), y al tocarlo aparece un globito
// con el nombre y la valoración -- nada más, según lo pedido.
//
// Pide permiso de ubicación al abrir (igual que Home) para centrar el
// mapa en el usuario; si lo deniega, arranca centrado en La Habana.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../core/app_colors.dart';
import '../services/location_service.dart';
import '../services/tiendas_service.dart';

// Centro por defecto: La Habana, Cuba.
const LatLng _kCentroLaHabana = LatLng(23.1136, -82.3666);

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

  @override
  void initState() {
    super.initState();
    _tiendasFuture = _tiendasService.obtenerTiendasParaMapa();
    _pedirUbicacion();
  }

  Future<void> _pedirUbicacion() async {
    try {
      final pos = await _locationService.obtenerUbicacionActual();
      if (!mounted) return;
      setState(() {
        _miUbicacion = LatLng(pos.latitude, pos.longitude);
        _cargandoUbicacion = false;
      });
      _mapController.move(_miUbicacion!, 14);
    } catch (_) {
      // GPS denegado/desactivado -- nos quedamos en La Habana, sin
      // bloquear el mapa por esto.
      if (mounted) setState(() => _cargandoUbicacion = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tiendas cerca de ti')),
      body: Stack(
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _tiendasFuture,
            builder: (context, snapshot) {
              final tiendas = snapshot.data ?? [];
              return FlutterMap(
                mapController: _mapController,
                options: const MapOptions(
                  initialCenter: _kCentroLaHabana,
                  initialZoom: 12,
                  minZoom: 5,
                  maxZoom: 18,
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
                  MarkerLayer(
                    markers: tiendas
                        .where((t) =>
                            t['latitud'] != null && t['longitud'] != null)
                        .map((t) => Marker(
                              point: LatLng(
                                (t['latitud'] as num).toDouble(),
                                (t['longitud'] as num).toDouble(),
                              ),
                              width: 46,
                              height: 46,
                              child: _PinTienda(
                                tienda: t,
                                onTap: () => _mostrarGlobito(t),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              );
            },
          ),
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
            right: 16,
            bottom: 24,
            child: FloatingActionButton(
              heroTag: 'centrar-ubicacion',
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              onPressed: () {
                if (_miUbicacion != null) {
                  _mapController.move(_miUbicacion!, 14);
                } else {
                  _pedirUbicacion();
                }
              },
              child: const Icon(Icons.my_location_rounded),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarGlobito(Map<String, dynamic> tienda) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              backgroundImage: (tienda['logo_url'] as String?) != null &&
                      (tienda['logo_url'] as String).isNotEmpty
                  ? NetworkImage(tienda['logo_url'] as String)
                  : null,
              child: (tienda['logo_url'] as String?) == null ||
                      (tienda['logo_url'] as String).isEmpty
                  ? const Icon(Icons.storefront_rounded,
                      color: AppColors.primary)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tienda['nombre'] ?? '',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 16, color: Color(0xFFD4AF37)),
                      const SizedBox(width: 3),
                      Text(
                        (tienda['promedio_estrellas'] as num?)
                                ?.toStringAsFixed(1) ??
                            'Sin reseñas',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13.5, color: AppColors.inkSecundarioLight),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/tienda/${tienda['id_tienda']}');
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Pin del mapa: círculo con el logo de la tienda dentro, o un ícono
/// genérico de tienda si no tiene foto de perfil todavía.
class _PinTienda extends StatelessWidget {
  final Map<String, dynamic> tienda;
  final VoidCallback onTap;

  const _PinTienda({required this.tienda, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final logoUrl = tienda['logo_url'] as String?;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: AppColors.primary, width: 2.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.all(3),
        child: ClipOval(
          child: (logoUrl != null && logoUrl.isNotEmpty)
              ? Image.network(
                  logoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.primary.withOpacity(0.1),
                    child: const Icon(Icons.storefront_rounded,
                        color: AppColors.primary, size: 18),
                  ),
                )
              : Container(
                  color: AppColors.primary.withOpacity(0.1),
                  child: const Icon(Icons.storefront_rounded,
                      color: AppColors.primary, size: 18),
                ),
        ),
      ),
    );
  }
}
