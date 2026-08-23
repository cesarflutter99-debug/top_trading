// product_edit_modal.dart
//
// Cambios respecto a la versión anterior:
// 1. Ya no hay campo de texto para pegar la URL de la imagen. Ahora es
//    un selector de foto que usa StorageService.subirFotoProducto()
//    (bucket "productos"), igual que ya usas subirLogoTienda() para
//    el logo.
// 2. Se quitó el switch "Visible en el catálogo". La visibilidad ya
//    no la controla el vendedor a mano: se asume que el producto debe
//    estar visible mientras la tienda tenga un plan activo (eso lo
//    maneja tu lógica de backend, no este modal).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/tiendas_service.dart';
import '../services/storage_service.dart';

class ProductEditModal extends StatefulWidget {
  final Map<String, dynamic> producto;
  // FIX: antes este modal solo dejaba cambiar la foto principal
  // (imagen_url), aunque agregar_producto_screen.dart ya permite subir
  // hasta 3 fotos en tiendas premium (imagen_url_2 / imagen_url_3).
  // Con esPremium en true se muestran los dos selectores extra para
  // poder editarlas también, no solo agregarlas una vez al crear.
  final bool esPremium;
  const ProductEditModal({
    super.key,
    required this.producto,
    this.esPremium = false,
  });

  @override
  State<ProductEditModal> createState() => _ProductEditModalState();
}

class _ProductEditModalState extends State<ProductEditModal> {
  final _tiendasService = TiendasService();
  final _storageService = StorageService();
  final _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descripcionCtrl;
  late final TextEditingController _precioCtrl;
  late final TextEditingController _cantidadCtrl;

  String? _imagenUrlActual; // la que ya tenía el producto
  File? _imagenNueva; // la que el vendedor acaba de elegir (aún sin subir)
  // NUEVO: fotos 2 y 3 -- mismo patrón que la principal (URL actual +
  // archivo nuevo aún sin subir). Solo se muestran/usan si
  // widget.esPremium es true.
  String? _imagenUrl2Actual;
  File? _imagenNueva2;
  String? _imagenUrl3Actual;
  File? _imagenNueva3;
  String? _categoriaSeleccionada;

