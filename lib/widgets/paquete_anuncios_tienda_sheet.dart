// paquete_anuncios_tienda_sheet.dart
//
// Sheet para comprar RANURAS EXTRA de anuncio para una TIENDA
// (independiente del plan contratado). Espejo de
// paquetes_negocio_sheet.dart, pero:
//   - el permiso resultante va a permisos_tienda_anuncios (no
//     permisos_negocio) -- ver crearCompraPendienteTienda().
//   - las ranuras compradas se SUMAN a las del plan, nunca las
//     reemplazan (ver ranurasDeTienda() en anuncios_service.dart).
//
// Mismo flujo de pago manual por WhatsApp: se registra la compra
// 'pendiente' con un código de referencia; el admin la aprueba y un
// trigger en Supabase crea el permiso con su vigencia.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/anuncios_service.dart';
import '../services/tiendas_service.dart';
import '../services/currency_service.dart';

const Color _kVerde = Color(0xFF0D9488);

Future<void> mostrarPaqueteAnunciosTiendaSheet(
  BuildContext context,
  Map<String, dynamic> tienda,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (_) => _PaqueteAnunciosTiendaSheet(tienda: tienda),
  );
}

class _PaqueteAnunciosTiendaSheet extends StatefulWidget {
  final Map<String, dynamic> tienda;
  const _PaqueteAnunciosTiendaSheet({required this.tienda});

  @override
  State<_PaqueteAnunciosTiendaSheet> createState() =>
      _PaqueteAnunciosTiendaSheetState();
}

