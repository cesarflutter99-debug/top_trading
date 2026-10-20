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
import 'package:flutter/foundation.dart';
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
import '../services/tutorial_service.dart';
import '../widgets/offline_banner.dart';
import '../widgets/coach_marks_widget.dart';
import 'home_screen.dart';
import 'mapa_tiendas_screen.dart';
import 'favoritos_screen.dart';
import 'anuncios_social_screen.dart';
import 'mi_perfil_screen.dart';
import 'panel_vendedor_screen.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _indice = 0;

  final String _desde = DateTime.now().toIso8601String();

  String _pestanaActual() => switch (_indice) {
        0 => 'Inicio',
        1 => 'Mapa',
        2 => 'Anuncios',
        3 => 'Favoritos',
        4 => 'Mi Tienda',
        5 => 'Perfil',
        _ => 'Inicio',
      };

  // ANUNCIOS (opción B): clave para hablar con el Home montado en el
  // IndexedStack y pedirle que rote el trío de anuncios del feed cada
  // vez que el usuario vuelve a la pestaña Inicio.
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  // Anclas del tour contextual: la barra de navegación inferior (para
  // iluminar pestaña por pestaña) y el área de la pestaña Mi Tienda.
  final GlobalKey _navBarKey = GlobalKey();
  final GlobalKey _tabMiTiendaKey = GlobalKey();

  Map<String, dynamic>? get _miTienda => TiendaStateService.instance.miTienda;
  bool get _cargandoTienda => TiendaStateService.instance.cargando;

  bool get _esWebDesktop =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  late final RealtimeChannel _canalPresencia;
  late final StreamSubscription<AuthState> _suscripcionAuth;

  // Tours contextuales en vuelo (para no duplicar el overlay si el
  // usuario salta de pestaña rápido mientras uno está abierto).
  final Set<String> _toursEnVuelo = {};

  @override
  void initState() {
    super.initState();
    TiendaStateService.instance.cargar();
    TiendaStateService.instance.addListener(_actualizarPresencia);
    // El IndexedStack construye TODAS las pestañas de una, aunque estén
    // ocultas. Por eso el tour de la pestaña VISIBLE inicial se agenda
    // acá (Home es la visible), y los tours de las demás se disparan en
    // _cambiarIndice(), cuando la pestaña pasa a estar visible de verdad.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _programarTourDePestana(_indice);
    });
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
    final rol = uid == null
        ? 'invitado'
        : (_miTienda != null ? 'vendedor' : 'comprador');
    try {
      await _canalPresencia.track({
        'user_id': uid,
        'rol': rol,
        'pestana': _pestanaActual(),
        'desde': _desde,
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _canalPresencia.untrack();
    _canalPresencia.unsubscribe();
    _suscripcionAuth.cancel();
    TiendaStateService.instance.removeListener(_actualizarPresencia);
    super.dispose();
  }

  /// Cambia de pestaña. Si la destino es Inicio, pide al Home que rote
  /// los anuncios del feed (nuevo sorteo "menos mostrados primero")
  /// después del frame, sin recargar el resto del contenido.
  void _cambiarIndice(int indice) {
    setState(() => _indice = indice);
    _actualizarPresencia();
    // El IndexedStack mantiene vivas todas las pestañas; los tours se
    // disparan recién cuando la pestaña se vuelve VISIBLE.
    _programarTourDePestana(indice);
    if (indice == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _homeKey.currentState?.rotarAnuncios();
      });
    }
  }

  /// Agenda el tour contextual de la pestaña `indice` si aún no se vio
  /// y no hay otro en vuelo para esa clave. No corre en el initState de
  /// pestañas ocultas: solo cuando `_cambiarIndice` las deja visibles
  /// (o para la pestaña inicial visible, al primer frame).
  void _programarTourDePestana(int indice) {
    final String? clave = switch (indice) {
      0 => TutorialService.claveHome,
      4 => TutorialService.claveMiTienda,
      _ => null,
    };
    if (clave == null || _toursEnVuelo.contains(clave)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _toursEnVuelo.contains(clave)) return;
      if (await TutorialService.instance.yaVisto(clave)) return;
      if (!mounted) return;

      _toursEnVuelo.add(clave);
      final pasos = switch (indice) {
        0 => [
            CoachStep(
              titulo: 'Explorá el mapa',
              descripcion:
                  'La pestaña Mapa te muestra las tiendas cerca de vos. '
                  'Tocá una para ver sus productos.',
              destino: _rectDestinoNav(0),
            ),
            CoachStep(
              titulo: 'Descubrí anuncios',
              descripcion:
                  'En Anuncios vas a encontrar promociones de tiendas, '
                  'negocios y la plataforma. Podés dar "me gusta" y comentar.',
              destino: _rectDestinoNav(1),
            ),
            CoachStep(
              titulo: 'Tu perfil',
              descripcion:
                  'Iniciá sesión con Google para comprar, guardar '
                  'favoritos y vender.',
              destino: _rectDestinoNav(4),
            ),
          ],
        4 => [
            CoachStep(
              titulo: 'Tu panel de ventas',
              descripcion:
                  'Desde "Mi Tienda" gestionás tus productos, pedidos, '
                  'promociones y tu plan.',
              destino: _rectDestinoNav(3),
            ),
            CoachStep(
              titulo: 'Publicá productos',
              descripcion:
                  'En esta área vas a encontrar el botón de nuevo producto '
                  'para sumar a tu catálogo y empezar a vender.',
              destino: _rectTabMiTienda(),
            ),
          ],
        _ => const <CoachStep>[],
      };

      await CoachMarks.mostrar(
        context,
        titulo: switch (indice) { 4 => 'Tu tienda', _ => 'Descubrí Al Lado' },
        pasos: pasos,
      );
      if (!mounted) return;
      _toursEnVuelo.remove(clave);
      await TutorialService.instance.marcarVisto(clave);
    });
  }

  /// Rect (en coordenadas globales) de la pestaña `posicionEnBarra`
  /// dentro de la barra de navegación. Orden visual de la barra:
  /// Mapa=0, Anuncios=1, Favoritos=2, Inicio=3, Mi Tienda=4, Perfil=5.
  Rect? _rectDestinoNav(int posicionEnBarra) {
    final render = _navBarKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return null;
    final origen = render.localToGlobal(Offset.zero);
    final anchoPorItem = render.size.width / 5;
    final centroX = origen.dx + anchoPorItem * posicionEnBarra + anchoPorItem / 2;
    // Resaltamos solo el icono (no toda la celda), para que el foco
    // quede centrado y preciso sobre la opcion correspondiente.
    const tamano = 48.0;
    return Rect.fromCenter(
      center: Offset(centroX, origen.dy + 22),
      width: tamano,
      height: tamano,
    );
  }

  /// Rect del contenido de la pestaña Mi Tienda (panel del vendedor o CTA).
  Rect? _rectTabMiTienda() {
    final render = _tabMiTiendaKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return null;
    return render.localToGlobal(Offset.zero) & render.size;
  }

  Future<void> _irA(int indice) async {
    final requiereSesion = indice == 3 || indice == 4 || indice == 5;
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

  Widget _bottomNavBar() {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final items = Row(
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
            iconoInactivo: Icons.campaign_outlined,
            iconoActivo: Icons.campaign_rounded,
            label: 'Anuncios',
            onTap: () => _cambiarIndice(2),
          ),
        ),
        Expanded(
          child: _ItemNav(
            activo: _indice == 0,
            iconoInactivo: Icons.home_outlined,
            iconoActivo: Icons.home_rounded,
            label: 'Inicio',
            tamanoIcono: 26,
            onTap: () => _cambiarIndice(0),
          ),
        ),
        Expanded(
          child: _ItemNav(
            activo: _indice == 4,
            iconoInactivo: Icons.storefront_outlined,
            iconoActivo: Icons.storefront_rounded,
            label: 'Mi Tienda',
            onTap: () => _irA(4),
          ),
        ),
        Expanded(
          child: _ItemNav(
            activo: _indice == 5,
            iconoInactivo: Icons.person_outline_rounded,
            iconoActivo: Icons.person_rounded,
            label: 'Perfil',
            onTap: () => _irA(5),
          ),
        ),
      ],
    );

    if (_esWebDesktop) {
      // Barra inferior sólida (no flotante) para web/escritorio.
      return Container(
        key: _navBarKey,
        decoration: BoxDecoration(
          color: esOscuro ? const Color(0xFF1C1C1E) : Colors.white,
          border: Border(
            top: BorderSide(
              color: (esOscuro ? Colors.white : Colors.black).withOpacity(0.08),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: items,
      );
    }

    // Barra inferior flotante (móvil).
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            key: _navBarKey,
            decoration: BoxDecoration(
              color: (esOscuro ? Colors.black : Colors.white).withOpacity(0.68),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: (esOscuro ? Colors.white : Colors.black).withOpacity(0.06),
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
            child: items,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: TiendaStateService.instance,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final paginas = [
      HomeScreen(key: _homeKey),
      const MapaTiendasScreen(),
      const AnunciosSocialScreen(),
      const FavoritosScreen(),
      // KeyedSubtree: ancla para que el tour de Mi Tienda pueda iluminar
      // todo el panel/CTA como segunda opción a destacar.
      KeyedSubtree(
        key: _tabMiTiendaKey,
        child: _cargandoTienda
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : (_miTienda != null
                ? PanelVendedorScreen(tienda: _miTienda!)
                : const _CTAHacerseVendedor()),
      ),
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
        appBar: null,
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: _esWebDesktop ? 900 : double.infinity),
            child: Column(
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
      ),
    ),
        bottomNavigationBar: _bottomNavBar(),
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
  final double tamanoIcono;

  const _ItemNav({
    required this.activo,
    required this.iconoInactivo,
    required this.iconoActivo,
    required this.label,
    required this.onTap,
    this.tamanoIcono = 22,
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
                size: tamanoIcono,
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
