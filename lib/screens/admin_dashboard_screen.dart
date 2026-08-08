import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/tiendas_service.dart';
import '../services/theme_provider.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _tiendasService = TiendasService();
  Map<String, dynamic>? _resumen;
  List<Map<String, dynamic>>? _topTiendas;
  List<Map<String, dynamic>>? _pedidosPendientes;
  List<Map<String, dynamic>>? _topProductos;
  List<Map<String, dynamic>>? _topAfiliados;
  List<Map<String, dynamic>>? _ingresosMes;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    setState(() => _cargando = true);
    try {
      final resumen = await _tiendasService.adminDashboardResumen();
      final topTiendas = await _tiendasService.adminTopTiendasPorPedidos();
      final pedidosPendientes = await _tiendasService.adminPedidosPendientes();
      final topProductos = await _tiendasService.adminTopProductos();
      final topAfiliados = await _tiendasService.adminTopAfiliados();
      final ingresosMes = await _tiendasService.adminIngresosPorMes();
      if (mounted) {
        setState(() {
          _resumen = resumen;
          _topTiendas = topTiendas;
          _pedidosPendientes = pedidosPendientes;
          _topProductos = topProductos;
          _topAfiliados = topAfiliados;
          _ingresosMes = ingresosMes;
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
        title: const Text('Dashboard Admin'),
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
                      _buildSectionTitle('Ingresos últimos 12 meses'),
                      const SizedBox(height: 8),
                      _buildIngresosChart(esOscuro),
                      const SizedBox(height: 16),
                      _buildSectionTitle('Top Tiendas por Pedidos'),
                      const SizedBox(height: 8),
                      _buildTopTiendas(esOscuro),
                      const SizedBox(height: 16),
                      _buildSectionTitle('Productos Más Vendidos'),
                      const SizedBox(height: 8),
                      _buildTopProductos(esOscuro),
                      const SizedBox(height: 16),
                      _buildSectionTitle('Pedidos Pendientes'),
                      const SizedBox(height: 8),
                      _buildPedidosPendientes(esOscuro),
                      const SizedBox(height: 16),
                      _buildSectionTitle('Top Afiliados'),
                      const SizedBox(height: 8),
                      _buildTopAfiliados(esOscuro),
                      const SizedBox(height: 88),
                    ],
                  ),
                ),
    );
  }

  Widget _buildResumenCard(bool esOscuro) {
    final r = _resumen!;
    final items = [
      ('Tiendas', '${r['total_tiendas'] ?? 0}', Icons.storefront_outlined),
      ('Activas', '${r['tiendas_activas'] ?? 0}', Icons.check_circle_outline),
      ('Pendientes', '${r['tiendas_pendientes'] ?? 0}', Icons.hourglass_top),
      ('Pedidos', '${r['total_pedidos'] ?? 0}', Icons.shopping_bag_outlined),
      ('Hoy', '${r['pedidos_hoy'] ?? 0}', Icons.today_outlined),
      ('Ingresos mes', '\$${(r['ingresos_mes'] ?? 0)}', Icons.attach_money),
      ('Afiliados', '${r['total_afiliados'] ?? 0}', Icons.people_outline),
      ('Retiros pend.', '${r['retiros_pendientes'] ?? 0}', Icons.pending_actions),
      ('Planes', '${r['planes_activos'] ?? 0}', Icons.workspace_premium_outlined),
    ];
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items.map((item) {
            return _buildResumenItem(item.$1, item.$2, item.$3, esOscuro);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildResumenItem(String label, String value, IconData icon, bool esOscuro) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: esOscuro ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(value,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.inkLight)),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: AppColors.inkSecundarioLight)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: GoogleFonts.plusJakartaSans(
            fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.inkLight));
  }

  Widget _buildIngresosChart(bool esOscuro) {
    if (_ingresosMes == null || _ingresosMes!.isEmpty) {
      return _emptyCard('Sin datos de ingresos', esOscuro);
    }
    final maxIngreso = (_ingresosMes!.map<double>((m) => (m['ingresos'] as num).toDouble()).reduce((a, b) => a > b ? a : b));
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: _ingresosMes!.map((m) {
            final mes = m['mes'] as String;
            final ingresos = (m['ingresos'] as num).toDouble();
            final pct = maxIngreso > 0 ? ingresos / maxIngreso : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Text(mes,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: AppColors.inkSecundarioLight)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 24,
                        width: double.infinity,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: AppColors.primary.withOpacity(pct * 0.3),
                          ),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                '\$${ingresos.toStringAsFixed(0)}',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
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

  Widget _buildTopTiendas(bool esOscuro) {
    if (_topTiendas == null || _topTiendas!.isEmpty) {
      return _emptyCard('Sin datos', esOscuro);
    }
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _topTiendas!.length,
        itemBuilder: (context, i) {
          final t = _topTiendas![i];
          return ListTile(
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
              '${(t['calificacion_promedio'] ?? 0).toStringAsFixed(1)} ⭐',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopProductos(bool esOscuro) {
    if (_topProductos == null || _topProductos!.isEmpty) {
      return _emptyCard('Sin datos', esOscuro);
    }
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _topProductos!.length,
        itemBuilder: (context, i) {
          final p = _topProductos![i];
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
            subtitle: Text(p['tienda_nombre'] ?? '',
                style: GoogleFonts.plusJakartaSans(fontSize: 12)),
            trailing: Text(
              '${p['veces_vendido']} vendidos',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPedidosPendientes(bool esOscuro) {
    if (_pedidosPendientes == null || _pedidosPendientes!.isEmpty) {
      return _emptyCard('No hay pedidos pendientes', esOscuro);
    }
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _pedidosPendientes!.length,
        itemBuilder: (context, i) {
          final p = _pedidosPendientes![i];
          return ListTile(
            leading: const Icon(Icons.shopping_bag_outlined, color: AppColors.primary),
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
        },
      ),
    );
  }

  Widget _buildTopAfiliados(bool esOscuro) {
    if (_topAfiliados == null || _topAfiliados!.isEmpty) {
      return _emptyCard('Sin datos', esOscuro);
    }
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _topAfiliados!.length,
        itemBuilder: (context, i) {
          final a = _topAfiliados![i];
          return ListTile(
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