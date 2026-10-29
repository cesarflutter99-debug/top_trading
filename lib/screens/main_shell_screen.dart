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
import '../widgets/tour_anchor.dart';
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
      1 => TutorialService.claveMapa,
      2 => TutorialService.claveAnuncios,
      4 => TutorialService.claveMiTienda,
      5 => TutorialService.clavePerfil,
      _ => null,
    };
    if (clave == null || _toursEnVuelo.contains(clave)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _toursEnVuelo.contains(clave)) return;
      if (await TutorialService.instance.yaVisto(clave)) return;
      if (!mounted) return;

      _toursEnVuelo.add(clave);
      final pasos = _pasosDelTour(indice);
      await CoachMarks.mostrar(
        context,
        titulo: _tituloDelTour(indice),
        pasos: pasos,
      );
      if (!mounted) return;
      _toursEnVuelo.remove(clave);
      await TutorialService.instance.marcarVisto(clave);
    });
  }

  String _tituloDelTour(int indice) => switch (indice) {
        1 => 'Explorar el mapa',
        2 => 'Anuncios',
        3 => 'Favoritos',
        4 => 'Tu tienda',
        5 => 'Tu perfil',
        _ => 'Bienvenido a Al Lado',
      };

  /// Pasos de cada tour. El foco se ancla a widgets REALES (TourAnchor),
  /// asi que el círculo cae con precisión de pixel sobre el botón.
  List<CoachStep> _pasosDelTour(int indice) => switch (indice) {
        0 => const [
            CoachStep(
              titulo: 'Tu inicio',
              descripcion:
                  'Acá ves las tiendas más cercanas, los productos que '
                  'están cerca de vos y los anuncios del barrio. Deslizá '
                  'para explorar.',
              ancla: TourAnclas.navInicio,
            ),
            CoachStep(
              titulo: 'Mapa: tiendas cerca de vos',
              descripcion:
                  'Tocá el mapa y filtrá por distancia. Ves dónde está cada '
                  'tienda antes de ir, para que no pierdas el tiempo '
                  'viajando.',
              ancla: TourAnclas.navMapa,
            ),
            CoachStep(
              titulo: 'Anuncios de la comunidad',
              descripcion:
                  'Promociones de tiendas, negocios y la plataforma. Podés '
                  'dar "me gusta", comentar y compartir.',
              ancla: TourAnclas.navAnuncios,
            ),
            CoachStep(
              titulo: 'Tu tienda y tu perfil',
              descripcion:
                  'En "Mi Tienda" vendés tus productos. En "Perfil" están tus '
                  'datos, tus pedidos y el soporte.',
              ancla: TourAnclas.navMiTienda,
            ),
            CoachStep(
              titulo: 'Todo a un toque',
              descripcion:
                  'El botón del medio siempre te trae de vuelta al inicio, '
                  'sin importar dónde estés. Abrimos el menú con el botón '
                  'de arriba a la izquierda.',
              ancla: TourAnclas.homeHamburguesa,
            ),
          ],
        1 => const [
            CoachStep(
              titulo: 'Filtra por distancia',
              descripcion:
                  'Ajusta el radio para ver solo lo que tienes cerca. Con '
                  'la ubicación activada el mapa se centra en vos.',
              ancla: TourAnclas.mapaBuscador,
            ),
            CoachStep(
              titulo: 'Filtra por categoría',
              descripcion:
                  'Tocá una categoría para ver solo tiendas de ese tipo: '
                  'gastronomía, moda, salud y más.',
              ancla: TourAnclas.mapaChips,
            ),
            CoachStep(
              titulo: 'Tocá un pin',
              descripcion:
                  'Cada pin es una tienda. Abrís su ficha con sus productos, '
                  'horarios y cómo contactarla.',
              ancla: TourAnclas.navMapa,
            ),
          ],
        2 => const [
            CoachStep(
              titulo: 'Buscá por categoría',
              descripcion:
                  'Tocá la categoría que te interesa y el feed se filtra al '
                  'instante. "Todos" para ver todo.',
              ancla: TourAnclas.anunciosChips,
            ),
            CoachStep(
              titulo: 'Creá y potenciá anuncios',
              descripcion:
                  'Con el botón flotante publicás un anuncio propio, o '
                  'potenciás uno de tu tienda para que salga más.',
              ancla: TourAnclas.anunciosFab,
            ),
            CoachStep(
              titulo: 'Interactuá con la comunidad',
              descripcion:
                  'Cada anuncio tiene su botón de WhatsApp. Alguien que '
                  'te escriba puede comprar en la tienda del anuncio.',
              ancla: TourAnclas.navAnuncios,
            ),
          ],
        4 => [
            CoachStep(
              titulo: 'Tu panel de ventas',
              descripcion:
                  'Desde "Mi Tienda" gestionás tus productos, pedidos, '
                  'promociones y tu plan. Es tu negocio desde el celular.',
              ancla: TourAnclas.navMiTienda,
            ),
            // Si el usuario todavía no tiene tienda, el botón de nuevo
            // producto no existe: el foco cae en la tarjeta de la
            // pestaña, que es donde se crea la tienda.
            if (_miTienda != null)
              CoachStep(
                titulo: 'Publicá productos',
                descripcion:
                    'Con el botón de nuevo producto sumás artículos a tu '
                    'catálogo y empezás a vender.',
                ancla: TourAnclas.miTiendaNuevo,
              )
            else
              CoachStep(
                titulo: '¿Querés vender?',
                descripcion:
                    'Creá tu tienda gratis y empezá a vender. Es un minuto '
                    'y te abre el catálogo al instante.',
                ancla: TourAnclas.navMiTienda,
              ),
          ],
        5 => const [
            CoachStep(
              titulo: 'Tu perfil',
              descripcion:
                  'Acá cambiás tu foto, ves tus pedidos, tus anuncios y tu '
                  'plan. También entrás al chat de soporte.',
              ancla: TourAnclas.navPerfil,
            ),
            CoachStep(
              titulo: 'Tus datos y tu foto',
              descripcion:
                  'Tocá tu foto para cambiarla. Podés sacarla con la cámara '
                  'o elegirla de la galería.',
              ancla: TourAnclas.perfilAvatar,
            ),
            CoachStep(
              titulo: '¿Necesitás ayuda?',
              descripcion:
                  'En el chat de soporte escribís y te responde el equipo '
                  'de Al Lado. También podés ver las preguntas frecuentes.',
              ancla: TourAnclas.navPerfil,
            ),
          ],
        _ => const <CoachStep>[],
      };

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
          child: TourAnchor(
            id: TourAnclas.navMapa,
            child: _ItemNav(
            activo: _indice == 1,
            iconoInactivo: Icons.map_outlined,
            iconoActivo: Icons.map_rounded,
            label: 'Mapa',
            onTap: () => _cambiarIndice(1),
            ),
          ),
        ),
        Expanded(
          child: TourAnchor(
            id: TourAnclas.navAnuncios,
            child: _ItemNav(
            activo: _indice == 2,
            iconoInactivo: Icons.campaign_outlined,
            iconoActivo: Icons.campaign_rounded,
            label: 'Anuncios',
            onTap: () => _cambiarIndice(2),
            ),
          ),
        ),
        Expanded(
          child: TourAnchor(
            id: TourAnclas.navInicio,
            child: _ItemNav(
            activo: _indice == 0,
            iconoInactivo: Icons.home_outlined,
            iconoActivo: Icons.home_rounded,
            label: 'Inicio',
            tamanoIcono: 26,
            onTap: () => _cambiarIndice(0),
            ),
          ),
        ),
        Expanded(
          child: TourAnchor(
            id: TourAnclas.navMiTienda,
            child: _ItemNav(
            activo: _indice == 4,
            iconoInactivo: Icons.storefront_outlined,
            iconoActivo: Icons.storefront_rounded,
            label: 'Mi Tienda',
            onTap: () => _irA(4),
            ),
          ),
        ),
        Expanded(
          child: TourAnchor(
            id: TourAnclas.navPerfil,
            child: _ItemNav(
            activo: _indice == 5,
            iconoInactivo: Icons.person_outline_rounded,
            iconoActivo: Icons.person_rounded,
            label: 'Perfil',
            onTap: () => _irA(5),
            ),
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
