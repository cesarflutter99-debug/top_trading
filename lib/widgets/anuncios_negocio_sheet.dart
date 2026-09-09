// anuncios_negocio_sheet.dart
//
// Bottom sheet "Anuncios y Promociones" del NEGOCIO (barbería, taller...),
// abierto desde la sección "Promociona tu negocio" del perfil cuando el
// negocio está aprobado. Diferencias clave con anuncios_tienda_sheet:
//
//   - NO hay "potenciar producto": el negocio no vende en la app.
//   - Los anuncios nacen 'pendiente': pasan por moderación del admin
//     (el trigger anuncios_before_insert los crea así).
//   - El cupo viene de permisos_negocio (paquete comprado), no del plan
//     de tienda. Sin permiso vigente -> CTA de WhatsApp para comprarlo.
//   - El dueño puede pausar/reactivar (requiere parche_negocio_pausar.sql)
//     y editar contenido; al editar un aprobado/rechazado vuelve a
//     'pendiente' (re-moderación automática del trigger).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/anuncios_service.dart';
import '../services/anuncios_state_service.dart';
import '../services/storage_service.dart';
import '../services/tiendas_service.dart';
import 'paquetes_negocio_sheet.dart';
import 'tarjeta_anuncio.dart';

const Color _kVerde = Color(0xFF0D9488);

/// Punto de entrada desde el perfil (negocio activo).
Future<void> mostrarAnunciosNegocioSheet(
  BuildContext context,
  Map<String, dynamic> negocio,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AnunciosNegocioSheet(negocio: negocio),
  );
}

enum _Vista { menu, crear, misAnuncios }

class _AnunciosNegocioSheet extends StatefulWidget {
  final Map<String, dynamic> negocio;
  const _AnunciosNegocioSheet({required this.negocio});

  @override
  State<_AnunciosNegocioSheet> createState() => _AnunciosNegocioSheetState();
}

class _AnunciosNegocioSheetState extends State<_AnunciosNegocioSheet> {
  final _anunciosService = AnunciosService();
  final _tiendasService = TiendasService();
  final _storageService = StorageService();

  _Vista _vista = _Vista.menu;
  bool _publicando = false;

  // Aviso temporal pintado DENTRO del sheet (los SnackBar quedaban
  // tapados por la propia hoja al salir del Scaffold de fondo).
  String? _aviso;

  // Vista "mis anuncios": futuro refrescable tras cada acción.
  Future<List<Map<String, dynamic>>>? _misAnunciosFuture;
  _OrdenMis _orden = _OrdenMis.recientes;

  // Vista crear anuncio
  final _formKeyCrear = GlobalKey<FormState>();
  final _tituloCtrl = TextEditingController();
  final _textoCtrl = TextEditingController();
  File? _imagenFile;
  bool _subiendoImagen = false;

