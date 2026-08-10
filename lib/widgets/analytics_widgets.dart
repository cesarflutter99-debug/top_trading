// analytics_widgets.dart
//
// Piezas reutilizables para las 4 pantallas de analítica (vendedor,
// admin, afiliado, comprador). Todo acá es genérico -- recibe datos ya
// calculados, no sabe nada de Supabase ni de nombres de tablas.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';

// ===========================================================================
// RANGO DE FECHAS
// ===========================================================================

enum RangoAnalitica { semana, mes, mesCalendario, historico }

extension RangoAnaliticaLabel on RangoAnalitica {
  String get label {
    switch (this) {
      case RangoAnalitica.semana:
        return '7 días';
      case RangoAnalitica.mes:
        return '30 días';
      case RangoAnalitica.mesCalendario:
        return 'Este mes';
      case RangoAnalitica.historico:
        return 'Histórico';
    }
  }

  /// Días hacia atrás desde hoy. null = sin límite (histórico) o "desde
  /// el día 1 del mes actual" para mesCalendario (se resuelve aparte).
  int? get dias {
    switch (this) {
      case RangoAnalitica.semana:
        return 7;
      case RangoAnalitica.mes:
        return 30;
      case RangoAnalitica.mesCalendario:
        return null;
      case RangoAnalitica.historico:
        return null;
    }
  }
}

class SelectorRango extends StatelessWidget {
  final RangoAnalitica seleccionado;
  final ValueChanged<RangoAnalitica> onChanged;
  const SelectorRango(
      {super.key, required this.seleccionado, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: RangoAnalitica.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final r = RangoAnalitica.values[i];
          final activo = r == seleccionado;
          return GestureDetector(
            onTap: () => onChanged(r),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: activo ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: activo ? AppColors.primary : AppColors.borderLight,
                ),
              ),
              child: Text(
                r.label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: activo ? Colors.white : AppColors.inkSecundarioLight,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ===========================================================================
// KPIs
// ===========================================================================

class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final double? variacionPct;
  final Color color;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.variacionPct,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final subiendo = (variacionPct ?? 0) >= 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: esOscuro ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const Spacer(),
              if (variacionPct != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: (subiendo ? AppColors.success : Colors.redAccent)
                        .withOpacity(0.12),
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
                        color: subiendo ? AppColors.success : Colors.redAccent,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${variacionPct!.abs().toStringAsFixed(0)}%',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color:
                              subiendo ? AppColors.success : Colors.redAccent,
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
            style: GoogleFonts.plusJakartaSans(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: esOscuro ? AppColors.inkDark : AppColors.inkLight,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5, color: AppColors.inkSecundarioLight),
          ),
        ],
      ),
    );
  }
}

class KpiGrid extends StatelessWidget {
  final List<Widget> children;
  const KpiGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.4,
      children: children,
    );
  }
}

// ===========================================================================
// GRÁFICA DE INGRESOS -- barras proporcionales reales, tocables
// ===========================================================================

class PuntoSerie {
  final String etiqueta;
  final double valor;
  const PuntoSerie(this.etiqueta, this.valor);
}

class GraficaSerie extends StatefulWidget {
  final List<PuntoSerie> datos;
  final Color color;
  final String Function(double) formatoValor;

  const GraficaSerie({
    super.key,
    required this.datos,
    this.color = AppColors.primary,
    this.formatoValor = _formatoUsdDefault,
  });

  static String _formatoUsdDefault(double v) => '\$${v.toStringAsFixed(0)}';

  @override
  State<GraficaSerie> createState() => _GraficaSerieState();
}

class _GraficaSerieState extends State<GraficaSerie> {
  int? _seleccionado;

