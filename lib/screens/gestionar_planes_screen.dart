import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../services/tiendas_service.dart';
import '../widgets/modal_pago_plan.dart';
import '../main.dart' show AppBanner;

class GestionarPlanesScreen extends StatefulWidget {
  final Map<String, dynamic> tienda;
  const GestionarPlanesScreen({super.key, required this.tienda});

  @override
  State<GestionarPlanesScreen> createState() => _GestionarPlanesScreenState();
}

class _GestionarPlanesScreenState extends State<GestionarPlanesScreen> {
  final _tiendasService = TiendasService();
  late Future<List<Map<String, dynamic>>> _planes;
  Map<String, dynamic>? _solicitudPendiente;
  bool _cargandoSolicitud = true;
  bool _procesandoGratis = false;

  @override
  void initState() {
    super.initState();
    _planes = _tiendasService.obtenerPlanesActivos();
    _cargarSolicitudPendiente();
  }

  Future<void> _cargarSolicitudPendiente() async {
    setState(() => _cargandoSolicitud = true);
    try {
      final solicitud = await _tiendasService
          .obtenerSolicitudPendienteDeTienda(widget.tienda['id_tienda']);
      if (mounted) setState(() => _solicitudPendiente = solicitud);
    } finally {
      if (mounted) setState(() => _cargandoSolicitud = false);
    }
  }

  void _abrirModalPago(Map<String, dynamic> plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ModalPagoPlan(
        tienda: widget.tienda,
        plan: plan,
        tiendasService: _tiendasService,
        // En cuanto se crea la solicitud (antes de que WhatsApp
        // siquiera se abra), refrescamos el banner de "en revisión" --
        // así el usuario ve el cambio de estado de inmediato, sin
        // esperar a volver de WhatsApp.
        onSolicitudCreada: _cargarSolicitudPendiente,
      ),
    );
  }

  Future<void> _activarGratis(Map<String, dynamic> plan) async {
    setState(() => _procesandoGratis = true);
    try {
      await _tiendasService.activarPlanGratis(
        idTienda: widget.tienda['id_tienda'],
        idPlan: plan['id_plan'],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Plan ${plan['nombre']} activado por ${plan['duracion_dias']} días 🎉')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo activar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _procesandoGratis = false);
    }
  }

  void _abrirDetallePlan(
    Map<String, dynamic> plan, {
    required bool esActual,
    required bool esGratis,
    required bool yaUsoGratis,
    required bool esElPlanSolicitado,
    required bool haySolicitudPendiente,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(plan['nombre'] ?? '',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.bold, fontSize: 22)),
              const SizedBox(height: 8),
              Text(
                esGratis
                    ? 'Gratis'
                    : '\$${plan['precio_usd']} USD',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary),
              ),
              const SizedBox(height: 4),
              Text('Duración: ${plan['duracion_dias']} días',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, color: AppColors.inkSecundarioLight)),
              const SizedBox(height: 4),
              Text('${plan['limite_productos']} productos permitidos',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, color: AppColors.inkSecundarioLight)),
              if ((plan['descripcion'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Descripción',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 6),
                Text(plan['descripcion'],
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, height: 1.4)),
              ],
              const SizedBox(height: 24),
              if (esActual)
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                      child: Text('Este es tu plan actual',
                          style: TextStyle(color: Colors.green))),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: esGratis
                      ? OutlinedButton(
                          onPressed: (_procesandoGratis ||
                                  yaUsoGratis ||
                                  haySolicitudPendiente)
                              ? null
                              : () {
                                  Navigator.pop(sheetContext);
                                  _activarGratis(plan);
                                },
                          child: const Text('Activar'),
                        )
                      : FilledButton(
                          onPressed: haySolicitudPendiente
                              ? null
                              : () {
                                  Navigator.pop(sheetContext);
                                  _abrirModalPago(plan);
                                },
                          child: Text(esElPlanSolicitado
                              ? 'Pendiente de revisión'
                              : 'Activar'),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final planActual =
        (widget.tienda['plan'] as String? ?? 'basic').toLowerCase();
    final haySolicitudPendiente = _solicitudPendiente != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Gestionar Planes')),
      body: RefreshIndicator(
        onRefresh: _cargarSolicitudPendiente,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _planes,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting ||
                _cargandoSolicitud) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final planes = snapshot.data ?? [];
            if (planes.isEmpty) {
              return const Center(
                  child: Text('No hay planes disponibles todavía'));
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (haySolicitudPendiente) ...[
                  AppBanner(
                    icon: Icons.hourglass_top_rounded,
                    titulo: 'Solicitud en revisión',
                    mensaje:
                        'Tu cambio al plan "${_solicitudPendiente!['planes']?['nombre'] ?? ''}" '
                        'está pendiente de que el administrador verifique tu pago. '
                        'No puedes solicitar otro cambio mientras esta esté activa.',
                  ),
                  const SizedBox(height: 16),
                ],
                ...planes.map((p) {
                  final esGratis = p['es_gratis'] as bool? ?? false;
                  final esActual = (p['codigo'] as String? ?? '')
                          .toLowerCase() ==
                      planActual;
                  final yaUsoGratis =
                      widget.tienda['plan_gratis_usado'] as bool? ?? false;
                  final esElPlanSolicitado = haySolicitudPendiente &&
                      _solicitudPendiente!['id_plan_solicitado'] ==
                          p['id_plan'];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _abrirDetallePlan(
                        p,
                        esActual: esActual,
                        esGratis: esGratis,
                        yaUsoGratis: yaUsoGratis,
                        esElPlanSolicitado: esElPlanSolicitado,
                        haySolicitudPendiente: haySolicitudPendiente,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(p['nombre'] ?? '',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18)),
                              if (esActual)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text('Plan actual',
                                      style: TextStyle(
                                          color: Colors.green, fontSize: 12)),
                                )
                              else if (esElPlanSolicitado)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.mostazaLight,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text('Pendiente de revisión',
                                      style: GoogleFonts.plusJakartaSans(
                                          color: AppColors.warm,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            esGratis
                                ? 'Gratis · ${p['duracion_dias']} días'
                                : '\$${p['precio_usd']} USD',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 16, color: AppColors.ink),
                          ),
                          Text('${p['limite_productos']} productos permitidos',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: AppColors.inkSecundarioLight)),
                          if ((p['descripcion'] ?? '')
                              .toString()
                              .isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(p['descripcion'],
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    color: AppColors.inkSecundarioLight)),
                          ],
                          if (esGratis && yaUsoGratis && !esActual) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Ya usaste tu plan gratuito anteriormente. Solo se puede activar una vez por cuenta.',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5, color: Colors.red.shade700),
                            ),
                          ],
                          const SizedBox(height: 12),
                          if (!esActual)
                            SizedBox(
                              width: double.infinity,
                              child: esGratis
                                  ? OutlinedButton(
                                      onPressed: (_procesandoGratis ||
                                              yaUsoGratis ||
                                              haySolicitudPendiente)
                                          ? null
                                          : () => _activarGratis(p),
                                      child: _procesandoGratis
                                          ? const SizedBox(
                                              height: 16,
                                              width: 16,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))
                                          : const Text('Activar gratis'),
                                    )
                                  : FilledButton(
                                      onPressed: haySolicitudPendiente
                                          ? null
                                          : () => _abrirModalPago(p),
                                      child: Text(esElPlanSolicitado
                                          ? 'Pendiente de revisión'
                                          : 'Seleccionar este plan'),
                                    ),
                            ),
                        ],
                      ),
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }
}