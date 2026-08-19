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
//
// NAVEGACIÓN "ATRÁS" (FIX): antes el diálogo de "¿Desea salir de la
// aplicación?" vivía dentro de HomeScreen (con su propio PopScope). El
// problema es que HomeScreen es una de las pestañas de un IndexedStack
// acá abajo -- un IndexedStack mantiene TODAS las pestañas montadas en
// todo momento (solo oculta las que no se ven). Eso significaba que el
// PopScope de HomeScreen seguía "vivo" sin importar en qué pestaña
// estuviera el usuario, así que presionar atrás en Favoritos, Mi Tienda
// o Perfil disparaba igual el diálogo de salir, en vez de comportarse
// como una navegación normal.
//
// Ahora el PopScope vive acá, en el dueño real de las pestañas:
//   - Si el usuario NO está en la pestaña "Inicio" (índice 0), atrás lo
//     regresa a Inicio en vez de preguntar si quiere salir.
//   - Si ya está en "Inicio", ahí sí se muestra el diálogo de salida.
// Las pantallas que se abren con Navigator.push (Gestionar Tienda,
// Admin, etc.) no se ven afectadas -- siguen cerrándose normalmente con
// atrás, ya que son rutas apiladas de verdad, no pestañas del shell.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../core/auth_guard.dart';
import '../core/supabase_client.dart';
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

  /// Cambia de pestaña. Favoritos (2), Mi Tienda (3) y Perfil (4)
  /// requieren sesión: un invitado que toque una de esas ve el modal
  /// "Debes iniciar sesión" en vez de la pestaña (que solo mostraría el
  /// estado de invitado / lo mandaría de vuelta a la Welcome).
  Future<void> _irA(int indice) async {
    final requiereSesion = indice == 2 || indice == 3 || indice == 4;
    if (!requiereSesion || supabase.auth.currentUser != null) {
      setState(() => _indice = indice);
      return;
    }
    await mostrarModalInicioSesion(context);
  }

  /// Diálogo de confirmación de salida -- solo se muestra cuando el
  /// usuario ya está en la pestaña "Inicio" (índice 0) y presiona atrás.
  Future<bool> _confirmarSalir() async {
    return await showDialog<bool>(
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

  /// Maneja el botón/gesto "atrás" del sistema para todo el shell:
  ///   1. Si no está en "Inicio", vuelve a "Inicio".
  ///   2. Si ya está en "Inicio", pregunta si quiere salir de la app.
  Future<void> _manejarAtras() async {
    if (_indice != 0) {
      setState(() => _indice = 0);
      return;
    }
    final salir = await _confirmarSalir();
    if (salir) SystemNavigator.pop();
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _manejarAtras();
      },
      child: Scaffold(
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
                  color: (esOscuro ? Colors.black : Colors.white)
                      .withOpacity(0.68),
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
                padding:
                    const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: _ItemNav(
                        activo: _indice == 1,
                        iconoInactivo: Icons.map_outlined,
                        iconoActivo: Icons.map_rounded,
                        label: 'Mapa',
                        onTap: () => setState(() => _indice = 1),
                      ),
                    ),
                    Expanded(
                      child: _ItemNav(
                        activo: _indice == 2,
                        iconoInactivo: Icons.favorite_border_rounded,
                        iconoActivo: Icons.favorite_rounded,
                        label: 'Favoritos',
                        onTap: () => _irA(2),
                      ),
                    ),
                    Expanded(
                      child: _ItemNav(
                        activo: _indice == 0,
                        iconoInactivo: Icons.home_outlined,
                        iconoActivo: Icons.home_rounded,
                        label: 'Inicio',
                        onTap: () => setState(() => _indice = 0),
                      ),
                    ),
                    Expanded(
                      child: _ItemNav(
                        activo: _indice == 3,
                        iconoInactivo: Icons.storefront_outlined,
                        iconoActivo: Icons.storefront_rounded,
                        label: 'Mi Tienda',
                        onTap: () => _irA(3),
                      ),
                    ),
                    Expanded(
                      child: _ItemNav(
                        activo: _indice == 4,
                        iconoInactivo: Icons.person_outline_rounded,
                        iconoActivo: Icons.person_rounded,
                        label: 'Perfil',
                        onTap: () => _irA(4),
                      ),
                    ),
                  ],
                ),
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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: activo
                    ? AppColors.primary.withOpacity(0.14)
                    : Colors.transparent,
              ),
              child: Icon(
                activo ? iconoActivo : iconoInactivo,
                size: 22,
                color:
                    activo ? AppColors.primary : AppColors.inkSecundarioLight,
              ),
            ),
            if (activo)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
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
                  if (!await requireAuth(context)) return;
                  if (!context.mounted) return;
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