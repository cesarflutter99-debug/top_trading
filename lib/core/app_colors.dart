// app_colors.dart
//
// Paleta Apple-style adaptativa (claro/oscuro).
// Diseñada para un marketplace moderno con tarjetas
// transparentes flotantes y alto contraste en ambos modos.
//
// Modo claro: fondos fríos gris-claro, tarjetas blancas,
// acento azul sistema Apple, naranja cálido para VIP/premium.
// Modo oscuro: fondos casi negros, tarjetas gris oscuro,
// acento azul luminoso, naranja cálido para VIP/premium.

import 'package:flutter/material.dart';

class AppColors {
  // ---- Acento principal / CTA ----
  // Azul sistema Apple — funciona en claro y oscuro.
  static const primary = Color(0xFF007AFF);
  static const primaryDark = Color(0xFF0A5FD4);

  // ---- Fondo ----
  // Modo claro: gris azulado muy suave (iOS grouped background).
  // Modo oscuro: casi negro.
  static const backgroundLight = Color(0xFFF2F2F7);
  static const backgroundDark = Color(0xFF000000);

  // ---- Superficie (tarjetas, inputs) ----
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF1C1C1E);

  // ---- Tarjetas flotantes transparentes ----
  // Fondo semitransparente que permite ver el gradiente
  // de fondo debajo, creando el efecto "flotante".
  static const cardTransparentLight = Color(0xF2FFFFFF);
  static const cardTransparentDark = Color(0xF21C1C1E);

  // ---- Texto ----
  static const inkLight = Color(0xFF1C1C1E);
  static const inkDark = Color(0xFFFFFFFF);
  static const inkSecundarioLight = Color(0xFF8E8E93);
  static const inkSecundarioDark = Color(0xFF8E8E93);

  static const coral = Color(0xFFFF6B35);
  static const coralDark = Color(0xFFE55A2B);
  static const crema = Color(0xFFFFF8F0);

  // ---- Acento cálido (VIP / premium / destacados) ----
  static const warm = Color(0xFFFF6B35);
  static const warmLight = Color(0xFFFFF0E6);

  static const ink = inkLight;
  static const mostazaLight = Color(0xFFFFF3E0);

  // ---- Éxito / confirmación ----
  static const success = Color(0xFF34C759);

  // ---- Borde sutil ----
  static const borderLight = Color(0xFFE5E5EA);
  static const borderDark = Color(0xFF38383A);
}

const double kCardRadius = 20.0;
const double kCardRadiusLarge = 28.0;