  bool _guardando = false;
  bool _subiendoImagen = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.producto;
    _nombreCtrl = TextEditingController(text: p['nombre'] ?? '');
    _descripcionCtrl = TextEditingController(text: p['descripcion'] ?? '');
    _precioCtrl = TextEditingController(
        text: (p['precio_usd'] as num?)?.toString() ?? '0');
    // OJO: si aquí sale vacío/0 para productos viejos, es porque la
    // columna se creó con DEFAULT 0 en la migración SQL. Este modal
    // es justo el lugar para corregirlo producto por producto.
    _cantidadCtrl = TextEditingController(
        text: (p['cantidad_disponible'] as num?)?.toString() ?? '0');
    _imagenUrlActual = p['imagen_url'] as String?;
    _imagenUrl2Actual = p['imagen_url_2'] as String?;
    _imagenUrl3Actual = p['imagen_url_3'] as String?;
    _categoriaSeleccionada = p['categoria'] as String?;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descripcionCtrl.dispose();
    _precioCtrl.dispose();
    _cantidadCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirImagen() async {
    final XFile? archivo = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      imageQuality: 80,
    );
    if (archivo == null) return;
    setState(() => _imagenNueva = File(archivo.path));
  }

  Future<void> _elegirImagen2() async {
    final XFile? archivo = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      imageQuality: 80,
    );
    if (archivo == null) return;
    setState(() => _imagenNueva2 = File(archivo.path));
  }

  Future<void> _elegirImagen3() async {
    final XFile? archivo = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      imageQuality: 80,
    );
    if (archivo == null) return;
    setState(() => _imagenNueva3 = File(archivo.path));
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      String? nuevaUrl;
      String? nuevaUrl2;
      String? nuevaUrl3;
      if (_imagenNueva != null ||
          _imagenNueva2 != null ||
          _imagenNueva3 != null) {
        setState(() => _subiendoImagen = true);
        if (_imagenNueva != null) {
          nuevaUrl = await _storageService.subirFotoProducto(
            archivo: _imagenNueva!,
            idTienda: widget.producto['id_tienda'],
          );
        }
        if (_imagenNueva2 != null) {
          nuevaUrl2 = await _storageService.subirFotoProducto(
            archivo: _imagenNueva2!,
            idTienda: widget.producto['id_tienda'],
          );
        }
        if (_imagenNueva3 != null) {
          nuevaUrl3 = await _storageService.subirFotoProducto(
            archivo: _imagenNueva3!,
            idTienda: widget.producto['id_tienda'],
          );
        }
        setState(() => _subiendoImagen = false);
      }

      await _tiendasService.actualizarProducto(
        idProducto: widget.producto['id_producto'],
        nombre: _nombreCtrl.text.trim(),
        descripcion: _descripcionCtrl.text.trim(),
        precioUsd: double.parse(_precioCtrl.text.trim()),
        imagenUrl: nuevaUrl, // null si no cambió -> no se toca ese campo
        imagenUrl2: nuevaUrl2,
        imagenUrl3: nuevaUrl3,
        cantidadDisponible: int.parse(_cantidadCtrl.text.trim()),
        categoria: _categoriaSeleccionada,
        // esVisible ya no se envía: la visibilidad es automática
        // según si el plan de la tienda está activo, no manual.
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: $e');
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
          _subiendoImagen = false;
        });
      }
    }
  }

  Future<void> _eliminar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Seguro que quieres eliminar "${_nombreCtrl.text}"? '
            'Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _guardando = true);
    try {
      await _tiendasService.eliminarProducto(widget.producto['id_producto']);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = 'No se pudo eliminar: $e';
        _guardando = false;
      });
    }
  }

  /// Selector chico de foto extra (2 o 3), mismo estilo que
  /// agregar_producto_screen.dart -- muestra la foto nueva elegida, si
  /// no hay ninguna nueva muestra la que ya tenía el producto, y si no
  /// tenía ninguna muestra el ícono de "agregar foto".
  Widget _selectorFotoChica({
    required String? urlActual,
    required File? archivoNuevo,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
            width: 1.4,
          ),
        ),
        child: archivoNuevo != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(archivoNuevo,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity),
              )
            : (urlActual != null && urlActual.isNotEmpty)
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(urlActual,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => Center(
                              child: Icon(Icons.image_not_supported_outlined,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary),
                            )),
                  )
                : Center(
                    child: Icon(Icons.add_a_photo_outlined,
                        size: 26, color: Theme.of(context).colorScheme.primary),
                  ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Editar producto',
                        style:
                            TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Eliminar producto',
                      onPressed: _guardando ? null : _eliminar,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ---------- Selector de imagen ----------
                Center(
                  child: GestureDetector(
                    onTap: _guardando ? null : _elegirImagen,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: _imagenNueva != null
                              ? Image.file(_imagenNueva!,
                                  width: 140, height: 140, fit: BoxFit.cover)
                              : (_imagenUrlActual != null &&
                                      _imagenUrlActual!.isNotEmpty)
                                  ? Image.network(_imagenUrlActual!,
                                      width: 140, height: 140, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                            width: 140,
                                            height: 140,
                                            color: Colors.grey.shade200,
                                            child: const Icon(
                                                Icons.image_not_supported_outlined),
                                          ))
                                  : Container(
                                      width: 140,
                                      height: 140,
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.image_outlined),
                                    ),
                        ),
                        if (_subiendoImagen)
                          const CircularProgressIndicator()
                        else
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Toca la foto para cambiarla',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ),
                ),

                // ---------- Fotos extra (solo tiendas premium) ----------
                // FIX: esto es lo que faltaba -- antes solo se podían
                // subir al crear el producto (agregar_producto_screen.dart)
                // pero no había forma de cambiarlas después desde acá.
                if (widget.esPremium) ...[
                  const SizedBox(height: 16),
                  Text('Fotos extra (opcional, hasta 2 más)',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _selectorFotoChica(
                          urlActual: _imagenUrl2Actual,
                          archivoNuevo: _imagenNueva2,
                          onTap: _guardando ? null : _elegirImagen2,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _selectorFotoChica(
                          urlActual: _imagenUrl3Actual,
                          archivoNuevo: _imagenNueva3,
                          onTap: _guardando ? null : _elegirImagen3,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),

                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _descripcionCtrl,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _precioCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Precio (USD)'),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          if (n == null || n < 0) return 'Precio inválido';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _cantidadCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Cantidad disponible',
                          helperText: 'Esto es lo que ve el comprador',
                        ),
                        keyboardType: TextInputType.number,
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
                  decoration: const InputDecoration(labelText: 'Categoría'),
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
                  onChanged: (v) =>
                      setState(() => _categoriaSeleccionada = v),
                  validator: (v) =>
                      v == null ? 'Selecciona una categoría' : null,
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _guardando ? null : _guardar,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(14)),
                    child: _guardando
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Guardar cambios'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}