  String get _idNegocio => widget.negocio['id_negocio'] as String;
  String get _nombreNegocio =>
      (widget.negocio['nombre'] as String?) ?? 'nuestro negocio';

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _textoCtrl.dispose();
    super.dispose();
  }

  /// FIX (UI): los SnackBar del Scaffold de fondo quedaban tapados por
  /// el propio sheet. El aviso se pinta dentro; si ya cerró, snackbar.
  void _snack(String msg) {
    if (!mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    setState(() => _aviso = msg);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _aviso == msg) setState(() => _aviso = null);
    });
  }

  /// Errores del trigger -> mensajes humanos.
  String _mensajeError(Object e) {
    final s = e.toString();
    if (s.contains('CUPO_ANUNCIOS')) {
      return 'Alcanzaste el máximo simultáneo de tu paquete. Pausa otro '
          'anuncio o renueva/mejora tu paquete.';
    }
    if (s.contains('SIN_PERMISO_VIGENTE')) {
      return 'No tienes paquete de anuncio vigente. Escríbenos por '
          'WhatsApp para comprarlo o renovarlo.';
    }
    if (s.contains('NEGOCIO_NO_HABILITADO')) {
      return 'Tu negocio aún no está habilitado para anunciarse.';
    }
    if (s.contains('CAMPO_PROTEGIDO')) {
      return 'Ese cambio solo lo puede hacer el administrador. Si quieres '
          'retirar un anuncio aprobado, ponlo en pausa.';
    }
    if (s.contains('SESION_REQUERIDA')) {
      return 'Inicia sesión de nuevo e inténtalo otra vez.';
    }
    return s.replaceFirst('Exception: ', '');
  }

  Future<void> _recargarMisAnuncios() async {
    _misAnunciosFuture = _anunciosService.misAnunciosDeNegocio(_idNegocio);
    setState(() {});
  }

  Color _colorEstado(String? estado) {
    switch (estado) {
      case 'aprobado':
        return Colors.green.shade600;
      case 'pausado':
        return Colors.amber.shade700;
      case 'rechazado':
        return Theme.of(context).colorScheme.error;
      default:
        return AppColors.primary;
    }
  }

  /// Abre WhatsApp con el admin (pagos de anuncios o contacto genérico)
  /// para comprar/renovar paquete.
  Future<void> _comprarPaquete() async {
    var telefono = await _anunciosService.obtenerWhatsappPagos();
    telefono ??= await _tiendasService.obtenerContactoWhatsappActivo();
    if (!mounted) return;
    if (telefono == null || telefono.trim().isEmpty) {
      _snack('El admin aún no configuró un WhatsApp de contacto');
      return;
    }
    final msg = Uri.encodeComponent(
        'Hola, quiero comprar/renovar un paquete de anuncios para '
        '"$_nombreNegocio" en Al Lado.');
    try {
      await launchUrl(
        Uri.parse('https://wa.me/${telefono.trim()}/?text=$msg'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      _snack('No se pudo abrir WhatsApp');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esOscuro = theme.brightness == Brightness.dark;
    final colorSuperficie =
        esOscuro ? theme.colorScheme.surface : Colors.white;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: colorSuperficie,
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
                    child: Text(
                      _vista == _Vista.crear
                          ? 'Crear anuncio'
                          : _vista == _Vista.misAnuncios
                              ? 'Mis anuncios'
                              : 'Anuncios',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: theme.textTheme.bodyLarge?.color),
                    ),
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_aviso != null) _bannerAviso(theme),
                    _contenido(theme),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Franja de aviso/erro visible dentro del sheet. Tócala para cerrar.
  Widget _bannerAviso(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.warm
            .withOpacity(theme.brightness == Brightness.dark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warm.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 17, color: AppColors.warm),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _aviso!,
              style: GoogleFonts.inter(fontSize: 12.5, height: 1.35),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _aviso = null),
            icon: const Icon(Icons.close_rounded, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _contenido(ThemeData theme) {
    switch (_vista) {
      case _Vista.menu:
        return _vistaMenu(theme);
      case _Vista.crear:
        return _vistaCrear(theme);
      case _Vista.misAnuncios:
        return _vistaMisAnuncios(theme);
    }
  }

  // ----------------------------- MENU -----------------------------

  Widget _vistaMenu(ThemeData theme) {
    // Ranuras ANTES de pintar: con cupo lleno, Crear queda atenuado.
    return FutureBuilder<({int usados, int max, DateTime? vigenteHasta})>(
      future: _anunciosService.ranurasDeNegocio(_idNegocio),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final r = snap.data ?? (usados: 0, max: 0, vigenteHasta: null);
        final sinPermiso = r.max <= 0;
        final lleno = !sinPermiso && r.usados >= r.max;
        final hasta = r.vigenteHasta;
        final hastaTxt = hasta == null
            ? ''
            : ' · válido hasta ${hasta.day}/${hasta.month}/${hasta.year}';

        if (sinPermiso) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warm.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.warm.withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.workspace_premium_rounded,
                          size: 18, color: AppColors.warm),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('No tienes paquete de anuncios activo',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700, fontSize: 13.5)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      'Compra un paquete para que tus promociones salgan '
                      'en el feed de inicio como "Negocio Patrocinado".',
                      style: GoogleFonts.inter(fontSize: 12, height: 1.45),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _kVerde,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _comprarPaquete,
                        icon: const Icon(Icons.chat_rounded, size: 17),
                        label: Text('Comprar por WhatsApp',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _opcionTile(
                theme,
                icono: Icons.local_offer_rounded,
                titulo: 'Ver ofertas',
                subtitulo: 'Paquetes de anuncio con pago por WhatsApp',
                onTap: () {
                  Navigator.of(context).pop();
                  mostrarPaquetesNegocioSheet(context, widget.negocio);
                },
              ),
              _opcionTile(
                theme,
                icono: Icons.list_alt_rounded,
                titulo: 'Mis anuncios',
                subtitulo: 'Historial y estado de moderación',
                onTap: () {
                  setState(() => _vista = _Vista.misAnuncios);
                  _recargarMisAnuncios();
                },
              ),
            ],
          );
        }

        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kVerde.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kVerde.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 18, color: _kVerde),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tu negocio ya se promociona solo en el feed de '
                          'inicio$hastaTxt -- sin que tengas que crear nada.',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _kVerde,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${r.usados} de ${r.max} anuncios en uso. Puedes usar el '
                    'resto para promos puntuales con "Crear anuncio" (estas '
                    'sí pasan por revisión).',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: _kVerde.withOpacity(0.85),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('· ',
                    style: GoogleFonts.inter(
                        fontSize: 10, color: _kVerde.withOpacity(0.7))),
                Text('Promociona solo',
                    style: GoogleFonts.inter(
                        fontSize: 10, color: _kVerde)),
              ],
            ),
            const SizedBox(height: 16),
            _opcionTile(
              theme,
              icono: Icons.add_circle_outline_rounded,
              titulo: 'Crear anuncio',
              subtitulo: lleno
                  ? 'Cupo lleno -- pausa uno o renueva tu paquete'
                  : 'Promo con título, texto e imagen opcional',
              atenuado: lleno,
              onTap: lleno
                  ? () => _snack('Cupo lleno: pausa un anuncio desde "Mis '
                      'anuncios" o renueva tu paquete.')
                  : () => setState(() => _vista = _Vista.crear),
            ),
            _opcionTile(
              theme,
              icono: Icons.list_alt_rounded,
              titulo: 'Mis anuncios',
              subtitulo: 'Estado, métricas, editar y pausar',
              onTap: () {
                setState(() => _vista = _Vista.misAnuncios);
                _recargarMisAnuncios();
              },
            ),
            _opcionTile(
              theme,
              icono: Icons.local_offer_rounded,
              titulo: 'Ofertas y renovación',
              subtitulo: 'Compra o amplía tu paquete por WhatsApp',
              onTap: () {
                Navigator.of(context).pop();
                mostrarPaquetesNegocioSheet(context, widget.negocio);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _opcionTile(
    ThemeData theme, {
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
    bool atenuado = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest
            .withOpacity(theme.brightness == Brightness.dark ? 0.25 : 0.55),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Opacity(
            opacity: atenuado ? 0.55 : 1,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(icono, size: 21, color: _kVerde),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo,
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                                color: theme.textTheme.bodyLarge?.color)),
                        const SizedBox(height: 2),
                        Text(subtitulo,
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                color: theme.textTheme.bodySmall?.color)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------- CREAR ------------------------------

  InputDecoration _decoracion(ThemeData theme, String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 19),
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest
          .withOpacity(theme.brightness == Brightness.dark ? 0.4 : 1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding:
          const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
    );
  }

  Widget _vistaCrear(ThemeData theme) {
    return Form(
      key: _formKeyCrear,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _tituloCtrl,
            maxLength: 60,
            decoration:
                _decoracion(theme, 'Título del anuncio', Icons.title_rounded),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'El título es obligatorio' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _textoCtrl,
            maxLines: 3,
            maxLength: 220,
            decoration:
                _decoracion(theme, '¿Qué quieres promocionar?', Icons.notes_rounded),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'El texto es obligatorio' : null,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kVerde,
                  side: BorderSide(color: _kVerde.withOpacity(0.5)),
                ),
                onPressed: _subiendoImagen
                    ? null
                    : () async {
                        final f = await _storageService.elegirFoto();
                        if (f != null) setState(() => _imagenFile = f);
                      },
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
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Imagen opcional. Sin imagen usamos una franja verde con '
                  'tu título.',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                      height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _kVerde,
              side: BorderSide(color: _kVerde.withOpacity(0.5)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _mostrarVistaPrevia,
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: Text('Ver vista previa',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.hourglass_top_rounded,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Este anuncio pasa por revisión. Te avisamos cuando sea '
                    'aprobado.',
                    style: GoogleFonts.inter(
                        fontSize: 11.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _kVerde,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _publicando ? null : _publicarPromo,
              icon: _subiendoImagen || _publicando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _publicando ? 'Enviando...' : 'Enviar a revisión',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Vista previa con la MISMA tarjeta que pinta el feed.
  void _mostrarVistaPrevia() {
    if (_tituloCtrl.text.trim().isEmpty || _textoCtrl.text.trim().isEmpty) {
      _snack('Completa título y texto para ver la vista previa.');
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Vista previa',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: IgnorePointer(
            child: TarjetaAnuncio(
              anuncio: Anuncio(
                idAnuncio: 'preview',
                tipo: 'negocio',
                titulo: _tituloCtrl.text.trim(),
                texto: _textoCtrl.text.trim(),
                destinoNombre: _nombreNegocio,
                destinoImagen: widget.negocio['logo_url'] as String?,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _publicarPromo() async {
    if (!_formKeyCrear.currentState!.validate()) return;
    setState(() => _publicando = true);
    try {
      String? imagenUrl;
      if (_imagenFile != null) {
        final uid = supabase.auth.currentUser?.id;
        if (uid == null) throw Exception('SESION_REQUERIDA');
        setState(() => _subiendoImagen = true);
        imagenUrl = await _storageService.subirImagenAnuncio(
            archivo: _imagenFile!, uid: uid);
        setState(() => _subiendoImagen = false);
      }
      await _anunciosService.crearPromoNegocio(
        idNegocio: _idNegocio,
        titulo: _tituloCtrl.text.trim(),
        texto: _textoCtrl.text.trim(),
        imagenUrl: imagenUrl,
      );
      // Nota: el canal realtime solo escucha UPDATE, así que el INSERT
      // no genera notificación -- el snackbar basta.
      if (!mounted) return;
      Navigator.of(context).pop();
      _snack('¡Enviado! Te avisaremos cuando sea aprobado.');
    } catch (e) {
      if (mounted) _snack(_mensajeError(e));
    } finally {
      if (mounted) {
        setState(() {
          _publicando = false;
          _subiendoImagen = false;
        });
      }
    }
  }

  // ------------------------- MIS ANUNCIOS -------------------------

  void _ordenar(List<Map<String, dynamic>> todas) {
    switch (_orden) {
      case _OrdenMis.recientes:
        todas.sort((a, b) => ((b['creado_en'] as String?) ?? '')
            .compareTo((a['creado_en'] as String?) ?? ''));
        break;
      case _OrdenMis.vistas:
        todas.sort((a, b) => ((b['veces_mostrado'] as num?) ?? 0)
            .compareTo((a['veces_mostrado'] as num?) ?? 0));
        break;
      case _OrdenMis.estado:
        int rango(String? e) => switch (e) {
              'aprobado' => 0,
              'pendiente' => 1,
              'pausado' => 2,
              'rechazado' => 3,
              _ => 4,
            };
        todas.sort((a, b) =>
            rango(a['estado'] as String?).compareTo(rango(b['estado'] as String?)));
        break;
    }
  }

  Widget _vistaMisAnuncios(ThemeData theme) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _misAnunciosFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final todas = snap.data ?? [];
        if (todas.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text(
                'Todavía no has enviado anuncios.\nCrea una promo para empezar.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    color: theme.textTheme.bodySmall?.color, height: 1.5),
              ),
            ),
          );
        }
        _ordenar([...todas]);
        return Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<_OrdenMis>(
                tooltip: 'Ordenar',
                onSelected: (o) => setState(() => _orden = o),
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sort_rounded,
                        size: 16, color: theme.textTheme.bodySmall?.color),
                    const SizedBox(width: 4),
                    Text(
                      switch (_orden) {
                        _OrdenMis.recientes => 'Recientes',
                        _OrdenMis.vistas => 'Más vistas',
                        _OrdenMis.estado => 'Por estado',
                      },
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                  ],
                ),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: _OrdenMis.recientes, child: Text('Recientes')),
                  PopupMenuItem(value: _OrdenMis.vistas, child: Text('Más vistas')),
                  PopupMenuItem(value: _OrdenMis.estado, child: Text('Por estado')),
                ],
              ),
            ),
            ...todas.map((a) => _tarjetaMiAnuncio(a, theme)),
          ],
        );
      },
    );
  }

  Widget _tarjetaMiAnuncio(Map<String, dynamic> a, ThemeData theme) {
    final estado = a['estado'] as String?;
    final motivo = a['motivo_rechazo'] as String?;
    final impresiones = (a['veces_mostrado'] as num?)?.toInt() ?? 0;
    final clics = (a['veces_clickeado'] as num?)?.toInt() ?? 0;
    final ctr = impresiones > 0 ? (clics * 100 / impresiones) : 0.0;
    final esAutomatico = a['es_automatico'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  a['titulo'] ?? '(sin título)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _colorEstado(estado).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  esAutomatico ? 'AUTOMÁTICO' : (estado ?? '').toUpperCase(),
                  style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: _colorEstado(estado)),
                ),
              ),
            ],
          ),
          if (motivo != null && motivo.isNotEmpty && estado == 'rechazado') ...[
            const SizedBox(height: 6),
            Text('Motivo del rechazo: $motivo',
                style: GoogleFonts.inter(
                    fontSize: 11.5, color: theme.colorScheme.error)),
          ],
