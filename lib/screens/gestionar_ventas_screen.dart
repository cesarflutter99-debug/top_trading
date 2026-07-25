import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/tiendas_service.dart';

class GestionarVentasScreen extends StatefulWidget {
  final Map<String, dynamic> tienda;

  const GestionarVentasScreen({super.key, required this.tienda});

  @override
  State<GestionarVentasScreen> createState() => _GestionarVentasScreenState();
}

class _GestionarVentasScreenState extends State<GestionarVentasScreen> {
  final _tiendasService = TiendasService();
  late Future<List<Map<String, dynamic>>> _pendientes;
  late Future<int> _ventasDelMes;
  final Set<String> _procesando = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    final idTienda = widget.tienda['id_tienda'] as String;
    _pendientes = _tiendasService.obtenerPedidosPendientes(idTienda);
    _ventasDelMes = _tiendasService.contarVentasDelMes(idTienda);
  }

  Future<void> _marcarVendido(String idPedido) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar venta'),
        content: const Text(
          '¿Confirmas que este pedido fue entregado y pagado? '
          'Se sumarán +15 puntos a tu tienda.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _procesando.add(idPedido));
    try {
      await _tiendasService.marcarPedidoCompletado(idPedido);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venta confirmada ✅ +15 puntos')),
        );
        setState(_cargar);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando.remove(idPedido));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Gestionar Ventas')),
      body: RefreshIndicator(
        onRefresh: () async => setState(_cargar),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---------- Stats del mes ----------
            Row(
              children: [
                Expanded(
                  child: FutureBuilder<int>(
                    future: _ventasDelMes,
                    builder: (context, snapshot) => _statCard(
                      icon: Icons.check_circle_outline,
                      color: Colors.green,
                      valor: snapshot.hasData ? '${snapshot.data}' : '-',
                      etiqueta: 'Vendidos este mes',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _pendientes,
                    builder: (context, snapshot) => _statCard(
                      icon: Icons.hourglass_top_rounded,
                      color: primary,
                      valor: snapshot.hasData ? '${snapshot.data!.length}' : '-',
                      etiqueta: 'Pendientes',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'El contador de vendidos se reinicia automáticamente cada mes.',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.black45),
            ),
            const SizedBox(height: 24),

            Text('Solicitudes pendientes', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 12),

            FutureBuilder<List<Map<String, dynamic>>>(
              future: _pendientes,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text('Error: ${snapshot.error}',
                          style: GoogleFonts.inter(color: Colors.red[700])),
                    ),
                  );
                }
                final pedidos = snapshot.data ?? [];
                if (pedidos.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No tienes solicitudes pendientes',
                        style: GoogleFonts.inter(color: Colors.black54),
                      ),
                    ),
                  );
                }
                return Column(
                  children: pedidos.map((p) {
                    final id = p['id_pedido'] as String;
                    final procesando = _procesando.contains(id);
                    final detalle = (p['detalle'] as List?) ?? [];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final item in detalle)
                              Text(
                                '${item['cantidad']}x ${item['nombre']}',
                                style: GoogleFonts.inter(fontSize: 13),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              'Total: \$${p['total_usd']} USD',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: procesando ? null : () => _marcarVendido(id),
                                icon: procesando
                                    ? const SizedBox(
                                        height: 16, width: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.check_rounded),
                                label: const Text('Marcar como vendido'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color color,
    required String valor,
    required String etiqueta,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(valor, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 20)),
            Text(etiqueta, style: GoogleFonts.inter(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
