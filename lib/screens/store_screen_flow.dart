// store_screen_flow.dart
//
// REDISEÑO (2026-08):
//   - FIX principal: la portada mostraba `logo_url` (pensado para un
//     círculo chico) estirado como banner ancho -- se veía deformado/
//     pixelado. Ahora usa `imagen_portada` (la que ya sube
//     gestionar_tienda_screen.dart) como banner real, y el logo va
//     superpuesto en círculo abajo-izquierda, mismo patrón visual que
//     GestionarTiendaScreen._buildPortadaYLogo.
//   - Header más compacto: menos capas de sombra, info agrupada en una
//     sola tarjeta (nombre + badges + ubicación + descripción + stats +
//     acciones) en vez de bloques sueltos.
//   - Tarjetas de producto más chicas y simples: sin BackdropFilter
//     (pesado y "ruidoso" visualmente), un botón circular de "agregar
//     rápido" (+1) sobre la foto en vez del selector +/- completo
//     dentro de la tarjeta -- para elegir más de 1 se abre el detalle
//     (ya existía ese modal, ahora es el único camino, más simple).
//   - FIX (2026-08): el botón de compartir (ícono en el AppBar) no
//     hacía nada -- onPressed estaba vacío. Ahora comparte el nombre
//     de la tienda + su link, mismo patrón que ya usa
//     product_detail_modal.dart (_shareTienda). Se guarda una copia de
//     los datos de la tienda (_tiendaCache) apenas carga el
//     FutureBuilder para poder armar el mensaje sin tener que esperar
//     de nuevo a la red al tocar compartir.
//
// PENDIENTE (revisado, no resuelto en este cambio):
//   - No hay forma de ver las reseñas/comentarios de la tienda, solo
//     el promedio de estrellas.
//   - No hay botón directo de WhatsApp para preguntar antes de
//     comprar (solo se abre WhatsApp al completar el pedido).
//   - Sin buscador dentro del catálogo de la tienda (solo orden por
//     precio/relevancia).

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../core/auth_guard.dart';
import '../services/cache_offline_service.dart';
import '../services/currency_service.dart';
import '../services/tiendas_service.dart';
import '../widgets/boton_favorito.dart';

enum _OrdenCatalogo { relevancia, menorPrecio, mayorPrecio }

/// Carrito local en memoria (State Management), TTL 72h según ERS.
/// Aislado por comercio: cada item recuerda a qué tienda pertenece.
class CartService extends ChangeNotifier {
  static final CartService instance = CartService._();
  CartService._();

  final Map<String, Map<String, dynamic>> _items = {};
  DateTime? _createdAt;

  void add(String idProducto, String idTienda, int cantidad) {
    if (cantidad <= 0) return;
    _createdAt ??= DateTime.now();
    final actual = _items[idProducto]?['cantidad'] ?? 0;
    _items[idProducto] = {'idTienda': idTienda, 'cantidad': actual + cantidad};
    notifyListeners();
  }

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

  // FIX (compartir): copia de los datos de la tienda disponible fuera
  // del FutureBuilder, para armar el mensaje de compartir sin
  // depender de que el snapshot todavía tenga datos en pantalla (por
  // ejemplo si se llama desde el ícono del AppBar, que vive fuera del
  // FutureBuilder que pinta el resto del header).
  Map<String, dynamic>? _tiendaCache;

  @override
  void initState() {
    super.initState();
    _tiendaFuture = _cargarTienda();
    _productosFuture = _cargarProductos();
    _ventasFuture = _tiendasService.contarVentasDelMes(widget.idTienda);
  }

