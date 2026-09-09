// main_shell_screen.dart
//
// OFFLINE (2026-08): se agrega OfflineBanner (main.dart) arriba del
// contenido, envuelto en su propio AnimatedBuilder escuchando
// ConnectivityService + PendingActionsQueue -- aparece solo cuando no
// hay red, y muestra cuántas acciones quedaron en cola para enviarse.
// No reemplaza el resto de la lógica del shell, solo se agrega una
// franja arriba del IndexedStack existente.
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../core/auth_guard.dart';
import '../core/supabase_client.dart';
import '../services/tienda_state_service.dart';
import '../services/connectivity_service.dart';
import '../services/pending_actions_queue.dart';
import '../widgets/offline_banner.dart';
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

  // ANUNCIOS (opción B): clave para hablar con el Home montado en el
  // IndexedStack y pedirle que rote el trío de anuncios del feed cada
  // vez que el usuario vuelve a la pestaña Inicio.
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  Map<String, dynamic>? get _miTienda => TiendaStateService.instance.miTienda;
  bool get _cargandoTienda => TiendaStateService.instance.cargando;

  late final RealtimeChannel _canalPresencia;
  late final StreamSubscription<AuthState> _suscripcionAuth;

  @override
  void initState() {
    super.initState();
    TiendaStateService.instance.cargar();
    _canalPresencia = supabase.channel(
      'usuarios-online',
      opts: const RealtimeChannelConfig(private: false),
    );
    _canalPresencia.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _actualizarPresencia();
      }
    });
    _suscripcionAuth = supabase.auth.onAuthStateChange.listen((_) {
      _actualizarPresencia();
    });
  }

  Future<void> _actualizarPresencia() async {
    final uid = supabase.auth.currentUser?.id;
    try {
      if (uid != null) {
        await _canalPresencia.track({
          'user_id': uid,
          'desde': DateTime.now().toIso8601String(),
        });
      } else {
        await _canalPresencia.untrack();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _canalPresencia.untrack();
    _canalPresencia.unsubscribe();
    _suscripcionAuth.cancel();
    super.dispose();
  }

  /// Cambia de pestaña. Si la destino es Inicio, pide al Home que rote
  /// los anuncios del feed (nuevo sorteo "menos mostrados primero")
  /// después del frame, sin recargar el resto del contenido.
  void _cambiarIndice(int indice) {
    setState(() => _indice = indice);
    if (indice == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _homeKey.currentState?.rotarAnuncios();
      });
    }
  }

  Future<void> _irA(int indice) async {
    final requiereSesion = indice == 2 || indice == 3 || indice == 4;
    if (!requiereSesion || supabase.auth.currentUser != null) {
      _cambiarIndice(indice);
      return;
    }
    await mostrarModalInicioSesion(context);
  }

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

  Future<void> _manejarAtras() async {
    if (_indice != 0) {
      _cambiarIndice(0);
      return;
    }
    final salir = await _confirmarSalir();
    if (salir) SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: TiendaStateService.instance,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;

    final paginas = [
      HomeScreen(key: _homeKey),
      const MapaTiendasScreen(),
      const FavoritosScreen(),
      _cargandoTienda
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (_miTienda != null
              ? PanelVendedorScreen(tienda: _miTienda!)
              : const _CTAHacerseVendedor()),
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
        body: Column(
          children: [
            // OFFLINE: franja roja que aparece sola sin importar en
            // qué pestaña esté el usuario -- escucha conexión y cola.
            AnimatedBuilder(
              animation: ConnectivityService.instance,
              builder: (context, _) {
                if (ConnectivityService.instance.online) {
                  return const SizedBox.shrink();
                }
                return AnimatedBuilder(
                  animation: PendingActionsQueue.instance,
                  builder: (context, __) => OfflineBanner(
                    accionesPendientes: PendingActionsQueue.instance.cantidad,
                  ),
                );
              },
            ),
            Expanded(
              child: IndexedStack(index: _indice, children: paginas),
            ),
          ],
        ),
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
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: _ItemNav(
                        activo: _indice == 1,
                        iconoInactivo: Icons.map_outlined,
                        iconoActivo: Icons.map_rounded,
                        label: 'Mapa',
                        onTap: () => _cambiarIndice(1),
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
                        onTap: () => _cambiarIndice(0),
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

class _CTAHacerseVendedor extends StatelessWidget {
  const _CTAHacerseVendedor();

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
                  await TiendaStateService.instance.refrescar();
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
