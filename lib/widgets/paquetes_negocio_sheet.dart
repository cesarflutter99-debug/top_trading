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

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/anuncios_service.dart';
import '../services/tiendas_service.dart';
import '../services/currency_service.dart';
import 'anuncios_negocio_sheet.dart';

const Color _kVerde = Color(0xFF0D9488);

Future<void> mostrarPaquetesNegocioSheet(
  BuildContext context,
  Map<String, dynamic> negocio,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (_) => _PaquetesNegocioSheet(negocio: negocio),
  );
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

class _PaquetesNegocioSheet extends StatefulWidget {
  final Map<String, dynamic> negocio;
  const _PaquetesNegocioSheet({required this.negocio});

  @override
  State<_PaquetesNegocioSheet> createState() => _PaquetesNegocioSheetState();
}

class _PaquetesNegocioSheetState extends State<_PaquetesNegocioSheet> {
  final _anunciosService = AnunciosService();
  final _tiendasService = TiendasService();

  late Future<List<Map<String, dynamic>>> _paquetes;
  // Compras aún sin verificar por el admin -- alimentan el banner
  // "en revisión" para que el usuario sepa que su solicitud quedó
  // registrada incluso antes de que el admin la apruebe.
  late Future<List<Map<String, dynamic>>> _pendientes;
  bool _procesando = false;
  String? _aviso;

  String get _idNegocio => widget.negocio['id_negocio'] as String;
  String get _nombreNegocio =>
      (widget.negocio['nombre'] as String?) ?? 'nuestro negocio';

  @override
  void initState() {
    super.initState();
    _paquetes = _anunciosService.obtenerPaquetesActivos();
    _pendientes = _anunciosService.comprasPendientesDeNegocio(_idNegocio);
    _anunciosService.ranurasDeNegocio(_idNegocio).then((r) {
      // Solo para refrescar el banner si cambió mientras tanto
      if (mounted) setState(() {});
    });
  }

