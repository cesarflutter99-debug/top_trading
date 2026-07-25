import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import '../services/tiendas_service.dart';
import 'admin_panel_screen.dart';
import 'onboarding_tienda_screen.dart';
import 'panel_vendedor_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _cargando = false;

  // serverClientId = Client ID tipo "Web application" creado en Google
  // Cloud Console (el mismo registrado en Supabase Dashboard -> Auth ->
  // Providers -> Google).
  final _googleSignIn = GoogleSignIn(
    serverClientId:
        '683096373585-1npogbmg8o8133c0l8f0hqid6puci18h.apps.googleusercontent.com',
  );

  Future<void> _entrarConGoogle({bool forzarSelector = false}) async {
    setState(() => _cargando = true);
    try {
      // GoogleSignIn cachea la última cuenta usada y por defecto no
      // vuelve a mostrar el selector. Si el usuario pide explícitamente
      // cambiar de cuenta (o siempre, para evitar loguearse sin querer
      // con la cuenta anterior), cerramos sesión local antes de pedir
      // el login -- así el selector nativo siempre aparece.
      if (forzarSelector) {
        await _googleSignIn.signOut();
      }

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // Usuario cerró el selector sin elegir cuenta
        setState(() => _cargando = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        throw Exception('No se obtuvo idToken de Google');
      }

      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      if (mounted) {
        await _decidirDestino();
      }
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

  Future<void> _decidirDestino() async {
    final tiendasService = TiendasService();

    // Primero chequeamos si esta cuenta está en la whitelist de admins.
    // Si lo está, la app lo manda directo al panel -- el usuario normal
    // nunca ve esta rama porque su cuenta no está en la tabla 'admins'.
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
      // Primera vez: todavía no tiene tienda -> onboarding
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingTiendaScreen()),
      );
    } else {
      // Ya tiene tienda -> a su panel de vendedor (ver/editar datos,
      // subir productos)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => PanelVendedorScreen(tienda: tienda)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acceso de Vendedor')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storefront_outlined, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Para vender en Top Trading necesitas iniciar sesión con Google',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _cargando ? null : () => _entrarConGoogle(),
                icon: _cargando
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login),
                label: const Text('Continuar con Google'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _cargando ? null : () => _entrarConGoogle(forzarSelector: true),
                child: const Text('Usar otra cuenta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
