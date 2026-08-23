// mis_pedidos_screen.dart
//
// Tarea 1: Módulo de Comprador - Pantalla "Mis Pedidos por Tienda".
//
// Lista los pedidos del comprador agrupados por tienda (cada tienda
// maneja su propio carrito, así que agrupar así refleja mejor cómo el
// usuario realmente compra). Cada pedido pendiente muestra una cuenta
// regresiva de 72 horas -- la autocancelación real corre en el
// backend (fn_autocancelar_pedidos_vencidos, ver
// sql/cancelacion_pedidos.sql); esta pantalla solo calcula y muestra
// el tiempo restante localmente, y refresca al hacer pull-to-refresh
// o abrir la pantalla de nuevo. También permite cancelar manualmente
// mientras el pedido siga 'pendiente'.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/tiendas_service.dart';
import '../widgets/analytics_widgets.dart'
    show mostrarDetallePedido, EstadoBadge;

class MisPedidosScreen extends StatefulWidget {
  const MisPedidosScreen({super.key});

  @override
  State<MisPedidosScreen> createState() => _MisPedidosScreenState();
}

class _MisPedidosScreenState extends State<MisPedidosScreen> {
  final _tiendasService = TiendasService();
  late Future<List<Map<String, dynamic>>> _pedidos;
  Timer? _tick;
  final Set<String> _cancelando = {};

  @override
  void initState() {
    super.initState();
    _cargar();
    // Refresca la UI cada minuto para que la cuenta regresiva avance
    // en pantalla sin necesitar pull-to-refresh.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _cargar() {
    final uid = supabase.auth.currentUser?.id;
    _pedidos = uid == null
        ? Future.value(<Map<String, dynamic>>[])
        : _tiendasService.obtenerPedidosDeCompradorConTienda(uid);
  }

  Future<void> _cancelar(String idPedido, String numeroPedido) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('¿Cancelar pedido #$numeroPedido?'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar pedido'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _cancelando.add(idPedido));
    try {
      await _tiendasService.cancelarPedidoComoComprador(idPedido);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido cancelado')),
        );
        setState(_cargar);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cancelar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelando.remove(idPedido));
    }
  }

  /// Tiempo restante antes de la autocancelación (72h desde
  /// creado_en). Devuelve null si el pedido ya no está pendiente.
  Duration? _tiempoRestante(Map<String, dynamic> p) {
    if (p['estado'] != 'pendiente') return null;
    final creadoStr = p['creado_en'] as String?;
    if (creadoStr == null) return null;
    final creado = DateTime.tryParse(creadoStr);
    if (creado == null) return null;
    final limite = creado.toLocal().add(const Duration(hours: 72));
    final restante = limite.difference(DateTime.now());
    return restante.isNegative ? Duration.zero : restante;
  }

  String _formatearRestante(Duration d) {
    if (d.inMinutes <= 0) return 'Por vencer';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}min restantes' : '${m}min restantes';
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final colorTexto = esOscuro ? const Color(0xFFF5F5F4) : AppColors.ink;
    final colorTextoSecundario =
        esOscuro ? AppColors.inkSecundarioDark : AppColors.inkSecundarioLight;
    final colorSuperficie = esOscuro
        ? AppColors.cardTransparentDark
        : AppColors.cardTransparentLight;
    final colorBorde =
        (esOscuro ? AppColors.borderDark : AppColors.borderLight)
            .withOpacity(0.6);
    final colorFondo = Theme.of(context).scaffoldBackgroundColor;

    if (supabase.auth.currentUser == null) {
      return Scaffold(
        backgroundColor: colorFondo,
        appBar: AppBar(title: const Text('Mis Pedidos')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 56, color: colorTextoSecundario),
                const SizedBox(height: 16),
                Text('Inicia sesión para ver tus pedidos',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: colorTexto)),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorFondo,
      appBar: AppBar(
        title: const Text('Mis Pedidos'),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_cargar),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _pedidos,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text('No se pudieron cargar tus pedidos: '
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                              color: colorTextoSecundario)),
                    ),
                  ),
                ],
              );
            }
            final pedidos = snapshot.data ?? [];
            if (pedidos.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 100),
                  Icon(Icons.receipt_long_outlined,
                      size: 56, color: colorTextoSecundario),
                  const SizedBox(height: 16),
                  Center(
                    child: Text('Todavía no tienes pedidos',
                        style: GoogleFonts.plusJakartaSans(
                            color: colorTextoSecundario)),
                  ),
                ],
              );
            }

            // Agrupar por tienda -- cada tienda maneja su propio
            // carrito, así que esta es la vista natural para el
            // comprador.
            final grupos = <String, List<Map<String, dynamic>>>{};
            for (final p in pedidos) {
              final t = p['tiendas'] as Map<String, dynamic>? ?? {};
              final idTienda = (t['id_tienda'] ?? 'sin_tienda').toString();
              grupos.putIfAbsent(idTienda, () => []).add(p);
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: grupos.entries.map((entrada) {
                final lista = entrada.value;
                final tienda =
                    lista.first['tiendas'] as Map<String, dynamic>? ?? {};
                final logo = tienda['logo_url'] as String?;

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorSuperficie,
                    borderRadius: BorderRadius.circular(kCardRadius),
                    border: Border.all(color: colorBorde),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor:
                                  AppColors.primary.withOpacity(0.1),
                              backgroundImage:
                                  (logo != null && logo.isNotEmpty)
                                      ? NetworkImage(logo)
                                      : null,
                              child: (logo == null || logo.isEmpty)
                                  ? const Icon(Icons.storefront_rounded,
                                      size: 16, color: AppColors.primary)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(tienda['nombre'] ?? 'Tienda',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                      color: colorTexto)),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: colorBorde),
                      ...lista.map((p) {
                        final restante = _tiempoRestante(p);
                        final idPedido = p['id_pedido'] as String;
                        final cancelandoEste = _cancelando.contains(idPedido);
                        return ListTile(
                          onTap: () => mostrarDetallePedido(context, p),
                          title: Row(
                            children: [
                              Text('#${p['numero_pedido'] ?? ''}',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: colorTexto)),
                              const SizedBox(width: 8),
                              EstadoBadge(estado: p['estado'] as String?),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text('\$${p['total_usd']} USD',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: colorTextoSecundario)),
                              if (restante != null) ...[
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(Icons.schedule_rounded,
                                        size: 12,
                                        color: restante.inHours < 12
                                            ? Colors.red
                                            : Colors.orange),
                                    const SizedBox(width: 4),
                                    Text(_formatearRestante(restante),
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: restante.inHours < 12
                                              ? Colors.red
                                              : Colors.orange,
                                          fontWeight: FontWeight.w600,
                                        )),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          trailing: p['estado'] == 'pendiente'
                              ? TextButton(
                                  onPressed: cancelandoEste
                                      ? null
                                      : () => _cancelar(
                                          idPedido, '${p['numero_pedido']}'),
                                  style: TextButton.styleFrom(
                                      foregroundColor: Colors.red),
                                  child: cancelandoEste
                                      ? const SizedBox(
                                          height: 16,
                                          width: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Text('Cancelar'),
                                )
                              : null,
                        );
                      }),
                      const SizedBox(height: 4),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}
