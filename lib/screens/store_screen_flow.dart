// store_screen_flow.dart
//
// Rediseño según referencia visual: banner + avatar superpuesto,
// stats (rating / cerca / ventas), botón "Cómo llegar", catálogo con
// orden seleccionable, y barra inferior "Ver Carrito" con total en
// vivo. Cantidad de cada producto arranca en 0 -- el botón "Añadir"
// está deshabilitado hasta que el usuario elige una cantidad > 0,
// evitando que se sumen productos sin querer mientras se explora.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/currency_service.dart';
import '../services/tiendas_service.dart';

enum _OrdenCatalogo { relevancia, menorPrecio, mayorPrecio }

/// Carrito local en memoria (State Management), TTL 72h según ERS.
/// Aislado por comercio: cada item recuerda a qué tienda pertenece.
class CartService extends ChangeNotifier {
  static final CartService instance = CartService._();
  CartService._();

  // idProducto -> {idTienda, cantidad}
  final Map<String, Map<String, dynamic>> _items = {};
  DateTime? _createdAt;

  void add(String idProducto, String idTienda, int cantidad) {
    if (cantidad <= 0) return;
    _createdAt ??= DateTime.now();
    final actual = _items[idProducto]?['cantidad'] ?? 0;
    _items[idProducto] = {'idTienda': idTienda, 'cantidad': actual + cantidad};
    notifyListeners();
  }

  /// Fija la cantidad exacta de un item (usado en CartScreen al editar
  /// con +/-). Si llega a 0, el producto se quita del carrito.
  void setCantidad(String idProducto, String idTienda, int cantidad) {
    if (cantidad <= 0) {
      _items.remove(idProducto);
    } else {
      _items[idProducto] = {'idTienda': idTienda, 'cantidad': cantidad};
    }
    notifyListeners();
  }

  void quitar(String idProducto) {
    _items.remove(idProducto);
    notifyListeners();
  }

  /// Vacía todos los items de una tienda puntual (se usa al completar
  /// la compra: ese pedido ya quedó registrado, no debe seguir en el
  /// carrito).
  void limpiarTienda(String idTienda) {
    _items.removeWhere((_, v) => v['idTienda'] == idTienda);
    notifyListeners();
  }

  List<String> productosDeTienda(String idTienda) => _items.entries
      .where((e) => e.value['idTienda'] == idTienda)
      .map((e) => e.key)
      .toList();

  int cantidadDe(String idProducto) => _items[idProducto]?['cantidad'] ?? 0;

  int totalItemsDeTienda(String idTienda) => _items.entries
      .where((e) => e.value['idTienda'] == idTienda)
      .fold(0, (a, e) => a + (e.value['cantidad'] as int));

  int get totalItems =>
      _items.values.fold(0, (a, b) => a + (b['cantidad'] as int));
}

class StoreScreen extends StatefulWidget {
  final String idTienda;
  final String? productoDestacadoId;
  final double? distanciaKm;
  const StoreScreen({
    super.key,
    required this.idTienda,
    this.productoDestacadoId,
    this.distanciaKm,
  });

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final _tiendasService = TiendasService();

  late Future<Map<String, dynamic>> _tiendaFuture;
  late Future<List<Map<String, dynamic>>> _productosFuture;
  late Future<int> _ventasFuture;

  final Map<String, int> _cantidadSeleccionada = {};
  final GlobalKey _destacadoKey = GlobalKey();
  _OrdenCatalogo _orden = _OrdenCatalogo.relevancia;

  bool _esFavorita = false;
  bool _cargandoFavorito = true;

  @override
  void initState() {
    super.initState();
    _tiendaFuture = _cargarTienda();
    _productosFuture = _cargarProductos();
    _ventasFuture = _tiendasService.contarVentasDelMes(widget.idTienda);
    _checkFavorito();
  }

  Future<Map<String, dynamic>> _cargarTienda() async {
    return await supabase
        .from('tiendas')
        .select()
        .eq('id_tienda', widget.idTienda)
        .single();
  }

