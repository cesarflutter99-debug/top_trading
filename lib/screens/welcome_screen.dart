import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/auth_guard.dart';

/// Pantalla de entrada única. Todo usuario puede ENTRAR sin cuenta y
/// mirar el marketplace libremente (botón "Explorar sin iniciar
/// sesión") -- pero para cualquier acción real (comprar, guardar
/// favoritos, vender, ver su perfil) va a necesitar loguearse con
/// Google. Las pantallas que requieren sesión ya validan
/// supabase.auth.currentUser (ver core/auth_guard.dart para el modal
/// "Debes iniciar sesión" que se muestra a los invitados).
///
/// El botón "Continuar con Google" usa el login NATIVO de Google
/// (google_sign_in): el selector de cuentas sale como UI del sistema,
/// sin navegador, y nunca se ve la URL de supabase.co (ver
/// core/google_auth_config.dart para la config).
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _cargando = false;

  Future<void> _entrarConGoogle() async {
    setState(() => _cargando = true);
    try {
      // Login nativo con fallback a OAuth -- comparte el mismo flujo
      // que el modal de core/auth_guard.dart, así que el login es
      // idéntico desde la Welcome o desde cualquier pantalla.
      await iniciarSesionConGoogle(context);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Entra al marketplace SIN autenticarse. El usuario puede navegar y
  /// mirar tiendas/productos con total libertad; en cuanto intente
  /// comprar, marcar un favorito, vender o ver su perfil, esas
  /// pantallas (que ya chequean supabase.auth.currentUser) muestran el
  /// modal de inicio de sesión de core/auth_guard.dart.
  void _explorarSinCuenta() {
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final fondo = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: fondo,
      // FIX (botón "quedaba abajo"): antes el Column vivía suelto
      // dentro del SingleChildScrollView, así que en pantallas donde
      // el contenido (hero + features + CTA + footer) medía más que
      // el alto visible, "Continuar con Google" aparecía recién al
      // hacer scroll. Ahora el Column se envuelve en un
      // ConstrainedBox con minHeight = alto real disponible
      // (LayoutBuilder) y mainAxisAlignment.center: si el contenido
      // entra en la pantalla, queda centrado verticalmente de una;
      // si no entra (pantallas chicas), simplemente scrollea como
      // antes, sin romper nada.
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---------- Hero con imagen de fondo + degradado ----------
                  // Alto proporcional a la pantalla (antes era un fijo
                  // 420, que en teléfonos chicos empujaba todo lo demás
                  // fuera de vista) -- clamp para no verse ni aplastado
                  // ni gigante en los extremos.
                  SizedBox(
                    height: (MediaQuery.of(context).size.height * 0.34)
                        .clamp(240.0, 380.0),
                    child: Stack(
                      alignment: Alignment.bottomLeft,
                      children: [
                        CachedNetworkImage(
                          imageUrl:
                              'https://dimg.dreamflow.cloud/v1/image/Havana%20street%20scene%20with%20vintage%20cars%20and%20colorful%20colonial%20architecture',
                          height: double.infinity,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                        Container(
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
                          padding: const EdgeInsets.all(28),
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
                              const SizedBox(height: 14),
                              Text(
                                'El mercado de La Habana en tu bolsillo',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 26,
                                  height: 1.2,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.color,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Explora, compra y vende localmente con conexiones reales.',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color,
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
                    padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
                    child: Column(
                      children: [
                        _FeatureItem(
                          icon: Icons.store_rounded,
                          title: 'Tiendas Verificadas',
                          desc:
                              'Compra con seguridad en comercios validados por la comunidad.',
                          color: primary,
                        ),
                        const SizedBox(height: 18),
                        _FeatureItem(
                          icon: Icons.payments_rounded,
                          title: 'Precio Local',
                          desc:
                              'Conversión automática USD/CUP según la tasa del día.',
                          color: primary,
                        ),
                        const SizedBox(height: 18),
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

                  // ---------- CTA: Google directo + explorar sin cuenta ----------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
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
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _cargando ? null : _explorarSinCuenta,
                          child: Text(
                            'Explorar sin iniciar sesión',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              color: primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Podrás mirar tiendas y productos libremente. Para '
                          'comprar, guardar favoritos o vender vas a necesitar '
                          'iniciar sesión con Google.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            height: 1.4,
                            color: Theme.of(context).textTheme.bodySmall?.color,
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
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color),
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
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color)),
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
                ],
              ),
            ),
          );
        },
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
