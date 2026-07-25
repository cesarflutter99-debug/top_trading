import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/supabase_client.dart';
import 'gestionar_ventas_screen.dart';

class GestionarTiendaScreen extends StatefulWidget {
  final Map<String, dynamic> tienda;

  const GestionarTiendaScreen({super.key, required this.tienda});

  @override
  State<GestionarTiendaScreen> createState() => _GestionarTiendaScreenState();
}

class _GestionarTiendaScreenState extends State<GestionarTiendaScreen> {
  late String _planActual = widget.tienda['plan'] ?? 'basic';
  bool _procesando = false;

  // ---------------------------------------------------------------------
  // 1. ELIMINAR TIENDA
  // ---------------------------------------------------------------------
  Future<void> _confirmarEliminarTienda() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar tienda?'),
        content: const Text(
          'Esta acción es permanente. Se borrarán todos tus productos '
          'y no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _procesando = true);
    try {
      final idTienda = widget.tienda['id_tienda'];
      await supabase.from('tiendas').delete().eq('id_tienda', idTienda);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tienda eliminada')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar la tienda: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  // ---------------------------------------------------------------------
  // 2. CAMBIAR DE PLAN
  // ---------------------------------------------------------------------
  Future<void> _cambiarPlan() async {
    final nuevoPlan = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar plan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('Basic'),
              subtitle: const Text('20 productos, 20 fotos'),
              value: 'basic',
              groupValue: _planActual,
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
            RadioListTile<String>(
              title: const Text('Premium'),
              subtitle: const Text('50 productos, 50 fotos, Portada Mensual'),
              value: 'premium',
              groupValue: _planActual,
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (nuevoPlan == null || nuevoPlan == _planActual) return;

    setState(() => _procesando = true);
    try {
      final idTienda = widget.tienda['id_tienda'];
      await supabase
          .from('tiendas')
          .update({'plan': nuevoPlan})
          .eq('id_tienda', idTienda);

      setState(() => _planActual = nuevoPlan);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Plan actualizado a ${nuevoPlan == "premium" ? "Premium" : "Basic"}',
            ),
          ),
        );
        // Ofrecemos de una vez enviar el pago/verificación por WhatsApp
        _solicitarVerificacion();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cambiar el plan: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  // ---------------------------------------------------------------------
  // 3. SOLICITAR VERIFICACIÓN POR WHATSAPP
  //    Lee el número marcado como activo=true en contactos_whatsapp.
  //    Debe haber SOLO UNO activo (garantízalo desde el panel de admin).
  // ---------------------------------------------------------------------
  Future<String?> _obtenerNumeroWhatsappActivo() async {
    try {
      final data = await supabase
          .from('contactos_whatsapp')
          .select('telefono')
          .eq('activo', true)
          .limit(1)
          .maybeSingle();
      return data?['telefono'] as String?;
    } catch (e) {
      debugPrint('Error obteniendo número WhatsApp activo: $e');
      return null;
    }
  }

  Future<void> _solicitarVerificacion() async {
    setState(() => _procesando = true);
    final numero = await _obtenerNumeroWhatsappActivo();
    if (mounted) setState(() => _procesando = false);

    if (numero == null || numero.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No hay un número de contacto activo configurado. '
              'Contacta al administrador.',
            ),
          ),
        );
      }
      return;
    }

    final usuario = supabase.auth.currentUser;
    final idUsuario = usuario?.email ?? usuario?.id ?? 'desconocido';
    final nombrePlan = _planActual == 'premium' ? 'Premium' : 'Basic';

    final mensaje = Uri.encodeComponent(
      'Hola, soy el usuario $idUsuario y quiero verificar mi tienda '
      'con el plan $nombrePlan.',
    );

    final url = Uri.parse('https://wa.me/$numero?text=$mensaje');

    final abierto = await launchUrl(url, mode: LaunchMode.externalApplication);

    if (!abierto && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp')),
      );
    }
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Gestionar Tienda')),
      body: AbsorbPointer(
        absorbing: _procesando,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: primary.withOpacity(0.1),
                      child: Icon(Icons.receipt_long_outlined, color: primary),
                    ),
                    title: Text('Gestionar Ventas',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Solicitudes pendientes y ventas del mes'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GestionarVentasScreen(tienda: widget.tienda),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: primary.withOpacity(0.1),
                      child: Icon(Icons.workspace_premium_outlined, color: primary),
                    ),
                    title: Text(
                      'Plan actual: ${_planActual == "premium" ? "Premium" : "Basic"}',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Toca para cambiar de plan'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _cambiarPlan,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFDCF8C6),
                      child: Icon(Icons.verified_outlined, color: Colors.green),
                    ),
                    title: Text('Solicitar verificación',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Envía tu solicitud por WhatsApp'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _solicitarVerificacion,
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  color: Colors.red.withOpacity(0.05),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.red,
                      child: Icon(Icons.delete_outline, color: Colors.white),
                    ),
                    title: Text(
                      'Eliminar tienda',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600, color: Colors.red),
                    ),
                    subtitle: const Text('Acción permanente'),
                    onTap: _confirmarEliminarTienda,
                  ),
                ),
              ],
            ),
            if (_procesando) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
