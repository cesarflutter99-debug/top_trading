// offline_banner.dart
//
// Banner delgado y persistente para "Sin conexión" -- distinto del
// AppBanner (que es para avisos puntuales de una pantalla).
// Se usa envuelto en un AnimatedBuilder(animation:
// ConnectivityService.instance) desde MainShellScreen, así aparece/
// desaparece solo en toda la app sin que cada pantalla lo repita.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OfflineBanner extends StatelessWidget {
  final int accionesPendientes;
  const OfflineBanner({super.key, this.accionesPendientes = 0});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.red.shade600,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 15, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  accionesPendientes > 0
                      ? 'Sin conexión · $accionesPendientes cambio${accionesPendientes == 1 ? '' : 's'} pendiente${accionesPendientes == 1 ? '' : 's'} de enviar'
                      : 'Sin conexión · viendo información guardada',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
