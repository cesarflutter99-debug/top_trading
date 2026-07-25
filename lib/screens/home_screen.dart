import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/location_service.dart';
import '../services/tiendas_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _tiendasService = TiendasService();
  final _locationService = LocationService();

  late Future<List<Map<String, dynamic>>> _premium;
  late Future<List<Map<String, dynamic>>> _trending;
  Future<List<Map<String, dynamic>>>? _cercanas;
  String? _errorUbicacion;

  @override
  void initState() {
    super.initState();
    _premium = _tiendasService.obtenerCarruselPremium();
    _trending = _tiendasService.obtenerCarruselTrending(limite: 10);
    _cargarCercanas();
  }

  Future<void> _cargarCercanas() async {
    setState(() {
      _errorUbicacion = null;
      _cercanas = null;
    });
    try {
      final pos = await _locationService.obtenerUbicacionActual();
      setState(() {
        _cercanas = _tiendasService.buscarTiendasCercanas(
          lat: pos.latitude,
          lon: pos.longitude,
        );
      });
    } catch (e) {
      setState(() {
        _errorUbicacion = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Top Trading')),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _premium = _tiendasService.obtenerCarruselPremium();
            _trending = _tiendasService.obtenerCarruselTrending(limite: 10);
          });
          await _cargarCercanas();
        },
        child: ListView(
          children: [
            _seccion(
              titulo: '⭐ Destacados',
              altura: 180,
              future: _premium,
            ),
            _seccion(
              titulo: '🔥 Lo más caliente de la semana',
              altura: 120,
              future: _trending,
            ),
            const SizedBox(height: 8),
            _feedCercanas(),
          ],
        ),
      ),
    );
  }

  /// Feed principal: todas las tiendas activas cerca del usuario
  /// (premium y no premium), ordenadas por distancia.
  Widget _feedCercanas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text('📍 Cerca de ti', style: Theme.of(context).textTheme.titleMedium),
        ),
        if (_errorUbicacion != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Column(
              children: [
                Icon(Icons.location_off_outlined, size: 40, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  'No pudimos acceder a tu ubicación.\n$_errorUbicacion',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.black54),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _cargarCercanas,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          )
        else if (_cercanas == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _cercanas,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Column(
                    children: [
                      Text(
                        'Error al buscar tiendas: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(color: Colors.red[700], fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _cargarCercanas,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                );
              }
              final tiendas = snapshot.data ?? [];
              if (tiendas.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                  child: Center(
                    child: Text(
                      'No hay tiendas activas cerca de ti todavía',
                      style: GoogleFonts.inter(color: Colors.black54),
                    ),
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: tiendas.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final t = tiendas[i];
                  final distanciaKm = t['distancia_km'] ?? t['distancia'];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        child: Icon(Icons.storefront_outlined,
                            color: Theme.of(context).colorScheme.primary),
                      ),
                      title: Text(t['nombre'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                      subtitle: Text('${t['municipio'] ?? ''}, ${t['provincia'] ?? ''}'),
                      trailing: distanciaKm != null
                          ? Text(
                              '${(distanciaKm is num ? distanciaKm.toDouble() : double.tryParse(distanciaKm.toString()) ?? 0).toStringAsFixed(1)} km',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.black54),
                            )
                          : null,
                      onTap: () {
                        // TODO: navegar a la vista de la tienda (Flujo 4.2 del Doc Maestro)
                      },
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }

  Widget _seccion({
    required String titulo,
    required double altura,
    required Future<List<Map<String, dynamic>>> future,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(titulo, style: Theme.of(context).textTheme.titleMedium),
        ),
        SizedBox(
          height: altura,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Error: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.red[700]),
                    ),
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('Nada por aquí todavía'));
              }
              final tiendas = snapshot.data!;
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: tiendas.length,
                itemBuilder: (context, i) {
                  final t = tiendas[i];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: SizedBox(
                      width: 140,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t['nombre'] ?? '',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (t.containsKey('puntos_semanales'))
                              Text('${t['puntos_semanales']} pts'),
                            if (t.containsKey('promedio_estrellas'))
                              Text('⭐ ${t['promedio_estrellas']}'),
                          ],
                        ),
                      ),
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
}
