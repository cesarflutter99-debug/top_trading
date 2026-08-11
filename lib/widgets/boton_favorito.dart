// boton_favorito.dart
//
// Botón de corazón para marcar/desmarcar una tienda como favorita.
// Reutilizable en cualquier pantalla que muestre una tienda (la vista
// de tienda, tarjetas de listado, etc.) -- maneja su propio estado de
// carga y falla en silencio con un SnackBar si algo sale mal.
//
// Uso:
//   BotonFavorito(idTienda: tienda['id_tienda'])

import 'package:flutter/material.dart';
import '../services/tiendas_service.dart';

class BotonFavorito extends StatefulWidget {
  final String idTienda;
  final double size;

  const BotonFavorito({super.key, required this.idTienda, this.size = 24});

  @override
  State<BotonFavorito> createState() => _BotonFavoritoState();
}

class _BotonFavoritoState extends State<BotonFavorito> {
  final _tiendasService = TiendasService();
  bool? _esFavorito;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _cargarEstado();
  }

  Future<void> _cargarEstado() async {
    try {
      final es = await _tiendasService.esFavorito(widget.idTienda);
      if (mounted) setState(() => _esFavorito = es);
    } catch (_) {
      if (mounted) setState(() => _esFavorito = false);
    }
  }

  Future<void> _alternar() async {
    if (_esFavorito == null || _procesando) return;
    setState(() => _procesando = true);
    final eraFavorito = _esFavorito!;
    try {
      if (eraFavorito) {
        await _tiendasService.quitarFavorito(widget.idTienda);
      } else {
        await _tiendasService.agregarFavorito(widget.idTienda);
      }
      if (mounted) setState(() => _esFavorito = !eraFavorito);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar favoritos: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_esFavorito == null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return IconButton(
      onPressed: _procesando ? null : _alternar,
      icon: Icon(
        _esFavorito! ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: _esFavorito! ? Colors.redAccent : null,
        size: widget.size,
      ),
    );
  }
}
