// notifications_screen.dart
//
// Lista completa de notificaciones, agrupadas por fecha (Hoy, Ayer,
// Esta semana, Anteriores). Al tocar una notificación se marca como
// leída y se navega según su 'tipo' + 'data'.
//
// REDISEÑO (2026-08): esta pantalla se había quedado con el estilo
// "de fábrica" de Flutter (Colors.grey/blue a mano, sin
// GoogleFonts, sin modo oscuro) mientras el resto de la app ya
// migró a la paleta AppColors + tarjetas "vidrio flotante". Cambios:
//   - Toda la paleta ahora sale de AppColors, con getters
//     _colorTexto/_colorTextoSecundario/_colorSuperficie que
//     responden a Theme.of(context).brightness, mismo patrón que
//     mi_perfil_screen.dart y home_screen.dart.
//   - Cada notificación es una tarjeta con borde sutil, ícono en
//     círculo de color según el tipo (antes todo era gris/azul
//     genérico) y texto en plusJakartaSans.
//   - "Marcar todas leídas" pasa a ser un botón con el color de marca
//     en vez de texto plano sin estilo, y se deshabilita solo si no
//     hay nada que marcar.
//   - Empty state ilustrado (ícono + título + subtítulo), igual que
//     favoritos_screen.dart, en vez de un Text() suelto.
//   - AppBar con elevation:0 / scrolledUnderElevation:0, igual que el
//     resto de pantallas (tasa_cambio_screen, mi_perfil_screen, etc.)

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../services/notificaciones_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool get _esOscuro => Theme.of(context).brightness == Brightness.dark;
  Color get _colorTexto => _esOscuro ? const Color(0xFFF5F5F4) : AppColors.ink;
  Color get _colorTextoSecundario =>
      _esOscuro ? AppColors.inkSecundarioDark : AppColors.inkSecundarioLight;
  Color get _colorFondo => Theme.of(context).scaffoldBackgroundColor;
  Color get _colorSuperficie => _esOscuro
      ? AppColors.cardTransparentDark
      : AppColors.cardTransparentLight;
  Color get _colorBorde =>
      (_esOscuro ? AppColors.borderDark : AppColors.borderLight)
          .withOpacity(0.6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        title: const Text('Notificaciones'),
        backgroundColor: _colorFondo,
        foregroundColor: _colorTexto,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          AnimatedBuilder(
            animation: NotificacionesService.instance,
            builder: (context, _) {
              final hayNoLeidas = NotificacionesService.instance.noLeidas > 0;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: hayNoLeidas
                      ? () => NotificacionesService.instance.marcarTodasLeidas()
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    disabledForegroundColor: _colorTextoSecundario,
                  ),
                  child: Text(
                    'Marcar todas leídas',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: NotificacionesService.instance,
        builder: (context, _) {
          final servicio = NotificacionesService.instance;
          if (servicio.cargando && servicio.notificaciones.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (servicio.notificaciones.isEmpty) {
            return _estadoVacio();
          }

          final grupos = _agruparPorFecha(servicio.notificaciones);

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: grupos.length,
            itemBuilder: (context, i) {
              final grupo = grupos[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(4, i == 0 ? 0 : 12, 4, 8),
                    child: Text(
                      grupo.titulo,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: _colorTextoSecundario,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  ...grupo.items.map((n) => _NotificacionTile(
                        notificacion: n,
                        colorTexto: _colorTexto,
                        colorTextoSecundario: _colorTextoSecundario,
                        colorSuperficie: _colorSuperficie,
                        colorBorde: _colorBorde,
                        esOscuro: _esOscuro,
                      )),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _estadoVacio() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Icon(Icons.notifications_none_rounded,
            size: 56, color: _colorTextoSecundario),
        const SizedBox(height: 16),
        Center(
          child: Text('No tienes notificaciones todavía',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: _colorTexto)),
        ),
        const SizedBox(height: 8),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Aquí verás pedidos, comisiones, retiros y avisos de tu '
              'tienda o programa de afiliados.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5, color: _colorTextoSecundario),
            ),
          ),
        ),
      ],
    );
  }

  List<_GrupoFecha> _agruparPorFecha(List<Map<String, dynamic>> lista) {
    final hoy = DateTime.now();
    final inicioHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final inicioAyer = inicioHoy.subtract(const Duration(days: 1));
    final inicioSemana = inicioHoy.subtract(const Duration(days: 7));

    final gHoy = <Map<String, dynamic>>[];
    final gAyer = <Map<String, dynamic>>[];
    final gSemana = <Map<String, dynamic>>[];
    final gAnteriores = <Map<String, dynamic>>[];

    for (final n in lista) {
      final fecha = DateTime.parse(n['creado_en']).toLocal();
      if (fecha.isAfter(inicioHoy)) {
        gHoy.add(n);
      } else if (fecha.isAfter(inicioAyer)) {
        gAyer.add(n);
      } else if (fecha.isAfter(inicioSemana)) {
        gSemana.add(n);
      } else {
        gAnteriores.add(n);
      }
    }

    final grupos = <_GrupoFecha>[];
    if (gHoy.isNotEmpty) grupos.add(_GrupoFecha('HOY', gHoy));
    if (gAyer.isNotEmpty) grupos.add(_GrupoFecha('AYER', gAyer));
    if (gSemana.isNotEmpty) grupos.add(_GrupoFecha('ESTA SEMANA', gSemana));
    if (gAnteriores.isNotEmpty) {
      grupos.add(_GrupoFecha('ANTERIORES', gAnteriores));
    }
    return grupos;
  }
}

