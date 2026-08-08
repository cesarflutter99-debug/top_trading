import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import '../services/notificaciones_service.dart';

/// Pantalla de entrada única. Ya no existe navegación anónima: todo
/// usuario (comprador o vendedor) debe autenticarse con Google antes
/// de entrar al marketplace.
///
/// Antes esto abría LoginScreen (pantalla intermedia con un solo
/// botón). Se fusionó aquí porque esa pantalla no aportaba nada por sí
/// sola -- "Continuar con Google" dispara el OAuth directo desde este
/// mismo botón, sin la pantalla de en medio. LoginScreen puede
/// borrarse del proyecto (y su ruta /login de router.dart, si aún
/// existe) una vez confirmes que esto funciona.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _cargando = false;
  StreamSubscription<AuthState>? _authSub;

  Future<void> _entrarConGoogle() async {
    setState(() => _cargando = true);
    try {
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.toptrading://login-callback/',
      );

      // Si ya había una suscripción de un intento anterior, no
      // agregamos otra encima.
      _authSub ??= supabase.auth.onAuthStateChange.listen((data) async {
        final sesion = data.session;
        if (sesion != null && mounted) {
          // Arranca el servicio de notificaciones (historial +
          // Realtime) justo después de un login exitoso -- antes esto
          // vivía en login_screen.dart y nunca se llamaba.
          await NotificacionesService.instance.iniciar();

          // AJUSTA '/home' si en tu router.dart la ruta de HomeScreen
          // tiene otro path.
          if (mounted) context.go('/home');
          await _authSub?.cancel();
          _authSub = null;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al iniciar sesión: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final fondo = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: fondo,
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
                          fondo,
                          fondo.withOpacity(0.75),
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
                            'AlLADO',
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
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Explora, compra y vende localmente con conexiones reales.',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            height: 1.5,
                            color: Theme.of(context).textTheme.bodyMedium?.color,
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
                    desc:
                        'Compra con seguridad en comercios validados por la comunidad.',
                    color: primary,
                  ),
                  const SizedBox(height: 24),
                  _FeatureItem(
                    icon: Icons.payments_rounded,
                    title: 'Precio Local',
                    desc:
                        'Conversión automática USD/CUP según la tasa del día.',
                    color: primary,
                  ),
                  const SizedBox(height: 24),
                  _FeatureItem(
                    icon: Icons.location_on_rounded,
                    title: 'Geolocalización',
                    desc:
                        'Encuentra productos cerca de ti en todos los municipios.',
                    color: primary,
                  ),
                ],
              ),
            ),

            // ---------- CTA único: Google directo, sin pantalla intermedia ----------
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: primary,
                      ),
                      onPressed: _cargando ? null : _entrarConGoogle,
                      icon: _cargando
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.login_rounded),
                      label: const Text('Continuar con Google'),
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
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color),
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
                              fontSize: 12,
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color)),
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
                      fontSize: 13,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                      height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}