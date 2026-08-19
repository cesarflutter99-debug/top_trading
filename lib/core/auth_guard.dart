// auth_guard.dart
//
// Chequeo centralizado para CUALQUIER acción que requiera sesión:
// agregar/quitar favorito, comprar (completar pedido), crear tienda,
// ver favoritos o la pestaña Mi Tienda/Perfil, etc.
//
// Uso en cualquier botón/acción:
//
//   onPressed: () async {
//     if (!await requireAuth(context)) return;
//     // ... la acción real, ya con sesión garantizada ...
//   }
//
// Si el usuario ya está logueado, retorna true de inmediato y no hace
// nada más -- el llamador sigue normal. Si es un invitado (currentUser
// == null), en vez de mandarlo de vuelta al WelcomeScreen ('/') muestra
// un modal "Debes iniciar sesión para utilizar estas funciones" con un
// botón que dispara el login de Google directo desde donde esté.
//
// El login usa google_sign_in (nativo): el selector de cuentas de
// Google sale como UI del sistema, SIN navegador, así nunca se ve la
// URL de supabase.co que antes asustaba a los usuarios. Si el login
// nativo no está configurado (falta el Web Client ID) cae al OAuth por
// navegador para no dejar la app rota. Al completarse la sesión navega
// a '/home' y el llamador corta la acción (el usuario ya quedó
// autenticado).
//
// Antes esto hacía snackbar + context.go('/'), lo que devolvía al
// invitado a la pantalla de entrada sin explicación. Ahora el login se
// lanza desde el propio modal, sin pasar por la Welcome de nuevo.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notificaciones_service.dart';
import 'app_colors.dart';
import 'google_auth_config.dart';
import 'supabase_client.dart';

