// router.dart
//
// Configuración única de GoRouter para toda la app.
//
// Rutas registradas:
//   '/'                     WelcomeScreen (pantalla de entrada; el botón
//                            "Continuar con Google" autentica directo
//                            desde ahí -- ya no existe LoginScreen)
//   '/home'                 MainShellScreen (destino post-login -- shell
//                            con menú inferior: Inicio/Mapa/Perfil)
//   '/mapa'                 MapaTiendasScreen (también accesible como
//                            pestaña del shell; ruta aparte para el
//                            ítem del Drawer y deep links)
//   '/tienda/:idTienda'     StoreScreen (?producto= para resaltar uno)
//   '/carrito/:idTienda'    CartScreen
//   '/crear-tienda'         OnboardingTiendaScreen ("Hacerte vendedor")
//   '/gestionar-tienda'     GestionarTiendaScreen (recibe extra: Map tienda)
//   '/gestionar-planes'     GestionarPlanesScreen (recibe extra: Map tienda;
//                            usado por "Hacerte premium" desde Home)
//   '/mi-tienda'            PanelVendedorScreen (recibe extra: Map tienda)
//   '/afiliados/registro'   AfiliadoRegistroScreen (primera vez)
//   '/afiliados/perfil'     AfiliadoPerfilScreen (ya es afiliado --
//                            saldo, historial, editar datos, retiro)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/supabase_client.dart';
import 'screens/welcome_screen.dart';
import 'screens/main_shell_screen.dart';
import 'screens/mapa_tiendas_screen.dart';
import 'screens/store_screen_flow.dart';
import 'screens/cart_screen.dart';
import 'screens/onboarding_tienda_screen.dart';
import 'screens/gestionar_tienda_screen.dart';
import 'screens/panel_vendedor_screen.dart';
import 'screens/gestionar_planes_screen.dart';
import 'screens/gestionar_ventas_screen.dart';
import 'screens/valorar_pedido_screen.dart';
import 'screens/afiliado_registro_screen.dart';
import 'screens/afiliado_dashboard_screen.dart';
import 'screens/afiliado_perfil_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/comprador_dashboard_screen.dart';
import 'screens/mi_perfil_screen.dart';
import 'screens/vendedor_dashboard_screen.dart';
import 'widgets/modal_pago_plan.dart';
import 'services/tiendas_service.dart';

class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier() {
    supabase.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
}

enum _DestinoVendedor { ventas, miTienda, planes }

/// Carga la tienda del usuario logueado (obtenerMiTienda()) y luego
/// muestra la pantalla real -- usado por las rutas /vendedor/* que
/// llegan desde una notificación y solo tienen el id del usuario en
/// sesión, no el Map completo de la tienda.
class _CargarMiTiendaYMostrar extends StatelessWidget {
  final _DestinoVendedor destino;
  const _CargarMiTiendaYMostrar({required this.destino});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: TiendasService().obtenerMiTienda(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final tienda = snapshot.data;
        if (tienda == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Mi Tienda')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No encontramos una tienda asociada a tu cuenta.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        switch (destino) {
          case _DestinoVendedor.ventas:
            return GestionarVentasScreen(tienda: tienda);
          case _DestinoVendedor.miTienda:
            return PanelVendedorScreen(tienda: tienda);
          case _DestinoVendedor.planes:
            return GestionarPlanesScreen(tienda: tienda);
        }
      },
    );
  }
}