  void _avisoMsg(String msg) {
    if (!mounted) return;
    setState(() => _aviso = msg);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _aviso == msg) setState(() => _aviso = null);
    });
  }

  String _generarCodigoCompra() {
    const alfabeto = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    return 'AN-' +
        List.generate(4, (_) => alfabeto[rnd.nextInt(alfabeto.length)]).join();
  }

  /// Flujo de compra estilo "modal pago plan": tarjeta de datos de la
  /// cuenta, pasos numerados y botón verde de WhatsApp. La compra queda
  /// 'pendiente' AL PRESIONAR "Verificar Pago" (con código AN-XXXX).
  Future<void> _abrirModalPago(Map<String, dynamic> paquete) async {
    final cuentas = await _anunciosService
        .obtenerCuentasDePaquete(paquete['id_paquete'] as String);
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => _ModalPagoPaquete(
        paquete: paquete,
        cuentas: cuentas,
        negocio: widget.negocio,
        onVerificar: () async {
          // 1) registrar compra pendiente con código legible
          final codigoRef = _generarCodigoCompra();
          await _anunciosService.crearCompraPendiente(
            idNegocio: _idNegocio,
            idPaquete: paquete['id_paquete'] as String,
            codigoRef: codigoRef,
          );
          return codigoRef;
        },
      ),
    );
    // Al volver del modal (pagó o canceló), resincroniza el banner de
    // pendientes -- si acaba de verificar, acá aparece su AN-XXXX.
    if (mounted) {
      setState(() {
        _pendientes = _anunciosService.comprasPendientesDeNegocio(_idNegocio);
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
                    child: Text('Anuncios y promociones',
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
              child: FutureBuilder<
                  ({List<Map<String, dynamic>> paquetes})>(
                future: _paquetes.then((p) => (paquetes: p)),
                builder: (context, snap) {
                  final paquetes = snap.data?.paquetes ?? [];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_aviso != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.warm
                                  .withOpacity(esOscuro ? 0.2 : 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: AppColors.warm.withOpacity(0.45)),
                            ),
                            child: Text(_aviso!,
                                style: GoogleFonts.inter(fontSize: 12.5)),
                          ),

                        // ---------- Compras en revisión ----------
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
                                      'verificar tu pago por WhatsApp y tu '
                                      'paquete se activa solo.',
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

                        // ---------- Estado del paquete actual ----------
                        FutureBuilder<({int usados, int max, DateTime? vigenteHasta})>(
                          future: _anunciosService
                              .ranurasDeNegocio(_idNegocio),
                          builder: (context, rsnap) {
                            final r = rsnap.data;
                            if (r == null || r.max <= 0) {
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.warm.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: AppColors.warm.withOpacity(0.4)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.workspace_premium_rounded,
                                        size: 20, color: AppColors.warm),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'No tienes paquete activo. Elige una '
                                        'oferta abajo para empezar.',
                                        style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            height: 1.4),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            final h = r.vigenteHasta;
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _kVerde.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: _kVerde.withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.check_circle_rounded,
                                          size: 20, color: _kVerde),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '${r.usados} de ${r.max} anuncios en uso'
                                          '${h != null ? ' · paquete válido hasta ${h.day}/${h.month}/${h.year}' : ''}',
                                          style: GoogleFonts.inter(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: _kVerde,
                                              height: 1.4),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 40,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _kVerde,
                                        side: BorderSide(
                                            color:
                                                _kVerde.withOpacity(0.5)),
                                      ),
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        mostrarAnunciosNegocioSheet(
                                            context, widget.negocio);
                                      },
                                      icon: const Icon(
                                          Icons.campaign_rounded,
                                          size: 17),
                                      label: Text('Gestionar mis anuncios',
                                          style: GoogleFonts.inter(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 18),

                        // ---------- Ofertas ----------
                        Text('Ofertas',
                            style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: theme.textTheme.bodyLarge?.color)),
                        const SizedBox(height: 4),
                        Text('Pago verificado por WhatsApp.',
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                color: theme.textTheme.bodySmall?.color)),
                        const SizedBox(height: 10),

                        // NUEVO (2026-08): explica para qué sirve el
                        // paquete más corto -- no solo negocios fijos
                        // (barberías, talleres) pueden anunciarse acá.
                        // Un evento puntual (fiesta, venta de garaje,
                        // rifa, bazar de un fin de semana) también
                        // puede registrarse como "negocio" y usar el
                        // paquete semanal para promocionarse sin pagar
                        // por más tiempo del que necesita.
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.warm
                                .withOpacity(esOscuro ? 0.14 : 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.warm.withOpacity(0.35)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.celebration_rounded,
                                  size: 18, color: AppColors.warm),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '¿Vas a organizar una fiesta, venta de '
                                  'garaje, rifa o evento de un fin de '
                                  'semana? El paquete de 1 semana es '
                                  'ideal: promociónalo sin comprometerte '
                                  'a más tiempo del que necesitas.',
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: theme.textTheme.bodySmall?.color),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (snap.connectionState == ConnectionState.waiting)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 30),
                            child:
                                Center(child: CircularProgressIndicator()),
                          )
                        else if (paquetes.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'No hay paquetes publicados todavía. '
                              'Escríbenos por WhatsApp y coordinamos.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                  color: theme.textTheme.bodySmall?.color,
                                  height: 1.45),
                            ),
                          )
                        else
                          ...paquetes.map((p) => _tarjetaPaquete(p, theme)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaPaquete(Map<String, dynamic> p, ThemeData theme) {
    // NUEVO (2026-08): paquetes de 7 días o menos se marcan como
    // "ideal para eventos" -- fiestas, ventas de garaje, rifas, etc.
    // que solo necesitan promoción por un fin de semana o una semana,
    // no todo un mes.
    final duracion = (p['duracion_dias'] as num?)?.toInt() ?? 0;
    final esParaEventos = duracion > 0 && duracion <= 7;

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
              AnimatedBuilder(
                animation: CurrencyService.instance,
                builder: (context, _) => Text(
                  CurrencyService.instance
                      .formatear((p['precio_usd'] as num).toDouble()),
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: _kVerde),
                ),
              ),
            ],
          ),
          if (esParaEventos) ...[
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warm.withOpacity(0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.celebration_rounded,
                      size: 12, color: AppColors.warm),
                  const SizedBox(width: 4),
                  Text('IDEAL PARA EVENTOS',
                      style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: AppColors.warm)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 2),
          Text(
            '${p['duracion_dias']} días · hasta ${p['max_anuncios']} anuncio(s) simultáneo(s)',
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
              onPressed: _procesando ? null : () => _abrirModalPago(p),
              icon: _procesando
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.chat_rounded, size: 16),
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
      buf.writeln('Compra de PAQUETE DE ANUNCIO en Al Lado:');
      buf.writeln('- Negocio: ${widget.negocio['nombre'] ?? 'nuestro negocio'}');
      final email = supabase.auth.currentUser?.email;
      if (email != null && email.isNotEmpty) buf.writeln('- Cuenta: $email');
      buf.writeln('- Paquete: ${widget.paquete['nombre']} '
          '(${CurrencyService.instance.formatear((widget.paquete['precio_usd'] as num).toDouble())} / '
          '${widget.paquete['duracion_dias']} días)');
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
                Text('Pagar paquete ${p['nombre']}',
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
                    '· ${p['duracion_dias']} días',
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
                      if (_cuentaSel != null)
                        _filaDato('Tarjeta ${_cuentaSel!['tipo']}',
                            _cuentaSel!['numero_tarjeta'] ?? 'No configurada')
                      else
                        _filaDato('Cuentas de pago',
                            'Sin cuentas configuradas -- coordina con el admin'),
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

  Widget _filaDato(String etiqueta, String valor) {
    return Row(
      children: [
        Text('$etiqueta: ',
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w600, fontSize: 13.5)),
        Expanded(
            child: SelectableText(valor,
                style: GoogleFonts.inter(fontSize: 13.5))),
      ],
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