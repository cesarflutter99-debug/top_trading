// favoritos_screen.dart
//
// Lista de tiendas que el usuario marcó como favoritas. Se lee de
// obtenerMisFavoritos() (join favoritos + tiendas). Cada fila se puede
// tocar para ir a la tienda, o quitar de favoritos con el ícono de
// corazón.
//
// FIX: el Row del subtitle armaba el municipio como Text suelto, sin
// Flexible/Expanded. Si el nombre del municipio + las estrellas no
// entraban en el ancho disponible del ListTile, Flutter tiraba un
// RenderFlex overflow (la pantalla roja/amarilla con rayas negras que
// aparecía al abrir esta pestaña). Se envuelve el texto de municipio
// en Flexible + ellipsis para que se recorte en vez de desbordar.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../core/auth_guard.dart';
import '../core/supabase_client.dart';
import '../services/tiendas_service.dart';

class FavoritosScreen extends StatefulWidget {
  const FavoritosScreen({super.key});

  @override
  State<FavoritosScreen> createState() => _FavoritosScreenState();
}

class _FavoritosScreenState extends State<FavoritosScreen> {
  final _tiendasService = TiendasService();
  late Future<List<Map<String, dynamic>>> _favoritos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _favoritos = _tiendasService.obtenerMisFavoritos();
  }

  Future<void> _quitar(String idTienda) async {
    try {
      await _tiendasService.quitarFavorito(idTienda);
      if (mounted) setState(_cargar);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo quitar de favoritos: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;

    // Invitado sin sesión: ni intentamos pedir obtenerMisFavoritos()
    // (fallaría por RLS, uid null) -- mostramos un CTA claro para
    // loguearse en vez de un error críptico.
    if (supabase.auth.currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Favoritos')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_border_rounded,
                    size: 56, color: AppColors.inkSecundarioLight),
                const SizedBox(height: 16),
                Text('Inicia sesión para ver tus favoritos',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                Text(
                  'Guarda tiendas favoritas iniciando sesión con Google.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5, color: AppColors.inkSecundarioLight),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => mostrarModalInicioSesion(context),
                  child: const Text('Iniciar sesión'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Favoritos')),
      body: RefreshIndicator(
        onRefresh: () async => setState(_cargar),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _favoritos,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                      'No se pudieron cargar tus favoritos: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                          color: AppColors.inkSecundarioLight)),
                ),
              );
            }
            final favoritos = snapshot.data ?? [];
            if (favoritos.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 100),
                  Icon(Icons.favorite_border_rounded,
                      size: 56, color: AppColors.inkSecundarioLight),
                  const SizedBox(height: 16),
                  Center(
                    child: Text('Todavía no tienes tiendas favoritas',
                        style: GoogleFonts.plusJakartaSans(
                            color: AppColors.inkSecundarioLight)),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                        'Toca el corazón en cualquier tienda para guardarla acá',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12.5,
                            color: AppColors.inkSecundarioLight)),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: favoritos.length,
              itemBuilder: (context, i) {
                final f = favoritos[i];
                final t = f['tiendas'] as Map<String, dynamic>? ?? {};
                final idTienda = t['id_tienda'] as String?;
                final esVip =
                    (t['plan'] as String? ?? '').toLowerCase() == 'premium';
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    onTap: idTienda != null
                        ? () => context.push('/tienda/$idTienda')
                        : null,
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      backgroundImage: (t['logo_url'] as String?) != null &&
                              (t['logo_url'] as String).isNotEmpty
                          ? NetworkImage(t['logo_url'] as String)
                          : null,
                      child: (t['logo_url'] as String?) == null ||
                              (t['logo_url'] as String).isEmpty
                          ? const Icon(Icons.storefront_rounded,
                              color: AppColors.primary)
                          : null,
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(t['nombre'] ?? '',
                              style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (esVip) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.star_rounded,
                              size: 14, color: AppColors.warm),
                        ],
                      ],
                    ),
                    subtitle: Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 13, color: Color(0xFFD4AF37)),
                        const SizedBox(width: 3),
                        Text(
                          (t['promedio_estrellas'] as num?)
                                  ?.toStringAsFixed(1) ??
                              'Sin reseñas',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12),
                        ),
                        if ((t['municipio'] ?? '').toString().isNotEmpty)
                          Flexible(
                            child: Text('  ·  ${t['municipio']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    GoogleFonts.plusJakartaSans(fontSize: 12)),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.favorite_rounded,
                          color: Colors.redAccent),
                      onPressed:
                          idTienda != null ? () => _quitar(idTienda) : null,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
