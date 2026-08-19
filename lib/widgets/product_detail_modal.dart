// product_detail_modal.dart
//
// Modal único y reutilizable para "Al Lado".
// Se invoca igual desde cualquier pantalla (búsqueda general, vista de
// tienda, ranking semanal, portada mensual, etc.):
//
//   showProductDetailModal(context: context, productId: producto.idProducto);
//
// El contenido se adapta automáticamente según si quien mira es el
// comprador o el dueño del producto (misma regla anti-autoventa que ya
// usan en el resto del sistema: client_id != owner_id).
//
// CAMBIOS: la sección de compra ("Lo quiero") deja elegir cantidad y,
// al añadir al carrito, pregunta "¿Comprar solo este artículo o ver
// los otros artículos de la tienda?":
//   - "Comprar este artículo" -> arma el mensaje del pedido (producto,
//     cantidad, precio, total) y lo abre directo en WhatsApp de esa
//     tienda, sin pasar por CartScreen.
//   - "Ver otros artículos" -> cierra el modal y abre StoreScreen de
//     esa misma tienda (el producto queda en el carrito por si el
//     usuario decide agregar más antes de ir a CartScreen).
// También se puede tocar el nombre de la tienda para ir directo a
// ella sin pasar por el carrito.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../core/supabase_client.dart';
import '../core/auth_guard.dart';
import '../services/currency_service.dart';

/// Modelo mínimo combinando producto + tienda + distancia ya calculada
/// por el motor de búsqueda (Haversine). Si el modal se abre desde un
/// lugar donde no hay distancia (ej. dentro de la propia tienda), pasar null.
class ProductDetailData {
  final String idProducto;
  final String nombre;
  final String? descripcion;
  final double precioUsd;
  final String imagenUrl;
  final int cantidadDisponible;
  final String idTienda;
  final String ownerId;
  final String nombreTienda;
  final String? telefonoWhatsapp;
  final double? distanciaKm;

  ProductDetailData({
    required this.idProducto,
    required this.nombre,
    this.descripcion,
    required this.precioUsd,
    required this.imagenUrl,
    required this.cantidadDisponible,
    required this.idTienda,
    required this.ownerId,
    required this.nombreTienda,
    this.telefonoWhatsapp,
    this.distanciaKm,
  });

  factory ProductDetailData.fromMap(
      Map<String, dynamic> p, Map<String, dynamic> t,
      {double? distanciaKm}) {
    return ProductDetailData(
      idProducto: p['id_producto'],
      nombre: p['nombre'],
      descripcion: p['descripcion'],
      precioUsd: (p['precio_usd'] as num).toDouble(),
      imagenUrl: p['imagen_url'],
      cantidadDisponible: p['cantidad_disponible'] ?? 0,
      idTienda: t['id_tienda'],
      ownerId: t['owner_id'],
      nombreTienda: t['nombre'],
      telefonoWhatsapp: t['telefono_whatsapp'],
      distanciaKm: distanciaKm,
    );
  }
}

/// Punto de entrada único. Llamar SIEMPRE esta función, nunca construir
/// el modal a mano, así garantizamos que se ve igual en toda la app.
Future<void> showProductDetailModal({
  required BuildContext context,
  required String productId,
  double? distanciaKm,
}) async {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ProductDetailModalLoader(
      productId: productId,
      distanciaKm: distanciaKm,
    ),
  );
}

class _ProductDetailModalLoader extends StatelessWidget {
  final String productId;
  final double? distanciaKm;
  const _ProductDetailModalLoader({required this.productId, this.distanciaKm});

  Future<ProductDetailData> _fetch() async {
    final producto = await supabase
        .from('productos')
        .select()
        .eq('id_producto', productId)
        .single();
    final tienda = await supabase
        .from('tiendas')
        .select()
        .eq('id_tienda', producto['id_tienda'])
        .single();
    return ProductDetailData.fromMap(producto, tienda,
        distanciaKm: distanciaKm);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProductDetailData>(
      future: _fetch(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return ProductDetailModal(data: snapshot.data!);
      },
    );
  }
}

class ProductDetailModal extends StatefulWidget {
  final ProductDetailData data;
  const ProductDetailModal({super.key, required this.data});

  @override
  State<ProductDetailModal> createState() => _ProductDetailModalState();
}

class _ProductDetailModalState extends State<ProductDetailModal> {
  bool _isFavorito = false;
  bool _loadingFavorito = true;

  @override
  void initState() {
    super.initState();
    _checkFavorito();
  }

  bool get _esDueno {
    final uid = supabase.auth.currentUser?.id;
    // Misma regla anti-autoventa del resto del sistema: client_id != owner_id.
    return uid != null && uid == widget.data.ownerId;
  }

