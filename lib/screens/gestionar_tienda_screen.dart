import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/storage_service.dart';
import 'gestionar_planes_screen.dart';
import 'gestionar_ventas_screen.dart';

class GestionarTiendaScreen extends StatefulWidget {
  final Map<String, dynamic> tienda;

  const GestionarTiendaScreen({
    super.key,
    required this.tienda,
  });

  @override
  State<GestionarTiendaScreen> createState() => _GestionarTiendaScreenState();
}

class _GestionarTiendaScreenState extends State<GestionarTiendaScreen> {
  final _storageService = StorageService();
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
      // Primero los archivos (logo, portada, fotos de productos), para
      // no dejar nada huérfano ocupando espacio en Storage; después la
      // fila de la base de datos.
      await _storageService.borrarArchivosDeTienda(idTienda);
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
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600)),
                    subtitle:
                        const Text('Solicitudes pendientes y ventas del mes'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              GestionarVentasScreen(tienda: widget.tienda),
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
                      child: Icon(Icons.inventory_2_outlined, color: primary),
                    ),
                    title: Text('Gestionar Productos',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600)),
                    subtitle:
                        const Text('Editar, ocultar o eliminar productos'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    // Los productos ya se gestionan en PanelVendedorScreen
                    // (grid + ProductEditModal al tocar uno, botón "Nuevo
                    // producto"). Esta pantalla está apilada encima de esa,
                    // así que simplemente regresamos a ella.
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      child: const Icon(Icons.workspace_premium_outlined,
                          color: AppColors.primary),
                    ),
                    title: Text('Cambiar Plan',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Plan actual: ${widget.tienda['plan'] ?? 'Sin plan'}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              GestionarPlanesScreen(tienda: widget.tienda),
                        ),
                      );
                    },
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
                      style: GoogleFonts.plusJakartaSans(
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
