import 'dart:io';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/tiendas_service.dart';

class AgregarProductoScreen extends StatefulWidget {
  final String idTienda;

  const AgregarProductoScreen({super.key, required this.idTienda});

  @override
  State<AgregarProductoScreen> createState() => _AgregarProductoScreenState();
}

class _AgregarProductoScreenState extends State<AgregarProductoScreen> {
  final _storageService = StorageService();
  final _tiendasService = TiendasService();

  final _nombreCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();

  File? _fotoSeleccionada;
  bool _subiendo = false;

  Future<void> _elegirFoto() async {
    final foto = await _storageService.elegirFoto();
    if (foto != null) {
      setState(() => _fotoSeleccionada = foto);
    }
  }

  Future<void> _guardarProducto() async {
    if (_fotoSeleccionada == null) {
      _mostrarError('Debes seleccionar una foto del producto');
      return;
    }
    if (_nombreCtrl.text.trim().isEmpty || _precioCtrl.text.trim().isEmpty) {
      _mostrarError('Completa nombre y precio');
      return;
    }

    setState(() => _subiendo = true);

    try {
      // 1. Subir la foto a Storage
      final url = await _storageService.subirFotoProducto(
        archivo: _fotoSeleccionada!,
        idTienda: widget.idTienda,
      );

      // 2. Insertar el producto (el backend valida el límite del plan)
      await _tiendasService.crearProducto(
        idTienda: widget.idTienda,
        nombre: _nombreCtrl.text.trim(),
        precioUsd: double.parse(_precioCtrl.text.trim()),
        imagenUrl: url,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo producto')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            GestureDetector(
              onTap: _elegirFoto,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _fotoSeleccionada == null
                    ? const Center(
                        child: Icon(Icons.add_a_photo,
                            size: 48, color: Colors.grey))
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child:
                            Image.file(_fotoSeleccionada!, fit: BoxFit.cover),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre del producto',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _precioCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Precio (USD)',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _subiendo ? null : _guardarProducto,
              child: _subiendo
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar producto'),
            ),
          ],
        ),
      ),
    );
  }
}
