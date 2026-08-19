// cart_screen.dart
//
// Carrito editable: cantidad +/- y eliminar por producto. Al
// "Completar Compra": guarda el pedido en Supabase (dispara el
// trigger de notificación al vendedor automáticamente), vacía el
// carrito de esa tienda, y abre WhatsApp con el desglose + número de
// pedido.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/supabase_client.dart';
import '../core/auth_guard.dart';
import '../services/currency_service.dart';
import '../services/tiendas_service.dart';
import 'store_screen_flow.dart' show CartService;

class CartScreen extends StatefulWidget {
  final String idTienda;
  const CartScreen({super.key, required this.idTienda});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _tiendasService = TiendasService();
  late Future<_CarritoData> _dataFuture;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _dataFuture = _cargarCarrito();
  }

  Future<_CarritoData> _cargarCarrito() async {
    final ids = CartService.instance.productosDeTienda(widget.idTienda);
    if (ids.isEmpty) {
      throw Exception('Carrito vacío');
    }
    final productos =
        await supabase.from('productos').select().inFilter('id_producto', ids);
    final tienda = await supabase
        .from('tiendas')
        .select()
        .eq('id_tienda', widget.idTienda)
        .single();
    return _CarritoData(
      tienda: tienda,
      productos: List<Map<String, dynamic>>.from(productos),
    );
  }

  double _totalUsd(_CarritoData data) {
    double total = 0;
    for (final p in data.productos) {
      final cantidad = CartService.instance.cantidadDe(p['id_producto']);
      total += cantidad * (p['precio_usd'] as num).toDouble();
    }
    return total;
  }

  void _cambiarCantidad(Map<String, dynamic> producto, int delta) {
    final disponible = producto['cantidad_disponible'] ?? 0;
    final actual = CartService.instance.cantidadDe(producto['id_producto']);
    final nueva = (actual + delta).clamp(0, disponible).toInt();
    setState(() {
      CartService.instance
          .setCantidad(producto['id_producto'], widget.idTienda, nueva);
    });
    // Si llegó a 0, el producto desaparece del carrito -> recargamos
    // la lista para que ya no se muestre esa fila.
    if (nueva == 0) {
      setState(() => _dataFuture = _cargarCarrito());
    }
  }

  void _eliminar(String idProducto) {
    setState(() {
      CartService.instance.quitar(idProducto);
      _dataFuture = _cargarCarrito();
    });
  }

  Future<void> _completarPedido(_CarritoData data) async {
    // Sesión requerida para comprar.
    if (!await requireAuth(context)) return;
    if (!mounted) return;

    // Defensa extra: la tienda ya no debería dejar llegar hasta acá al
    // propio dueño (se ocultó "Agregar" en StoreScreen), pero si de
    // todas formas el carrito quedó con productos de su propia tienda
    // (ej. cambió de cuenta con el carrito ya cargado), cortamos acá
    // con un mensaje claro en vez del error crudo de Supabase.
    final uid = supabase.auth.currentUser!.id;
    if (data.tienda['owner_id'] == uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No puedes comprar en tu propia tienda')),
      );
      return;
    }

    final telefono = data.tienda['telefono_whatsapp'];
    if (telefono == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Esta tienda no tiene WhatsApp configurado')),
      );
      return;
    }

    setState(() => _procesando = true);
    try {
      // 1. Armar el detalle línea por línea.
      final detalle = data.productos.map((p) {
        final cantidad = CartService.instance.cantidadDe(p['id_producto']);
        return {
          'id_producto': p['id_producto'],
          'nombre': p['nombre'],
          'cantidad': cantidad,
          'precio_usd': p['precio_usd'],
        };
      }).toList();

      final total = _totalUsd(data);

      // 2. Guardar el pedido en Supabase ANTES de abrir WhatsApp.
      // Esto dispara automáticamente la notificación al vendedor
      // (trigger notificar_nuevo_pedido) y le da al pedido su
      // numero_pedido único.
      final pedidoCreado = await _tiendasService.crearPedido(
        idTienda: widget.idTienda,
        detalle: detalle,
        totalUsd: total,
      );
      final numeroPedido = pedidoCreado['numero_pedido'];

      // 3. Vaciar el carrito de esta tienda: el pedido ya quedó
      // registrado, no debe seguir "flotando" en el carrito local.
      CartService.instance.limpiarTienda(widget.idTienda);

      // 4. Armar el mensaje de WhatsApp con el desglose + número.
      final buffer = StringBuffer();
      buffer.writeln('Hola, quiero completar mi pedido #$numeroPedido:');
      buffer.writeln();
      for (final item in detalle) {
        final cantidad = item['cantidad'] as int;
        final precio = (item['precio_usd'] as num).toDouble();
        final subtotal = cantidad * precio;
        buffer.writeln(
            '- ${item['nombre']}: $cantidad x \$${precio.toStringAsFixed(2)} = \$${subtotal.toStringAsFixed(2)}');
      }
      buffer.writeln();
      buffer.writeln('Total: \$${total.toStringAsFixed(2)} USD');
      buffer.writeln();
      buffer.writeln('Pedido #$numeroPedido');

      final mensaje = Uri.encodeComponent(buffer.toString());
      final url = 'https://wa.me/$telefono?text=$mensaje';
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo completar el pedido: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Carrito de tienda'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: CurrencyToggle()),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: CartService.instance,
        builder: (context, _) {
          return FutureBuilder<_CarritoData>(
            future: _dataFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Tu carrito está vacío'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              final itemsTotal =
                  CartService.instance.totalItemsDeTienda(widget.idTienda);

              return AbsorbPointer(
                absorbing: _procesando,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundImage: data.tienda['logo_url'] != null
                                ? NetworkImage(data.tienda['logo_url'])
                                : null,
                            child: data.tienda['logo_url'] == null
                                ? const Icon(Icons.storefront)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data.tienda['nombre'],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                if (data.tienda['municipio'] != null)
                                  Text(
                                    '${data.tienda['municipio']}',
                                    style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                          Text('$itemsTotal items',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: data.productos.length,
                        itemBuilder: (context, i) {
                          final p = data.productos[i];
                          final cantidad =
                              CartService.instance.cantidadDe(p['id_producto']);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(p['imagen_url'],
                                      width: 56, height: 56, fit: BoxFit.cover),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(p['nombre'],
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      PriceTag(
                                          montoUsd: (p['precio_usd'] as num)
                                              .toDouble()),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                                Icons.remove_circle_outline),
                                            onPressed: () =>
                                                _cambiarCantidad(p, -1),
                                          ),
                                          Text('$cantidad'),
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                                Icons.add_circle_outline),
                                            onPressed: () =>
                                                _cambiarCantidad(p, 1),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () => _eliminar(p['id_producto']),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(color: Colors.black12, blurRadius: 6)
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Subtotal'),
                                PriceTag(montoUsd: _totalUsd(data)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total a pagar',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                PriceTag(
                                  montoUsd: _totalUsd(data),
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.info_outline,
                                    size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'El pago se coordina directamente con el vendedor vía WhatsApp.',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _procesando
                                    ? null
                                    : () => _completarPedido(data),
                                style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.all(16),
                                    backgroundColor: Colors.black),
                                child: _procesando
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Text('Completar Compra'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CarritoData {
  final Map<String, dynamic> tienda;
  final List<Map<String, dynamic>> productos;
  _CarritoData({required this.tienda, required this.productos});
}