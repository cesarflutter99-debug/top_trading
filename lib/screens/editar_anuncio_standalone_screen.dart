// editar_anuncio_standalone_screen.dart
//
// Formulario de EDICIÓN de un anuncio independiente (standalone). Se
// abre desde GestionarAnuncioScreen con el botón "Editar" y devuelve
// `true` al cerrar si se guardó algo (para que la pantalla anterior
// recargue).
//
// Reglas (espejo de standalone_anuncio_screen.dart, para que crear y
// editar se comporten igual):
//   - Título (máx. 60) y texto (máx. 220) obligatorios.
//   - Precio en USD > 0 y WhatsApp obligatorios.
//   - La imagen es opcional: si no se cambia, se conserva la actual.
//
// Detalles de backend:
//   - El trigger anuncios_before_update NO re-modera los anuncios
//     standalone al editar el contenido (solo los de negocio), igual que
//     hoy en la publicación: nacen aprobados sin revisión previa.
//   - Si se cambia la foto, la anterior se borra de ImageKit SOLO
//     después de guardar con éxito y SOLO si era una subida de anuncio
//     (carpeta /anuncios/) que ningún otro anuncio usa -- la misma
//     red de seguridad que ya usa AnunciosService.eliminarAnuncio().

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/anuncios_service.dart';
import '../services/storage_service.dart';

class EditarAnuncioStandaloneScreen extends StatefulWidget {
  /// Fila completa de `anuncios` (la que devuelve anuncio_gestion_detalle).
  final Map<String, dynamic> anuncio;
  const EditarAnuncioStandaloneScreen({super.key, required this.anuncio});

  @override
  State<EditarAnuncioStandaloneScreen> createState() =>
      _EditarAnuncioStandaloneScreenState();
}

