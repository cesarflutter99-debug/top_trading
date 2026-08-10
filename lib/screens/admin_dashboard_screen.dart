import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../core/app_colors.dart';
import '../services/tiendas_service.dart';
import '../services/currency_service.dart';
import '../widgets/analytics_widgets.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _tiendasService = TiendasService();
  final _scrollController = ScrollController();

  // Llaves para poder saltar a cada sección al tocar un KPI de arriba.
  final _keyIngresos = GlobalKey();
  final _keyTiendas = GlobalKey();
  final _keyProductos = GlobalKey();
  final _keyPedidos = GlobalKey();
  final _keyRetiros = GlobalKey();
  final _keyAfiliados = GlobalKey();

  RangoAnalitica _rango = RangoAnalitica.mes;

  Map<String, dynamic>? _resumen;
  Map<String, dynamic>? _ingresosPeriodo;
  List<Map<String, dynamic>>? _topTiendas;
  List<Map<String, dynamic>>? _pedidosPendientes;
  List<Map<String, dynamic>>? _topProductos;
  List<Map<String, dynamic>>? _topAfiliados;
  List<Map<String, dynamic>>? _retirosPendientes;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _cargarTodo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resumen = await _tiendasService.adminDashboardResumen();
      final ingresosPeriodo =
          await _tiendasService.adminIngresosPeriodo(_rango);
      final topTiendas = await _tiendasService.adminTopTiendasPorPedidos();
      final pedidosPendientes = await _tiendasService.adminPedidosPendientes();
      final topProductos = await _tiendasService.adminTopProductos();
      final topAfiliados = await _tiendasService.adminTopAfiliados();
      final retirosPendientes =
          await _tiendasService.obtenerRetirosPendientes();
      if (mounted) {
        setState(() {
          _resumen = resumen;
          _ingresosPeriodo = ingresosPeriodo;
          _topTiendas = topTiendas;
          _pedidosPendientes = pedidosPendientes;
          _topProductos = topProductos;
          _topAfiliados = topAfiliados;
          _retirosPendientes = retirosPendientes;
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

  void _irA(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Dashboard Admin'),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Center(child: CurrencyToggle()),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: _cargarTodo,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _cargarTodo,
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      SelectorRango(
                          seleccionado: _rango, onChanged: _cambiarRango),
                      const SizedBox(height: 16),
                      _buildKpis(),
                      const SizedBox(height: 14),
                      KeyedSubtree(
                        key: _keyIngresos,
                        child: SeccionAnalitica(
                          titulo: 'Ingresos por planes',
                          icono: Icons.attach_money_rounded,
                          child: _buildIngresosChart(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      KeyedSubtree(
                        key: _keyTiendas,
                        child: SeccionAnalitica(
                          titulo: 'Top Tiendas por Pedidos',
                          icono: Icons.storefront_outlined,
                          accion: _verMasBtn(() => _abrirListaCompleta(
                              'Top Tiendas', _topTiendas ?? [], _tileTienda)),
                          child: _listaTop(_topTiendas, _tileTienda),
                        ),
                      ),
                      const SizedBox(height: 14),
                      KeyedSubtree(
                        key: _keyProductos,
                        child: SeccionAnalitica(
                          titulo: 'Productos Más Vendidos',
                          icono: Icons.inventory_2_outlined,
                          accion: _verMasBtn(() => _abrirListaCompleta(
                              'Productos Más Vendidos',
                              _topProductos ?? [],
                              _tileProducto)),
                          child: _listaTop(_topProductos, _tileProducto),
                        ),
                      ),
                      const SizedBox(height: 14),
                      KeyedSubtree(
                        key: _keyPedidos,
                        child: SeccionAnalitica(
                          titulo: 'Pedidos Pendientes',
                          icono: Icons.receipt_long_outlined,
                          accion: (_pedidosPendientes?.length ?? 0) > 3
                              ? _verMasBtn(() => _abrirListaCompleta(
                                  'Pedidos Pendientes',
                                  _pedidosPendientes ?? [],
                                  _tilePedido))
                              : null,
                          child: _listaTop(_pedidosPendientes, _tilePedido,
                              vacio: 'No hay pedidos pendientes'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      KeyedSubtree(
                        key: _keyRetiros,
                        child: SeccionAnalitica(
                          titulo: 'Retiros Pendientes',
                          icono: Icons.pending_actions_rounded,
                          accion: (_retirosPendientes?.length ?? 0) > 3
                              ? _verMasBtn(() => _abrirListaCompleta(
                                  'Retiros Pendientes',
                                  _retirosPendientes ?? [],
                                  _tileRetiro))
                              : null,
                          child: _listaTop(_retirosPendientes, _tileRetiro,
                              vacio: 'No hay retiros pendientes'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      KeyedSubtree(
                        key: _keyAfiliados,
                        child: SeccionAnalitica(
                          titulo: 'Top Afiliados',
                          icono: Icons.handshake_outlined,
                          accion: _verMasBtn(() => _abrirListaCompleta(
                              'Top Afiliados',
                              _topAfiliados ?? [],
                              _tileAfiliado)),
                          child: _listaTop(_topAfiliados, _tileAfiliado),
                        ),
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

  Widget? _verMasBtn(VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(padding: EdgeInsets.zero),
      child: const Text('Ver más'),
    );
  }

  void _abrirListaCompleta(String titulo, List<Map<String, dynamic>> items,
      Widget Function(Map<String, dynamic>, int) tileBuilder) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(titulo,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                itemBuilder: (ctx, i) => tileBuilder(items[i], i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listaTop(List<Map<String, dynamic>>? items,
      Widget Function(Map<String, dynamic>, int) tileBuilder,
      {String vacio = 'Sin datos'}) {
    if (items == null || items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(vacio,
            style: GoogleFonts.plusJakartaSans(
                color: AppColors.inkSecundarioLight)),
      );
    }
    final top3 = items.take(3).toList();
    return Column(
      children: List.generate(top3.length, (i) => tileBuilder(top3[i], i)),
    );
  }

  // -----------------------------------------------------------------
  // KPIs
  // -----------------------------------------------------------------

  Widget _buildKpis() {
    final r = _resumen ?? {};
    final ip = _ingresosPeriodo ?? {};
    return KpiGrid(
      children: [
        GestureDetector(
          onTap: () => _irA(_keyIngresos),
          child: KpiCard(
            label: 'Ingresos (planes)',
            value: '\$${((ip['ingresos'] as num?) ?? 0).toStringAsFixed(2)}',
            icon: Icons.attach_money_rounded,
            variacionPct: (ip['variacion_pct'] as num?)?.toDouble(),
            color: AppColors.primary,
          ),
        ),
        GestureDetector(
          onTap: () => _irA(_keyTiendas),
          child: KpiCard(
            label: 'Tiendas activas',
            value: '${r['tiendas_activas'] ?? 0}',
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.success,
          ),
        ),
        GestureDetector(
          onTap: () => _irA(_keyTiendas),
          child: KpiCard(
            label: 'Tiendas pendientes',
            value: '${r['tiendas_pendientes'] ?? 0}',
            icon: Icons.hourglass_top_rounded,
            color: Colors.orange,
          ),
        ),
        GestureDetector(
          onTap: () => _irA(_keyPedidos),
          child: KpiCard(
            label: 'Pedidos (marketplace)',
            value: '${r['total_pedidos'] ?? 0}',
            icon: Icons.shopping_bag_outlined,
            color: AppColors.warm,
          ),
        ),
        GestureDetector(
          onTap: () => _irA(_keyRetiros),
          child: KpiCard(
            label: 'Retiros pendientes',
            value: '${r['retiros_pendientes'] ?? 0}',
            icon: Icons.pending_actions_rounded,
            color: Colors.redAccent,
          ),
        ),
        GestureDetector(
          onTap: () => _irA(_keyAfiliados),
          child: KpiCard(
            label: 'Afiliados',
            value: '${r['total_afiliados'] ?? 0}',
            icon: Icons.people_outline_rounded,
            color: AppColors.warm,
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------
  // Gráfica de ingresos (histórico mensual ya existente)
  // -----------------------------------------------------------------

  Widget _buildIngresosChart() {
    final ip = _ingresosPeriodo ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${(ip['pagos'] as num?) ?? 0} pagos de plan en este período',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5, color: AppColors.inkSecundarioLight),
        ),
        const SizedBox(height: 4),
        Text(
          'Si el pago fue con código de afiliado, se cuenta el 90% real transferido, no el precio de lista.',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11, color: AppColors.inkSecundarioLight),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------
  // Tiles de cada tipo de item
  // -----------------------------------------------------------------

  Widget _tileTienda(Map<String, dynamic> t, int i) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: t['id_tienda'] != null
          ? () => context.push('/tienda/${t['id_tienda']}')
          : null,
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withOpacity(0.1),
        child: Text('${i + 1}',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: AppColors.primary)),
      ),
      title: Text(t['nombre'] ?? '',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${t['total_pedidos']} pedidos · \$${(t['ingresos_total'] ?? 0)}',
        style: GoogleFonts.plusJakartaSans(fontSize: 12),
      ),
      trailing: Text(
        '${((t['calificacion_promedio'] as num?) ?? 0).toStringAsFixed(1)} ⭐',
        style: GoogleFonts.plusJakartaSans(fontSize: 12),
      ),
    );
  }

  Widget _tileProducto(Map<String, dynamic> p, int i) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: p['id_tienda'] != null
          ? () => context.push('/tienda/${p['id_tienda']}')
          : null,
      leading: CircleAvatar(
        backgroundColor: AppColors.warm.withOpacity(0.1),
        child: Text('${i + 1}',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: AppColors.warm)),
      ),
      title: Text(p['nombre'] ?? '',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
      subtitle: Text(p['tienda_nombre'] ?? '',
          style: GoogleFonts.plusJakartaSans(fontSize: 12)),
      trailing: Text(
        '${p['veces_vendido']} vendidos',
        style: GoogleFonts.plusJakartaSans(fontSize: 12),
      ),
    );
  }

  Widget _tilePedido(Map<String, dynamic> p, int i) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => mostrarDetallePedido(context, p),
      leading:
          const Icon(Icons.shopping_bag_outlined, color: AppColors.primary),
      title: Text('Pedido #${p['numero_pedido'] ?? ''}',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${p['tienda_nombre'] ?? ''} · ${p['comprador_email'] ?? ''}',
        style: GoogleFonts.plusJakartaSans(fontSize: 12),
      ),
      trailing: Text(
        '\$${(p['total_usd'] ?? 0)}',
        style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700, color: AppColors.primary),
      ),
    );
  }

  Widget _tileRetiro(Map<String, dynamic> r, int i) {
    final afiliado = r['afiliados'] as Map<String, dynamic>? ?? {};
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => _mostrarPerfilAfiliado(afiliado),
      leading: const Icon(Icons.pending_actions_rounded, color: Colors.orange),
      title: Text(afiliado['nombre'] ?? 'Afiliado',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
      subtitle: Text('Código: ${afiliado['codigo'] ?? '-'}',
          style: GoogleFonts.plusJakartaSans(fontSize: 12)),
      trailing: Text(
        '${r['monto_cup'] ?? 0} CUP',
        style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700, color: Colors.orange.shade700),
      ),
    );
  }

  Widget _tileAfiliado(Map<String, dynamic> a, int i) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => _mostrarPerfilAfiliado(a),
      leading: CircleAvatar(
        backgroundColor: AppColors.warm.withOpacity(0.1),
        child: Text('${i + 1}',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: AppColors.warm)),
      ),
      title: Text(a['nombre'] ?? '',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
      subtitle: Text(
        'Código: ${a['codigo'] ?? ''} · ${a['retiros_realizados'] ?? 0} retiros',
        style: GoogleFonts.plusJakartaSans(fontSize: 12),
      ),
      trailing: Text(
        '\$${(a['comisiones_acumuladas'] ?? 0)}',
        style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700, color: AppColors.warm),
      ),
    );
  }

  // -----------------------------------------------------------------
  // Perfil de afiliado (modal) -- código, saldo, historial de usos
  // -----------------------------------------------------------------

  void _mostrarPerfilAfiliado(Map<String, dynamic> afiliado) {
    final idAfiliado = afiliado['id_afiliado'] as String?;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.warm.withOpacity(0.1),
                    child: const Icon(Icons.handshake_outlined,
                        color: AppColors.warm),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(afiliado['nombre'] ?? '',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 17, fontWeight: FontWeight.w800)),
                        Text('Código: ${afiliado['codigo'] ?? '-'}',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12.5,
                                color: AppColors.inkSecundarioLight)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _statChip('Saldo',
                        '${afiliado['saldo_cup'] ?? 0} CUP', AppColors.success),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statChip(
                        'Comisiones',
                        '\$${afiliado['comisiones_acumuladas'] ?? 0}',
                        AppColors.warm),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statChip(
                        'Retiros',
                        '${afiliado['retiros_realizados'] ?? 0}',
                        AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Historial de usos',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              Expanded(
                child: idAfiliado == null
                    ? Text('No se pudo identificar al afiliado',
                        style: GoogleFonts.plusJakartaSans(
                            color: AppColors.inkSecundarioLight))
                    : FutureBuilder<List<Map<String, dynamic>>>(
                        future:
                            _tiendasService.obtenerUsosDeAfiliado(idAfiliado),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError) {
                            return Text('Error al cargar: ${snapshot.error}',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12, color: Colors.redAccent));
                          }
                          final usos = snapshot.data ?? [];
                          if (usos.isEmpty) {
                            return Text('Sin usos todavía',
                                style: GoogleFonts.plusJakartaSans(
                                    color: AppColors.inkSecundarioLight));
                          }
                          return ListView.builder(
                            controller: scrollController,
                            itemCount: usos.length,
                            itemBuilder: (context, i) {
                              final u = usos[i];
                              final tienda =
                                  u['tiendas'] as Map<String, dynamic>?;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.storefront_outlined,
                                    color: AppColors.warm, size: 20),
                                title: Text(tienda?['nombre'] ?? 'Tienda',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(u['estado'] ?? '',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11)),
                                trailing: Text(
                                  '${u['comision_cup_acreditada'] ?? 0} CUP',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: AppColors.success),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800, fontSize: 13, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5, color: AppColors.inkSecundarioLight)),
        ],
      ),
    );
  }
}
