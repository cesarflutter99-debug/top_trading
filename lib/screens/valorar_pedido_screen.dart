// valorar_pedido_screen.dart
//
// Pantalla que llega desde la notificación "valorar_servicio" (ver
// notificar_pedido_completado() en SQL: se dispara cuando el vendedor
// marca un pedido como completado). Deja al comprador puntuar 1-5
// estrellas, escribir un comentario opcional y adjuntar una foto
// opcional de evidencia.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/tiendas_service.dart';

class ValorarPedidoScreen extends StatefulWidget {
  final String idPedido;
  final String? idTienda;

  const ValorarPedidoScreen({
    super.key,
    required this.idPedido,
    this.idTienda,
  });

  @override
  State<ValorarPedidoScreen> createState() => _ValorarPedidoScreenState();
}

class _ValorarPedidoScreenState extends State<ValorarPedidoScreen> {
  final _tiendasService = TiendasService();
  final _comentarioCtrl = TextEditingController();

  late Future<_DatosValoracion> _datos;
  int _estrellas = 0;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _datos = _cargarDatos();
  }

  Future<_DatosValoracion> _cargarDatos() async {
    // Chequeo de "ya valorado" primero -- si ya existe, no hace falta
    // ni buscar el nombre de la tienda.
    final yaExiste =
        await _tiendasService.obtenerValoracionDePedido(widget.idPedido);
    if (yaExiste != null) {
      return _DatosValoracion(yaValorado: true, nombreTienda: null);
    }

    String? nombreTienda;
    if (widget.idTienda != null) {
      final tienda = await supabase
          .from('tiendas')
          .select('nombre')
          .eq('id_tienda', widget.idTienda!)
          .maybeSingle();
      nombreTienda = tienda?['nombre'] as String?;
    }
    return _DatosValoracion(yaValorado: false, nombreTienda: nombreTienda);
  }

  Future<void> _enviar() async {
    if (_estrellas == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Toca las estrellas para calificar')),
      );
      return;
    }
    if (widget.idTienda == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se pudo identificar la tienda de este pedido')),
      );
      return;
    }

    setState(() => _enviando = true);
    try {
      await _tiendasService.valorarPedido(
        idPedido: widget.idPedido,
        idTienda: widget.idTienda!,
        estrellas: _estrellas,
        comentario: _comentarioCtrl.text.trim().isEmpty
            ? null
            : _comentarioCtrl.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Gracias por tu valoración! 🎉')),
        );
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/home');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo enviar: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _enviando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Puntúa tu compra')),
      body: FutureBuilder<_DatosValoracion>(
        future: _datos,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final datos = snapshot.data!;

          if (datos.yaValorado) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 56, color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text('Ya valoraste este pedido',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700, fontSize: 18)),
                    const SizedBox(height: 8),
                    Text('¡Gracias por tu tiempo!',
                        style: GoogleFonts.plusJakartaSans(
                            color: AppColors.inkSecundarioLight)),
                  ],
                ),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  datos.nombreTienda != null
                      ? '¿Cómo fue tu compra en "${datos.nombreTienda}"?'
                      : '¿Cómo fue tu compra?',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 24),

                // ---------- Selector de estrellas ----------
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final numero = i + 1;
                    return IconButton(
                      iconSize: 40,
                      onPressed: () => setState(() => _estrellas = numero),
                      icon: Icon(
                        numero <= _estrellas
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: numero <= _estrellas
                            ? AppColors.warm
                            : Colors.grey.shade400,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),

                TextField(
                  controller: _comentarioCtrl,
                  maxLines: 4,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Comentario (opcional)',
                    hintText: 'Cuéntanos cómo fue la atención...',
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _enviando ? null : _enviar,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _enviando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Enviar valoración'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DatosValoracion {
  final bool yaValorado;
  final String? nombreTienda;
  _DatosValoracion({required this.yaValorado, this.nombreTienda});
}
