import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../services/storage_service.dart';
import '../services/tiendas_service.dart';

class AgregarProductoScreen extends StatefulWidget {
  final String idTienda;
  final String? plan;

  const AgregarProductoScreen({super.key, required this.idTienda, this.plan});

  @override
  State<AgregarProductoScreen> createState() => _AgregarProductoScreenState();
}

class _AgregarProductoScreenState extends State<AgregarProductoScreen> {
  final _storageService = StorageService();
  final _tiendasService = TiendasService();
  final _formKey = GlobalKey<FormState>();

  final _nombreCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _cantidadCtrl = TextEditingController(text: '1');
  String? _categoriaSeleccionada;

  File? _fotoSeleccionada;
  File? _foto2;
  File? _foto3;
  bool _subiendo = false;

  bool get _esPremium => widget.plan == 'premium';

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _precioCtrl.dispose();
    _descripcionCtrl.dispose();
    _cantidadCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirFoto() async {
    final foto = await _storageService.elegirFoto();
    if (foto != null) {
      setState(() => _fotoSeleccionada = foto);
    }
  }

  Future<void> _elegirFoto2() async {
    final foto = await _storageService.elegirFoto();
    if (foto != null) {
      setState(() => _foto2 = foto);
    }
  }

  Future<void> _elegirFoto3() async {
    final foto = await _storageService.elegirFoto();
    if (foto != null) {
      setState(() => _foto3 = foto);
    }
  }

  Future<void> _guardarProducto() async {
    if (_fotoSeleccionada == null) {
      _mostrarError('Debes seleccionar una foto del producto');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _subiendo = true);

    try {
      // 1. Subir la foto principal a Storage
      final url = await _storageService.subirFotoProducto(
        archivo: _fotoSeleccionada!,
        idTienda: widget.idTienda,
      );

      // 1b. Fotos extra: solo tiendas premium pueden subir hasta 3.
      String? url2;
      String? url3;
      if (_esPremium && _foto2 != null) {
        url2 = await _storageService.subirFotoProducto(
          archivo: _foto2!,
          idTienda: widget.idTienda,
        );
      }
      if (_esPremium && _foto3 != null) {
        url3 = await _storageService.subirFotoProducto(
          archivo: _foto3!,
          idTienda: widget.idTienda,
        );
      }

      // 2. Insertar el producto (el backend valida el límite del plan)
      await _tiendasService.crearProducto(
        idTienda: widget.idTienda,
        nombre: _nombreCtrl.text.trim(),
        precioUsd: double.parse(_precioCtrl.text.trim()),
        imagenUrl: url,
        imagenUrl2: url2,
        imagenUrl3: url3,
        descripcion: _descripcionCtrl.text.trim().isEmpty
            ? null
            : _descripcionCtrl.text.trim(),
        cantidadDisponible: int.parse(_cantidadCtrl.text.trim()),
        categoria: _categoriaSeleccionada,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto agregado ✅')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('ERROR REAL: $e');
      // Aquí llega, por ejemplo, el error del trigger:
      // "Límite de 20 productos alcanzado para Plan Basic"
      _mostrarError(_mensajeAmigable(e.toString()));
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  String _mensajeAmigable(String errorCrudo) {
    if (errorCrudo.contains('Límite de')) {
      return 'Llegaste al límite de productos de tu plan. '
          'Mejora a Premium o desactiva algún producto para subir uno nuevo.';
    }
    return 'No se pudo guardar el producto. Intenta de nuevo.';
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.red),
    );
  }

  Widget _selectorFotoChica(
      {required File? foto, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(kCardRadius),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.25),
            width: 1.4,
          ),
        ),
        child: foto == null
            ? Center(
                child: Icon(Icons.add_a_photo_outlined,
                    size: 26, color: AppColors.primary),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(kCardRadius),
                child: Image.file(foto,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo producto')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ---------- Selector de foto ----------
            GestureDetector(
              onTap: _elegirFoto,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(kCardRadius),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.25),
                    width: 1.4,
                  ),
                ),
                child: _fotoSeleccionada == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_a_photo_outlined,
                                size: 40, color: AppColors.primary),
                            const SizedBox(height: 8),
                            Text('Toca para agregar una foto',
                                style: GoogleFonts.plusJakartaSans(
                                    color: AppColors.inkSecundarioLight,
                                    fontSize: 13)),
                          ],
                        ),
                      )
                    : Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(kCardRadius),
                            child: Image.file(_fotoSeleccionada!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Material(
                              color: Colors.black45,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _elegirFoto,
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.edit_outlined,
                                      color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),

            if (_esPremium) ...[
              Text('Fotos extra (opcional, hasta 2 más)',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.ink)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _selectorFotoChica(
                      foto: _foto2,
                      onTap: _elegirFoto2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _selectorFotoChica(
                      foto: _foto3,
                      onTap: _elegirFoto3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],

            Text('Información básica',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.ink)),
            const SizedBox(height: 10),

            TextFormField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre del producto',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _descripcionCtrl,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                hintText: 'Color, tamaño, material, detalles importantes...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _precioCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Precio (USD)',
                      prefixText: '\$ ',
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Precio inválido';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _cantidadCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      helperText: 'En stock',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 0) return 'Inválido';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _categoriaSeleccionada,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Categoría',
              ),
              items: kCategoriasTienda
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(
                          c,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _categoriaSeleccionada = v),
              validator: (v) => v == null ? 'Selecciona una categoría' : null,
            ),
            const SizedBox(height: 28),

            FilledButton(
              onPressed: _subiendo ? null : _guardarProducto,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _subiendo
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Guardar producto'),
            ),
          ],
        ),
      ),
    );
  }
}