class _EditarAnuncioStandaloneScreenState
    extends State<EditarAnuncioStandaloneScreen> {
  final _formKey = GlobalKey<FormState>();
  final _anunciosService = AnunciosService();
  final _storageService = StorageService();

  late final TextEditingController _tituloCtrl;
  late final TextEditingController _textoCtrl;
  late final TextEditingController _precioCtrl;
  late final TextEditingController _whatsappCtrl;

  File? _imagenNueva;
  bool _guardando = false;
  bool _subiendoImagen = false;

  String get _idAnuncio => widget.anuncio['id_anuncio'].toString();
  String? get _imagenActual {
    final u = (widget.anuncio['imagen_url'] as String?)?.trim();
    return (u == null || u.isEmpty) ? null : u;
  }

  @override
  void initState() {
    super.initState();
    final a = widget.anuncio;
    _tituloCtrl = TextEditingController(text: (a['titulo'] as String?) ?? '');
    _textoCtrl = TextEditingController(text: (a['texto'] as String?) ?? '');
    final precio = (a['precio_usd'] as num?)?.toDouble();
    _precioCtrl = TextEditingController(
      text: precio == null
          ? ''
          : (precio == precio.roundToDouble()
              ? precio.toInt().toString()
              : precio.toStringAsFixed(2)),
    );
    _whatsappCtrl =
        TextEditingController(text: (a['whatsapp'] as String?) ?? '');
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _textoCtrl.dispose();
    _precioCtrl.dispose();
    _whatsappCtrl.dispose();
    super.dispose();
  }

  bool get _esOscuro => Theme.of(context).brightness == Brightness.dark;
  Color get _colorTexto => _esOscuro ? Colors.white : AppColors.inkLight;
  Color get _colorSecundario => AppColors.inkSecundarioLight;

  InputDecoration _decoracion(String label, IconData icono) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icono, size: 20, color: _colorSecundario),
      labelStyle: GoogleFonts.plusJakartaSans(color: _colorSecundario),
    );
  }

  Future<void> _elegirImagen() async {
    final foto = await _storageService.elegirFoto();
    if (foto != null && mounted) setState(() => _imagenNueva = foto);
  }

  String _mensajeError(Object e) {
    final s = e.toString();
    if (s.contains('NO_AUTORIZADO')) {
      return 'No pudimos guardar: este anuncio ya no es tuyo o fue eliminado.';
    }
    if (s.contains('SESION_REQUERIDA')) {
      return 'Inicia sesión de nuevo e inténtalo otra vez.';
    }
    return 'No se pudieron guardar los cambios. Intenta de nuevo.';
  }

  /// Borra la foto anterior solo si era una subida de anuncio y ningún
  /// otro anuncio la usa (mismo criterio que eliminarAnuncio()).
  Future<void> _limpiarFotoAnterior(String urlAnterior) async {
    try {
      if (!Uri.parse(urlAnterior).pathSegments.contains('anuncios')) return;
      final enUso = await supabase
          .from('anuncios')
          .select('id_anuncio')
          .eq('imagen_url', urlAnterior)
          .limit(1);
      if ((enUso as List).isNotEmpty) return;
      await _storageService.borrarFoto(urlAnterior);
    } catch (_) {
      // Limpieza de mejor esfuerzo: nunca debe romper el guardado.
    }
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;
    final precio =
        double.tryParse(_precioCtrl.text.trim().replaceAll(',', '.'));
    if (precio == null || precio <= 0) return;

    setState(() => _guardando = true);
    try {
      String? urlNueva;
      if (_imagenNueva != null) {
        final uid = supabase.auth.currentUser?.id;
        if (uid == null) throw Exception('SESION_REQUERIDA');
        setState(() => _subiendoImagen = true);
        urlNueva = await _storageService.subirImagenAnuncio(
          archivo: _imagenNueva!,
          uid: uid,
        );
        if (mounted) setState(() => _subiendoImagen = false);
      }

      await _anunciosService.actualizarAnuncioStandalone(
        idAnuncio: _idAnuncio,
        titulo: _tituloCtrl.text,
        texto: _textoCtrl.text,
        precioUsd: precio,
        whatsapp: _whatsappCtrl.text,
        imagenUrl: urlNueva,
      );

      final anterior = _imagenActual;
      if (urlNueva != null && anterior != null && anterior != urlNueva) {
        await _limpiarFotoAnterior(anterior);
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensajeError(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
          _subiendoImagen = false;
        });
      }
    }
  }

  Widget _vistaImagen() {
    final radius = BorderRadius.circular(16);
    Widget contenido;
    if (_imagenNueva != null) {
      contenido = Image.file(_imagenNueva!, fit: BoxFit.cover);
    } else if (_imagenActual != null) {
      contenido = Image.network(
        _imagenActual!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderImagen(),
      );
    } else {
      contenido = _placeholderImagen();
    }
    return ClipRRect(
      borderRadius: radius,
      child: AspectRatio(aspectRatio: 16 / 8, child: contenido),
    );
  }

  Widget _placeholderImagen() => Container(
        color: AppColors.primary.withOpacity(0.10),
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined,
            size: 36, color: AppColors.primary),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar anuncio'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _guardando ? null : () => Navigator.of(context).pop(false),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _vistaImagen(),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _guardando ? null : _elegirImagen,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(_imagenNueva == null
                    ? 'Cambiar imagen'
                    : 'Elegir otra imagen'),
              ),
            ),
            const SizedBox(height: 16),
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
                  TextFormField(
                    controller: _precioCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.plusJakartaSans(color: _colorTexto),
                    decoration: _decoracion(
                        'Precio en USD (ej: 120)', Icons.attach_money_rounded),
                    validator: (v) {
                      final n = double.tryParse(
                          (v ?? '').trim().replaceAll(',', '.'));
                      if (n == null || n <= 0) {
                        return 'Pon un precio mayor a 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _whatsappCtrl,
                    keyboardType: TextInputType.phone,
                    maxLength: 15,
                    style: GoogleFonts.plusJakartaSans(color: _colorTexto),
                    decoration: _decoracion('Tu WhatsApp (ej: 584120000000)',
                        Icons.phone_android_rounded),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Requerido para recibir "Me interesa"'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _guardando ? null : _guardar,
                    icon: _guardando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_rounded, size: 20),
                    label: Text(_subiendoImagen
                        ? 'Subiendo imagen...'
                        : (_guardando ? 'Guardando...' : 'Guardar cambios')),
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
