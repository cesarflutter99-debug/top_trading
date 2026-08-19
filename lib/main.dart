import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'core/app_colors.dart';
import 'core/supabase_client.dart';
import 'router.dart';
import 'services/theme_provider.dart';

// AppColors y kCardRadius ahora viven en core/app_colors.dart -- se
// mantiene ahí para que home_screen.dart y esta config compartan la
// misma fuente de verdad, en vez de duplicarla acá.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const TopTradingApp(),
    ),
  );
}

class TopTradingApp extends StatelessWidget {
  const TopTradingApp({super.key});

  @override
  Widget build(BuildContext context) {
    // FIX (No GoRouter found in context): antes esto era un
    // MaterialApp normal con `home: const WelcomeScreen()`. Eso
    // significa que en TODA la app nunca existió un GoRouter -- por
    // eso cualquier context.go()/context.push() (logout, ir a la
    // tienda, seguir explorando, redirigir tras el login) fallaba con
    // "No GoRouter found in context". Ahora se usa MaterialApp.router
    // conectado a la configuración de router.dart.
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp.router(
      title: 'Al Lado',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: themeProvider.themeMode,
      routerConfig: router,
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final esOscuro = brightness == Brightness.dark;

  final fondo = esOscuro ? AppColors.backgroundDark : AppColors.backgroundLight;
  final superficie = esOscuro ? AppColors.surfaceDark : AppColors.surfaceLight;
  final superficieElevada =
      esOscuro ? Color(0xFF2C2C2E) : AppColors.surfaceLight;
  final textoPrincipal = esOscuro ? AppColors.inkDark : AppColors.inkLight;
  final textoSecundario =
      esOscuro ? AppColors.inkSecundarioDark : AppColors.inkSecundarioLight;
  final bordeSutil = esOscuro
      ? AppColors.borderDark.withOpacity(0.6)
      : AppColors.borderLight.withOpacity(0.8);
  final inputFill =
      esOscuro ? const Color(0xFF2C2C2E) : const Color(0xFFF8F8FA);
  final cardBg = esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight;

  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: superficie,
    brightness: brightness,
  );

  final textTheme = GoogleFonts.plusJakartaSansTextTheme().apply(
    bodyColor: textoPrincipal,
    displayColor: textoPrincipal,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: fondo,
    textTheme: textTheme,

    appBarTheme: AppBarTheme(
      backgroundColor: fondo,
      foregroundColor: textoPrincipal,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: textoPrincipal,
      ),
      systemOverlayStyle:
          esOscuro ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),

    cardTheme: CardThemeData(
      elevation: esOscuro ? 0 : 2,
      shadowColor: Colors.black.withOpacity(0.06),
      color: cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
        side: BorderSide(color: bordeSutil),
      ),
      margin: EdgeInsets.zero,
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputFill,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      hintStyle: GoogleFonts.plusJakartaSans(color: textoSecundario),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: inputFill,
      selectedColor:
          esOscuro ? AppColors.primary.withOpacity(0.2) : AppColors.primary.withOpacity(0.1),
      labelStyle: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: textoPrincipal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9999),
        side: BorderSide.none,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),

    iconTheme: IconThemeData(color: textoPrincipal, size: 22),

    dialogTheme: DialogThemeData(
      backgroundColor: superficieElevada,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadiusLarge),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: superficieElevada,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),

    dividerTheme: DividerThemeData(
      color: bordeSutil,
      thickness: 0.5,
      space: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor:
          esOscuro ? const Color(0xFF2C2C2E) : textoPrincipal,
      contentTextStyle: GoogleFonts.plusJakartaSans(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

// ---------------------------------------------------------------------
// WIDGET REUTILIZABLE: banner destacado en amarillo mostaza
// ---------------------------------------------------------------------
// Úsalo para avisos importantes -- ej. "Tienda en revisión", "Plan por
// vencer", promociones. Mantiene el estilo consistente sin que cada
// pantalla reinvente su propio Container.
class AppBanner extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String mensaje;
  final Widget? accion;

  const AppBanner({
    super.key,
    required this.icon,
    required this.titulo,
    required this.mensaje,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: esOscuro
            ? AppColors.warm.withOpacity(0.12)
            : AppColors.warmLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.warm.withOpacity(0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.warm, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: esOscuro
                        ? AppColors.warm.withOpacity(0.9)
                        : const Color(0xFF92400E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  mensaje,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    height: 1.4,
                    color: esOscuro
                        ? AppColors.inkSecundarioDark
                        : const Color(0xFF78350F),
                  ),
                ),
                if (accion != null) ...[
                  const SizedBox(height: 10),
                  accion!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
