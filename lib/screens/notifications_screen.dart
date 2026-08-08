// notifications_screen.dart
//
// Lista completa de notificaciones, agrupadas por fecha (Hoy, Ayer,
// Esta semana, Anteriores). Al tocar una notificación se marca como
// leída y se navega según su 'tipo' + 'data'.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/notificaciones_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          TextButton(
            onPressed: () => NotificacionesService.instance.marcarTodasLeidas(),
            child: const Text('Marcar todas leídas'),
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
            return const Center(child: Text('No tienes notificaciones todavía'));
          }

          final grupos = _agruparPorFecha(servicio.notificaciones);

          return ListView.builder(
            itemCount: grupos.length,
            itemBuilder: (context, i) {
              final grupo = grupos[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      grupo.titulo,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                  ),
                  ...grupo.items.map((n) => _NotificacionTile(notificacion: n)),
                ],
              );
            },
          );
        },
      ),
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
    if (gHoy.isNotEmpty) grupos.add(_GrupoFecha('Hoy', gHoy));
    if (gAyer.isNotEmpty) grupos.add(_GrupoFecha('Ayer', gAyer));
    if (gSemana.isNotEmpty) grupos.add(_GrupoFecha('Esta semana', gSemana));
    if (gAnteriores.isNotEmpty) grupos.add(_GrupoFecha('Anteriores', gAnteriores));
    return grupos;
  }
}

class _GrupoFecha {
  final String titulo;
  final List<Map<String, dynamic>> items;
  _GrupoFecha(this.titulo, this.items);
}

class _NotificacionTile extends StatelessWidget {
  final Map<String, dynamic> notificacion;
  const _NotificacionTile({required this.notificacion});

  IconData _iconoPorTipo(String tipo) {
    switch (tipo) {
      case 'nuevo_pedido':
        return Icons.shopping_bag_outlined;
      case 'tienda_aprobada':
        return Icons.verified_outlined;
      case 'solicitud_plan':
        return Icons.workspace_premium_outlined;
      case 'valorar_servicio':
        return Icons.star_outline;
      case 'plan_por_vencer':
        return Icons.schedule_outlined;
      case 'pedido_por_expirar':
        return Icons.timer_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  void _navegar(BuildContext context) {
    final tipo = notificacion['tipo'];
    final data = notificacion['data'] as Map<String, dynamic>?;
    if (data == null) return;

    switch (tipo) {
      case 'nuevo_pedido':
      case 'pedido_por_expirar':
        // Ir al panel de "Gestionar Pedidos" del vendedor.
        context.push('/vendedor/pedidos');
        break;
      case 'tienda_aprobada':
      case 'plan_por_vencer':
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final leida = notificacion['leida'] == true;
    final fecha = DateTime.parse(notificacion['creado_en']).toLocal();
    final hora =
        '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: () {
        NotificacionesService.instance
            .marcarLeida(notificacion['id_notificacion']);
        _navegar(context);
      },
      child: Container(
        color: leida ? Colors.transparent : Colors.blue.shade50,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: leida ? Colors.grey.shade200 : Colors.blue.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _iconoPorTipo(notificacion['tipo']),
                size: 20,
                color: leida ? Colors.grey.shade600 : Colors.blue.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notificacion['titulo'],
                    style: TextStyle(
                      fontWeight: leida ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notificacion['mensaje'],
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hora,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (!leida)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}