  Future<void> _checkFavorito() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loadingFavorito = false);
      return;
    }
    final res = await supabase
        .from('favoritos')
        .select()
        .eq('id_usuario', uid)
        .eq('id_tienda', widget.data.idTienda)
        .maybeSingle();
    if (!mounted) return;
    setState(() {
      _isFavorito = res != null;
      _loadingFavorito = false;
    });
  }

  Future<void> _toggleFavorito() async {
    // Invitado (sin sesión): en vez de no hacer nada silenciosamente,
    // lo mandamos a loguearse con Google -- misma regla para toda
    // acción real en la app.
    if (!await requireAuth(context)) return;
    final uid = supabase.auth.currentUser!.id;
    if (_isFavorito) {
      await supabase
          .from('favoritos')
          .delete()
          .eq('id_usuario', uid)
          .eq('id_tienda', widget.data.idTienda);
    } else {
      await supabase.from('favoritos').insert({
        'id_usuario': uid,
        'id_tienda': widget.data.idTienda,
      });
    }
    if (!mounted) return;
    setState(() => _isFavorito = !_isFavorito);
  }

  void _shareTienda() {
    final link = 'https://toptrading.app/tienda/${widget.data.idTienda}';
    Share.share(
      'Mira la tienda "${widget.data.nombreTienda}" en Al Lado: $link',
    );
  }

  /// Ir a la tienda dueña del producto SIN pasar por el carrito (el
  /// usuario solo quiere ver el resto del catálogo). Se usa al tocar
  /// el nombre/fila de la tienda.
  void _verTienda() {
    Navigator.of(context).pop(); // cierra el modal
    context.push('/tienda/${widget.data.idTienda}');
  }

  /// Botón principal del comprador: cierra el modal y va directo a la
  /// tienda, con este producto resaltado (mismo scroll-to-destacado que
  /// ya usa StoreScreen vía `productoDestacadoId`). Ahí es donde el
  /// usuario elige cantidad y agrega al carrito -- ya no se agrega
  /// nada al carrito desde este modal.
  void _verEnTienda() {
    final d = widget.data;
    Navigator.of(context).pop();
    context.push('/tienda/${d.idTienda}?producto=${d.idProducto}');
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final hayStock = d.cantidadDisponible > 0;
    final sinStock = !hayStock;
    final bajoStock = hayStock && d.cantidadDisponible < 10;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Opacity(
                    opacity: sinStock ? 0.5 : 1,
                    child: Image.network(
                      d.imagenUrl,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (sinStock || bajoStock)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.red.shade600,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 1)),
                          ],
                        ),
                        child: Text(
                          sinStock ? 'Agotado' : '¡Se agota!',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(d.nombre,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                const CurrencyToggle(),
              ],
            ),
            const SizedBox(height: 4),
            PriceTag(
                montoUsd: d.precioUsd,
                style: const TextStyle(fontSize: 18, color: Colors.green)),
            if (bajoStock) ...[
              const SizedBox(height: 4),
              Text(
                '¡Se agota! Quedan ${d.cantidadDisponible} unidades',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.red.shade600),
              ),
            ],
            if (d.descripcion != null && d.descripcion!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                d.descripcion!,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),

            // Fila tienda + favorito + compartir (visible para todos).
            // Tocar el nombre/icono de la tienda navega a ella.
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _verTienda,
                    child: Row(
                      children: [
                        const Icon(Icons.storefront, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(d.nombreTienda,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_loadingFavorito)
                  IconButton(
                    icon: Icon(
                      _isFavorito ? Icons.favorite : Icons.favorite_border,
                      color: _isFavorito ? Colors.red : null,
                    ),
                    tooltip: 'Mis tiendas',
                    onPressed: _toggleFavorito,
                  ),
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: 'Compartir tienda',
                  onPressed: _shareTienda,
                ),
              ],
            ),

            // Distancia: solo si viene calculada (rol comprador navegando)
            if (d.distanciaKm != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('${d.distanciaKm!.toStringAsFixed(1)} km de distancia',
                      style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ],

            const SizedBox(height: 20),

            // Zona que cambia según el rol
            if (_esDueno)
              _VendedorInfo(cantidadDisponible: d.cantidadDisponible)
            else if (!hayStock)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: null,
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(14)),
                  child: const Text('Agotado'),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _verEnTienda,
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(14)),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Ver en la tienda'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Vista que ve el vendedor cuando abre el modal de SU PROPIO producto:
/// sin botón de compra, solo info operativa.
class _VendedorInfo extends StatelessWidget {
  final int cantidadDisponible;
  const _VendedorInfo({required this.cantidadDisponible});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined),
          const SizedBox(width: 8),
          Text('Disponibles: $cantidadDisponible unidades'),
          const Spacer(),
          TextButton(
            onPressed: () {
              // Navegar a la pantalla de edición de producto del vendedor.
              Navigator.pop(context);
              // context.push('/vendedor/producto/editar/$idProducto');
            },
            child: const Text('Editar'),
          ),
        ],
      ),
    );
  }
}