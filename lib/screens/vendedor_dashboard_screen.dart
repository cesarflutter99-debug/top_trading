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
  bool _cargando = true;
  String? _error;

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
      if (mounted) {
        setState(() {
          _resumen = resumen;
          _pedidos = pedidos;
          _productos = productos;
          _valoraciones = valoraciones;
          _ingresosSerie = ingresosSerie;
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
                  : RefreshIndicator(
                      onRefresh: _cargarTodo,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          SelectorRango(
                              seleccionado: _rango, onChanged: _cambiarRango),
                          const SizedBox(height: 16),
                          _buildKpis(),
                          const SizedBox(height: 14),
                          SeccionAnalitica(
                            titulo: 'Ingresos',
                            icono: Icons.show_chart_rounded,
                            child: GraficaSerie(
                              datos: (_ingresosSerie ?? [])
                                  .map((m) => PuntoSerie(
                                      (m['etiqueta'] ?? '') as String,
                                      ((m['valor'] as num?) ?? 0).toDouble()))
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SeccionAnalitica(
                            titulo: 'Productos',
                            icono: Icons.inventory_2_outlined,
                            child:
                                RankingProductos(productos: _productos ?? []),
                          ),
                          const SizedBox(height: 14),
                          SeccionAnalitica(
                            titulo: 'Pedidos del período',
                            icono: Icons.receipt_long_outlined,
                            child: _buildPedidos(),
                          ),
                          const SizedBox(height: 14),
                          SeccionAnalitica(
                            titulo: 'Valoraciones',
                            icono: Icons.star_outline_rounded,
                            child: _buildValoraciones(),
                          ),
                          const SizedBox(height: 88),
                        ],
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
                    fontSize: 12, color: AppColors.inkSecundarioLight)),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _cargarTodo, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  Widget _buildKpis() {
    final r = _resumen ?? {};
    return KpiGrid(
      children: [
        KpiCard(
          label: 'Ingresos',
          value: '\$${((r['ingresos'] as num?) ?? 0).toStringAsFixed(2)}',
          icon: Icons.attach_money_rounded,
          variacionPct: (r['variacion_ingresos_pct'] as num?)?.toDouble(),
          color: AppColors.primary,
        ),
        KpiCard(
          label: 'Pedidos',
          value: '${(r['pedidos'] as num?) ?? 0}',
          icon: Icons.shopping_bag_outlined,
          variacionPct: (r['variacion_pedidos_pct'] as num?)?.toDouble(),
          color: AppColors.warm,
        ),
        KpiCard(
          label: 'Ticket promedio',
          value:
              '\$${((r['ticket_promedio'] as num?) ?? 0).toStringAsFixed(2)}',
          icon: Icons.receipt_outlined,
          color: AppColors.success,
        ),
        KpiCard(
          label: 'Calificación',
          value:
              '${((r['calificacion_promedio'] as num?) ?? 0).toStringAsFixed(1)} ⭐',
          icon: Icons.star_rounded,
          color: Colors.amber.shade700,
        ),
      ],
    );
  }

  Widget _buildPedidos() {
    final pedidos = _pedidos ?? [];
    if (pedidos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('Sin pedidos en este período',
            style: GoogleFonts.plusJakartaSans(
                color: AppColors.inkSecundarioLight)),
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

  Widget _buildValoraciones() {
    final valoraciones = _valoraciones ?? [];
    if (valoraciones.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('Sin valoraciones aún',
            style: GoogleFonts.plusJakartaSans(
                color: AppColors.inkSecundarioLight)),
      );
    }
    return Column(
      children: valoraciones.map((v) {
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
                          style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                    Text(v['comprador_email'] ?? '',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: AppColors.inkSecundarioLight)),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
