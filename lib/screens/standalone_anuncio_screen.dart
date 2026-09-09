// standalone_anuncio_screen.dart
//
// REDISEÑO (2026-09): antes cualquier usuario podía elegir un paquete
// standalone y publicar directo, sin ninguna verificación de pago real
// (el propio código lo admitía en un comentario). Ahora el flujo es:
//
//   1. Se consultan las ranuras REALES del usuario (tabla
//      permisos_usuario_anuncios, alimentada por compras aprobadas por
//      el admin -- ver anuncios_service.dart).
//   2. Si tiene ranuras libres -> se muestra el formulario para crear
//      el anuncio directo (sin volver a elegir paquete: el cupo es un
//      pool compartido entre todos sus permisos vigentes).
//   3. Si NO tiene ninguna ranura -> se oculta el formulario y se
//      muestra un CTA "Ver planes disponibles", que abre
//      mostrarPlanesStandaloneSheet() (función pública de este archivo,
//      reutilizada también desde Mi Perfil) con el flujo de compra por
//      WhatsApp, igual que ya existe para negocio/tienda.
//   4. Siempre hay un botón "Comprar más ranuras" visible arriba, para
//      que alguien con ranuras pueda sumar más sin tener que vaciar su
//      cupo primero.
//
// El trigger anuncios_before_insert (Supabase) es la fuente de verdad
// final del cupo -- esta pantalla solo refleja ese estado para no
// dejar publicar en vano, pero aunque algo se desincronice, el server
// sigue rechazando con 'CUPO_ANUNCIOS' si no corresponde.

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/anuncios_service.dart';
import '../services/storage_service.dart';
import '../services/currency_service.dart';

/// Punto de entrada reutilizable: lista los paquetes standalone
/// disponibles y, al elegir uno, abre el modal de pago por WhatsApp.
/// Se usa tanto desde esta pantalla como desde Mi Perfil.
Future<void> mostrarPlanesStandaloneSheet(
  BuildContext context, {
  VoidCallback? onCompraRegistrada,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _PlanesStandaloneSheet(onCompraRegistrada: onCompraRegistrada),
  );
}

class StandaloneAnuncioScreen extends StatefulWidget {
  const StandaloneAnuncioScreen({super.key});

  @override
  State<StandaloneAnuncioScreen> createState() =>
      _StandaloneAnuncioScreenState();
}

class _StandaloneAnuncioScreenState extends State<StandaloneAnuncioScreen> {
  final _anunciosService = AnunciosService();
  final _storageService = StorageService();
  final _formKey = GlobalKey<FormState>();

  final _tituloCtrl = TextEditingController();
  final _textoCtrl = TextEditingController();

  late Future<({int usados, int max, DateTime? vigenteHasta})> _ranurasFuture;
  late Future<List<Map<String, dynamic>>> _permisosFuture;
  late Future<List<Map<String, dynamic>>> _pendientesFuture;

