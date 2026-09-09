// anuncios_tienda_sheet.dart
//
// Bottom sheet "Anuncios y Promociones" de la tienda del vendedor,
// abierto desde Gestionar Tienda. Dos flujos, un mismo tipo en BD
// (anuncios.tipo='producto'):
//
//   1) POTENCIAR PRODUCTO -> elige uno de sus productos; se anuncia
//      tal cual (imagen + nombre + precio como texto).
//   2) CREAR ANUNCIO -> promo en pleno: título + texto + imagen
//      opcional, ligada a la tienda sin producto concreto.
//
// El trigger anuncios_before_insert valida la RANURA (planes.ranuras_
// anuncios + permisos_tienda_anuncios vigentes -- ver anuncios_service.
// dart): si no hay cupo lanza CUPO_ANUNCIOS y la convertimos en mensaje
// amable. Si hay cupo nace 'aprobado' directo (los anuncios de tienda
// NO pasan por moderación).
//
// NUEVO (2026-09): ranurasDeTienda() ahora devuelve el desglose
// maxPlan/maxExtra -- se muestra en el banner del menú cuando hay
// ranuras extra compradas, y se ofrece un acceso a "Comprar ranuras
// extra" que abre paquete_anuncios_tienda_sheet.dart.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/anuncios_service.dart';
import '../services/anuncios_state_service.dart';
import '../services/storage_service.dart';
import '../services/tiendas_service.dart';
import '../screens/gestionar_planes_screen.dart';
import 'tarjeta_anuncio.dart';
import 'paquete_anuncios_tienda_sheet.dart';

const Color _kVerde = Color(0xFF0D9488);

/// Punto de entrada único para Gestionar Tienda.
Future<void> mostrarAnunciosSheet(
  BuildContext context,
  Map<String, dynamic> tienda,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AnunciosSheet(tienda: tienda),
  );
}

enum _Vista { menu, potenciar, crear, misAnuncios }

/// Orden del listado "Mis anuncios".
enum _OrdenMis { recientes, vistas, estado }

class _AnunciosSheet extends StatefulWidget {
  final Map<String, dynamic> tienda;
  const _AnunciosSheet({required this.tienda});

  @override
  State<_AnunciosSheet> createState() => _AnunciosSheetState();
}

class _AnunciosSheetState extends State<_AnunciosSheet> {
  final _anunciosService = AnunciosService();
  final _tiendasService = TiendasService();
  final _storageService = StorageService();
  final ImagePickerHost _pickerHost = ImagePickerHost();

  _Vista _vista = _Vista.menu;
  bool _publicando = false;

  String? _aviso;

  Future<List<Map<String, dynamic>>>? _misAnunciosFuture;
  _OrdenMis _orden = _OrdenMis.recientes;

  final _formKeyCrear = GlobalKey<FormState>();
  final _tituloCtrl = TextEditingController();
  final _textoCtrl = TextEditingController();
  File? _imagenFile;
  bool _subiendoImagen = false;

