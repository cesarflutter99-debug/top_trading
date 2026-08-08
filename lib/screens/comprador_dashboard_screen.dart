import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/tiendas_service.dart';

class CompradorDashboardScreen extends StatefulWidget {
  const CompradorDashboardScreen({super.key});

  @override
  State<CompradorDashboardScreen> createState() =>
      _CompradorDashboardScreenState();
}

class _CompradorDashboardScreenState extends State<CompradorDashboardScreen> {
  final _tiendasService = TiendasService();
  Map<String, dynamic>? _resumen;
  List<Map<String, dynamic>>? _pedidos;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    setState(() => _cargando = true);
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _cargando = false);
        return;
      }
      final resumen = await _tiendasService.compradorDashboardResumen(uid);
      final pedidos = await _tiendasService.compradorPedidos(uid);
      if (mounted) {
        setState(() {
          _resumen = resumen;
          _pedidos = pedidos;
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
        title: const Text('Mis Pedidos'),
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
                      _buildSectionTitle('Historial de pedidos'),
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
            Text('Resumen de compras',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                      'Total pedidos',
                      '${r['total_pedidos'] ?? 0}',
                      Icons.shopping_bag),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Activos',
                      '${r['pedidos_activos'] ?? 0}',
                      Icons.hourglass_top),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Completados',
                      '${r['pedidos_completados'] ?? 0}',
                      Icons.check_circle_outline),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                      'Gasto total',
                      '\$${(r['gasto_total'] ?? 0)}',
                      Icons.account_balance_wallet),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Este mes',
                      '\$${(r['gasto_mes'] ?? 0)}',
                      Icons.calendar_today),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Tiendas',
                      '${r['tiendas_favoritas'] ?? 0}',
                      Icons.storefront),
                ),
              ],
            ),
            if (r['primera_compra'] != null) ...[
              const Divider(height: 24),
              Text(
                'Cliente desde ${_formatDate(r['primera_compra'])}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: AppColors.inkSecundarioLight),
              ),
            ],
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

  Widget _buildPedidos(bool esOscuro) {
    if (_pedidos == null || _pedidos!.isEmpty) {
      return Card(
        color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text('No tienes pedidos yet',
                style: GoogleFonts.plusJakartaSans(
                    color: AppColors.inkSecundarioLight)),
          ),
        ),
      );
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
            leading: Icon(
              _estadoIcon(p['estado']),
              color: _estadoColor(p['estado']),
            ),
            title: Text('#${p['numero_pedido'] ?? ''}',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${p['tienda_nombre'] ?? ''} · ${p['productos_count'] ?? 0} productos',
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

  IconData _estadoIcon(String? estado) {
    switch (estado) {
      case 'pending':
        return Icons.hourglass_top;
      case 'confirmed':
        return Icons.shopping_cart_checkout;
      case 'completado':
        return Icons.check_circle_outline;
      case 'cancelado':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  Color _estadoColor(String? estado) {
    switch (estado) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return AppColors.primary;
      case 'completado':
        return AppColors.success;
      case 'cancelado':
        return Colors.red;
      default:
        return AppColors.inkSecundarioLight;
    }
  }

  String _formatDate(dynamic fecha) {
    if (fecha is String) return fecha;
    if (fecha is DateTime) return '${fecha.day}/${fecha.month}/${fecha.year}';
    return '';
  }
}