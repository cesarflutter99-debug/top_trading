// afiliado_tiendas_referidas_screen.dart
//
// Lista completa de tiendas referidas por el afiliado -- se abre
// desde el botón "Ver todas" de AfiliadoPerfilScreen cuando hay más
// de 5. Recibe la lista ya agrupada por tienda (ver
// AfiliadoPerfilScreen._agruparPorTienda), no vuelve a golpear la
// base de datos.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';

class AfiliadoTiendasReferidasScreen extends StatelessWidget {
  final List<Map<String, dynamic>> tiendas;

  const AfiliadoTiendasReferidasScreen({super.key, required this.tiendas});

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final colorTexto = esOscuro ? const Color(0xFFF5F5F4) : AppColors.ink;
    final colorTextoSecundario =
        esOscuro ? AppColors.inkSecundarioDark : AppColors.inkSecundarioLight;
    final colorSuperficie =
        esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight;
    final colorBorde =
        (esOscuro ? AppColors.borderDark : AppColors.borderLight)
            .withOpacity(0.6);

    // Ordenadas por comisión acumulada, de mayor a menor.
    final ordenadas = List<Map<String, dynamic>>.from(tiendas)
      ..sort((a, b) => ((b['comision_acumulada'] as num?) ?? 0)
          .compareTo((a['comision_acumulada'] as num?) ?? 0));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Tiendas referidas'),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ordenadas.isEmpty
          ? Center(
              child: Text('Todavía no tienes tiendas referidas',
                  style: GoogleFonts.plusJakartaSans(color: colorTextoSecundario)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: ordenadas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final t = ordenadas[i];
                final logo = t['logo_url'] as String?;
                final comision = (t['comision_acumulada'] as num?) ?? 0;
                final aprobado = t['estado'] == 'aprobado';
                return Container(
                  decoration: BoxDecoration(
                    color: colorSuperficie,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorBorde),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.warm.withOpacity(0.1),
                      backgroundImage: (logo != null && logo.isNotEmpty)
                          ? NetworkImage(logo)
                          : null,
                      child: (logo == null || logo.isEmpty)
                          ? const Icon(Icons.storefront_rounded,
                              color: AppColors.warm)
                          : null,
                    ),
                    title: Text(t['nombre'] ?? 'Tienda',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: colorTexto)),
                    subtitle: Text(
                      aprobado ? 'Comisión aprobada' : 'Pendiente de aprobación',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: aprobado ? AppColors.success : Colors.orange),
                    ),
                    trailing: Text(
                      '+${comision.toStringAsFixed(0)} CUP',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          color: AppColors.warm,
                          fontSize: 14),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