class _GrupoFecha {
  final String titulo;
  final List<Map<String, dynamic>> items;
  _GrupoFecha(this.titulo, this.items);
}

/// Metadatos visuales (ícono + color) por tipo de notificación -- antes
/// todo tipo desconocido caía en el mismo gris/azul genérico. Ahora
/// cada dominio (pedidos, tienda, afiliados, valoraciones) tiene su
/// propio color, coherente con el resto de la app: AppColors.primary
/// para pedidos/tienda, AppColors.warm para afiliados/planes,
/// ámbar para valoraciones, rojo para vencimientos.
class _EstiloNotificacion {
  final IconData icono;
  final Color color;
  const _EstiloNotificacion(this.icono, this.color);
}

_EstiloNotificacion _estiloPorTipo(String? tipo) {
  switch (tipo) {
    case 'nuevo_pedido':
      return const _EstiloNotificacion(
          Icons.shopping_bag_rounded, AppColors.primary);
    case 'tienda_aprobada':
      return const _EstiloNotificacion(
          Icons.verified_rounded, AppColors.success);
    case 'solicitud_plan':
      return const _EstiloNotificacion(
          Icons.workspace_premium_rounded, AppColors.warm);
    case 'valorar_servicio':
      return const _EstiloNotificacion(Icons.star_rounded, Color(0xFFD4AF37));
    case 'plan_por_vencer':
      return const _EstiloNotificacion(
          Icons.schedule_rounded, Colors.deepOrange);
    case 'pedido_por_expirar':
      return const _EstiloNotificacion(Icons.timer_rounded, Colors.deepOrange);
    case 'nuevo_afiliado':
      return const _EstiloNotificacion(Icons.handshake_rounded, AppColors.warm);
    case 'retiro_solicitado':
    case 'retiro_pagado':
      return const _EstiloNotificacion(
          Icons.account_balance_wallet_rounded, AppColors.warm);
    case 'retiro_rechazado':
      return const _EstiloNotificacion(
          Icons.error_outline_rounded, Colors.redAccent);
    case 'comision_afiliado':
      return const _EstiloNotificacion(
          Icons.attach_money_rounded, AppColors.success);
    case 'venta_confirmada':
      return const _EstiloNotificacion(
          Icons.check_circle_rounded, AppColors.success);
    case 'stock_bajo':
      return const _EstiloNotificacion(
          Icons.warning_amber_rounded, Colors.orange);
    case 'producto_agotado':
      return const _EstiloNotificacion(
          Icons.remove_shopping_cart_rounded, Colors.redAccent);
    case 'plan_vencido':
      return const _EstiloNotificacion(Icons.cancel_rounded, Colors.redAccent);
    case 'tienda_eliminada_plan_vencido':
      return const _EstiloNotificacion(
          Icons.delete_outline_rounded, Colors.redAccent);
    case 'tienda_rechazada':
      return const _EstiloNotificacion(Icons.storefront_rounded, Colors.redAccent);
    case 'pedido_cancelado':
      return const _EstiloNotificacion(Icons.cancel_outlined, Colors.redAccent);
    case 'pedido_cancelado_comprador':
      return const _EstiloNotificacion(
          Icons.person_off_rounded, Colors.deepOrange);
    case 'pedido_completado':
      return const _EstiloNotificacion(
          Icons.inventory_rounded, AppColors.success);
    case 'negocio_aprobado':
      return const _EstiloNotificacion(
          Icons.verified_rounded, AppColors.success);
    case 'negocio_rechazado':
      return const _EstiloNotificacion(
          Icons.storefront_rounded, Colors.redAccent);
    case 'negocio_suspendido':
      return const _EstiloNotificacion(
          Icons.pause_circle_rounded, Colors.deepOrange);
    case 'anuncio_por_vencer':
      return const _EstiloNotificacion(
          Icons.schedule_rounded, Colors.deepOrange);
    case 'nueva_resena':
      return const _EstiloNotificacion(
          Icons.reviews_rounded, Color(0xFFD4AF37));
    default:
      return const _EstiloNotificacion(
          Icons.notifications_rounded, AppColors.primary);
  }
}