const SizedBox(height: 6),
          Text('$impresiones impresiones · $clics clics (${ctr.toStringAsFixed(1)}%)',
              style: GoogleFonts.inter(
                  fontSize: 11.5, color: theme.textTheme.bodySmall?.color)),
          const SizedBox(height: 10),
          if (esAutomatico)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _kVerde.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 14, color: _kVerde),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Generado automáticamente por tu paquete -- se '
                      'actualiza y renueva solo, no se edita a mano.',
                      style: GoogleFonts.inter(fontSize: 11.5, color: _kVerde),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _dialogEditar(a),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Editar'),
                ),
                if (estado == 'aprobado')
                  TextButton.icon(
                    onPressed: () => _cambiarEstado(a, 'pausado'),
                    icon: const Icon(Icons.pause_circle_outline_rounded, size: 16),
                    label: const Text('Pausar'),
                  ),
                if (estado == 'pausado')
                  TextButton.icon(
                    onPressed: () => _cambiarEstado(a, 'aprobado'),
                    icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
                    label: const Text('Activar'),
                  ),
                const Spacer(),
                if (estado != 'aprobado')
                  IconButton(
                    tooltip: 'Eliminar',
                    onPressed: () => _confirmarEliminar(a),
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 19, color: theme.colorScheme.error),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _cambiarEstado(Map<String, dynamic> a, String nuevo) async {
    final id = a['id_anuncio'] as String;
    try {
      // Suprimimos el eco realtime: ya sabemos qué va a pasar.
      AnunciosStateService.instance.marcarCambioPropio(id, nuevo);
      if (nuevo == 'pausado') {
        await _anunciosService.pausarAnuncio(id);
      } else {
        await _anunciosService.activarAnuncio(id);
      }
      _snack(nuevo == 'pausado'
          ? 'Anuncio pausado.'
          : 'Anuncio enviado a reactivación.');
    } catch (e) {
      _snack(_mensajeError(e));
    }
    _recargarMisAnuncios();
  }

  void _confirmarEliminar(Map<String, dynamic> a) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Eliminar este anuncio?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: Text('Esta acción no se puede deshacer.',
            style: GoogleFonts.plusJakartaSans()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    ).then((ok) async {
      if (ok != true) return;
      try {
        await _anunciosService.eliminarAnuncio(a['id_anuncio'] as String);
        _snack('Anuncio eliminado.');
      } catch (e) {
        _snack(_mensajeError(e));
      }
      _recargarMisAnuncios();
    });
  }

  Future<void> _dialogEditar(Map<String, dynamic> a) async {
    final tituloCtrl = TextEditingController(text: a['titulo'] ?? '');
    final textoCtrl = TextEditingController(text: a['texto'] ?? '');
    File? nuevaImagen;

    final guardado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Editar anuncio',
              style:
                  GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tituloCtrl,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'Título'),
                ),
                TextField(
                  controller: textoCtrl,
                  maxLines: 3,
                  maxLength: 220,
                  decoration: const InputDecoration(labelText: 'Texto'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final f = await _storageService.elegirFoto();
                    if (f != null) setDialogState(() => nuevaImagen = f);
                  },
                  icon: const Icon(Icons.image_outlined, size: 17),
                  label: Text(nuevaImagen == null
                      ? 'Cambiar imagen (opcional)'
                      : 'Imagen lista'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Al guardar, el anuncio vuelve a revisión si estaba '
                  'aprobado o rechazado.',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Theme.of(dialogContext)
                          .textTheme
                          .bodySmall
                          ?.color),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kVerde),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (guardado != true || !mounted) return;
    if (tituloCtrl.text.trim().isEmpty || textoCtrl.text.trim().isEmpty) {
      _snack('Título y texto son obligatorios');
      return;
    }
    try {
      String? url;
      if (nuevaImagen != null) {
        final uid = supabase.auth.currentUser?.id;
        if (uid != null) {
          url = await _storageService.subirImagenAnuncio(
              archivo: nuevaImagen!, uid: uid);
        }
      }
      await _anunciosService.editarContenido(
        idAnuncio: a['id_anuncio'] as String,
        titulo: tituloCtrl.text.trim(),
        texto: textoCtrl.text.trim(),
        imagenUrl: url,
      );
      // Suprimimos el eco del UPDATE (re-moderación -> pendiente).
      // Suprimimos el eco del UPDATE (re-moderación -> pendiente).
      AnunciosStateService.instance.marcarCambioPropio(
          a['id_anuncio'] as String,
          (a['estado'] as String?) == 'pausado' ? 'pausado' : 'pendiente');
      _snack('Anuncio actualizado');
    } catch (e) {
      _snack(_mensajeError(e));
    }
    _recargarMisAnuncios();
  }
}

enum _OrdenMis { recientes, vistas, estado }