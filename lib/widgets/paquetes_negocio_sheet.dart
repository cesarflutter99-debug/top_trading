// paquetes_negocio_sheet.dart
//
// ENTRADA de "Anuncios y promociones" del negocio: primero muestra las
// OFERTAS (paquetes_anuncio activos) y el flujo de pago por WhatsApp
// (registrar compra pendiente con código -> abrir chat -> el admin
// verifica el comprobante y aprueba; el trigger compras_anuncio_aprobar
// crea el permiso solo). Espejo del flujo de adquisición de plan.
//
// Si el negocio ya tiene permiso vigente, arriba aparece su estado y un
// acceso directo a GESTIONAR sus anuncios (anuncios_negocio_sheet).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/anuncios_service.dart';
import '../services/tiendas_service.dart';
import '../services/currency_service.dart';
import '../screens/standalone_anuncio_screen.dart';
import 'fila_dato_copiable.dart';

const Color _kVerde = Color(0xFF0D9488);

/// Compatibilidad: la antigua hoja "Anuncios y promociones" del negocio
/// ya no existe. Todo se gestiona desde el anuncio unificado.
Future<void> mostrarPaquetesNegocioSheet(
  BuildContext context,
  Map<String, dynamic> negocio,
) {
  return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const StandaloneAnuncioScreen()));
}

/// Modal de pago de UN paquete, público para reutilizarlo desde el
/// onboarding de negocio (primer pago al registrarse) y desde este
/// sheet (paquetes adicionales). [onVerificar] se ejecuta al presionar
/// "Verificar Pago" -- debe registrar la compra pendiente y devolver
/// el código de referencia (AN-XXXX) que se incluye en el mensaje.
/// `negocio` solo necesita 'nombre' (para el mensaje de WhatsApp); la
/// fila puede no existir todavía -- onVerificar decide qué crear.
Future<void> mostrarModalPagoPaquete({
  required BuildContext context,
  required Map<String, dynamic> paquete,
  required List<Map<String, dynamic>> cuentas,
  required Map<String, dynamic> negocio,
  required Future<String> Function() onVerificar,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (_) => _ModalPagoPaquete(
      paquete: paquete,
      cuentas: cuentas,
      negocio: negocio,
      onVerificar: onVerificar,
    ),
  );
}

/// Modal de pago de un paquete -- MISMO estilo que ModalPagoPlan:
/// precio verde, tarjeta blanca con QR, datos de la cuenta, pasos
/// numerados y botón verde "Verificar Pago" (WhatsApp).
class _ModalPagoPaquete extends StatefulWidget {
  final Map<String, dynamic> paquete;
  final List<Map<String, dynamic>> cuentas;
  final Map<String, dynamic> negocio;
  final Future<String> Function() onVerificar;

  const _ModalPagoPaquete({
    required this.paquete,
    required this.cuentas,
    required this.negocio,
    required this.onVerificar,
  });

  @override
  State<_ModalPagoPaquete> createState() => _ModalPagoPaqueteState();
}

class _ModalPagoPaqueteState extends State<_ModalPagoPaquete> {
  final _anunciosService = AnunciosService();
  final _tiendasService = TiendasService();
  bool _procesando = false;

  late Map<String, dynamic>? _cuentaSel =
      widget.cuentas.isEmpty ? null : widget.cuentas.first;

  // Teléfono a mostrar/copiar: el del paquete si existe; si no, el
  // WhatsApp de pagos de anuncios y como último recurso el contacto
  // genérico de la app.
  String? _telefonoPago;

  @override
  void initState() {
    super.initState();
    final t = widget.paquete['numero_telefono_pago'];
    _telefonoPago = t is String ? t : t?.toString();
    if (_telefonoPago == null || _telefonoPago!.trim().isEmpty) {
      _cargarTelefonoPago();
    }
  }

  Future<void> _cargarTelefonoPago() async {
    String? numero = await _anunciosService.obtenerWhatsappPagos();
    numero ??= await _tiendasService.obtenerContactoWhatsappActivo();
    if (numero != null && numero.trim().isNotEmpty) {
      if (mounted) setState(() => _telefonoPago = numero);
    }
  }