  File? _imagenFile;
  bool _publicando = false;
  bool _subiendoImagen = false;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  void _cargarTodo() {
    _ranurasFuture = _anunciosService.ranurasStandalone();
    _permisosFuture = _anunciosService.misPermisosStandalone();
    _pendientesFuture = _anunciosService.comprasPendientesStandalone();
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _textoCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirImagen() async {
    final foto = await _storageService.elegirFoto();
    if (foto != null) setState(() => _imagenFile = foto);
  }

  String _mensajeError(Object e) {
    final s = e.toString();
    if (s.contains('CUPO_ANUNCIOS')) {
      return 'No tienes ranuras libres en este momento. Compra un paquete '
          'o espera a que termine uno de tus anuncios activos.';
    }
    if (s.contains('SESION_REQUERIDA')) {
      return 'Inicia sesión de nuevo e inténtalo otra vez.';
    }
    return 'No se pudo publicar el anuncio. Intenta de nuevo.';
  }

  Future<void> _abrirPlanes() async {
    await mostrarPlanesStandaloneSheet(
      context,
      onCompraRegistrada: () => setState(_cargarTodo),
    );
  }

  Future<void> _publicar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _publicando = true);
    try {
      String? imagenUrl;
      if (_imagenFile != null) {
        final uid = supabase.auth.currentUser?.id;
        if (uid == null) throw Exception('SESION_REQUERIDA');
        setState(() => _subiendoImagen = true);
        imagenUrl = await _storageService.subirImagenAnuncio(
          archivo: _imagenFile!,
          uid: uid,
        );
        setState(() => _subiendoImagen = false);
      }

      await _anunciosService.crearAnuncioStandalone(
        titulo: _tituloCtrl.text.trim(),
        texto: _textoCtrl.text.trim(),
        imagenUrl: imagenUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('¡Anuncio publicado! Ya está corriendo en el feed.')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensajeError(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _publicando = false;
          _subiendoImagen = false;
        });
      }
    }
  }

  bool get _esOscuro => Theme.of(context).brightness == Brightness.dark;
  Color get _colorTexto => _esOscuro ? const Color(0xFFF5F5F4) : AppColors.ink;
  Color get _colorTextoSecundario =>
      _esOscuro ? AppColors.inkSecundarioDark : AppColors.inkSecundarioLight;
  Color get _colorSuperficie => _esOscuro
      ? AppColors.cardTransparentDark
      : AppColors.cardTransparentLight;
  Color get _colorBorde =>
      (_esOscuro ? AppColors.borderDark : AppColors.borderLight)
          .withOpacity(0.6);

  InputDecoration _decoracion(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 19),
      filled: true,
      fillColor:
          _esOscuro ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
    );
  }

  Color _colorFraccion(double fracLibre) {
    const verde = Color(0xFF2ECC71);
    const amarillo = Color(0xFFFFC107);
    const rojo = Color(0xFFE53935);
    if (fracLibre <= 0) return rojo;
    if (fracLibre >= 0.5) {
      final t = ((fracLibre - 0.5) / 0.5).clamp(0.0, 1.0);
      return Color.lerp(amarillo, verde, t)!;
    }
    final t = (fracLibre / 0.5).clamp(0.0, 1.0);
    return Color.lerp(rojo, amarillo, t)!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Anuncio independiente'),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _abrirPlanes,
            icon: const Icon(Icons.add_shopping_cart_rounded, size: 17),
            label: const Text('Ranuras'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_cargarTodo),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(kCardRadius),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ideal para vender algo puntual (una moto, un mueble...) '
                      'sin necesidad de tener tienda ni negocio registrado. '
                      'Se publica directo, sin moderación, mientras tengas '
                      'ranuras disponibles.',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          color: _colorTextoSecundario,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ---------- Compras pendientes de verificación ----------
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _pendientesFuture,
              builder: (context, snap) {
                final pends = snap.data ?? const [];
                if (pends.isEmpty) return const SizedBox.shrink();
                final codigo = (pends.first['codigo_ref'] as String?) ?? '';
                final extra =
                    pends.length > 1 ? ' (y ${pends.length - 1} más)' : '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warm.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.warm.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.hourglass_top_rounded,
                          size: 20, color: AppColors.warm),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Compra ${codigo.trim().isEmpty ? 'registrada' : codigo}'
                          '$extra en revisión: el admin va a verificar tu '
                          'pago por WhatsApp y tus ranuras se activan solas.',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                              color: _colorTexto),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // ---------- Ranuras + permisos activos ----------
            Text('Tus ranuras de anuncio',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: _colorTexto)),
            const SizedBox(height: 10),
            FutureBuilder<({int usados, int max, DateTime? vigenteHasta})>(
              future: _ranurasFuture,
              builder: (context, snap) {
                final r = snap.data;
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final max = r?.max ?? 0;
                final usados = r?.usados ?? 0;
                if (max <= 0) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _colorSuperficie,
                      borderRadius: BorderRadius.circular(kCardRadius),
                      border: Border.all(color: _colorBorde),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.workspace_premium_rounded,
                                size: 18, color: AppColors.warm),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('No tienes ranuras activas',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: _colorTexto)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Compra un paquete para poder publicar tu anuncio '
                          'independiente.',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              color: _colorTextoSecundario,
                              height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _abrirPlanes,
                            icon: const Icon(Icons.local_offer_rounded,
                                size: 18),
                            label: const Text('Ver planes disponibles'),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final pct = (usados / max).clamp(0.0, 1.0);
                final restantes = (max - usados).clamp(0, max);
                final color = _colorFraccion(1 - pct);
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _colorSuperficie,
                    borderRadius: BorderRadius.circular(kCardRadius),
                    border: Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.campaign_rounded,
                                  size: 16, color: color),
                              const SizedBox(width: 6),
                              Text('$usados de $max en uso',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _colorTexto)),
                            ],
                          ),
                          Text(
                            restantes <= 0
                                ? 'Sin libres'
                                : '$restantes libre${restantes == 1 ? '' : 's'}',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: color),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          height: 9,
                          color: color.withOpacity(0.15),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: pct.clamp(0.03, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: LinearGradient(
                                      colors: [color.withOpacity(0.65), color]),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: _permisosFuture,
                        builder: (context, psnap) {
                          final permisos = psnap.data ?? const [];
                          if (permisos.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: permisos.map((p) {
                              final paquete = p['paquetes_anuncio']
                                  as Map<String, dynamic>?;
                              final nombre =
                                  paquete?['nombre'] as String? ?? 'Paquete';
                              final hasta =
                                  DateTime.tryParse(p['hasta'] as String? ?? '');
                              final txt = hasta != null
                                  ? '$nombre · vence ${hasta.day}/${hasta.month}'
                                  : nombre;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(txt,
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: color)),
                              );
                            }).toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _abrirPlanes,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Comprar más ranuras'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // ---------- Formulario -- solo tiene sentido mostrarlo
            // pintado en detalle si hay (o puede haber) cupo; si no,
            // igual se deja visible pero el botón queda deshabilitado
            // y el propio insert es la garantía final. ----------
            Text('Tu anuncio',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: _colorTexto)),
            const SizedBox(height: 10),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _tituloCtrl,
                    maxLength: 60,
                    style: GoogleFonts.plusJakartaSans(color: _colorTexto),
                    decoration:
                        _decoracion('Título del anuncio', Icons.title_rounded),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _textoCtrl,
                    maxLines: 4,
                    maxLength: 220,
                    style: GoogleFonts.plusJakartaSans(color: _colorTexto),
                    decoration: _decoracion(
                        '¿Qué estás anunciando?', Icons.notes_rounded),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _elegirImagen,
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: Text(_imagenFile == null
                            ? 'Añadir imagen'
                            : 'Cambiar imagen'),
                      ),
                      if (_imagenFile != null) ...[
                        const SizedBox(width: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_imagenFile!,
                              width: 46, height: 46, fit: BoxFit.cover),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _publicando ? null : _publicar,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _publicando
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.rocket_launch_rounded, size: 19),
                    label: Text(
                      _publicando
                          ? (_subiendoImagen
                              ? 'Subiendo imagen...'
                              : 'Publicando...')
                          : 'Publicar anuncio',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// SHEET: lista de planes standalone + flujo de pago por WhatsApp
// ---------------------------------------------------------------------

class _PlanesStandaloneSheet extends StatefulWidget {
  final VoidCallback? onCompraRegistrada;
  const _PlanesStandaloneSheet({this.onCompraRegistrada});

  @override
  State<_PlanesStandaloneSheet> createState() =>
      _PlanesStandaloneSheetState();
}

class _PlanesStandaloneSheetState extends State<_PlanesStandaloneSheet> {
  final _anunciosService = AnunciosService();
  late Future<List<Map<String, dynamic>>> _paquetes;

  @override
  void initState() {
    super.initState();
    _paquetes = _anunciosService
        .obtenerPaquetesActivos()
        .then((l) => l.where((p) => p['standalone'] == true).toList());
  }

  Future<void> _abrirModalPago(Map<String, dynamic> paquete) async {
    final cuentas =
        await _anunciosService.obtenerCuentasDePaquete(paquete['id_paquete']);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ModalPagoStandalone(
        paquete: paquete,
        cuentas: cuentas,
      ),
    );
    widget.onCompraRegistrada?.call();
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
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: esOscuro ? theme.colorScheme.surface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                    child: Text('Planes de anuncio',
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
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _paquetes,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final paquetes = snap.data ?? [];
                  if (paquetes.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Todavía no hay paquetes de anuncio independiente '
                        'disponibles. Vuelve a intentarlo más tarde.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                            color: theme.textTheme.bodySmall?.color,
                            height: 1.45),
                      ),
                    );
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Column(
                      children:
                          paquetes.map((p) => _tarjeta(p, theme)).toList(),
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

  Widget _tarjeta(Map<String, dynamic> p, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        color: AppColors.primary.withOpacity(0.05),
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
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${p['duracion_dias']} días · ${p['max_anuncios']} anuncio'
            '${(p['max_anuncios'] as num? ?? 1) > 1 ? 's' : ''} a la vez',
            style: GoogleFonts.inter(
                fontSize: 12, color: theme.textTheme.bodySmall?.color),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _abrirModalPago(p),
              icon: const Icon(Icons.chat_rounded, size: 16),
              label: Text('Adquirir por WhatsApp',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal de pago de un paquete standalone -- mismo patrón visual que
/// los de negocio/tienda: datos de cuenta, QR si existe, y botón verde
/// que registra la compra pendiente y abre WhatsApp con el mensaje
/// armado para que el admin verifique el comprobante.
class _ModalPagoStandalone extends StatefulWidget {
  final Map<String, dynamic> paquete;
  final List<Map<String, dynamic>> cuentas;

  const _ModalPagoStandalone({required this.paquete, required this.cuentas});

  @override
  State<_ModalPagoStandalone> createState() => _ModalPagoStandaloneState();
}

class _ModalPagoStandaloneState extends State<_ModalPagoStandalone> {
  final _anunciosService = AnunciosService();
  bool _procesando = false;

  late Map<String, dynamic>? _cuentaSel =
      widget.cuentas.isEmpty ? null : widget.cuentas.first;

  String _generarCodigoCompra() {
    const alfabeto = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    return 'AI-' +
        List.generate(4, (_) => alfabeto[rnd.nextInt(alfabeto.length)]).join();
  }

  Future<void> _verificarPago() async {
    if (widget.cuentas.isNotEmpty && _cuentaSel == null) return;
    setState(() => _procesando = true);
    try {
      final codigoRef = _generarCodigoCompra();
      await _anunciosService.crearCompraPendienteStandalone(
        idPaquete: widget.paquete['id_paquete'] as String,
        codigoRef: codigoRef,
      );

      var telefono = await _anunciosService.obtenerWhatsappPagos();
      if (!mounted) return;
      Navigator.of(context).pop();

      final buf = StringBuffer();
      buf.writeln('Compra de RANURAS DE ANUNCIO INDEPENDIENTE en Al Lado:');
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
    final colorSuperficie = esOscuro
        ? AppColors.cardTransparentDark
        : AppColors.cardTransparentLight;
    final colorBorde =
        (esOscuro ? AppColors.borderDark : AppColors.borderLight)
            .withOpacity(0.6);
    final p = widget.paquete;

    return Container(
      decoration: BoxDecoration(
        color: esOscuro ? Theme.of(context).colorScheme.surface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                  const SizedBox(height: 6),
                  AnimatedBuilder(
                    animation: CurrencyService.instance,
                    builder: (context, _) => Text(
                        '${CurrencyService.instance.formatear((p['precio_usd'] as num).toDouble())} '
                        '· ${p['duracion_dias']} días',
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
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
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
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5)),
                              Expanded(
                                child: SelectableText(
                                    _cuentaSel!['numero_tarjeta'] ??
                                        'No configurada',
                                    style: GoogleFonts.inter(fontSize: 13.5)),
                              ),
                            ],
                          )
                        : Text(
                            'Sin cuentas configuradas -- coordina con el admin',
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