class _PaqueteAnunciosTiendaSheetState
    extends State<_PaqueteAnunciosTiendaSheet> {
  final _anunciosService = AnunciosService();
  final _tiendasService = TiendasService();

  late Future<List<Map<String, dynamic>>> _paquetes;
  late Future<List<Map<String, dynamic>>> _pendientes;

  String get _idTienda => widget.tienda['id_tienda'] as String;

  @override
  void initState() {
    super.initState();
    // NOTA: por ahora se listan TODOS los paquetes activos no
    // standalone. Si el admin necesita distinguir paquetes "para
    // negocio" de "para tienda", hace falta una columna nueva en
    // paquetes_anuncio (ver nota SQL al pie).
    _paquetes = _anunciosService
        .obtenerPaquetesActivos()
        .then((lista) => lista.where((p) => p['standalone'] != true).toList());
    _pendientes = _anunciosService.comprasPendientesDeTienda(_idTienda);
  }

  String _generarCodigoCompra() {
    const alfabeto = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    return 'AT-' +
        List.generate(4, (_) => alfabeto[rnd.nextInt(alfabeto.length)]).join();
  }

  Future<void> _abrirModalPago(Map<String, dynamic> paquete) async {
    final cuentas = await _anunciosService
        .obtenerCuentasDePaquete(paquete['id_paquete'] as String);
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => _ModalPagoRanurasExtra(
        paquete: paquete,
        cuentas: cuentas,
        tienda: widget.tienda,
        onVerificar: () async {
          final codigoRef = _generarCodigoCompra();
          await _anunciosService.crearCompraPendienteTienda(
            idTienda: _idTienda,
            idPaquete: paquete['id_paquete'] as String,
            codigoRef: codigoRef,
          );
          return codigoRef;
        },
      ),
    );
    if (mounted) {
      setState(() {
        _pendientes = _anunciosService.comprasPendientesDeTienda(_idTienda);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esOscuro = theme.brightness == Brightness.dark;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: esOscuro ? theme.colorScheme.surface : Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Comprar ranuras extra',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: theme.textTheme.bodyLarge?.color)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _kVerde.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kVerde.withOpacity(0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 18, color: _kVerde),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Estas ranuras se SUMAN a las que ya trae tu '
                              'plan -- no lo reemplazan. Ej: si tu plan trae '
                              '3 y compras un paquete de 2, tendrás 5 en '
                              'total mientras el paquete esté vigente.',
                              style: GoogleFonts.inter(
                                  fontSize: 12, height: 1.4, color: _kVerde),
                            ),
                          ),
                        ],
                      ),
                    ),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _pendientes,
                      builder: (context, psnap) {
                        final pends = psnap.data ?? const [];
                        if (pends.isEmpty) return const SizedBox.shrink();
                        final primera = pends.first;
                        final codigo =
                            (primera['codigo_ref'] as String?) ?? '';
                        final extra = pends.length > 1
                            ? ' (y ${pends.length - 1} más)'
                            : '';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.warm.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: AppColors.warm.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.hourglass_top_rounded,
                                  size: 20, color: AppColors.warm),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Compra ${codigo.trim().isEmpty ? 'registrada' : codigo}'
                                  '$extra en revisión: el admin va a '
                                  'verificar tu pago por WhatsApp y las '
                                  'ranuras se activan solas.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                    color: theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _paquetes,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 30),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final paquetes = snap.data ?? [];
                        if (paquetes.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'No hay paquetes publicados todavía. '
                              'Escríbenos por WhatsApp y coordinamos.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                  color: theme.textTheme.bodySmall?.color,
                                  height: 1.45),
                            ),
                          );
                        }
                        return Column(
                          children:
                              paquetes.map((p) => _tarjetaPaquete(p, theme)).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaPaquete(Map<String, dynamic> p, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kVerde.withOpacity(0.35)),
        color: _kVerde.withOpacity(0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(p['nombre'] ?? 'Paquete',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              Text(
                  CurrencyService.instance
                      .formatear((p['precio_usd'] as num).toDouble()),
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: _kVerde)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${p['duracion_dias']} días · +${p['max_anuncios']} ranura(s) extra',
            style: GoogleFonts.inter(
                fontSize: 12, color: theme.textTheme.bodySmall?.color),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _kVerde,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _abrirModalPago(p),
              icon: const Icon(Icons.chat_rounded, size: 16),
              label: Text('Adquirir por WhatsApp',
                  style:
                      GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal de pago -- mismo estilo que _ModalPagoPaquete de
/// paquetes_negocio_sheet.dart, pero el mensaje de WhatsApp habla de
/// "ranuras extra de tienda" en vez de paquete de negocio.
class _ModalPagoRanurasExtra extends StatefulWidget {
  final Map<String, dynamic> paquete;
  final List<Map<String, dynamic>> cuentas;
  final Map<String, dynamic> tienda;
  final Future<String> Function() onVerificar;

  const _ModalPagoRanurasExtra({
    required this.paquete,
    required this.cuentas,
    required this.tienda,
    required this.onVerificar,
  });

  @override
  State<_ModalPagoRanurasExtra> createState() =>
      _ModalPagoRanurasExtraState();
}

class _ModalPagoRanurasExtraState extends State<_ModalPagoRanurasExtra> {
  final _anunciosService = AnunciosService();
  final _tiendasService = TiendasService();
  bool _procesando = false;

  late Map<String, dynamic>? _cuentaSel =
      widget.cuentas.isEmpty ? null : widget.cuentas.first;

  Future<void> _verificarPago() async {
    if (widget.cuentas.isNotEmpty && _cuentaSel == null) return;
    setState(() => _procesando = true);
    try {
      final codigoRef = await widget.onVerificar();

      var telefono = await _anunciosService.obtenerWhatsappPagos();
      telefono ??= await _tiendasService.obtenerContactoWhatsappActivo();
      if (!mounted) return;
      Navigator.of(context).pop();

      final buf = StringBuffer();
      buf.writeln('Compra de RANURAS EXTRA DE ANUNCIO (tienda) en Al Lado:');
      buf.writeln('- Tienda: ${widget.tienda['nombre'] ?? 'mi tienda'}');
      final email = supabase.auth.currentUser?.email;
      if (email != null && email.isNotEmpty) buf.writeln('- Cuenta: $email');
      buf.writeln('- Paquete: ${widget.paquete['nombre']} '
          '(${CurrencyService.instance.formatear((widget.paquete['precio_usd'] as num).toDouble())} / '
          '${widget.paquete['duracion_dias']} días '
          '/ +${widget.paquete['max_anuncios']} ranuras)');
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
    final colorSuperficie = esOscuro
        ? AppColors.cardTransparentDark
        : AppColors.cardTransparentLight;
    final colorBorde =
        (esOscuro ? AppColors.borderDark : AppColors.borderLight).withOpacity(0.6);
    final p = widget.paquete;

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
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 16),
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
                  Text('Pagar ${p['nombre']}',
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
                        '· +${p['max_anuncios']} ranuras · ${p['duracion_dias']} días',
                        style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color:
                                esOscuro ? Colors.green.shade300 : Colors.green)),
                  ),
                  const SizedBox(height: 16),
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
                            onSelected: (_) => setState(() => _cuentaSel = c),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_cuentaSel?['qr_url'] != null &&
                      (_cuentaSel!['qr_url'] as String).isNotEmpty) ...[
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colorBorde),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _cuentaSel!['qr_url'] as String,
                            width: 156,
                            height: 156,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorSuperficie,
                      borderRadius: BorderRadius.circular(kCardRadius),
                      border: Border.all(color: colorBorde),
                    ),
                    child: _cuentaSel != null
                        ? Row(
                            children: [
                              Text('Tarjeta ${_cuentaSel!['tipo']}: ',
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600, fontSize: 13.5)),
                              Expanded(
                                child: SelectableText(
                                    _cuentaSel!['numero_tarjeta'] ?? 'No configurada',
                                    style: GoogleFonts.inter(fontSize: 13.5)),
                              ),
                            ],
                          )
                        : Text('Sin cuentas configuradas -- coordina con el admin',
                            style: GoogleFonts.inter(fontSize: 13.5)),
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
}