  String get _idTienda => widget.tienda['id_tienda'] as String;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _textoCtrl.dispose();
    super.dispose();
  }

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

  String _mensajeError(Object e) {
    final s = e.toString();
    if (s.contains('CUPO_ANUNCIOS')) {
      return 'Alcanzaste el máximo de ranuras de tu plan. Sube de plan, '
          'compra ranuras extra, pon en pausa otro anuncio o espera a '
          'que expire.';
    }
    if (s.contains('TIENDA_AJENA')) {
      return 'Esta tienda no te pertenece.';
    }
    if (s.contains('SESION_REQUERIDA')) {
      return 'Inicia sesión de nuevo e inténtalo otra vez.';
    }
    return s.replaceFirst('Exception: ', '');
  }

  Future<void> _publicarProducto(Map<String, dynamic> producto) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Potenciar "${producto['nombre']}"?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se publicará como "Promoción Pagada" en el feed de inicio. '
                'No pasa por moderación: sale al instante si tienes ranura '
                'libre.',
                style: GoogleFonts.plusJakartaSans(height: 1.4),
              ),
              const SizedBox(height: 14),
              Text('Vista previa:',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              IgnorePointer(
                child: TarjetaAnuncio(
                  anuncio: Anuncio(
                    idAnuncio: 'preview',
                    tipo: 'producto',
                    titulo: '${producto['nombre']}',
                    texto:
                        'Ahora \$${producto['precio_usd']} en ${widget.tienda['nombre'] ?? 'nuestra tienda'}. ¡Pídelo ya!',
                    imagenUrl: producto['imagen_url'] as String?,
                    destinoNombre: producto['nombre'] as String?,
                  ),
                ),
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
            child: const Text('Potenciar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _publicando = true);
    try {
      await _anunciosService.potenciarProducto(
        idTienda: _idTienda,
        idProducto: producto['id_producto'] as String,
        titulo: '${producto['nombre']}',
        texto:
            'Ahora \$${producto['precio_usd']} en ${widget.tienda['nombre'] ?? 'nuestra tienda'}. ¡Pídelo ya!',
        imagenUrl: producto['imagen_url'] as String?,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _snack('¡Producto potenciado! Ya está corriendo en el feed.');
    } catch (e) {
      if (mounted) _snack(_mensajeError(e));
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  void _mostrarVistaPrevia(ThemeData theme) {
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IgnorePointer(
                child: TarjetaAnuncio(
                  anuncio: Anuncio(
                    idAnuncio: 'preview',
                    tipo: 'producto',
                    titulo: _tituloCtrl.text.trim(),
                    texto: _textoCtrl.text.trim(),
                    destinoNombre: widget.tienda['nombre'] as String?,
                  ),
                ),
              ),
              if (_imagenFile != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Tu imagen elegida se subirá al publicar.',
                  style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: theme.textTheme.bodySmall?.color),
                ),
              ],
            ],
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
      await _anunciosService.crearPromoTienda(
        idTienda: _idTienda,
        titulo: _tituloCtrl.text.trim(),
        texto: _textoCtrl.text.trim(),
        imagenUrl: imagenUrl,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _snack('¡Anuncio publicado! Ya está corriendo en el feed.');
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

  Widget _bannerAviso(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.warm.withOpacity(theme.brightness == Brightness.dark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warm.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 17, color: AppColors.warm),
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
      case _Vista.potenciar:
        return _vistaPotenciar(theme);
      case _Vista.crear:
        return _vistaCrear(theme);
      case _Vista.misAnuncios:
        return _vistaMisAnuncios(theme);
    }
  }

  // ----------------------------- MENU -----------------------------

  Widget _vistaMenu(ThemeData theme) {
    final idTienda = _idTienda;
    return FutureBuilder<({int usados, int max, int maxPlan, int maxExtra})>(
      future: _anunciosService.ranurasDeTienda(idTienda),
      builder: (context, snap) {
        final datos = snap.data;
        final maximo = datos?.max ?? 0;
        final usados = datos?.usados ?? 0;
        final maxExtra = datos?.maxExtra ?? 0;
        final lleno = datos != null && maximo > 0 && usados >= maximo;

        void sinRanuras() => _snack('No tienes ranuras libres: sube de '
            'plan, compra ranuras extra o pon en pausa uno de tus '
            'anuncios.');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (datos != null && maximo > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _kVerde.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kVerde.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      lleno
                          ? Icons.error_outline_rounded
                          : Icons.campaign_rounded,
                      color: lleno ? Colors.amber.shade700 : _kVerde,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        lleno
                            ? 'Ranuras llenas ($usados de $maximo). '
                                'Pausa uno, sube de plan o compra extra.'
                            : maxExtra > 0
                                ? '$usados de $maximo ranuras en uso '
                                    '(${maximo - maxExtra} del plan + '
                                    '$maxExtra extra).'
                                : '$usados de $maximo ranuras de tu '
                                    'plan en uso.',
                        style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: theme.textTheme.bodySmall?.color),
                      ),
                    ),
                  ],
                ),
              ),
            _opcionTile(
              theme,
              icono: Icons.inventory_2_outlined,
              titulo: 'Potenciar producto',
              subtitulo: 'Elige un producto tuyo y anúncialo en el feed',
              atenuado: lleno,
              onTap: lleno
                  ? sinRanuras
                  : () => setState(() => _vista = _Vista.potenciar),
            ),
            const SizedBox(height: 10),
            _opcionTile(
              theme,
              icono: Icons.campaign_outlined,
              titulo: 'Crear anuncio',
              subtitulo: 'Promoción libre con tu propio título e imagen',
              atenuado: lleno,
              onTap: lleno
                  ? sinRanuras
                  : () => setState(() => _vista = _Vista.crear),
            ),
            const SizedBox(height: 10),
            _opcionTile(
              theme,
              icono: Icons.add_shopping_cart_rounded,
              titulo: 'Comprar ranuras extra',
              subtitulo: 'Súmale ranuras a tu tienda sin cambiar de plan',
              onTap: () {
                Navigator.of(context).pop();
                mostrarPaqueteAnunciosTiendaSheet(context, widget.tienda);
              },
            ),
            const SizedBox(height: 10),
            _opcionTile(
              theme,
              icono: Icons.list_alt_rounded,
              titulo: 'Mis anuncios',
              subtitulo: 'Edita, pausa o elimina los que ya publicaste',
              onTap: () {
                _misAnunciosFuture ??=
                    _anunciosService.misAnunciosDeTienda(_idTienda);
                setState(() => _vista = _Vista.misAnuncios);
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
    return Opacity(
      opacity: atenuado ? 0.5 : 1,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest
            .withOpacity(theme.brightness == Brightness.dark ? 0.4 : 1),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _kVerde.withOpacity(0.12),
                  child: Icon(icono, color: _kVerde, size: 22),
                ),
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
    );
  }

  // -------------------------- POTENCIAR ---------------------------

  Widget _vistaPotenciar(ThemeData theme) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _tiendasService.obtenerProductosDeTienda(_idTienda),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final productos = snap.data ?? [];
        if (productos.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text(
                'No tienes productos todavía.\nCrea uno y vuelve a potenciarlo.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    color: theme.textTheme.bodySmall?.color, height: 1.4),
              ),
            ),
          );
        }
        return Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Elige el producto a potenciar',
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodySmall?.color),
              ),
            ),
            const SizedBox(height: 10),
            ...productos.map((p) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: AppColors.primary.withOpacity(0.1),
                    child: p['imagen_url'] != null
                        ? Image.network(p['imagen_url'], fit: BoxFit.cover)
                        : const Icon(Icons.image_outlined),
                  ),
                ),
                title: Text(p['nombre'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                subtitle: Text('\$${p['precio_usd']} USD',
                    style: GoogleFonts.inter(fontSize: 12)),
                trailing: _publicando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.rocket_launch_outlined,
                        color: _kVerde, size: 20),
                onTap: _publicando ? null : () => _publicarProducto(p),
              );
            }),
          ],
        );
      },
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
            style: GoogleFonts.inter(color: theme.textTheme.bodyLarge?.color),
            decoration: _decoracion(theme, 'Título llamativo *',
                Icons.title_rounded),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _textoCtrl,
            maxLength: 200,
            maxLines: 3,
            style: GoogleFonts.inter(color: theme.textTheme.bodyLarge?.color),
            decoration: _decoracion(
                theme, 'Texto del anuncio *', Icons.notes_rounded),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GestureDetector(
                onTap: () async {
                  final f = await _pickerHost.elegirFoto();
                  if (f != null) setState(() => _imagenFile = f);
                },
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: _kVerde.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _kVerde.withOpacity(0.35),
                        style: BorderStyle.solid),
                  ),
                  child: _imagenFile != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(_imagenFile!, fit: BoxFit.cover))
                      : Icon(Icons.add_photo_alternate_outlined,
                          color: _kVerde, size: 26),
                ),
              ),
              const SizedBox(width: 14),
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
            onPressed: () => _mostrarVistaPrevia(theme),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: Text('Ver vista previa',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
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
                  : const Icon(Icons.rocket_launch_rounded, size: 19),
              label: Text(
                _publicando ? 'Publicando...' : 'Publicar anuncio',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------- MIS ANUNCIOS -------------------------

  void _recargarMisAnuncios() {
    _misAnunciosFuture = _anunciosService.misAnunciosDeTienda(_idTienda);
    setState(() {});
  }

  Color _colorEstado(String? estado) {
    switch (estado) {
      case 'aprobado':
        return Colors.green.shade600;
      case 'pausado':
        return Colors.amber.shade700;
      case 'rechazado':
        return themeColorError();
      default:
        return AppColors.primary;
    }
  }

  Color themeColorError() => Theme.of(context).colorScheme.error;

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
                'Todavía no has publicado anuncios.\n'
                'Potencia un producto o crea una promo.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    color: theme.textTheme.bodySmall?.color, height: 1.5),
              ),
            ),
          );
        }
        final anuncios = [...todas];
        switch (_orden) {
          case _OrdenMis.recientes:
            anuncios.sort((a, b) => ((b['creado_en'] as String?) ?? '')
                .compareTo((a['creado_en'] as String?) ?? ''));
            break;
          case _OrdenMis.vistas:
            anuncios.sort((a, b) =>
                ((b['veces_mostrado'] as num?) ?? 0)
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
            anuncios.sort((a, b) =>
                rango(a['estado'] as String?)
                    .compareTo(rango(b['estado'] as String?)));
            break;
        }
        return Column(
          children: [
            if (todas.isNotEmpty)
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
                    PopupMenuItem(
                        value: _OrdenMis.recientes, child: Text('Recientes')),
                    PopupMenuItem(
                        value: _OrdenMis.vistas, child: Text('Más vistas')),
                    PopupMenuItem(
                        value: _OrdenMis.estado, child: Text('Por estado')),
                  ],
                ),
              ),
            ...anuncios.map((a) => _tarjetaMiAnuncio(a, theme)),
          ],
        );
      },
    );
  }

  Widget _tarjetaMiAnuncio(Map<String, dynamic> a, ThemeData theme) {
    final estado = a['estado'] as String?;
    final enFeed = estado == 'aprobado';
    final impresiones = (a['veces_mostrado'] as num?)?.toInt() ?? 0;
    final clics = (a['veces_clickeado'] as num?)?.toInt() ?? 0;
    final ctr = impresiones > 0 ? (clics * 100 / impresiones) : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withOpacity(theme.brightness == Brightness.dark ? 0.4 : 1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 56,
              height: 56,
              color: AppColors.primary.withOpacity(0.1),
              child: (a['imagen_url'] as String?)?.isNotEmpty == true
                  ? Image.network(a['imagen_url'], fit: BoxFit.cover)
                  : Icon(Icons.campaign_rounded,
                      color: _kVerde.withOpacity(0.6)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a['titulo'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: theme.textTheme.bodyLarge?.color)),
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _colorEstado(estado).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${enFeed ? "EN FEED" : (estado ?? '').toUpperCase()} · '
                    '$impresiones impresiones · $clics clics '
                    '(${ctr.toStringAsFixed(1)}%)',
                    style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _colorEstado(estado)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _iconoAccion(
                      icono: Icons.edit_rounded,
                      tooltip: 'Editar',
                      onTap: () => _dialogEditar(a),
                    ),
                    _iconoAccion(
                      icono: enFeed
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                      tooltip: enFeed ? 'Pausar' : 'Reactivar',
                      onTap: () async {
                        try {
                          if (enFeed) {
                            AnunciosStateService.instance
                                .marcarCambioPropio(
                                    a['id_anuncio'] as String, 'pausado');
                            await _anunciosService.pausarAnuncio(
                                a['id_anuncio'] as String);
                          } else if (estado == 'pausado') {
                            AnunciosStateService.instance
                                .marcarCambioPropio(
                                    a['id_anuncio'] as String, 'aprobado');
                            await _anunciosService.activarAnuncio(
                                a['id_anuncio'] as String);
                          }
                        } catch (e) {
                          _snack(_mensajeError(e));
                        }
                        _recargarMisAnuncios();
                      },
                    ),
                    _iconoAccion(
                      icono: Icons.delete_outline_rounded,
                      tooltip: 'Eliminar',
                      color: Colors.redAccent,
                      onTap: () => _confirmarEliminar(a),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconoAccion({
    required IconData icono,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icono, size: 20, color: color ?? _kVerde),
        ),
      ),
    );
  }

  Future<void> _confirmarEliminar(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Eliminar anuncio?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: Text('Se quitará del feed para siempre.',
            style: GoogleFonts.plusJakartaSans(height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _anunciosService.eliminarAnuncio(a['id_anuncio'] as String);
    } catch (e) {
      if (mounted) _snack(_mensajeError(e));
    }
    _recargarMisAnuncios();
  }

  Future<void> _dialogEditar(Map<String, dynamic> a) async {
    final tituloCtrl = TextEditingController(text: a['titulo'] ?? '');
    final textoCtrl = TextEditingController(text: a['texto'] ?? '');
    File? nuevaImagen;

    final guardado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
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
                  decoration:
                      const InputDecoration(labelText: 'Título *'),
                ),
                TextField(
                  controller: textoCtrl,
                  maxLength: 200,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(labelText: 'Texto *'),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final f = await _pickerHost.elegirFoto();
                    if (f != null) setDialogState(() => nuevaImagen = f);
                  },
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 52,
                          height: 52,
                          color: _kVerde.withOpacity(0.08),
                          child: nuevaImagen != null
                              ? Image.file(nuevaImagen!, fit: BoxFit.cover)
                              : ((a['imagen_url'] as String?)
                                          ?.isNotEmpty ==
                                      true)
                                  ? Image.network(a['imagen_url'],
                                      fit: BoxFit.cover)
                                  : const Icon(Icons.image_outlined),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('Tocar para cambiar imagen',
                          style: GoogleFonts.inter(fontSize: 12.5)),
                    ],
                  ),
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
      AnunciosStateService.instance.marcarCambioPropio(
          a['id_anuncio'] as String,
          (a['estado'] as String?) ?? 'aprobado');
      _snack('Anuncio actualizado');
    } catch (e) {
      _snack(_mensajeError(e));
    }
    _recargarMisAnuncios();
  }
}

/// Envoltura mínima sobre StorageService.elegirFoto().
class ImagePickerHost {
  final StorageService _storage = StorageService();

  Future<File?> elegirFoto() => _storage.elegirFoto();
}