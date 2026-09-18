// detalle_anuncio_modal.dart
//
// Modal CENTRADO con los detalles completos de un anuncio. Se abre al
// tocar la tarjeta en el feed (TarjetaAnuncio / TarjetaCarruselAnuncio).
//
// Antes, tocar la tarjeta navegaba DIRECTO al destino (modal de
// producto / tienda / negocio / WhatsApp). Eso no dejaba ver qué era el
// anuncio. Ahora el tap abre este diálogo con la imagen grande, el
// título, el texto completo y (si es standalone) el precio como CTA, y
// recién al tocar "Ver tienda" / "Ver negocio" / "Me interesa" ejecuta
// la navegación real -- que la ejecuta el callback onVerAnunciante del
// llamador para reutilizar el flujo existente (registro de clic, rutas).
//
// Uso:
//   mostrarDetalleAnuncio(
//     context: context,
//     anuncio: a,
//     onVerAnunciante: () { ...navegación actual... },
//   );

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../services/anuncios_service.dart';

/// Abre el modal centrado. [onVerAnunciante] se invoca SOLO cuando el
/// usuario toca el botón de acción principal (ver tienda/negocio o Me
/// interesa), y el llamador es quien ejecuta la navegación real.
Future<void> mostrarDetalleAnuncio({
  required BuildContext context,
  required Anuncio anuncio,
  required VoidCallback onVerAnunciante,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _DetalleAnuncioDialog(
      anuncio: anuncio,
      onVerAnunciante: () {
        Navigator.of(dialogContext).pop();
        onVerAnunciante();
      },
    ),
  );
}

class _DetalleAnuncioDialog extends StatelessWidget {
  final Anuncio anuncio;
  final VoidCallback onVerAnunciante;

  const _DetalleAnuncioDialog({
    required this.anuncio,
    required this.onVerAnunciante,
  });

  String get _labelAccion {
    if (anuncio.idProducto != null) return 'Ver producto';
    if (anuncio.idTienda != null) return 'Ver tienda';
    if (anuncio.idNegocio != null) return 'Ver negocio';
    return 'Me interesa';
  }

  IconData get _iconoAccion {
    if (anuncio.idProducto != null) return Icons.shopping_bag_outlined;
    if (anuncio.idTienda != null) return Icons.storefront_rounded;
    if (anuncio.idNegocio != null) return Icons.apartment_rounded;
    return Icons.chat_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final colorSuperficie =
        esOscuro ? AppColors.cardTransparentDark : Colors.white;
    final colorBorde =
        (esOscuro ? AppColors.borderDark : AppColors.borderLight)
            .withOpacity(0.6);
    final a = anuncio;
    final imagen = (a.imagenUrl ?? '').trim();
    final precio = a.precioUsd;

    return Dialog(
      backgroundColor: colorSuperficie,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorBorde),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Imagen grande (o placeholder) ----
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              child: imagen.isNotEmpty
                  ? Image.network(
                      imagen,
                      height: 190,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _placeholderImagen(height: 190),
                    )
                  : _placeholderImagen(height: 190),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- Badge de etiqueta ----
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      a.etiquetaFinal.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ---- Título ----
                  Text(
                    a.titulo ?? 'Anuncio',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _colorTexto(esOscuro),
                    ),
                  ),
                  // ---- Precio (standalone) ----
                  if (precio != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '\$ ${_formatearPrecio(precio)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // ---- Texto completo ----
                  Text(
                    a.texto ?? '',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      height: 1.45,
                      color: _colorTextoSecundario(esOscuro),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // ---- Botón principal: ver anunciante/Me interesa ----
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onVerAnunciante,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: Icon(_iconoAccion, size: 18),
                      label: Text(_labelAccion,
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  ),
                  // ---- Cerrar ----
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderImagen({required double height}) {
    return Container(
      height: height,
      color: AppColors.primary.withOpacity(0.08),
      alignment: Alignment.center,
      child: Icon(Icons.campaign_rounded,
          size: 54, color: AppColors.primary.withOpacity(0.55)),
    );
  }

  Color _colorTexto(bool esOscuro) =>
      esOscuro ? const Color(0xFFF5F5F4) : AppColors.ink;

  Color _colorTextoSecundario(bool esOscuro) =>
      esOscuro ? AppColors.inkSecundarioDark : AppColors.inkSecundarioLight;

  String _formatearPrecio(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }
}