  Future<List<Map<String, dynamic>>> _cargarProductos() async {
    final data = await supabase
        .from('productos')
        .select()
        .eq('id_tienda', widget.idTienda)
        .eq('es_visible', true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.productoDestacadoId != null &&
          _destacadoKey.currentContext != null) {
        Scrollable.ensureVisible(
          _destacadoKey.currentContext!,
          duration: const Duration(milliseconds: 400),
          alignment: 0.1,
        );
      }
    });
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> _checkFavorito() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      setState(() => _cargandoFavorito = false);
      return;
    }
    final res = await supabase
        .from('favoritos')
        .select()
        .eq('id_usuario', uid)
        .eq('id_tienda', widget.idTienda)
        .maybeSingle();
    if (!mounted) return;
    setState(() {
      _esFavorita = res != null;
      _cargandoFavorito = false;
    });
  }

  Future<void> _toggleFavorito() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    if (_esFavorita) {
      await supabase
          .from('favoritos')
          .delete()
          .eq('id_usuario', uid)
          .eq('id_tienda', widget.idTienda);
    } else {
      await supabase.from('favoritos').insert({
        'id_usuario': uid,
        'id_tienda': widget.idTienda,
      });
    }
    if (!mounted) return;
    setState(() => _esFavorita = !_esFavorita);
  }

  Future<void> _comoLlegar(double? lat, double? lon) async {
    if (lat == null || lon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Esta tienda no tiene ubicación registrada')),
      );
      return;
    }
    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lon';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  int _cantidad(String idProducto) => _cantidadSeleccionada[idProducto] ?? 0;

  void _cambiarCantidad(String idProducto, int delta, int maxDisponible) {
    setState(() {
      final actual = _cantidad(idProducto);
      final nueva = (actual + delta).clamp(0, maxDisponible).toInt();
      _cantidadSeleccionada[idProducto] = nueva;
    });
  }

  void _agregarAlCarrito(Map<String, dynamic> producto) {
    final cantidad = _cantidad(producto['id_producto']);
    if (cantidad <= 0) return;
    CartService.instance
        .add(producto['id_producto'], widget.idTienda, cantidad);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Agregado: ${cantidad}x ${producto['nombre']}'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        // La barra "Ver Carrito" queda fija en bottom:16 y ocupa unos
        // ~64px de alto -- este margen levanta el SnackBar por encima
        // de ella en vez de superponerse (siempre va a estar visible
        // en este punto, ya que acabamos de agregar un producto).
        margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
      ),
    );
    // Reseteamos el selector de ESE producto a 0, listo para la
    // siguiente decisión del usuario -- ya quedó guardado en el carrito.
    setState(() => _cantidadSeleccionada[producto['id_producto']] = 0);
  }

  List<Map<String, dynamic>> _ordenar(List<Map<String, dynamic>> productos) {
    final lista = List<Map<String, dynamic>>.from(productos);
    switch (_orden) {
      case _OrdenCatalogo.menorPrecio:
        lista.sort((a, b) =>
            (a['precio_usd'] as num).compareTo(b['precio_usd'] as num));
        break;
      case _OrdenCatalogo.mayorPrecio:
        lista.sort((a, b) =>
            (b['precio_usd'] as num).compareTo(a['precio_usd'] as num));
        break;
      case _OrdenCatalogo.relevancia:
        break; // orden natural que devuelve la query
    }
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: AnimatedBuilder(
        animation: CartService.instance,
        builder: (context, _) {
          final totalItemsTienda =
              CartService.instance.totalItemsDeTienda(widget.idTienda);
          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    backgroundColor: AppColors.backgroundLight,
                    elevation: 0,
                    scrolledUnderElevation: 1,
                    surfaceTintColor: Colors.transparent,
                    leading: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _botonToolbar(
                        icon: Icons.arrow_back_rounded,
                        onPressed: () => context.pop(),
                      ),
                    ),
                    actions: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: _botonToolbar(
                          icon: Icons.share_outlined,
                          onPressed: () {},
                        ),
                      ),
                    ],
                  ),
                  // ---------- Tarjeta de foto flotante ----------
                  // Ya no es un banner borde a borde: es una tarjeta
                  // independiente con margen, esquinas redondeadas y
                  // sombra propia -- el efecto "flotando" real, en vez
                  // de intentar fundir una foto edge-to-edge con el
                  // fondo con un degradado parche.
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Container(
                        height: 220,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            // Sombra de contacto: cercana y definida,
                            // simula dónde "tocaría" la tarjeta si
                            // estuviera apoyada.
                            BoxShadow(
                              color: Colors.black.withOpacity(0.10),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                            // Sombra ambiental: amplia, muy difusa y con
                            // spread negativo (más chica que la caja) --
                            // es lo que realmente vende el efecto
                            // "flotando", en vez de un cuadro plano con
                            // borde oscuro.
                            BoxShadow(
                              color: Colors.black.withOpacity(0.12),
                              blurRadius: 32,
                              offset: const Offset(0, 18),
                              spreadRadius: -6,
                            ),
                            // Toque de color de marca, muy sutil -- evita
                            // que la sombra se vea gris/genérica y la
                            // ata visualmente a la paleta de la app.
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.10),
                              blurRadius: 40,
                              offset: const Offset(0, 22),
                              spreadRadius: -10,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: FutureBuilder<Map<String, dynamic>>(
                            future: _tiendaFuture,
                            builder: (context, snapshot) {
                              final t = snapshot.data;
                              final fotoPerfil = t?['logo_url'] as String?;
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  (fotoPerfil != null && fotoPerfil.isNotEmpty)
                                      ? Image.network(
                                          fotoPerfil,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const _PortadaIlustracion(),
                                        )
                                      : const _PortadaIlustracion(),
                                  // Brillo superior sutil -- simula luz
                                  // tocando la tarjeta, refuerza la
                                  // sensación de superficie elevada.
                                  const DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Color(0x26FFFFFF),
                                          Colors.transparent,
                                        ],
                                        stops: [0, 0.25],
                                      ),
                                    ),
                                  ),
                                  // Degradado decorativo inferior -- le da
                                  // profundidad a la tarjeta incluso sin
                                  // texto encima (ya no hace falta para
                                  // legibilidad, el nombre vive abajo).
                                  const DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.transparent,
                                          Color(0x3D000000),
                                        ],
                                        stops: [0, 0.6, 1],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: FutureBuilder<Map<String, dynamic>>(
                      future: _tiendaFuture,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final t = snapshot.data!;
                        final esVip = (t['plan'] as String? ?? '') == 'premium';
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          t['nombre'] ?? '',
                                          style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        if (t['estado'] == 'active')
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.verified,
                                                    size: 14,
                                                    color:
                                                        Colors.green.shade700),
                                                const SizedBox(width: 3),
                                                Text('Verificada',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .green.shade700)),
                                              ],
                                            ),
                                          ),
                                        // VIP se movió acá, junto al
                                        // nombre -- ya no compite con
                                        // la foto de portada.
                                        if (esVip)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 5),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Color(0xFFF7D774),
                                                  Color(0xFFD4A017),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFFD4A017)
                                                      .withOpacity(0.35),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.star_rounded,
                                                    size: 12,
                                                    color: Colors.white),
                                                SizedBox(width: 4),
                                                Text('TIENDA VIP',
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w800)),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Favorito -- se movió acá desde el
                                  // banner, junto al nombre.
                                  if (!_cargandoFavorito)
                                    IconButton(
                                      icon: Icon(
                                        _esFavorita
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_border_rounded,
                                        color: _esFavorita
                                            ? Colors.redAccent
                                            : AppColors.inkSecundarioLight,
                                      ),
                                      onPressed: _toggleFavorito,
                                    ),
                                ],
                              ),
                              if (t['municipio'] != null)
                                Text(
                                  '${t['municipio']}, ${t['provincia'] ?? ''}',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13),
                                ),
                              if ((t['descripcion'] ?? '')
                                  .toString()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  t['descripcion'],
                                  style: const TextStyle(
                                      color: AppColors.ink,
                                      fontSize: 14,
                                      height: 1.4),
                                ),
                              ],
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 12),

                              // Stats: rating / distancia-cerca / ventas
                              Row(
                                children: [
                                  Expanded(
                                    child: _statTile(
                                      valor: t['promedio_estrellas'] != null
                                          ? (t['promedio_estrellas'] as num)
                                              .toStringAsFixed(1)
                                          : '-',
                                      etiqueta: 'Puntaje',
                                    ),
                                  ),
                                  Expanded(
                                    child: _statTile(
                                      valor: widget.distanciaKm != null
                                          ? '${widget.distanciaKm!.toStringAsFixed(1)}km'
                                          : 'Cerca',
                                      etiqueta: widget.distanciaKm != null
                                          ? 'Distancia'
                                          : '',
                                    ),
                                  ),
                                  Expanded(
                                    child: FutureBuilder<int>(
                                      future: _ventasFuture,
                                      builder: (context, snapshot) => _statTile(
                                        valor: snapshot.hasData
                                            ? '${snapshot.data}+'
                                            : '-',
                                        etiqueta: 'Ventas (mes)',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => _comoLlegar(
                                    (t['latitud'] as num?)?.toDouble(),
                                    (t['longitud'] as num?)?.toDouble(),
                                  ),
                                  icon: const Icon(Icons.directions_rounded,
                                      size: 18),
                                  label: const Text('Cómo llegar'),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Catálogo',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          DropdownButton<_OrdenCatalogo>(
                            value: _orden,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(
                                value: _OrdenCatalogo.relevancia,
                                child: Text('Más relevantes'),
                              ),
                              DropdownMenuItem(
                                value: _OrdenCatalogo.menorPrecio,
                                child: Text('Menor precio'),
                              ),
                              DropdownMenuItem(
                                value: _OrdenCatalogo.mayorPrecio,
                                child: Text('Mayor precio'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _orden = v ?? _orden),
                          ),
                        ],
                      ),
                    ),
                  ),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _productosFuture,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        );
                      }
                      final productos = _ordenar(snapshot.data!);
                      return SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final p = productos[i];
                              final esDestacado = p['id_producto'] ==
                                  widget.productoDestacadoId;
                              final cantidad = _cantidad(p['id_producto']);
                              final disponible = p['cantidad_disponible'] ?? 0;
                              return Container(
                                key: esDestacado ? _destacadoKey : null,
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: esDestacado
                                        ? primary
                                        : Colors.grey.shade300,
                                    width: esDestacado ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(p['imagen_url'],
                                          width: 64,
                                          height: 64,
                                          fit: BoxFit.cover),
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
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                icon: const Icon(Icons
                                                    .remove_circle_outline),
                                                onPressed: cantidad > 0
                                                    ? () => _cambiarCantidad(
                                                        p['id_producto'],
                                                        -1,
                                                        disponible)
                                                    : null,
                                              ),
                                              Text('$cantidad'),
                                              IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                icon: const Icon(
                                                    Icons.add_circle_outline),
                                                onPressed: cantidad < disponible
                                                    ? () => _cambiarCantidad(
                                                        p['id_producto'],
                                                        1,
                                                        disponible)
                                                    : null,
                                              ),
                                              const Spacer(),
                                              ElevatedButton(
                                                onPressed: cantidad > 0
                                                    ? () => _agregarAlCarrito(p)
                                                    : null,
                                                child: const Text('Añadir'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            childCount: productos.length,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),

              // Barra inferior "Ver Carrito"
              if (totalItemsTienda > 0)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _productosFuture,
                    builder: (context, snapshot) {
                      double total = 0;
                      if (snapshot.hasData) {
                        for (final p in snapshot.data!) {
                          final cant =
                              CartService.instance.cantidadDe(p['id_producto']);
                          total += cant * (p['precio_usd'] as num).toDouble();
                        }
                      }
                      return SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            backgroundColor: Colors.black,
                          ),
                          onPressed: () =>
                              context.push('/carrito/${widget.idTienda}'),
                          child: AnimatedBuilder(
                            animation: CurrencyService.instance,
                            builder: (context, _) => Text(
                              'Ver Carrito (${CurrencyService.instance.formatear(total)})',
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _botonToolbar({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.black.withOpacity(0.05),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: AppColors.ink, size: 20),
        ),
      ),
    );
  }

  Widget _statTile({required String valor, required String etiqueta}) {
    return Column(
      children: [
        Text(valor,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        if (etiqueta.isNotEmpty)
          Text(etiqueta,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }
}

/// Ilustración vectorial de marca (100% Flutter, sin assets externos)
/// usada como fondo de portada cuando la tienda todavía no subió una
/// imagen_portada propia. Iconos de tiendas + carrito + corazón sobre
/// halos difusos en tonos teal, con el wordmark "AlLado" -- son los
/// colores reales del logo (assets), distintos del azul que usa el
/// resto de la interfaz (es la paleta de marca, no la paleta de UI) --
/// se mantiene así a propósito, confirmado con el dueño de la app.
class _PortadaIlustracion extends StatelessWidget {
  const _PortadaIlustracion();

  static const _teal = Color(0xFF2DB6A8);
  static const _tealSoft = Color(0xFF9FE0D8);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF3FBFA), AppColors.backgroundLight],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo difuso detrás de los íconos
          Positioned(
            left: 24,
            top: 10,
            child: _halo(70, _tealSoft.withOpacity(0.35)),
          ),
          Positioned(
            right: 60,
            bottom: 20,
            child: _halo(50, _tealSoft.withOpacity(0.3)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Composición de "tienditas" con íconos lineales
                Expanded(
                  flex: 3,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _tiendaIcono(30, _teal.withOpacity(0.55)),
                          const SizedBox(width: 6),
                          _tiendaIcono(42, _teal),
                          const SizedBox(width: 6),
                          _tiendaIcono(34, _teal.withOpacity(0.75)),
                        ],
                      ),
                      Positioned(
                        top: -6,
                        left: 8,
                        child: _iconoFlotante(
                            Icons.two_wheeler_rounded, 16, _teal),
                      ),
                      Positioned(
                        top: -2,
                        right: 4,
                        child: _iconoFlotante(
                            Icons.favorite_rounded, 14, _teal.withOpacity(0.8)),
                      ),
                      Positioned(
                        bottom: 30,
                        right: -4,
                        child: _iconoFlotante(
                            Icons.shopping_cart_rounded, 15, _teal),
                      ),
                    ],
                  ),
                ),
                // Wordmark "AlLado"
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'AlLado',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: _teal,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Icon(Icons.location_on_outlined, color: _teal, size: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _halo(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
      ),
    );
  }

  Widget _tiendaIcono(double size, Color color) {
    return Container(
      width: size,
      height: size * 0.85,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(Icons.storefront_rounded, color: color, size: size * 0.55),
    );
  }

  Widget _iconoFlotante(IconData icon, double size, Color color) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.25),
            blurRadius: 6,
          ),
        ],
      ),
      child: Icon(icon, size: size, color: color),
    );
  }
}