/// Muestra el modal "Debes iniciar sesión para utilizar estas
/// funciones". Si el usuario acepta, lanza el login de Google directo
/// (sin pasar por WelcomeScreen) y al completarse navega a '/home'.
/// Si ya hay sesión, no hace nada.
Future<void> mostrarModalInicioSesion(
  BuildContext context, {
  String mensaje = 'Debes iniciar sesión para utilizar estas funciones',
}) async {
  if (supabase.auth.currentUser != null) return;

  final esOscuro = Theme.of(context).brightness == Brightness.dark;

  final continuar = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor:
          esOscuro ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
      title: const Row(
        children: [
          Icon(Icons.lock_outline_rounded,
              color: AppColors.primary, size: 22),
          SizedBox(width: 10),
          Expanded(child: Text('Iniciar sesión')),
        ],
      ),
      content: Text(
        mensaje,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: esOscuro
              ? AppColors.inkSecundarioDark
              : AppColors.inkSecundarioLight,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(
            'Cancelar',
            style: GoogleFonts.plusJakartaSans(
              color: esOscuro
                  ? AppColors.inkSecundarioDark
                  : AppColors.inkSecundarioLight,
            ),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(
            'Iniciar sesión con Google',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  if (continuar == true && context.mounted) {
    await iniciarSesionConGoogle(context);
  }
}

/// Login de Google. Primero intenta el flujo NATIVO (google_sign_in):
/// el selector de cuentas sale como UI del sistema, sin navegador y sin
/// que se vea la URL de supabase.co. Si el nativo no está configurado o
/// falla, cae al OAuth por navegador (el flujo de antes).
///
/// Al completarse, arranca las notificaciones y navega a '/home'.
/// Retorna true si el login se completó; false si el usuario canceló o
/// falló.
Future<bool> iniciarSesionConGoogle(BuildContext context) async {
  if (supabase.auth.currentUser != null) return true;

  // 1) Intento nativo: depende del Web Client ID en
  //    google_auth_config.dart. Si está sin configurar, signIn() tira
  //    y caemos al punto 2.
  try {
    final sesion = await _iniciarSesionNativa();
    if (sesion != null) {
      await NotificacionesService.instance.iniciar();
      if (context.mounted) context.go('/home');
      return true;
    }
  } on _CanceladoInicioSesion {
    // El usuario cerró el selector de cuentas de Google: no es un
    // error, simplemente no hay nada que mostrar.
    return false;
  } catch (_) {
    // Config de Google incompleta o sin Google Play Services: caemos
    // al OAuth del navegador para no dejar el login roto.
  }

  // 2) Fallback: OAuth por navegador (el flujo de antes).
  if (!context.mounted) return false;
  return _iniciarSesionConGoogleOAuth(context);
}

/// Login nativo con google_sign_in + signInWithIdToken de Supabase.
/// Nunca abre el navegador. Retorna la sesión, o lanza
/// [_CanceladoInicioSesion] si el usuario cierra el selector de cuentas.
Future<Session?> _iniciarSesionNativa() async {
  final signIn = GoogleSignIn(
    clientId: GoogleAuthConfig.iosClientId.isEmpty
        ? null
        : GoogleAuthConfig.iosClientId,
    serverClientId: GoogleAuthConfig.webClientId,
    scopes: const ['email', 'profile'],
  );

  final GoogleSignInAccount? googleUser;
  try {
    googleUser = await signIn.signIn();
  } on PlatformException catch (e) {
    final codigo = e.code.toLowerCase();
    if (codigo.contains('cancel')) throw const _CanceladoInicioSesion();
    rethrow;
  }
  if (googleUser == null) throw const _CanceladoInicioSesion();

  final auth = await googleUser.authentication;
  final idToken = auth.idToken;
  if (idToken == null) {
    throw StateError('Google no devolvió un token de sesión.');
  }

  final respuesta = await supabase.auth.signInWithIdToken(
    provider: OAuthProvider.google,
    idToken: idToken,
    accessToken: auth.accessToken,
  );
  return respuesta.session;
}

/// OAuth de Google por navegador (deep link de Supabase), usado como
/// fallback cuando el login nativo no está configurado. Espera a que
/// llegue la sesión; cuando llega, arranca las notificaciones y navega
/// a '/home'. Retorna true si el login se completó; false si falló o el
/// usuario canceló el flujo (timeout de 5 min por si cierra la pestaña
/// de Google sin loguearse y el listener nunca avisa).
Future<bool> _iniciarSesionConGoogleOAuth(BuildContext context) async {
  final completer = Completer<bool>();
  final sub = supabase.auth.onAuthStateChange.listen((data) {
    if (data.session != null && !completer.isCompleted) {
      completer.complete(true);
    }
  });

  try {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.toptrading://login-callback/',
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al iniciar sesión: $e')),
      );
    }
    await sub.cancel();
    if (!completer.isCompleted) completer.complete(false);
    return false;
  }

  final timeout = Timer(const Duration(minutes: 5), () {
    if (!completer.isCompleted) completer.complete(false);
  });

  final ok = await completer.future;
  timeout.cancel();
  await sub.cancel();

  if (ok) {
    await NotificacionesService.instance.iniciar();
    if (context.mounted) context.go('/home');
  }
  return ok;
}

/// Marca interna para distinguir "el usuario cerró el selector de
/// cuentas de Google" de un error real (en ese caso no hay que mostrar
/// ningún mensaje ni hacer fallback).
class _CanceladoInicioSesion implements Exception {
  const _CanceladoInicioSesion();
}

/// true si ya hay sesión. Para invitados muestra el modal y retorna
/// false -- el llamador corta la acción (tras el login el usuario queda
/// en '/home', ya autenticado, y puede repetir la acción).
Future<bool> requireAuth(
  BuildContext context, {
  String mensaje = 'Debes iniciar sesión para utilizar estas funciones',
}) async {
  if (supabase.auth.currentUser != null) return true;
  await mostrarModalInicioSesion(context, mensaje: mensaje);
  return false;
}