final GoRouter router = GoRouter(
  initialLocation: '/',
  refreshListenable: _AuthChangeNotifier(),
  redirect: (context, state) {
    final haySesion = supabase.auth.currentSession != null;
    final enWelcome = state.matchedLocation == '/';

    if (haySesion && enWelcome) return '/home';
    if (!haySesion && !enWelcome) return '/';
    return null;
  },
  routes: [
    GoRoute(
      path: '/gestionar-planes',
      builder: (context, state) {
        final tienda = state.extra as Map<String, dynamic>? ?? {};
        return GestionarPlanesScreen(tienda: tienda);
      },
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const WelcomeScreen(),
    ),
    GoRoute(
      path: '/home',
      // FIX: antes esto abría HomeScreen directo. Ahora abre el shell
      // con el menú inferior (Inicio/Mapa/Perfil) -- HomeScreen sigue
      // siendo exactamente la misma pantalla, solo que ahora vive
      // adentro del shell como la primera pestaña.
      builder: (context, state) => const MainShellScreen(),
    ),
    GoRoute(
      path: '/mapa',
      builder: (context, state) => const MapaTiendasScreen(),
    ),
    GoRoute(
      path: '/tienda/:idTienda',
      builder: (context, state) => StoreScreen(
        idTienda: state.pathParameters['idTienda']!,
        productoDestacadoId: state.uri.queryParameters['producto'],
      ),
    ),
    GoRoute(
      path: '/carrito/:idTienda',
      builder: (context, state) => CartScreen(
        idTienda: state.pathParameters['idTienda']!,
      ),
    ),
    GoRoute(
      path: '/crear-tienda',
      builder: (context, state) => const OnboardingTiendaScreen(),
    ),
    GoRoute(
      path: '/pago-plan',
      builder: (context, state) => _PagoPlanScreen(
        extra: state.extra as Map<String, dynamic>? ?? const {},
      ),
    ),
    GoRoute(
      path: '/gestionar-tienda',
      builder: (context, state) {
        final tienda = state.extra as Map<String, dynamic>? ?? {};
        return GestionarTiendaScreen(tienda: tienda);
      },
    ),
    GoRoute(
      path: '/mi-tienda',
      builder: (context, state) {
        final tienda = state.extra as Map<String, dynamic>? ?? {};
        return PanelVendedorScreen(tienda: tienda);
      },
    ),
    // -----------------------------------------------------------------
    // Rutas usadas por notifications_screen.dart al tocar una
    // notificación. A diferencia de las rutas de arriba, estas NO
    // reciben la tienda por `extra` (la notificación solo trae
    // id_tienda/id_pedido en su `data`, no el Map completo) -- así que
    // cargan la tienda del usuario logueado con obtenerMiTienda() antes
    // de mostrar la pantalla real. Esto asume que la notificación
    // siempre es sobre la tienda del propio usuario (nunca de otro),
    // lo cual es cierto para nuevo_pedido, pedido_por_expirar,
    // tienda_aprobada, plan_por_vencer y solicitud_plan.
    // -----------------------------------------------------------------
    GoRoute(
      path: '/vendedor/pedidos',
      builder: (context, state) => const _CargarMiTiendaYMostrar(
        destino: _DestinoVendedor.ventas,
      ),
    ),
    GoRoute(
      path: '/vendedor/mi-tienda',
      builder: (context, state) => const _CargarMiTiendaYMostrar(
        destino: _DestinoVendedor.miTienda,
      ),
    ),
    GoRoute(
      path: '/vendedor/planes',
      builder: (context, state) => const _CargarMiTiendaYMostrar(
        destino: _DestinoVendedor.planes,
      ),
    ),
    GoRoute(
      path: '/valorar/:idPedido',
      builder: (context, state) => ValorarPedidoScreen(
        idPedido: state.pathParameters['idPedido']!,
        idTienda: state.uri.queryParameters['tienda'],
      ),
    ),
    GoRoute(
      path: '/afiliados/registro',
      builder: (context, state) => const AfiliadoRegistroScreen(),
    ),
    GoRoute(
      path: '/afiliados/perfil',
      builder: (context, state) => const AfiliadoPerfilScreen(),
    ),
    GoRoute(
      path: '/mi-perfil',
      builder: (context, state) => const MiPerfilScreen(),
    ),
    GoRoute(
      path: '/vendedor/dashboard',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final idTienda = extra?['id'] as String?;
        return VendedorDashboardScreen(idTienda: idTienda);
      },
    ),
    GoRoute(
      path: '/admin/dashboard',
      builder: (context, state) => const AdminDashboardScreen(),
    ),
    GoRoute(
      path: '/comprador/dashboard',
      builder: (context, state) => const CompradorDashboardScreen(),
    ),
    GoRoute(
      path: '/afiliado/dashboard',
      builder: (context, state) => const AfiliadoDashboardScreen(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('Página no encontrada')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No se encontró la ruta "${state.uri}".\n\n'
          'Si acabas de agregar una pantalla nueva, revisa que esté '
          'registrada en router.dart.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  ),
);

/// Pantalla de pago del plan tras crear la tienda en el onboarding.
/// Carga la tienda recién creada (por id) y el plan elegido (por código)
/// y muestra ModalPagoPlan en un Scaffold a pantalla completa.
class _PagoPlanScreen extends StatefulWidget {
  final Map<String, dynamic> extra;
  const _PagoPlanScreen({required this.extra});

  @override
  State<_PagoPlanScreen> createState() => _PagoPlanScreenState();
}

class _PagoPlanScreenState extends State<_PagoPlanScreen> {
  late Future<Map<String, dynamic>?> _tienda;
  late Future<Map<String, dynamic>?> _plan;

  @override
  void initState() {
    super.initState();
    final tiendasService = TiendasService();
    final idTienda = widget.extra['idTienda'] as String?;
    final codigoPlan = widget.extra['plan'] as String? ?? 'basic';
    _tienda = idTienda == null
        ? Future.value(null)
        : tiendasService.obtenerTiendaPorId(idTienda);
    _plan = tiendasService.obtenerPlanesActivos().then((planes) {
      for (final p in planes) {
        if ((p['codigo'] as String? ?? '') == codigoPlan) return p;
      }
      return planes.isNotEmpty ? planes.first : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Pago del plan'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/crear-tienda'),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _tienda,
        builder: (context, tiendaSnap) {
          if (!tiendaSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final tienda = tiendaSnap.data;
          if (tienda == null) {
            return const Center(
              child: Text('No se pudo cargar la tienda. Vuelve a intentarlo.'),
            );
          }
          return FutureBuilder<Map<String, dynamic>?>(
            future: _plan,
            builder: (context, planSnap) {
              if (!planSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final plan = planSnap.data;
              if (plan == null) {
                return const Center(
                  child: Text('No se pudo cargar el plan seleccionado.'),
                );
              }
              return ModalPagoPlan(
                tienda: tienda,
                plan: plan,
                tiendasService: TiendasService(),
                esPantallaCompleta: true,
                onSolicitudCreada: () => context.go('/vendedor/mi-tienda'),
              );
            },
          );
        },
      ),
    );
  }
}
