// gestionar_anuncios_standalone_sheet.dart
//
// Sheet "Mis anuncios" para anuncios INDEPENDIENTES (standalone) --
// listarlos, ver impresiones/clics, editar título/texto/imagen, pausar/
// reactivar y eliminar. Mismo patrón que ya usan las tiendas y los
// negocios (anuncios_tienda_sheet.dart / anuncios_negocio_sheet.dart),
// adaptado a que un standalone no tiene tienda ni negocio detrás --
// pertenece solo al usuario (columna `creado_por`).
//
// Se abre desde:
//   - standalone_anuncio_screen.dart (botón "Mis anuncios" del AppBar)
//   - mi_perfil_screen.dart (tab Anuncios, botón "Gestionar")

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/anuncios_service.dart';
import '../services/storage_service.dart';

/// [destacarAnuncioId] resalta ese anuncio en la lista (flujo:
/// notificación de like/comentario -> tu anuncio).
Future<void> mostrarGestionarAnunciosStandaloneSheet(
  BuildContext context, {
  String? destacarAnuncioId,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _GestionarAnunciosStandaloneSheet(
      destacarAnuncioId: destacarAnuncioId,
    ),
  );
}

enum _OrdenMis { recientes, vistas, estado }

class _GestionarAnunciosStandaloneSheet extends StatefulWidget {
  final String? destacarAnuncioId;
  const _GestionarAnunciosStandaloneSheet({this.destacarAnuncioId});

  @override
  State<_GestionarAnunciosStandaloneSheet> createState() =>
      _GestionarAnunciosStandaloneSheetState();
}

