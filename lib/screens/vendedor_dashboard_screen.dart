import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../services/tiendas_service.dart';
import '../widgets/analytics_widgets.dart';

class VendedorDashboardScreen extends StatefulWidget {
  final String? idTienda;
  const VendedorDashboardScreen({super.key, this.idTienda});

  @override
  State<VendedorDashboardScreen> createState() =>
      _VendedorDashboardScreenState();
}

class _VendedorDashboardScreenState extends State<VendedorDashboardScreen> {
  final _tiendasService = TiendasService();

  RangoAnalitica _rango = RangoAnalitica.mes;

  Map<String, dynamic>? _resumen;
  List<Map<String, dynamic>>? _pedidos;
  List<Map<String, dynamic>>? _productos;
  List<Map<String, dynamic>>? _valoraciones;
  List<Map<String, dynamic>>? _ingresosSerie;
  // Inventario: NO depende del rango semana/mes/histórico -- es el
  // estado real de la tienda en este momento, así que se carga una
  // sola vez (se refresca con el pull-to-refresh, igual que el resto).
  Map<String, dynamic>? _inventario;
  bool _cargando = true;
  String? _error;

  bool get _esOscuro => Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    final idTienda = widget.idTienda;
    if (idTienda == null) {
      setState(() => _cargando = false);
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resumen =
          await _tiendasService.vendedorResumenPeriodo(idTienda, _rango);
      final pedidos =
          await _tiendasService.vendedorPedidosPeriodo(idTienda, _rango);
      final productos = await _tiendasService.vendedorRankingProductosPeriodo(
          idTienda, _rango);
      final valoraciones = await _tiendasService.vendedorValoraciones(idTienda);
      final ingresosSerie =
          await _tiendasService.vendedorIngresosSerie(idTienda, _rango);
      final inventario =
          await _tiendasService.vendedorInventarioActual(idTienda);
      if (mounted) {
        setState(() {
          _resumen = resumen;
          _pedidos = pedidos;
          _productos = productos;
          _valoraciones = valoraciones;
          _ingresosSerie = ingresosSerie;
          _inventario = inventario;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = e.toString();
        });
      }
    }
  }

  void _cambiarRango(RangoAnalitica r) {
    if (r == _rango) return;
    setState(() => _rango = r);
    _cargarTodo();
  }

  // -----------------------------------------------------------------
  // Derivados calculados en el cliente a partir de datos YA reales
  // que traen los RPC -- no son estimaciones, son agregaciones sobre
  // los mismos pedidos/productos del período que ya se están mostrando.
  // -----------------------------------------------------------------
  int get _clientesUnicos {
    final pedidos = _pedidos ?? [];
    final ids = pedidos
        .map((p) => p['comprador_email'] ?? p['id_comprador'])
        .where((v) => v != null)
        .toSet();
    return ids.length;
  }

  int get _unidadesVendidas {
    final productos = _productos ?? [];
    return productos.fold<int>(
        0, (acc, p) => acc + ((p['veces_vendido'] as num?)?.toInt() ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Mis Ventas'),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: _cargarTodo,
          ),
        ],
      ),
      body: widget.idTienda == null
          ? const Center(child: Text('No se encontró la tienda'))
          : _cargando
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _buildError()
                  : Stack(
                      children: [
                        // ---- Fondo con manchas de color suaves: sin
                        // esto, el BackdropFilter de las tarjetas de
                        // vidrio no tiene nada que difuminar y el
                        // efecto no se nota. ----
                        _fondoDecorativo(),
                        RefreshIndicator(
                          onRefresh: _cargarTodo,
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              SelectorRango(
                                  seleccionado: _rango,
                                  onChanged: _cambiarRango),
                              const SizedBox(height: 16),
                              _buildKpis(),
                              const SizedBox(height: 14),
                              _seccionVidrio(
                                titulo: 'Ingresos',
                                icono: Icons.show_chart_rounded,
                                child: GraficaSerie(
                                  datos: (_ingresosSerie ?? [])
                                      .map((m) => PuntoSerie(
                                          (m['etiqueta'] ?? '') as String,
                                          ((m['valor'] as num?) ?? 0)
                                              .toDouble()))
                                      .toList(),
                                ),
                              ),
                              const SizedBox(height: 14),
                              _seccionVidrio(
                                titulo: 'Inventario en tiempo real',
                                icono: Icons.inventory_2_rounded,
                                child: _buildInventario(),
                              ),
                              const SizedBox(height: 14),
                              _seccionVidrio(
                                titulo: 'Productos',
                                icono: Icons.category_rounded,
                                child: RankingProductos(
                                    productos: _productos ?? []),
                              ),
                              const SizedBox(height: 14),
                              _seccionVidrio(
                                titulo: 'Pedidos del período',
                                icono: Icons.receipt_long_rounded,
                                child: _buildPedidos(),
                              ),
                              const SizedBox(height: 14),
                              _seccionVidrio(
                                titulo: 'Valoraciones',
                                icono: Icons.star_rounded,
                                child: _buildValoraciones(),
                              ),
                              const SizedBox(height: 88),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }

  // -----------------------------------------------------------------
  // Fondo decorativo: dos manchas de color muy difusas y de baja
  // opacidad, ancladas a esquinas opuestas -- dan profundidad detrás
  // de las tarjetas de vidrio sin distraer del contenido. Se adaptan
  // de intensidad entre modo claro/oscuro.
  // -----------------------------------------------------------------
  Widget _fondoDecorativo() {
    final esOscuro = _esOscuro;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -60,
              right: -60,
              child: _mancha(
                  220, AppColors.primary.withOpacity(esOscuro ? 0.16 : 0.10)),
            ),
            Positioned(
              bottom: 40,
              left: -80,
              child: _mancha(
                  260, AppColors.warm.withOpacity(esOscuro ? 0.12 : 0.08)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mancha(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
      ),
    );
  }

  // -----------------------------------------------------------------
  // Envoltorio "vidrio flotante": blur + opacidad translúcida + borde
  // suave. Reemplaza a SeccionAnalitica (tarjeta sólida) solo en esta
  // pantalla -- los demás dashboards (admin/comprador/afiliado) no se
  // tocan.
  // -----------------------------------------------------------------
  Widget _seccionVidrio({
    required String titulo,
    IconData? icono,
    required Widget child,
    Widget? accion,
  }) {
    final esOscuro = _esOscuro;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(esOscuro ? 0.06 : 0.55),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withOpacity(esOscuro ? 0.09 : 0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(esOscuro ? 0.35 : 0.05),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icono != null) ...[
                    Icon(icono, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      titulo,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: esOscuro ? Colors.white : AppColors.inkLight,
                      ),
                    ),
                  ),
                  if (accion != null) accion,
                ],
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 40, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text('No se pudieron cargar las analíticas',
                textAlign: TextAlign.center,
                style:
                    GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _esOscuro
                        ? AppColors.inkSecundarioDark
                        : AppColors.inkSecundarioLight)),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _cargarTodo, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  // KPIs -- vidrio + grid de 2 columnas. Se agregaron "Clientes
  // únicos" y "Unidades vendidas" (calculados de datos reales que ya
  // trae el período, sin RPC nuevo).
  // -----------------------------------------------------------------
  Widget _buildKpis() {
    final r = _resumen ?? {};
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.35,
      children: [
        _kpiVidrio(
          label: 'Ingresos',
          value: '\$${((r['ingresos'] as num?) ?? 0).toStringAsFixed(2)}',
          icon: Icons.attach_money_rounded,
          variacionPct: (r['variacion_ingresos_pct'] as num?)?.toDouble(),
          color: AppColors.primary,
        ),
        _kpiVidrio(
          label: 'Pedidos',
          value: '${(r['pedidos'] as num?) ?? 0}',
          icon: Icons.shopping_bag_rounded,
          variacionPct: (r['variacion_pedidos_pct'] as num?)?.toDouble(),
          color: AppColors.warm,
        ),
        _kpiVidrio(
          label: 'Ticket promedio',
          value:
              '\$${((r['ticket_promedio'] as num?) ?? 0).toStringAsFixed(2)}',
          icon: Icons.receipt_rounded,
          color: AppColors.success,
        ),
        _kpiVidrio(
          label: 'Calificación',
          value:
              '${((r['calificacion_promedio'] as num?) ?? 0).toStringAsFixed(1)} ⭐',
          icon: Icons.star_rounded,
          color: Colors.amber.shade700,
        ),
        _kpiVidrio(
          label: 'Clientes únicos',
          value: '$_clientesUnicos',
          icon: Icons.people_alt_rounded,
          color: AppColors.primary,
        ),
        _kpiVidrio(
          label: 'Unidades vendidas',
          value: '$_unidadesVendidas',
          icon: Icons.local_shipping_rounded,
          color: AppColors.success,
        ),
      ],
    );
  }

  Widget _kpiVidrio({
    required String label,
    required String value,
    required IconData icon,
    double? variacionPct,
    required Color color,
  }) {
    final esOscuro = _esOscuro;
    final subiendo = (variacionPct ?? 0) >= 0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(esOscuro ? 0.06 : 0.55),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: Colors.white.withOpacity(esOscuro ? 0.09 : 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 14, color: color),
                  ),
                  const Spacer(),
                  if (variacionPct != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (subiendo ? AppColors.success : Colors.redAccent)
                            .withOpacity(0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            subiendo
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 10,
                            color:
                                subiendo ? AppColors.success : Colors.redAccent,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${variacionPct.abs().toStringAsFixed(0)}%',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: subiendo
                                  ? AppColors.success
                                  : Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: esOscuro ? Colors.white : AppColors.inkLight,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  color: esOscuro
                      ? AppColors.inkSecundarioDark
                      : AppColors.inkSecundarioLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  // INVENTARIO -- datos reales de la tabla `productos`, en tiempo
  // real (no depende del selector de rango semana/mes/histórico).
  // -----------------------------------------------------------------
  Widget _buildInventario() {
    final esOscuro = _esOscuro;
    final inv = _inventario ?? {};
    final totalProductos = (inv['total_productos'] as int?) ?? 0;
    final unidades = (inv['unidades_totales'] as int?) ?? 0;
    final valorTotal = (inv['valor_total_usd'] as num?)?.toDouble() ?? 0;
    final sinStock = (inv['sin_stock'] as int?) ?? 0;
    final bajoStock = (inv['bajo_stock'] as int?) ?? 0;
    final limite = inv['limite_productos'] as int?;
    final porCategoria =
        List<Map<String, dynamic>>.from(inv['por_categoria'] ?? []);

    final colorTexto =
        esOscuro ? AppColors.inkSecundarioDark : AppColors.inkSecundarioLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _miniStat(
                'Valor del inventario',
                '\$${valorTotal.toStringAsFixed(2)}',
                Icons.payments_rounded,
                AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _miniStat(
                'Unidades en stock',
                '$unidades',
                Icons.widgets_rounded,
                AppColors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _miniStat(
                'Sin stock',
                '$sinStock',
                Icons.remove_shopping_cart_rounded,
                Colors.redAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _miniStat(
                'Stock bajo (<10)',
                '$bajoStock',
                Icons.warning_amber_rounded,
                Colors.orange,
              ),
            ),
          ],
        ),
        if (limite != null && limite > 0) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Uso del plan',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: esOscuro ? Colors.white : AppColors.inkLight)),
              Text('$totalProductos / $limite productos',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5, color: colorTexto)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (totalProductos / limite).clamp(0, 1).toDouble(),
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(esOscuro ? 0.08 : 0.4),
              color: (totalProductos / limite) >= 0.9
                  ? Colors.orange
                  : AppColors.primary,
            ),
          ),
        ],
        if (porCategoria.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('Por categoría',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: esOscuro ? Colors.white : AppColors.inkLight)),
          const SizedBox(height: 8),
          ...porCategoria.take(6).map((c) {
            final categoria = c['categoria'] as String? ?? '';
            final cantidad = (c['cantidad'] as int?) ?? 0;
            final proporcion =
                totalProductos == 0 ? 0.0 : cantidad / totalProductos;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 108,
                    child: Text(categoria,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5, color: colorTexto)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: proporcion,
                        minHeight: 7,
                        backgroundColor:
                            Colors.white.withOpacity(esOscuro ? 0.08 : 0.4),
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 22,
                    child: Text('$cantidad',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color:
                                esOscuro ? Colors.white : AppColors.inkLight)),
                  ),
                ],
              ),
            );
          }),
        ],
        if (totalProductos == 0) ...[
          const SizedBox(height: 4),
          Text('Todavía no tienes productos publicados.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5, color: colorTexto)),
        ],
      ],
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    final esOscuro = _esOscuro;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(esOscuro ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: esOscuro ? Colors.white : AppColors.inkLight)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        color: esOscuro
                            ? AppColors.inkSecundarioDark
                            : AppColors.inkSecundarioLight)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPedidos() {
    final pedidos = _pedidos ?? [];
    if (pedidos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('Sin pedidos en este período',
            style: GoogleFonts.plusJakartaSans(
                color: _esOscuro
                    ? AppColors.inkSecundarioDark
                    : AppColors.inkSecundarioLight)),
      );
    }
    return Column(
      children: pedidos
          .map((p) => PedidoTile(
                pedido: p,
                onTap: () => mostrarDetallePedido(context, p),
              ))
          .toList(),
    );
  }

  // -----------------------------------------------------------------
  // VALORACIONES -- se agrega el histograma 1-5 estrellas encima del
  // listado de comentarios que ya había.
  // -----------------------------------------------------------------
  Widget _buildValoraciones() {
    final esOscuro = _esOscuro;
    final valoraciones = _valoraciones ?? [];
    final colorTexto =
        esOscuro ? AppColors.inkSecundarioDark : AppColors.inkSecundarioLight;
    if (valoraciones.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('Sin valoraciones aún',
            style: GoogleFonts.plusJakartaSans(color: colorTexto)),
      );
    }

    final conteo = List<int>.filled(5, 0);
    for (final v in valoraciones) {
      final e = (v['estrellas'] as num?)?.toInt() ?? 0;
      if (e >= 1 && e <= 5) conteo[e - 1]++;
    }
    final total = valoraciones.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 5; i >= 1; i--)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text('$i★',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          color: esOscuro ? Colors.white : AppColors.inkLight)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : conteo[i - 1] / total,
                      minHeight: 7,
                      backgroundColor:
                          Colors.white.withOpacity(esOscuro ? 0.08 : 0.4),
                      color: AppColors.warm,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 22,
                  child: Text('${conteo[i - 1]}',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5, color: colorTexto)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 10),
        ...valoraciones.map((v) {
          final estrellas = (v['estrellas'] as num?)?.toInt() ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                      estrellas,
                      (j) => const Icon(Icons.star_rounded,
                          size: 14, color: AppColors.warm)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((v['comentario'] ?? '').toString().isNotEmpty)
                        Text(v['comentario'],
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: esOscuro
                                    ? Colors.white
                                    : AppColors.inkLight)),
                      Text(v['comprador_email'] ?? '',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, color: colorTexto)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
