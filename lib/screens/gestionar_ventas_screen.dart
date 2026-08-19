import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../services/tiendas_service.dart';
import '../widgets/analytics_widgets.dart';

class GestionarVentasScreen extends StatefulWidget {
  final Map<String, dynamic> tienda;

  const GestionarVentasScreen({super.key, required this.tienda});

  @override
  State<GestionarVentasScreen> createState() => _GestionarVentasScreenState();
}

class _GestionarVentasScreenState extends State<GestionarVentasScreen>
    with SingleTickerProviderStateMixin {
  final _tiendasService = TiendasService();
  late TabController _tabController;
  late Future<List<Map<String, dynamic>>> _pendientes;
  late Future<List<Map<String, dynamic>>> _vendidos;
  final Set<String> _procesando = {};
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargar();
  }

  void _cargar() {
    final idTienda = widget.tienda['id_tienda'] as String;
    _pendientes = _tiendasService.obtenerPedidosPendientes(idTienda);
    _vendidos = _tiendasService.obtenerVentasDelMes(idTienda);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _busquedaCtrl.dispose();
    super.dispose();
  }

  /// Filtra por número de pedido -- "contiene", no exacto, para poder
  /// escribir solo una parte del número (ej. "45" encuentra #12345).
  List<Map<String, dynamic>> _filtrar(List<Map<String, dynamic>> todos) {
    if (_busqueda.trim().isEmpty) return todos;
    final query = _busqueda.trim().toLowerCase();
    return todos.where((p) {
      final numero = (p['numero_pedido'] ?? '').toString().toLowerCase();
      return numero.contains(query);
    }).toList();
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
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _procesando.add(idPedido));
    try {
      final productosBajoStock =
          await _tiendasService.marcarPedidoCompletado(idPedido);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venta confirmada ✅ +15 puntos')),
        );
        if (productosBajoStock.isNotEmpty) {
          final nombres = productosBajoStock
              .map((p) => '${p['nombre']} (${p['cantidad_disponible']})')
              .join(', ');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade600,
              content: Text('⚠️ Stock bajo: $nombres'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
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
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Gestionar Ventas'),
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Pendientes'),
            Tab(text: 'Ventas realizadas'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _busquedaCtrl,
              onChanged: (v) => setState(() => _busqueda = v),
              decoration: InputDecoration(
                hintText: 'Buscar por número de pedido (ej. 1234)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _busqueda.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _busquedaCtrl.clear();
                          _busqueda = '';
                        }),
                      ),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _listaPedidos(
                  future: _pendientes,
                  primary: primary,
                  esPendientes: true,
                  vacioTexto: 'No tienes pedidos pendientes',
                ),
                _listaPedidos(
                  future: _vendidos,
                  primary: primary,
                  esPendientes: false,
                  vacioTexto: 'Todavía no tienes ventas este mes',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listaPedidos({
    required Future<List<Map<String, dynamic>>> future,
    required Color primary,
    required bool esPendientes,
    required String vacioTexto,
  }) {
    return RefreshIndicator(
      onRefresh: () async => setState(_cargar),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text('Error: ${snapshot.error}',
                        style: GoogleFonts.plusJakartaSans(
                            color: Colors.red[700])),
                  ),
                ),
              ],
            );
          }
          final todos = snapshot.data ?? [];
          final pedidos = _filtrar(todos);
          if (todos.isEmpty) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Text(vacioTexto,
                        style: GoogleFonts.plusJakartaSans(
                            color: AppColors.inkSecundarioLight)),
                  ),
                ),
              ],
            );
          }
          if (pedidos.isEmpty) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Text(
                      'Ningún pedido coincide con "$_busqueda"',
                      style: GoogleFonts.plusJakartaSans(
                          color: AppColors.inkSecundarioLight),
                    ),
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: pedidos.length,
            itemBuilder: (context, i) {
              final p = pedidos[i];
              final id = p['id_pedido'] as String;
              final procesando = _procesando.contains(id);
              final detalle = (p['detalle'] as List?) ?? [];
              final numeroPedido = p['numero_pedido'];

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kCardRadius)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(kCardRadius),
                  onTap: () => mostrarDetallePedido(context, p),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (numeroPedido != null)
                              Text(
                                'Pedido #$numeroPedido',
                                style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: primary),
                              ),
                            EstadoBadge(estado: p['estado'] as String?),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final item in detalle.take(3))
                          Text(
                            '${item['cantidad']}x ${item['nombre']}',
                            style: GoogleFonts.plusJakartaSans(fontSize: 13),
                          ),
                        if (detalle.length > 3)
                          Text(
                            '+${detalle.length - 3} producto(s) más — toca para ver todo',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11.5,
                                color: AppColors.inkSecundarioLight),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Total: \$${p['total_usd']} USD',
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.bold),
                        ),
                        if (esPendientes) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed:
                                  procesando ? null : () => _marcarVendido(id),
                              icon: procesando
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check_rounded),
                              label: const Text('Marcar como vendido'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