class _GestionarAnunciosStandaloneSheetState
    extends State<_GestionarAnunciosStandaloneSheet> {
  final _anunciosService = AnunciosService();
  final _storageService = StorageService();

  late Future<List<Map<String, dynamic>>> _misAnunciosFuture;
  _OrdenMis _orden = _OrdenMis.recientes;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _misAnunciosFuture = _anunciosService.misAnunciosStandalone();
  }

  void _snack(String msg) {
    if (!mounted) return;
    setState(() => _aviso = msg);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _aviso == msg) setState(() => _aviso = null);
    });
  }

  void _recargar() {
    if (!mounted) return;
    setState(() {
      _misAnunciosFuture = _anunciosService.misAnunciosStandalone();
    });
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

  Future<void> _cambiarEstado(Map<String, dynamic> a, String nuevo) async {
    try {
      if (nuevo == 'pausado') {
        await _anunciosService.pausarAnuncio(a['id_anuncio'] as String);
      } else {
        await _anunciosService.activarAnuncio(a['id_anuncio'] as String);
      }
      _snack(nuevo == 'pausado' ? 'Anuncio pausado.' : 'Anuncio reactivado.');
    } catch (e) {
      _snack('No se pudo actualizar: '
          '${e.toString().replaceFirst('Exception: ', '')}');
    }
    _recargar();
  }

  Future<void> _confirmarEliminar(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Eliminar este anuncio?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: const Text('Esta acción no se puede deshacer.'),
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
    );
    if (ok != true) return;
    try {
      await _anunciosService.eliminarAnuncio(a['id_anuncio'] as String);
      _snack('Anuncio eliminado.');
    } catch (e) {
      _snack('No se pudo eliminar: '
          '${e.toString().replaceFirst('Exception: ', '')}');
    }
    _recargar();
  }

  Future<void> _dialogEditar(Map<String, dynamic> a) async {
    final tituloCtrl = TextEditingController(text: a['titulo'] ?? '');
    final textoCtrl = TextEditingController(text: a['texto'] ?? '');
    final precioCtrl = TextEditingController(
        text: (a['precio_usd'] as num?)?.toString() ?? '');
    final whatsappCtrl =
        TextEditingController(text: a['whatsapp'] ?? '');
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
                  decoration: const InputDecoration(labelText: 'Título'),
                ),
                TextField(
                  controller: textoCtrl,
                  maxLines: 3,
                  maxLength: 220,
                  decoration: const InputDecoration(labelText: 'Texto'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: precioCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Precio USD',
                          hintText: 'ej: 120',
                          prefixText: '\$ ',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: whatsappCtrl,
                        keyboardType: TextInputType.phone,
                        maxLength: 15,
                        decoration: const InputDecoration(
                          labelText: 'WhatsApp',
                          hintText: 'ej: 584120000000',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'La foto, el precio y el WhatsApp se muestran en el '
                  'detalle del anuncio: quien lo vea puede escribir '
                  '"Me interesa".',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: Theme.of(dialogContext)
                          .textTheme
                          .bodySmall
                          ?.color),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final f = await _storageService.elegirFoto();
                    if (f != null) setDialogState(() => nuevaImagen = f);
                  },
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 52,
                          height: 52,
                          color: AppColors.primary.withOpacity(0.08),
                          child: nuevaImagen != null
                              ? Image.file(nuevaImagen!, fit: BoxFit.cover)
                              : ((a['imagen_url'] as String?)?.isNotEmpty ==
                                      true)
                                  ? Image.network(a['imagen_url'],
                                      fit: BoxFit.cover)
                                  : const Icon(Icons.image_outlined),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('Tocar para cambiar imagen',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12.5)),
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
    double? precio;
    final precioTxt = precioCtrl.text.trim().replaceAll(',', '.');
    if (precioTxt.isNotEmpty) {
      final n = double.tryParse(precioTxt);
      if (n == null || n <= 0) {
        _snack('Poné un precio válido o dejalo vacío');
        return;
      }
      precio = n;
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
        precioUsd: precio,
        whatsapp: whatsappCtrl.text.trim(),
      );
      _snack('Anuncio actualizado');
    } catch (e) {
      _snack('No se pudo guardar: '
          '${e.toString().replaceFirst('Exception: ', '')}');
    }
    _recargar();
  }

  void _ordenar(List<Map<String, dynamic>> lista) {
    switch (_orden) {
      case _OrdenMis.recientes:
        lista.sort((a, b) => ((b['creado_en'] as String?) ?? '')
            .compareTo((a['creado_en'] as String?) ?? ''));
        break;
      case _OrdenMis.vistas:
        lista.sort((a, b) => ((b['veces_mostrado'] as num?) ?? 0)
            .compareTo((a['veces_mostrado'] as num?) ?? 0));
        break;
      case _OrdenMis.estado:
        int rango(String? e) => switch (e) {
              'aprobado' => 0,
              'pausado' => 1,
              'rechazado' => 2,
              _ => 3,
            };
        lista.sort((a, b) => rango(a['estado'] as String?)
            .compareTo(rango(b['estado'] as String?)));
        break;
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
                    child: Text('Mis anuncios independientes',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_aviso != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                        decoration: BoxDecoration(
                          color: AppColors.warm
                              .withOpacity(esOscuro ? 0.2 : 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: AppColors.warm.withOpacity(0.45)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 17, color: AppColors.warm),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_aviso!,
                                  style: GoogleFonts.inter(fontSize: 12.5)),
                            ),
                          ],
                        ),
                      ),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _misAnunciosFuture,
                      builder: (context, snap) {
                        if (snap.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final todos = snap.data ?? [];
                        if (todos.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 30),
                            child: Center(
                              child: Text(
                                'Todavía no has publicado anuncios '
                                'independientes.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                    color: theme.textTheme.bodySmall?.color,
                                    height: 1.5),
                              ),
                            ),
                          );
                        }
                        final anuncios = [...todos];
                        _ordenar(anuncios);
                        final destacarId = widget.destacarAnuncioId;
                        if (destacarId != null) {
                          final idx = anuncios.indexWhere(
                              (x) => (x['id_anuncio'] as String?) == destacarId);
                          if (idx > 0) {
                            final destacado = anuncios.removeAt(idx);
                            anuncios.insert(0, destacado);
                          }
                        }
                        return Column(
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: PopupMenuButton<_OrdenMis>(
                                tooltip: 'Ordenar',
                                onSelected: (o) =>
                                    setState(() => _orden = o),
                                icon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.sort_rounded,
                                        size: 16,
                                        color:
                                            theme.textTheme.bodySmall?.color),
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
                                      value: _OrdenMis.recientes,
                                      child: Text('Recientes')),
                                  PopupMenuItem(
                                      value: _OrdenMis.vistas,
                                      child: Text('Más vistas')),
                                  PopupMenuItem(
                                      value: _OrdenMis.estado,
                                      child: Text('Por estado')),
                                ],
                              ),
                            ),
                            ...anuncios.map((a) => _tarjeta(a, theme)),
                          ],
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

  Widget _tarjeta(Map<String, dynamic> a, ThemeData theme) {
    final estado = a['estado'] as String?;
    final enFeed = estado == 'aprobado';
    final impresiones = (a['veces_mostrado'] as num?)?.toInt() ?? 0;
    final clics = (a['veces_clickeado'] as num?)?.toInt() ?? 0;
    final ctr = impresiones > 0 ? (clics * 100 / impresiones) : 0.0;
    final vigenciaHasta =
        DateTime.tryParse(a['vigencia_hasta'] as String? ?? '');
    final totalLikes = (a['total_likes'] as num?)?.toInt() ?? 0;
    final totalComentarios = (a['total_comentarios'] as num?)?.toInt() ?? 0;
    final esDestacado =
        (a['id_anuncio'] as String?) == widget.destacarAnuncioId;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: esDestacado
            ? AppColors.primary.withOpacity(
                theme.brightness == Brightness.dark ? 0.18 : 0.08)
            : theme.colorScheme.surfaceContainerHighest
                .withOpacity(theme.brightness == Brightness.dark ? 0.4 : 1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: esDestacado ? AppColors.primary : theme.dividerColor,
          width: esDestacado ? 1.6 : 1,
        ),
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
                  : const Icon(Icons.rocket_launch_rounded,
                      color: AppColors.primary),
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
                    '$impresiones vistas · $clics clics '
                    '(${ctr.toStringAsFixed(1)}%)',
                    style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _colorEstado(estado)),
                  ),
                ),
                if (vigenciaHasta != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Vence ${vigenciaHasta.day}/${vigenciaHasta.month}/${vigenciaHasta.year}',
                    style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: theme.textTheme.bodySmall?.color),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.favorite_rounded,
                        size: 13, color: Colors.redAccent),
                    const SizedBox(width: 3),
                    Text('$totalLikes',
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.textTheme.bodySmall?.color)),
                    const SizedBox(width: 14),
                    Icon(Icons.comment_rounded,
                        size: 13,
                        color: theme.textTheme.bodySmall?.color),
                    const SizedBox(width: 3),
                    Text('$totalComentarios',
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.textTheme.bodySmall?.color)),
                  ],
                ),
                const SizedBox(height: 8),
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
                        icon: const Icon(Icons.pause_circle_outline_rounded,
                            size: 16),
                        label: const Text('Pausar'),
                      ),
                    if (estado == 'pausado')
                      TextButton.icon(
                        onPressed: () => _cambiarEstado(a, 'aprobado'),
                        icon: const Icon(Icons.play_circle_outline_rounded,
                            size: 16),
                        label: const Text('Activar'),
                      ),
                    const Spacer(),
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
          ),
        ],
      ),
    );
  }
}