class _NotificacionTile extends StatelessWidget {
  final Map<String, dynamic> notificacion;
  final Color colorTexto;
  final Color colorTextoSecundario;
  final Color colorSuperficie;
  final Color colorBorde;
  final bool esOscuro;

  const _NotificacionTile({
    required this.notificacion,
    required this.colorTexto,
    required this.colorTextoSecundario,
    required this.colorSuperficie,
    required this.colorBorde,
    required this.esOscuro,
  });

  void _navegar(BuildContext context) {
    final tipo = notificacion['tipo'];
    final data = notificacion['data'] as Map<String, dynamic>?;
    if (data == null) return;

    switch (tipo) {
      case 'nuevo_pedido':
      case 'pedido_por_expirar':
        context.push('/vendedor/pedidos');
        break;
      case 'tienda_aprobada':
      case 'plan_por_vencer':
      case 'venta_confirmada':
        context.push('/vendedor/mi-tienda');
        break;
      case 'solicitud_plan':
        context.push('/vendedor/planes');
        break;
      case 'valorar_servicio':
        final idTienda = data['id_tienda'];
        final ruta = idTienda != null
            ? '/valorar/${data['id_pedido']}?tienda=$idTienda'
            : '/valorar/${data['id_pedido']}';
        context.push(ruta);
        break;
      case 'nuevo_afiliado':
      case 'retiro_solicitado':
      case 'retiro_pagado':
      case 'retiro_rechazado':
      case 'comision_afiliado':
        context.push('/afiliados/perfil');
        break;
      case 'stock_bajo':
      case 'producto_agotado':
        // FIX: antes mandaba solo a "Mi Tienda" en general -- ahora
        // lleva EXACTAMENTE al producto con el modal de edición ya
        // abierto (ver panel_vendedor_screen.dart ->
        // _abrirEdicionDesdeNotificacion). Si por algún motivo la
        // notificación no trae id_producto, cae al panel general en
        // vez de romper.
        final idProducto = data['id_producto'];
        context.push(idProducto != null
            ? '/vendedor/mi-tienda?producto=$idProducto'
            : '/vendedor/mi-tienda');
        break;
      case 'nueva_resena':
        context.push('/vendedor/mi-tienda');
        break;
      case 'plan_vencido':
        context.push('/vendedor/planes');
        break;
      case 'pedido_cancelado':
        context.push('/comprador/dashboard');
        break;
      case 'pedido_cancelado_comprador':
        context.push('/vendedor/pedidos');
        break;
      case 'pedido_completado':
        final idTienda2 = data['id_tienda'];
        final rutaCompleto = idTienda2 != null
            ? '/valorar/${data['id_pedido']}?tienda=$idTienda2'
            : '/valorar/${data['id_pedido']}';
        context.push(rutaCompleto);
        break;
      case 'negocio_aprobado':
      case 'negocio_rechazado':
      case 'negocio_suspendido':
        context.push('/mi-perfil');
        break;
      case 'tienda_rechazada':
        context.push('/vendedor/mi-tienda');
        break;
      case 'anuncio_por_vencer':
        context.push('/mi-perfil');
        break;
      case 'tienda_eliminada_plan_vencido':
        // La tienda ya no existe -- no hay a dónde navegar dentro de
        // ella. Se ofrece crear una nueva en su lugar.
        context.push('/crear-tienda');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final leida = notificacion['leida'] == true;
    final fecha = DateTime.parse(notificacion['creado_en']).toLocal();
    final hora =
        '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
    final estilo = _estiloPorTipo(notificacion['tipo'] as String?);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: leida
            ? colorSuperficie
            : estilo.color.withOpacity(esOscuro ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(kCardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(kCardRadius),
          onTap: () {
            NotificacionesService.instance
                .marcarLeida(notificacion['id_notificacion']);
            _navegar(context);
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kCardRadius),
              border: Border.all(
                color: leida ? colorBorde : estilo.color.withOpacity(0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: estilo.color.withOpacity(esOscuro ? 0.20 : 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(estilo.icono, size: 19, color: estilo.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notificacion['titulo'] ?? '',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: leida ? FontWeight.w600 : FontWeight.w800,
                          fontSize: 13.5,
                          color: colorTexto,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        notificacion['mensaje'] ?? '',
                        style: GoogleFonts.plusJakartaSans(
                          color: colorTextoSecundario,
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        hora,
                        style: GoogleFonts.plusJakartaSans(
                          color: colorTextoSecundario,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!leida) ...[
                  const SizedBox(width: 6),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: estilo.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