  @override
  Widget build(BuildContext context) {
    final datos = widget.datos;
    if (datos.isEmpty) {
      return SizedBox(
        height: 150,
        child: Center(
          child: Text('Sin datos en este período',
              style: GoogleFonts.plusJakartaSans(
                  color: AppColors.inkSecundarioLight, fontSize: 13)),
        ),
      );
    }
    final maxValor =
        datos.map((d) => d.valor).fold<double>(0, (a, b) => a > b ? a : b);
    final i = _seleccionado;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 20,
          child: i != null
              ? Text(
                  '${datos[i].etiqueta} · ${widget.formatoValor(datos[i].valor)}',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: widget.color),
                )
              : Text(
                  'Toca una barra para ver el detalle',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5, color: AppColors.inkSecundarioLight),
                ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 130,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(datos.length, (idx) {
              final d = datos[idx];
              final alturaPct = maxValor > 0 ? (d.valor / maxValor) : 0.0;
              final activo = _seleccionado == idx;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      setState(() => _seleccionado = activo ? null : idx),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 98 * alturaPct.clamp(0.02, 1.0),
                          decoration: BoxDecoration(
                            color: activo
                                ? widget.color
                                : widget.color.withOpacity(0.32),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          d.etiqueta,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 9, color: AppColors.inkSecundarioLight),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// RANKING DE PRODUCTOS -- toggle Más vendidos / Menos vendidos
// ===========================================================================

class RankingProductos extends StatefulWidget {
  /// Cada item: {nombre, precio_usd, veces_vendido, ingresos_generados}
  final List<Map<String, dynamic>> productos;
  final ValueChanged<Map<String, dynamic>>? onTapProducto;

  const RankingProductos(
      {super.key, required this.productos, this.onTapProducto});

  @override
  State<RankingProductos> createState() => _RankingProductosState();
}

class _RankingProductosState extends State<RankingProductos> {
  bool _masVendidos = true;

  @override
  Widget build(BuildContext context) {
    final lista = List<Map<String, dynamic>>.from(widget.productos);
    lista.sort((a, b) {
      final va = (a['veces_vendido'] as num?)?.toInt() ?? 0;
      final vb = (b['veces_vendido'] as num?)?.toInt() ?? 0;
      return _masVendidos ? vb.compareTo(va) : va.compareTo(vb);
    });
    final top = lista.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _tab('Más vendidos', true),
            const SizedBox(width: 8),
            _tab('Menos vendidos', false),
          ],
        ),
        const SizedBox(height: 12),
        if (top.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Sin ventas en este período',
                style: GoogleFonts.plusJakartaSans(
                    color: AppColors.inkSecundarioLight)),
          )
        else
          ...List.generate(top.length, (i) {
            final p = top[i];
            final medalla =
                _masVendidos && i < 3 ? ['🥇', '🥈', '🥉'][i] : null;
            final ventas = (p['veces_vendido'] as num?)?.toInt() ?? 0;
            final ingresos = (p['ingresos_generados'] as num?)?.toDouble() ?? 0;
            return InkWell(
              onTap: widget.onTapProducto != null
                  ? () => widget.onTapProducto!(p)
                  : null,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: medalla != null
                          ? Text(medalla, style: const TextStyle(fontSize: 18))
                          : CircleAvatar(
                              radius: 12,
                              backgroundColor:
                                  AppColors.primary.withOpacity(0.1),
                              child: Text('${i + 1}',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary)),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p['nombre'] ?? '',
                              style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w600, fontSize: 13.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(
                              '\$${(p['precio_usd'] as num?)?.toStringAsFixed(2) ?? '0'} c/u',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: AppColors.inkSecundarioLight)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$ventas vendidos',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700, fontSize: 12.5)),
                        Text('\$${ingresos.toStringAsFixed(2)}',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11, color: AppColors.success)),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _tab(String label, bool esMas) {
    final activo = _masVendidos == esMas;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _masVendidos = esMas),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: activo
                ? AppColors.primary
                : AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: activo ? Colors.white : AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// LISTA DE PEDIDOS TOCABLE + MODAL DE DETALLE
// ===========================================================================

class PedidoTile extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final String? subtituloExtra;
  final VoidCallback onTap;

  const PedidoTile({
    super.key,
    required this.pedido,
    required this.onTap,
    this.subtituloExtra,
  });

  @override
  Widget build(BuildContext context) {
    final total = (pedido['total_usd'] as num?)?.toDouble() ?? 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: _EstadoIcono(estado: pedido['estado']),
      title: Text('#${pedido['numero_pedido'] ?? ''}',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtituloExtra ??
            '${pedido['comprador_email'] ?? pedido['tienda_nombre'] ?? ''} · ${pedido['productos_count'] ?? 0} productos',
        style: GoogleFonts.plusJakartaSans(fontSize: 12),
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('\$${total.toStringAsFixed(2)}',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, color: AppColors.primary)),
          const Icon(Icons.chevron_right_rounded,
              size: 16, color: AppColors.inkSecundarioLight),
        ],
      ),
    );
  }
}