  Future<void> _verificarPago() async {
    if (widget.cuentas.isNotEmpty && _cuentaSel == null) return;
    setState(() => _procesando = true);
    try {
      // AQUÍ es donde el plan/compra pasa a 'pendiente'.
      final codigoRef = await widget.onVerificar();

      var telefono = await _anunciosService.obtenerWhatsappPagos();
      telefono ??= await _tiendasService.obtenerContactoWhatsappActivo();
      if (!mounted) return;
      Navigator.of(context).pop();

      final buf = StringBuffer();
      final esRegistro = widget.paquete['tipo_paquete'] == 'registro_negocio';
      buf.writeln(esRegistro
          ? 'REGISTRO DE NEGOCIO (pago único) en Al Lado:'
          : 'Compra de PAQUETE DE ANUNCIO en Al Lado:');
      buf.writeln('- Negocio: ${widget.negocio['nombre'] ?? 'nuestro negocio'}');
      final email = supabase.auth.currentUser?.email;
      if (email != null && email.isNotEmpty) buf.writeln('- Cuenta: $email');
      buf.writeln('- Paquete: ${widget.paquete['nombre']} '
          '(${CurrencyService.instance.formatear((widget.paquete['precio_usd'] as num).toDouble())} / '
          '${esRegistro ? 'pago único' : '${widget.paquete['duracion_dias']} días'})');
      if (_cuentaSel != null) {
        buf.writeln(
            '- Pagado en: ${_cuentaSel!['tipo']} · ${_cuentaSel!['numero_tarjeta']}');
      }
      buf.writeln('- Código de compra: $codigoRef');
      buf.write('Adjunto la captura del comprobante.');

      if (telefono == null || telefono.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Solicitud registrada. El admin aún no configuró WhatsApp '
                'de contacto.')));
        return;
      }
      final url = Uri.parse('https://wa.me/${telefono.trim()}/?text='
          '${Uri.encodeComponent(buf.toString())}');
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al procesar la solicitud: $e')));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final colorSecundario = AppColors.inkSecundarioLight;
    final colorSuperficie = esOscuro
        ? AppColors.cardTransparentDark
        : AppColors.cardTransparentLight;
    final colorBorde =
        (esOscuro ? AppColors.borderDark : AppColors.borderLight).withOpacity(0.6);
    final p = widget.paquete;

    // FIX (2026-08): este modal se abría con showModalBottomSheet(
    // backgroundColor: Colors.transparent) desde _abrirModalPago() más
    // arriba, y ESTE widget nunca ponía su propio fondo opaco encima
    // -- a diferencia de _PaquetesNegocioSheet (el sheet padre), que sí
    // envuelve todo en un Container con color. Resultado: el modal de
    // pago se veía completamente transparente, con el texto flotando
    // sobre lo que hubiera detrás e ilegible. Ahora se envuelve todo en
    // un Container con el mismo color de superficie que el resto de la
    // app (blanco / gris oscuro según el tema).
    return Container(
      decoration: BoxDecoration(
        color: esOscuro ? Theme.of(context).colorScheme.surface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Text(p['tipo_paquete'] == 'registro_negocio'
                    ? 'Pagar ${p['nombre']}'
                    : 'Pagar paquete ${p['nombre']}',
                    style: GoogleFonts.inter(
                        fontSize: 19, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: CurrencyToggle(),
                ),
                const SizedBox(height: 6),
                AnimatedBuilder(
                  animation: CurrencyService.instance,
                  builder: (context, _) => Text(
                    '${CurrencyService.instance.formatear((p['precio_usd'] as num).toDouble())} '
                    p['tipo_paquete'] == 'registro_negocio'
                        ? '· pago único, para siempre'
                        : '· ${p['duracion_dias']} días',
                    style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: esOscuro
                            ? Colors.green.shade300
                            : Colors.green),
                  ),
                ),
                const SizedBox(height: 16),

                // ---------- Selector de cuenta (si hay varias) ----------
                if (widget.cuentas.length > 1) ...[
                  Text('¿Dónde vas a pagar?',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final c in widget.cuentas)
                        ChoiceChip(
                          label: Text('${c['tipo']} · '
                              '${(c['numero_tarjeta'] as String? ?? '').length > 6 ? (c['numero_tarjeta'] as String).substring((c['numero_tarjeta']).length - 4) : c['numero_tarjeta']}'),
                          selected: _cuentaSel == c,
                          onSelected: (_) =>
                              setState(() => _cuentaSel = c),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // ---------- QR (si la cuenta lo tiene) ----------
                if (_cuentaSel?['qr_url'] != null &&
                    (_cuentaSel!['qr_url'] as String).isNotEmpty) ...[
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorBorde),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withOpacity(esOscuro ? 0.35 : 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _cuentaSel!['qr_url'] as String,
                          width: 156,
                          height: 156,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ---------- Datos de pago ----------
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorSuperficie,
                    borderRadius: BorderRadius.circular(kCardRadius),
                    border: Border.all(color: colorBorde),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_cuentaSel != null) ...[
                        FilaDatoCopiable(
                          etiqueta: 'Tarjeta ${_cuentaSel!['tipo']}',
                          valor: _cuentaSel!['numero_tarjeta'] ??
                              'No configurada',
                        ),
                        const SizedBox(height: 8),
                        FilaDatoCopiable(
                          etiqueta: 'Teléfono',
                          valor: _telefonoPago?.trim().isNotEmpty == true
                              ? _telefonoPago!
                              : 'No configurado',
                        ),
                      ] else
                        FilaDatoCopiable(
                          etiqueta: 'Cuentas de pago',
                          valor: 'Sin cuentas configuradas -- coordina con el admin',
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---------- Pasos ----------
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(esOscuro ? 0.10 : 0.06),
                    borderRadius: BorderRadius.circular(kCardRadius),
                    border: Border.all(
                        color:
                            AppColors.primary.withOpacity(esOscuro ? 0.3 : 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cómo verificar tu pago',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold, fontSize: 13.5)),
                      const SizedBox(height: 8),
                      _pasoNumerado(1,
                          'Transfiere ${CurrencyService.instance.formatear((p['precio_usd'] as num).toDouble())} a la tarjeta mostrada arriba.'),
                      _pasoNumerado(2,
                          'Toma una captura de la confirmación de la transferencia.'),
                      _pasoNumerado(3,
                          'Presiona "Verificar Pago" -- se abrirá WhatsApp con el mensaje listo.'),
                      _pasoNumerado(4,
                          'Adjunta la captura en ese chat y envíala.'),
                      _pasoNumerado(5,
                          'El admin verificará tu pago y tu paquete se activa solo.',
                          ultimo: true),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _procesando ? null : _verificarPago,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF25D366),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _procesando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Verificar Pago'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _pasoNumerado(int numero, String texto, {bool ultimo = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: ultimo ? 0 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: AppColors.primary,
            child: Text('$numero',
                style: const TextStyle(fontSize: 11, color: Colors.white)),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(texto, style: GoogleFonts.inter(fontSize: 12))),
        ],
      ),
    );
  }
}