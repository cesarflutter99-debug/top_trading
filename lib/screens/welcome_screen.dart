import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/supabase_client.dart';
import '../services/tiendas_service.dart';
import 'admin_panel_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'onboarding_tienda_screen.dart';
import 'panel_vendedor_screen.dart';

/// Adaptado del diseño original hecho en FlutterFlow ("Onboarding Entry").
/// Se reconstruyó con widgets Flutter puros para conectarlo a la
/// navegación y lógica reales de la app (sin las dependencias del
/// paquete FlutterFlowTheme / componentes personalizados del export).
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // true mientras comprobamos si ya hay una sesión de vendedor guardada.
  // Evita el parpadeo de la pantalla de bienvenida si vamos a redirigir.
  bool _verificandoSesion = true;

  @override
  void initState() {
    super.initState();
    _verificarSesionExistente();
  }

  /// Supabase ya persiste la sesión en el dispositivo por defecto.
  /// Esto solo la lee y, si es válida, manda directo al panel
  /// correspondiente sin pasar por LoginScreen -- así el vendedor
  /// no tiene que loguearse cada vez que abre la app.
  Future<void> _verificarSesionExistente() async {
    final session = supabase.auth.currentSession;

    if (session == null) {
      if (mounted) setState(() => _verificandoSesion = false);
      return;
    }

    try {
      final tiendasService = TiendasService();

      final esAdmin = await tiendasService.esAdmin();
      if (!mounted) return;

      if (esAdmin) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
        );
        return;
      }

      final tienda = await tiendasService.obtenerMiTienda();
      if (!mounted) return;

      if (tienda == null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingTiendaScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => PanelVendedorScreen(tienda: tienda)),
        );
      }
    } catch (e) {
      // Si falla la consulta (ej. sin internet), no bloqueamos al usuario:
      // simplemente mostramos la bienvenida normal.
      if (mounted) setState(() => _verificandoSesion = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_verificandoSesion) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---------- Hero con imagen de fondo + degradado ----------
            SizedBox(
              height: 420,
              child: Stack(
                alignment: Alignment.bottomLeft,
                children: [
                  CachedNetworkImage(
                    imageUrl:
                        'https://dimg.dreamflow.cloud/v1/image/Havana%20street%20scene%20with%20vintage%20cars%20and%20colorful%20colonial%20architecture',
                    height: 420,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                  Container(
                    height: 420,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.white,
                          Colors.white.withOpacity(0.75),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.6, 1],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: primary,
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Text(
                            'HABANA MARKET',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'El mercado de La Habana en tu bolsillo',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w900,
                            fontSize: 30,
                            height: 1.2,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Explora, compra y vende localmente con conexiones reales.',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            height: 1.5,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ---------- Feature items ----------
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  _FeatureItem(
                    icon: Icons.store_rounded,
                    title: 'Tiendas Verificadas',
                    desc: 'Compra con seguridad en comercios validados por la comunidad.',
                    color: primary,
                  ),
                  const SizedBox(height: 24),
                  _FeatureItem(
                    icon: Icons.payments_rounded,
                    title: 'Precio Local',
                    desc: 'Conversión automática USD/CUP según la tasa del día.',
                    color: primary,
                  ),
                  const SizedBox(height: 24),
                  _FeatureItem(
                    icon: Icons.location_on_rounded,
                    title: 'Geolocalización',
                    desc: 'Encuentra productos cerca de ti en todos los municipios.',
                    color: primary,
                  ),
                ],
              ),
            ),

            // ---------- Botones de acceso ----------
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Text(
                    '¿Quieres empezar a comprar?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Comprador: entra directo, sin login (navegación anónima)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: primary,
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const HomeScreen()),
                        );
                      },
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Explorar como Comprador'),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('O',
                              style: GoogleFonts.inter(color: Colors.black45)),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                  ),

                  Text(
                    '¿Eres vendedor?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),

                  // Vendedor: requiere autenticación Google (obligatoria)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.g_mobiledata_rounded, size: 28),
                          const SizedBox(width: 8),
                          Text(
                            'Entrar como Vendedor',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ---------- Footer legal ----------
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    'Al continuar, aceptas nuestros',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.black45),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Términos de Servicio',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: primary,
                              decoration: TextDecoration.underline)),
                      Text(' y ',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: Colors.black45)),
                      Text('Privacidad',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: primary,
                              decoration: TextDecoration.underline)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final Color color;

  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.desc,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 4),
              Text(desc,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: Colors.black54, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
