import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../services/tiendas_service.dart';

class VendedorDashboardScreen extends StatefulWidget {
  final String? idTienda;
  const VendedorDashboardScreen({super.key, this.idTienda});

  @override
  State<VendedorDashboardScreen> createState() =>
      _VendedorDashboardScreenState();
}

class _VendedorDashboardScreenState extends State<VendedorDashboardScreen> {
  final _tiendasService = TiendasService();
  Map<String, dynamic>? _resumen;
  List<Map<String, dynamic>>? _pedidos;
  List<Map<String, dynamic>>? _productos;
  List<Map<String, dynamic>>? _valoraciones;
  List<Map<String, dynamic>>? _ingresosDiarios;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    setState(() => _cargando = true);
    try {
      final idTienda = widget.idTienda;
      if (idTienda == null) {
        if (mounted) setState(() => _cargando = false);
        return;
      }
      final resumen = await _tiendasService.vendedorDashboardResumen(idTienda);
      final pedidos = await _tiendasService.vendedorPedidos(idTienda);
      final productos = await _tiendasService.vendedorProductosConVentas(idTienda);
      final valoraciones = await _tiendasService.vendedorValoraciones(idTienda);
      final ingresosDiarios = await _tiendasService.vendedorIngresosDiarios(idTienda);
      if (mounted) {
        setState(() {
          _resumen = resumen;
          _pedidos = pedidos;
          _productos = productos;
          _valoraciones = valoraciones;
          _ingresosDiarios = ingresosDiarios;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Mis Ventas'),
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargarTodo,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _resumen == null
              ? const Center(child: Text('Sin datos'))
              : RefreshIndicator(
                  onRefresh: _cargarTodo,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildResumenCard(esOscuro),
                      const SizedBox(height: 16),
                      _buildSectionTitle('Ingresos últimos 30 días'),
                      const SizedBox(height: 8),
                      _buildIngresosChart(esOscuro),
                      const SizedBox(height: 16),
                      _buildSectionTitle('Productos más vendidos'),
                      const SizedBox(height: 8),
                      _buildTopProductos(esOscuro),
                      const SizedBox(height: 16),
                      _buildSectionTitle('Valoraciones'),
                      const SizedBox(height: 8),
                      _buildValoraciones(esOscuro),
                      const SizedBox(height: 16),
                      _buildSectionTitle('Pedidos recientes'),
                      const SizedBox(height: 8),
                      _buildPedidos(esOscuro),
                      const SizedBox(height: 88),
                    ],
                  ),
                ),
    );
  }

  Widget _buildResumenCard(bool esOscuro) {
    final r = _resumen!;
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r['nombre_tienda'] ?? 'Mi Tienda',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                      'Pedidos totales',
                      '${r['total_pedidos'] ?? 0}',
                      Icons.shopping_bag),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Hoy', '${r['pedidos_hoy'] ?? 0}', Icons.today),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Mes', '${r['pedidos_mes'] ?? 0}', Icons.calendar_today),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                      'Ingresos mes',
                      '\$${(r['ingresos_mes'] ?? 0)}',
                      Icons.attach_money),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Total',
                      '\$${(r['ingresos_total'] ?? 0)}',
                      Icons.account_balance_wallet),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Calificación',
                      '${(r['calificacion_promedio'] ?? 0).toStringAsFixed(1)} ⭐',
                      Icons.star),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                      'Pendientes',
                      '${r['pedidos_pendientes'] ?? 0}',
                      Icons.hourglass_top),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Completados',
                      '${r['pedidos_completados'] ?? 0}',
                      Icons.check_circle_outline),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Cancelados',
                      '${r['pedidos_cancelados'] ?? 0}',
                      Icons.cancel_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: GoogleFonts.plusJakartaSans(
            fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.inkLight));
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(height: 4),
        Text(value,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, color: AppColors.inkSecundarioLight)),
      ],
    );
  }

  Widget _buildIngresosChart(bool esOscuro) {
    if (_ingresosDiarios == null || _ingresosDiarios!.isEmpty) {
      return _emptyCard('Sin datos de ingresos', esOscuro);
    }
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: _ingresosDiarios!.map((m) {
            final fecha = m['fecha'] as String;
            final ingresos = (m['ingresos'] as num).toDouble();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(fecha.substring(5),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: AppColors.inkSecundarioLight)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 18,
                        width: double.infinity,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: AppColors.primary.withOpacity(0.2),
                          ),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(
                                '\$${ingresos.toStringAsFixed(0)}',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.inkLight),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTopProductos(bool esOscuro) {
    if (_productos == null || _productos!.isEmpty) {
      return _emptyCard('Sin productos', esOscuro);
    }
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _productos!.length,
        itemBuilder: (context, i) {
          final p = _productos![i];
          return ListTile(
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
            subtitle: Text(
              '${p['veces_vendido'] ?? 0} vendidos · \$${(p['precio_usd'] ?? 0)}',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
            trailing: Text(
              'Stock: ${p['stock_actual'] ?? 0}',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
          );
        },
      ),
    );
  }

  Widget _buildValoraciones(bool esOscuro) {
    if (_valoraciones == null || _valoraciones!.isEmpty) {
      return _emptyCard('Sin valoraciones aún', esOscuro);
    }
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _valoraciones!.length,
        itemBuilder: (context, i) {
          final v = _valoraciones![i];
          return ListTile(
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                v['estrellas'] ?? 0,
                (j) => const Icon(Icons.star_rounded, size: 14, color: AppColors.warm),
              ),
            ),
            title: Text(v['comentario'] ?? '',
                style: GoogleFonts.plusJakartaSans(fontSize: 13)),
            subtitle: Text(
              v['comprador_email'] ?? '',
              style: GoogleFonts.plusJakartaSans(fontSize: 11),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPedidos(bool esOscuro) {
    if (_pedidos == null || _pedidos!.isEmpty) {
      return _emptyCard('Sin pedidos', esOscuro);
    }
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _pedidos!.length,
        itemBuilder: (context, i) {
          final p = _pedidos![i];
          return ListTile(
            leading: const Icon(Icons.shopping_bag_outlined, color: AppColors.primary),
            title: Text('#${p['numero_pedido'] ?? ''}',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${p['comprador_email'] ?? ''} · ${p['productos_count'] ?? 0} productos',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
            trailing: Text(
              '\$${(p['total_usd'] ?? 0)}',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyCard(String texto, bool esOscuro) {
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(texto,
              style: GoogleFonts.plusJakartaSans(color: AppColors.inkSecundarioLight)),
        ),
      ),
    );
  }
}