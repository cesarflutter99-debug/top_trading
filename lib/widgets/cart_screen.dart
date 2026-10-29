// cart_screen.dart
//
// Carrito editable: cantidad +/- y eliminar por producto. Al
// "Completar compra": guarda el pedido en Supabase (dispara el
// trigger de notificación al vendedor automáticamente), vacía el
// carrito de esa tienda, y abre WhatsApp con el desglose + número de
// pedido.
//
// REDISEÑO (2026-10): estilo "Mi carrito" (tarjeta de tienda, filas de
// producto con stepper en píldora, resumen y botón principal), en modo
// claro y oscuro con AppColors. La lógica de pedido y de stock no cambia.
//   - NUEVO: botón "Vaciar" (quita todo lo de esta tienda del carrito,
//     con confirmación; no crea ningún pedido).
//   - NUEVO: tocar la tarjeta de la tienda abre la tienda.
//   - Selector de moneda: CurrencyDropdownButton ("USD ⌄").
//   - Avisos arriba con AppToast (antes SnackBar abajo).
//   - El + se detiene en el stock disponible y avisa "Máx. N".

import '../services/tutorial_service.dart';
import '../widgets/coach_marks_widget.dart';
import '../widgets/tour_runner.dart';
import 'tour_anchor.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import 'tour_anchor.dart';
import '../core/supabase_client.dart';
import '../core/auth_guard.dart';
import '../services/currency_service.dart';
import '../services/tiendas_service.dart';
import '../widgets/app_toast.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await TourRunner.mostrarSiNoVisto(
        context,
        clave: TutorialService.claveCarrito,
        titulo: 'Tu carrito',
        pasos: const [
            CoachStep(
              titulo: 'Revisá el total',
              descripcion:
                  'Acá ves cuánto vas a pagar en total. Podés cambiar las '
                  'cantidades con los botones + y −.',
              ancla: TourAnclas.carritoTotal,
            ),
            CoachStep(
              titulo: 'Completá la compra',
              descripcion:
                  'Al confirmar se abre WhatsApp con el pedido ya escrito '
                  'para que lo coordines directo con el vendedor.',
              ancla: TourAnclas.carritoConfirmar,
            ),
        ],
      );
    });
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

  int _disponibleDe(Map<String, dynamic> producto) =>
      (producto['cantidad_disponible'] as num? ?? 0).toInt();

  void _cambiarCantidad(Map<String, dynamic> producto, int delta) {
    final disponible = _disponibleDe(producto);
    final actual = CartService.instance.cantidadDe(producto['id_producto']);
    final tope = disponible < 0 ? 0 : disponible;
    final nueva = (actual + delta).clamp(0, tope).toInt();
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

  /// Quita TODO lo de esta tienda del carrito (no crea ningún pedido).
  Future<void> _vaciar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Vaciar carrito?'),
        content: const Text(
            'Se quitarán todos los productos de este carrito. No se creará ningún pedido.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Vaciar',
                style: TextStyle(color: Color(0xFFFF3B30))),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    CartService.instance.limpiarTienda(widget.idTienda);
    AppToast.info(context, 'Carrito vaciado');
    context.pop();
  }

  /// Abre la tienda. Al volver recargamos el carrito por si el usuario
  /// agregó más productos allá.
  Future<void> _verTienda() async {
    await context.push('/tienda/${widget.idTienda}');
    if (!mounted) return;
    setState(() => _dataFuture = _cargarCarrito());
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
      AppToast.aviso(context, 'No puedes comprar en tu propia tienda');
      return;
    }

    final telefono = data.tienda['telefono_whatsapp'];
    if (telefono == null) {
      AppToast.aviso(context, 'Esta tienda no tiene WhatsApp configurado');
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
        // El pedido puede rechazarse a nivel de base de datos si alguien
        // más se llevó el stock justo antes (trigger reservar_stock_pedido
        // -- RAISE EXCEPTION cuando no alcanza). Ese mensaje ya viene
        // redactado para el usuario ("Sin stock suficiente de..."); se
        // muestra tal cual. Además se refresca la data del carrito para
        // que las cantidades disponibles queden al día.
        AppToast.error(context, _mensajeErrorPedido(e));
        setState(() => _dataFuture = _cargarCarrito());
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  String _mensajeErrorPedido(Object e) {
    if (e is PostgrestException &&
        (e.message.contains('Sin stock suficiente') ||
            e.message.contains('ya no existe'))) {
      return e.message;
    }
    return 'No se pudo completar el pedido. Inténtalo de nuevo.';
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = _Colores.de(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Mi carrito',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          AnimatedBuilder(
            animation: CartService.instance,
            builder: (context, _) {
              final hayItems = CartService.instance
                  .productosDeTienda(widget.idTienda)
                  .isNotEmpty;
              if (!hayItems) return const SizedBox.shrink();
              return TextButton.icon(
                onPressed: _procesando ? null : _vaciar,
                icon: Icon(Icons.delete_outline_rounded,
                    size: 18, color: c.primary),
                label: Text('Vaciar',
                    style: TextStyle(
                        color: c.primary, fontWeight: FontWeight.w700)),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.only(right: 12, left: 4),
            child: Center(child: CurrencyDropdownButton()),
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
                return _estadoVacio(c);
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
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          _tarjetaTienda(data, c),
                          const SizedBox(height: 14),
                          for (final p in data.productos) _filaProducto(p, c),
                        ],
                      ),
                    ),
                    _barraInferior(data, itemsTotal, c),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _estadoVacio(_Colores c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 56, color: c.textoSec),
            const SizedBox(height: 12),
            Text('Tu carrito está vacío',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: c.texto)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Volver a la tienda'),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _decoTarjeta(_Colores c) => BoxDecoration(
        color: c.superficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.borde),
      );

  Widget _tarjetaTienda(_CarritoData data, _Colores c) {
    final t = data.tienda;
    final logo = (t['logo_url'] as String?) ?? '';
    final ubicacion = [t['municipio'], t['provincia']]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .join(', ');

    return Container(
      decoration: _decoTarjeta(c),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _verTienda,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: c.primarioSuave,
                    backgroundImage: logo.isNotEmpty ? NetworkImage(logo) : null,
                    child: logo.isEmpty
                        ? Icon(Icons.storefront, color: c.primary)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${t['nombre'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: c.texto),
                        ),
                        if (ubicacion.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 14, color: c.textoSec),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  ubicacion,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12, color: c.textoSec),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.textoSec),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: c.primarioSuave,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.storefront_outlined, size: 16, color: c.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pedido coordinado directamente con la tienda',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagenPlaceholder(_Colores c) => Container(
        color: c.primarioSuave,
        alignment: Alignment.center,
        child: Icon(Icons.image_not_supported_outlined, color: c.textoSec),
      );

  Widget _filaProducto(Map<String, dynamic> p, _Colores c) {
    final id = p['id_producto'] as String;
    final cantidad = CartService.instance.cantidadDe(id);
    final disponible = _disponibleDe(p);
    final excede = cantidad > disponible;
    final enMaximo = cantidad >= disponible;
    final imagen = (p['imagen_url'] as String?) ?? '';

    String? aviso;
    if (excede) {
      aviso = 'Solo hay $disponible';
    } else if (enMaximo) {
      aviso = 'Máx. $disponible';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: _decoTarjeta(c),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 68,
              height: 68,
              child: imagen.isEmpty
                  ? _imagenPlaceholder(c)
                  : Image.network(
                      imagen,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imagenPlaceholder(c),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p['nombre'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: c.texto),
                ),
                const SizedBox(height: 2),
                PriceTag(montoUsd: (p['precio_usd'] as num).toDouble()),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _stepper(
                      cantidad: cantidad,
                      puedeSumar: !enMaximo,
                      onMenos: () => _cambiarCantidad(p, -1),
                      onMas: () => _cambiarCantidad(p, 1),
                      c: c,
                    ),
                    if (aviso != null) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          aviso,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: excede
                                  ? const Color(0xFFFF3B30)
                                  : Colors.orange.shade800),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline_rounded),
            color: const Color(0xFFFF3B30),
            onPressed: () => _eliminar(id),
          ),
        ],
      ),
    );
  }

  Widget _stepper({
    required int cantidad,
    required bool puedeSumar,
    required VoidCallback onMenos,
    required VoidCallback onMas,
    required _Colores c,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: c.primarioSuave,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _botonStepper(Icons.remove_rounded, onMenos, c),
          SizedBox(
            width: 28,
            child: Text(
              '$cantidad',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: c.texto),
            ),
          ),
          _botonStepper(Icons.add_rounded, puedeSumar ? onMas : null, c),
        ],
      ),
    );
  }

  Widget _botonStepper(IconData icono, VoidCallback? onTap, _Colores c) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(icono,
            size: 18,
            color: onTap == null ? c.textoSec.withOpacity(0.5) : c.primary),
      ),
    );
  }

  Widget _barraInferior(_CarritoData data, int itemsTotal, _Colores c) {
    final total = _totalUsd(data);
    final verde = c.oscuro ? const Color(0xFF4ADE80) : const Color(0xFF15803D);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: c.superficie,
        border: Border(top: BorderSide(color: c.borde)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(c.oscuro ? 0.35 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Subtotal · $itemsTotal ${itemsTotal == 1 ? 'artículo' : 'artículos'}',
                  style: TextStyle(fontSize: 13.5, color: c.textoSec),
                ),
                PriceTag(
                  montoUsd: total,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: c.texto),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: c.borde),
            ),
            TourAnchor(
              id: TourAnclas.carritoTotal,
              child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total estimado',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: c.texto)),
                PriceTag(
                  montoUsd: total,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: verde),
                ),
              ],
            ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: c.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'El pago se coordina directamente con el vendedor vía WhatsApp.',
                    style: TextStyle(fontSize: 11.5, color: c.textoSec),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TourAnchor(
              id: TourAnclas.carritoConfirmar,
              child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _procesando ? null : () => _completarPedido(data),
                style: FilledButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: c.primary.withOpacity(0.5),
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                icon: _procesando
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.chat_rounded, size: 20),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_procesando
                      ? 'Procesando…'
                      : 'Completar compra y continuar por WhatsApp'),
                ),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Colores del carrito según modo claro/oscuro (todo sale de AppColors).
class _Colores {
  final bool oscuro;
  final Color superficie;
  final Color borde;
  final Color texto;
  final Color textoSec;
  final Color primary;
  final Color primarioSuave;

  const _Colores._({
    required this.oscuro,
    required this.superficie,
    required this.borde,
    required this.texto,
    required this.textoSec,
    required this.primary,
    required this.primarioSuave,
  });

  factory _Colores.de(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return _Colores._(
      oscuro: oscuro,
      superficie: oscuro ? AppColors.surfaceDark : AppColors.surfaceLight,
      borde: oscuro ? AppColors.borderDark : AppColors.borderLight,
      texto: oscuro ? AppColors.inkDark : AppColors.inkLight,
      textoSec:
          oscuro ? AppColors.inkSecundarioDark : AppColors.inkSecundarioLight,
      primary: AppColors.primary,
      primarioSuave: AppColors.primary.withOpacity(oscuro ? 0.20 : 0.10),
    );
  }
}

class _CarritoData {
  final Map<String, dynamic> tienda;
  final List<Map<String, dynamic>> productos;
  _CarritoData({required this.tienda, required this.productos});
}
