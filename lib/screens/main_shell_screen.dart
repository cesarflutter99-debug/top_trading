// main_shell_screen.dart
//
// Contenedor con menú inferior (bottom navigation) para las 5
// secciones principales: Inicio, Mapa, Favoritos, Mi Tienda y Perfil.
// Cada pestaña conserva su propio Scaffold/AppBar tal cual ya estaban
// -- este shell solo decide cuál se muestra y agrega la barra de abajo.
//
// La pestaña "Mi Tienda" es la única que depende de un dato async (si
// el usuario ya tiene tienda registrada): mientras carga muestra un
// spinner, y una vez resuelto muestra PanelVendedorScreen si ya es
// vendedor, o una tarjeta invitando a registrarse si no.

import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../services/tiendas_service.dart';
import 'home_screen.dart';
import 'mapa_tiendas_screen.dart';
import 'favoritos_screen.dart';
import 'mi_perfil_screen.dart';
import 'panel_vendedor_screen.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _indice = 0;
  final _tiendasService = TiendasService();

  Map<String, dynamic>? _miTienda;
  bool _cargandoTienda = true;

  @override
  void initState() {
    super.initState();
    _cargarMiTienda();
  }

  Future<void> _cargarMiTienda() async {
    try {
      final tienda = await _tiendasService.obtenerMiTienda();
      if (mounted) {
        setState(() {
          _miTienda = tienda;
          _cargandoTienda = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoTienda = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;

    final paginas = [
      const HomeScreen(),
      const MapaTiendasScreen(),
      const FavoritosScreen(),
      _cargandoTienda
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (_miTienda != null
              ? PanelVendedorScreen(tienda: _miTienda!)
              : _CTAHacerseVendedor(onCreada: _cargarMiTienda)),
      const MiPerfilScreen(),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _indice, children: paginas),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color:
                    (esOscuro ? Colors.black : Colors.white).withOpacity(0.92),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: (esOscuro ? Colors.white : Colors.black)
                      .withOpacity(0.06),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(esOscuro ? 0.4 : 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // ---- Mapa (izquierda) ----
                  Expanded(
                    child: _ItemNav(
                      activo: _indice == 1,
                      iconoInactivo: Icons.map_outlined,
                      iconoActivo: Icons.map_rounded,
                      label: 'Mapa',
                      onTap: () => setState(() => _indice = 1),
                    ),
                  ),
                  // ---- Favoritos ----
                  Expanded(
                    child: _ItemNav(
                      activo: _indice == 2,
                      iconoInactivo: Icons.favorite_border_rounded,
                      iconoActivo: Icons.favorite_rounded,
                      label: 'Favoritos',
                      onTap: () => setState(() => _indice = 2),
                    ),
                  ),
                  // ---- Inicio: siempre al centro, con icono de casita ----
                  Expanded(
                    child: _ItemNav(
                      activo: _indice == 0,
                      iconoInactivo: Icons.home_outlined,
                      iconoActivo: Icons.home_rounded,
                      label: 'Inicio',
                      onTap: () => setState(() => _indice = 0),
                    ),
                  ),
                  // ---- Mi Tienda ----
                  Expanded(
                    child: _ItemNav(
                      activo: _indice == 3,
                      iconoInactivo: Icons.storefront_outlined,
                      iconoActivo: Icons.storefront_rounded,
                      label: 'Mi Tienda',
                      onTap: () => setState(() => _indice = 3),
                    ),
                  ),
                  // ---- Perfil ----
                  Expanded(
                    child: _ItemNav(
                      activo: _indice == 4,
                      iconoInactivo: Icons.person_outline_rounded,
                      iconoActivo: Icons.person_rounded,
                      label: 'Perfil',
                      onTap: () => setState(() => _indice = 4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un ítem de la barra flotante: el ícono activo crece con un
/// resorte (Curves.elasticOut) y aparece con un halo azul detrás +
/// la etiqueta debajo -- los inactivos quedan solo el ícono gris,
/// sin texto, para que la barra se sienta liviana.
class _ItemNav extends StatelessWidget {
  final bool activo;
  final IconData iconoInactivo;
  final IconData iconoActivo;
  final String label;
  final VoidCallback onTap;

  const _ItemNav({
    required this.activo,
    required this.iconoInactivo,
    required this.iconoActivo,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: activo ? 0.0 : 1.0, end: activo ? 1.0 : 0.0),
              builder: (context, t, child) {
                return Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withOpacity(0.14 * t),
                  ),
                  child: Transform.scale(
                    scale: 1.0 + (0.15 * t),
                    child: Icon(
                      activo ? iconoActivo : iconoInactivo,
                      size: 21,
                      color: Color.lerp(
                          AppColors.inkSecundarioLight, AppColors.primary, t),
                    ),
                  ),
                );
              },
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: activo
                  ? Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : const SizedBox(height: 0),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contenido de la pestaña "Mi Tienda" cuando el usuario todavía no
/// tiene una registrada -- invita a crear una. Al volver del registro,
/// refresca (onCreada) para que la pestaña pase a mostrar el panel
/// real sin que el usuario tenga que reabrir la app.
class _CTAHacerseVendedor extends StatelessWidget {
  final VoidCallback onCreada;
  const _CTAHacerseVendedor({required this.onCreada});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi Tienda')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storefront_outlined,
                  size: 64, color: AppColors.primary),
              const SizedBox(height: 16),
              Text('Todavía no tienes una tienda',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'Regístrate como vendedor para empezar a publicar tus productos.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: AppColors.inkSecundarioLight),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () async {
                  await context.push('/crear-tienda');
                  onCreada();
                },
                child: const Text('Hacerte vendedor'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