  Future<Map<String, dynamic>> _cargarTienda() async {
    try {
      final res = await supabase
          .from('tiendas')
          .select()
          .eq('id_tienda', widget.idTienda)
          .single();
      // OFFLINE: dejamos copia para navegar sin conexión
      CacheOfflineService.instance
          .guardar('tienda_${widget.idTienda}', Map<String, dynamic>.from(res));
      return res;
    } catch (_) {
      final cache = await CacheOfflineService.instance
          .leerMapa('tienda_${widget.idTienda}');
      if (cache != null) return cache;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _cargarProductos() async {
    try {
      final data = await supabase
          .from('productos')
          .select()
          .eq('id_tienda', widget.idTienda)
          .eq('es_visible', true);
      final lista = List<Map<String, dynamic>>.from(data);
      CacheOfflineService.instance
          .guardar('productos_${widget.idTienda}', lista);
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
      return lista;
    } catch (_) {
      // OFFLINE: catálogo visto antes de esta tienda
      return CacheOfflineService.instance
          .leerLista('productos_${widget.idTienda}');
    }
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

  /// FIX (compartir): antes el ícono de compartir del AppBar tenía
  /// onPressed: () {} -- no hacía absolutamente nada al tocarlo. Ahora
  /// arma el mismo tipo de mensaje que ya usa
  /// product_detail_modal.dart (_shareTienda), usando _tiendaCache si
  /// ya cargó, o el snapshot del FutureBuilder como respaldo.
  void _compartirTienda([Map<String, dynamic>? datos]) {
    final t = datos ?? _tiendaCache;
    final nombre = (t?['nombre'] as String?)?.trim();
    final link = 'https://toptrading.app/tienda/${widget.idTienda}';
    if (nombre == null || nombre.isEmpty) {
      // Sin nombre todavía cargado (raro, pero por si acaso): igual
      // compartimos el link, mejor que no hacer nada.
      Share.share('Mira esta tienda en Al Lado: $link');
      return;
    }
    Share.share('Mira la tienda "$nombre" en Al Lado: $link');
  }

  int _cantidad(String idProducto) => _cantidadSeleccionada[idProducto] ?? 0;

  void _cambiarCantidad(String idProducto, int delta, int maxDisponible) {
    setState(() {
      final actual = _cantidad(idProducto);
      final nueva = (actual + delta).clamp(0, maxDisponible).toInt();
      _cantidadSeleccionada[idProducto] = nueva;
    });
  }

  /// Agregado rápido: suma 1 unidad directamente desde la tarjeta, sin
  /// pasar por el detalle. Si el usuario quiere más de 1, abre el
  /// detalle (_abrirDetalleProducto) donde sí hay selector completo.
  void _agregarRapido(Map<String, dynamic> producto) {
    final disponible = (producto['cantidad_disponible'] as num? ?? 0).toInt();
    if (disponible <= 0) return;
    CartService.instance.add(producto['id_producto'], widget.idTienda, 1);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Agregado: ${producto['nombre']}'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
      ),
    );
  }

  void _abrirDetalleProducto(Map<String, dynamic> producto) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _DetalleProductoModal(
        producto: producto,
        onAgregar: (cantidad) {
          CartService.instance
              .add(producto['id_producto'], widget.idTienda, cantidad);
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Agregado: ${cantidad}x ${producto['nombre']}'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 90, left: 16, right: 16),
            ),
          );
        },
      ),
    );
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
        break;
    }
    return lista;
  }

  bool get _esOscuro => Theme.of(context).brightness == Brightness.dark;
  Color get _colorTexto => _esOscuro ? const Color(0xFFF5F5F4) : AppColors.ink;
  Color get _colorTextoSecundario =>
      _esOscuro ? AppColors.inkSecundarioDark : AppColors.inkSecundarioLight;
  Color get _colorSuperficie => _esOscuro
      ? AppColors.cardTransparentDark
      : AppColors.cardTransparentLight;
  Color get _colorBorde =>
      (_esOscuro ? AppColors.borderDark : AppColors.borderLight)
          .withOpacity(0.6);

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                          // FIX: antes onPressed: () {} -- no hacía
                          // nada. Ahora comparte nombre + link de la
                          // tienda (ver _compartirTienda arriba).
                          onPressed: () => _compartirTienda(),
                        ),
                      ),
                    ],
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
                        // Guardamos la copia apenas está disponible,
                        // así el botón de compartir del AppBar (que
                        // vive fuera de este FutureBuilder) ya tiene
                        // el nombre listo sin esperar nada más.
                        _tiendaCache = t;
                        return Column(
                          children: [
                            _buildPortadaYLogo(t, primary),
                            const SizedBox(height: 44),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: _buildTarjetaInfo(t, primary),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Catálogo',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: _colorTexto)),
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
                      if (productos.isEmpty) {
                        return SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Text(
                                  'Esta tienda no tiene productos '
                                  'todavía',
                                  style:
                                      TextStyle(color: _colorTextoSecundario)),
                            ),
                          ),
                        );
                      }
                      return SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.72,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final p = productos[i];
                              final esDestacado = p['id_producto'] ==
                                  widget.productoDestacadoId;
                              return Container(
                                key: esDestacado ? _destacadoKey : null,
                                child: _ProductoCardChica(
                                  producto: p,
                                  destacado: esDestacado,
                                  primary: primary,
                                  colorSuperficie: _colorSuperficie,
                                  colorBorde: _colorBorde,
                                  colorTexto: _colorTexto,
                                  colorTextoSecundario: _colorTextoSecundario,
                                  onTap: () => _abrirDetalleProducto(p),
                                  onAgregarRapido: () => _agregarRapido(p),
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
                            backgroundColor: primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 4,
                          ),
                          onPressed: () async {
                            if (!await requireAuth(context)) return;
                            if (!context.mounted) return;
                            context.push('/carrito/${widget.idTienda}');
                          },
                          child: AnimatedBuilder(
                            animation: CurrencyService.instance,
                            builder: (context, _) => Text(
                              'Ver Carrito (${CurrencyService.instance.formatear(total)})',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
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

  // -----------------------------------------------------------------
  // PORTADA + LOGO -- mismo patrón visual que GestionarTiendaScreen:
  // portada real (imagen_portada) con esquinas redondeadas y sombra
  // "flotante" sutil, logo circular superpuesto abajo-izquierda. Ya
  // NO se usa el logo estirado como banner.
  // -----------------------------------------------------------------
  Widget _buildPortadaYLogo(Map<String, dynamic> t, Color primary) {
    final portada = t['imagen_portada'] as String?;
    final logo = t['logo_url'] as String?;
    final placeholder =
        _esOscuro ? const Color(0xFF2A2A2A) : Colors.grey.shade200;
    final anilloLogo = _esOscuro ? AppColors.surfaceDark : Colors.white;

    return SizedBox(
      height: 200,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(_esOscuro ? 0.35 : 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (portada != null && portada.isNotEmpty)
                      Image.network(portada,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const _PortadaIlustracion())
                    else
                      const _PortadaIlustracion(),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.30),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 32,
            bottom: 0,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: anilloLogo, width: 3.5),
                color: placeholder,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: (logo != null && logo.isNotEmpty)
                    ? Image.network(logo,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.storefront_rounded, color: primary))
                    : Icon(Icons.storefront_rounded, color: primary, size: 30),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------
  // TARJETA DE INFO -- agrupa nombre, badges, ubicación, descripción,
  // stats y acciones en un solo bloque (antes eran varias secciones
  // sueltas apiladas).
  // -----------------------------------------------------------------
  Widget _buildTarjetaInfo(Map<String, dynamic> t, Color primary) {
    final esVip = (t['plan'] as String? ?? '') == 'premium';
    return ClipRRect(
      borderRadius: BorderRadius.circular(kCardRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: _colorSuperficie,
            borderRadius: BorderRadius.circular(kCardRadius),
            border: Border.all(color: _colorBorde),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(t['nombre'] ?? '',
                            style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: _colorTexto)),
                        if (t['estado'] == 'active')
                          _chip(Icons.verified_rounded, 'Verificada',
                              AppColors.success),
                        if (esVip)
                          _chip(Icons.star_rounded, 'VIP',
                              const Color(0xFFD4A017)),
                      ],
                    ),
                  ),
                  BotonFavorito(idTienda: widget.idTienda, size: 24),
                ],
              ),
              if (t['municipio'] != null) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.place_outlined,
                        size: 13, color: _colorTextoSecundario),
                    const SizedBox(width: 4),
                    Text('${t['municipio']}, ${t['provincia'] ?? ''}',
                        style: TextStyle(
                            color: _colorTextoSecundario, fontSize: 12.5)),
                  ],
                ),
              ],
              if ((t['descripcion'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(t['descripcion'],
                    style: TextStyle(
                        color: _colorTexto, fontSize: 13.5, height: 1.4)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  _statPill(
                    icon: Icons.star_rounded,
                    color: const Color(0xFFD4AF37),
                    valor: t['promedio_estrellas'] != null
                        ? (t['promedio_estrellas'] as num).toStringAsFixed(1)
                        : '—',
                  ),
                  const SizedBox(width: 8),
                  if (widget.distanciaKm != null)
                    _statPill(
                      icon: Icons.near_me_rounded,
                      color: primary,
                      valor: '${widget.distanciaKm!.toStringAsFixed(1)} km',
                    ),
                  if (widget.distanciaKm != null) const SizedBox(width: 8),
                  FutureBuilder<int>(
                    future: _ventasFuture,
                    builder: (context, snapshot) => _statPill(
                      icon: Icons.shopping_bag_rounded,
                      color: AppColors.success,
                      valor: snapshot.hasData
                          ? '${snapshot.data}+ ventas'
                          : '— ventas',
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
                  icon: const Icon(Icons.directions_rounded, size: 18),
                  label: const Text('Cómo llegar'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(_esOscuro ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(texto,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _statPill({
    required IconData icon,
    required Color color,
    required String valor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(_esOscuro ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(valor,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _botonToolbar({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: (_esOscuro ? Colors.white : Colors.black).withOpacity(0.06),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: _colorTexto, size: 20),
        ),
      ),
    );
  }
}

/// Tarjeta de producto chica y simple para la grilla: foto, nombre,
/// precio, estado de stock, y un botón circular de agregado rápido.
/// Sin blur ni sombras apiladas -- borde sutil + una sombra suave.
class _ProductoCardChica extends StatelessWidget {
  final Map<String, dynamic> producto;
  final bool destacado;
  final Color primary;
  final Color colorSuperficie;
  final Color colorBorde;
  final Color colorTexto;
  final Color colorTextoSecundario;
  final VoidCallback onTap;
  final VoidCallback onAgregarRapido;

  const _ProductoCardChica({
    required this.producto,
    required this.destacado,
    required this.primary,
    required this.colorSuperficie,
    required this.colorBorde,
    required this.colorTexto,
    required this.colorTextoSecundario,
    required this.onTap,
    required this.onAgregarRapido,
  });

  @override
  Widget build(BuildContext context) {
    final disponible = (producto['cantidad_disponible'] as num? ?? 0).toInt();
    final sinStock = disponible <= 0;
    final bajoStock = !sinStock && disponible < 10;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: colorSuperficie,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: destacado ? primary : colorBorde,
                width: destacado ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        producto['imagen_url'] ?? '',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image_not_supported_outlined,
                              color: Colors.grey),
                        ),
                      ),
                      if (sinStock)
                        Container(
                          color: Colors.black.withOpacity(0.45),
                          alignment: Alignment.center,
                          child: const Text('Agotado',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        )
                      else if (bajoStock)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red.shade600,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('¡Últimas!',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      if (!sinStock)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Material(
                            color: primary,
                            shape: const CircleBorder(),
                            elevation: 2,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onAgregarRapido,
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.add_rounded,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(9, 7, 9, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        producto['nombre'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                            color: colorTexto),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(
                            child: PriceTag(
                              montoUsd:
                                  (producto['precio_usd'] as num).toDouble(),
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700),
                            ),
                          ),
                        ],
                      ),
                      if (bajoStock) ...[
                        const SizedBox(height: 2),
                        Text('Quedan $disponible',
                            style: TextStyle(
                                fontSize: 9.5, color: Colors.red.shade600)),
                      ],
                    ],
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

/// Modal de detalle de producto: carrusel de hasta 3 fotos, precio,
/// descripción, stock y selector de cantidad + agregar al carrito.
class _DetalleProductoModal extends StatefulWidget {
  final Map<String, dynamic> producto;
  final void Function(int cantidad) onAgregar;

  const _DetalleProductoModal({
    required this.producto,
    required this.onAgregar,
  });

  @override
  State<_DetalleProductoModal> createState() => _DetalleProductoModalState();
}

class _DetalleProductoModalState extends State<_DetalleProductoModal> {
  int _cantidad = 0;
  int _paginaFoto = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<String> get _fotos {
    final p = widget.producto;
    return [p['imagen_url'], p['imagen_url_2'], p['imagen_url_3']]
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toList();
  }

  void _compartir() {
    final nombre = widget.producto['nombre'] ?? 'producto';
    final precio = (widget.producto['precio_usd'] as num?)?.toStringAsFixed(2);
    Share.share(
        'Mira este producto: $nombre${precio != null ? ' - \$$precio USD' : ''} en Al Lado 🛍️');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.producto;
    final disponible = p['cantidad_disponible'] ?? 0;
    final sinStock = disponible <= 0;
    final bajoStock = !sinStock && disponible < 10;
    final fotos = _fotos;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 280,
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (i) => setState(() => _paginaFoto = i),
                    itemCount: fotos.isEmpty ? 1 : fotos.length,
                    itemBuilder: (context, i) {
                      if (fotos.isEmpty) {
                        return Container(
                          color: Colors.grey.shade100,
                          child: const Icon(Icons.image_not_supported_outlined,
                              size: 48, color: Colors.grey),
                        );
                      }
                      return Image.network(fotos[i], fit: BoxFit.cover);
                    },
                  ),
                ),
                if (fotos.length > 1)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        fotos.length,
                        (i) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _paginaFoto
                                ? Colors.white
                                : Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.black.withOpacity(0.35),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.share_outlined,
                          color: Colors.white, size: 20),
                      onPressed: _compartir,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['nombre'] ?? '',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  PriceTag(montoUsd: (p['precio_usd'] as num).toDouble()),
                  const SizedBox(height: 4),
                  Text(
                    sinStock
                        ? 'Sin stock disponible'
                        : bajoStock
                            ? '¡Se agota! Quedan $disponible disponibles'
                            : '$disponible disponibles',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: (sinStock || bajoStock)
                            ? Colors.red.shade600
                            : Colors.green.shade700),
                  ),
                  if ((p['descripcion'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Descripción',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(p['descripcion'],
                        style: const TextStyle(fontSize: 14, height: 1.4)),
                  ],
                  const SizedBox(height: 20),
                  if (!sinStock)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: _cantidad > 0
                              ? () => setState(() => _cantidad--)
                              : null,
                        ),
                        Text('$_cantidad',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: _cantidad < disponible
                              ? () => setState(() => _cantidad++)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _cantidad > 0
                                ? () => widget.onAgregar(_cantidad)
                                : null,
                            style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14)),
                            child: const Text('Agregar al carrito'),
                          ),
                        ),
                      ],
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

/// Ilustración vectorial de marca usada como fondo de portada cuando
/// la tienda todavía no subió una imagen_portada propia.
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _tiendaIcono(30, _teal.withOpacity(0.55)),
              const SizedBox(width: 6),
              _tiendaIcono(42, _teal),
              const SizedBox(width: 6),
              _tiendaIcono(34, _teal.withOpacity(0.75)),
            ],
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
}