class _EstadoIcono extends StatelessWidget {
  final String? estado;
  const _EstadoIcono({required this.estado});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (estado) {
      'pending' => (Icons.hourglass_top_rounded, Colors.orange),
      'confirmed' => (Icons.shopping_cart_checkout_rounded, AppColors.primary),
      'completado' => (Icons.check_circle_outline_rounded, AppColors.success),
      'cancelado' => (Icons.cancel_outlined, Colors.redAccent),
      _ => (Icons.help_outline_rounded, AppColors.inkSecundarioLight),
    };
    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withOpacity(0.1),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

class EstadoBadge extends StatelessWidget {
  final String? estado;
  const EstadoBadge({super.key, required this.estado});

  @override
  Widget build(BuildContext context) {
    final color = switch (estado) {
      'pending' => Colors.orange,
      'confirmed' => AppColors.primary,
      'completado' => AppColors.success,
      'cancelado' => Colors.redAccent,
      _ => AppColors.inkSecundarioLight,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        estado ?? '',
        style: GoogleFonts.plusJakartaSans(
            fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// Abre el detalle de un pedido: productos, cantidades y precios.
/// Lee `pedido['detalle']` -- lista jsonb con {id_producto, nombre,
/// cantidad, precio_usd} por línea, tal como la guarda crearPedido().
Future<void> mostrarDetallePedido(
    BuildContext context, Map<String, dynamic> pedido) {
  final detalleRaw = pedido['detalle'];
  final detalle = detalleRaw is List ? detalleRaw : <dynamic>[];
  final total = (pedido['total_usd'] as num?)?.toDouble() ?? 0;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Pedido #${pedido['numero_pedido'] ?? ''}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                EstadoBadge(estado: pedido['estado'] as String?),
              ],
            ),
            if ((pedido['comprador_email'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(pedido['comprador_email'],
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5, color: AppColors.inkSecundarioLight)),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 8),
            if (detalle.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('No hay detalle de productos para este pedido',
                    style: GoogleFonts.plusJakartaSans(
                        color: AppColors.inkSecundarioLight)),
              )
            else
              ...detalle.map((item) {
                final m = item as Map<String, dynamic>;
                final cantidad = (m['cantidad'] as num?)?.toInt() ?? 1;
                final nombre = m['nombre'] ?? '';
                final precio = (m['precio_usd'] as num?)?.toDouble() ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${cantidad}x',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(nombre,
                            style: GoogleFonts.plusJakartaSans(fontSize: 13.5)),
                      ),
                      Text('\$${(precio * cantidad).toStringAsFixed(2)}',
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                Text('\$${total.toStringAsFixed(2)}',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: AppColors.primary)),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

// ===========================================================================
// TARJETA CONTENEDORA -- envoltorio consistente para cada sección
// ===========================================================================

class SeccionAnalitica extends StatelessWidget {
  final String titulo;
  final IconData? icono;
  final Widget child;
  final Widget? accion;

  const SeccionAnalitica({
    super.key,
    required this.titulo,
    required this.child,
    this.icono,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: esOscuro ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight.withOpacity(0.5)),
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
                child: Text(titulo,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              if (accion != null) accion!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
