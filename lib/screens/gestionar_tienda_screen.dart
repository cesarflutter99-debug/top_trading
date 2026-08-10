import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/storage_service.dart';
import '../services/tiendas_service.dart';
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
  final _tiendasService = TiendasService();
  final _formKey = GlobalKey<FormState>();

  late Map<String, dynamic> _tienda;
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _telefonoCtrl;
  late final TextEditingController _provinciaCtrl;
  late final TextEditingController _municipioCtrl;
  late final TextEditingController _descripcionCtrl;

  bool _procesando = false;
  bool _subiendoLogo = false;
  bool _subiendoPortada = false;
  bool _editandoDatos = false;

  @override
  void initState() {
    super.initState();
    _tienda = Map<String, dynamic>.from(widget.tienda);
    _nombreCtrl = TextEditingController(text: _tienda['nombre'] ?? '');
    _telefonoCtrl =
        TextEditingController(text: _tienda['telefono_whatsapp'] ?? '');
    _provinciaCtrl = TextEditingController(text: _tienda['provincia'] ?? '');
    _municipioCtrl = TextEditingController(text: _tienda['municipio'] ?? '');
    _descripcionCtrl =
        TextEditingController(text: _tienda['descripcion'] ?? '');
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _provinciaCtrl.dispose();
    _municipioCtrl.dispose();
    _descripcionCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // FOTOS (logo / portada)
  // ---------------------------------------------------------------------
  Future<void> _cambiarLogo() async {
    final archivo = await _storageService.elegirFoto();
    if (archivo == null) return;
    setState(() => _subiendoLogo = true);
    try {
      final url = await _storageService.subirLogoTienda(
        archivo: archivo,
        idTienda: _tienda['id_tienda'],
      );
      await _tiendasService.actualizarLogoTienda(
        idTienda: _tienda['id_tienda'],
        logoUrl: url,
      );
      if (mounted) setState(() => _tienda['logo_url'] = url);
    } catch (e) {
      _mostrarError('No se pudo subir el logo: $e');
    } finally {
      if (mounted) setState(() => _subiendoLogo = false);
    }
  }

  Future<void> _cambiarPortada() async {
    final archivo = await _storageService.elegirFoto();
    if (archivo == null) return;
    setState(() => _subiendoPortada = true);
    try {
      final url = await _storageService.subirPortadaTienda(
        archivo: archivo,
        idTienda: _tienda['id_tienda'],
      );
      await _tiendasService.actualizarPortadaTienda(
        idTienda: _tienda['id_tienda'],
        portadaUrl: url,
      );
      if (mounted) setState(() => _tienda['imagen_portada'] = url);
    } catch (e) {
      _mostrarError('No se pudo subir la portada: $e');
    } finally {
      if (mounted) setState(() => _subiendoPortada = false);
    }
  }

  // ---------------------------------------------------------------------
  // DATOS BÁSICOS
  // ---------------------------------------------------------------------
  Future<void> _guardarDatos() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _procesando = true);
    try {
      await _tiendasService.actualizarTienda(
        idTienda: _tienda['id_tienda'],
        nombre: _nombreCtrl.text.trim(),
        telefonoWhatsapp: _telefonoCtrl.text.trim(),
        provincia: _provinciaCtrl.text.trim(),
        municipio: _municipioCtrl.text.trim(),
        descripcion: _descripcionCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {
          _tienda['nombre'] = _nombreCtrl.text.trim();
          _tienda['telefono_whatsapp'] = _telefonoCtrl.text.trim();
          _tienda['provincia'] = _provinciaCtrl.text.trim();
          _tienda['municipio'] = _municipioCtrl.text.trim();
          _tienda['descripcion'] = _descripcionCtrl.text.trim();
          _editandoDatos = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos actualizados ✅')),
        );
      }
    } catch (e) {
      _mostrarError('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _mostrarError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ---------------------------------------------------------------------
  // ELIMINAR TIENDA
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
      final idTienda = _tienda['id_tienda'];
      await _storageService.borrarArchivosDeTienda(idTienda);
      await supabase.from('tiendas').delete().eq('id_tienda', idTienda);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tienda eliminada')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _mostrarError('No se pudo eliminar la tienda: $e');
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
              padding: EdgeInsets.zero,
              children: [
                _buildPortadaYLogo(primary),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildEstadisticas(),
                      const SizedBox(height: 16),
                      _buildDatosBasicos(primary),
                      const SizedBox(height: 16),
                      _buildAccesos(primary),
                      const SizedBox(height: 24),
                      _buildEliminar(),
                    ],
                  ),
                ),
              ],
            ),
            if (_procesando)
              const ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Secciones
  // ---------------------------------------------------------------------
  Widget _buildPortadaYLogo(Color primary) {
    final portadaUrl = _tienda['imagen_portada'] as String?;
    final logoUrl = _tienda['logo_url'] as String?;

    return SizedBox(
      height: 190,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ---------- Portada ----------
          GestureDetector(
            onTap: _subiendoPortada ? null : _cambiarPortada,
            child: Container(
              height: 150,
              width: double.infinity,
              color: Colors.grey.shade300,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (portadaUrl != null && portadaUrl.isNotEmpty)
                    Image.network(portadaUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade300,
                            ))
                  else
                    Container(color: Colors.grey.shade300),
                  Container(color: Colors.black.withOpacity(0.15)),
                  if (_subiendoPortada)
                    const Center(child: CircularProgressIndicator())
                  else
                    const Center(
                      child: Icon(Icons.camera_alt_outlined,
                          color: Colors.white, size: 28),
                    ),
                ],
              ),
            ),
          ),
          // ---------- Logo ----------
          Positioned(
            left: 16,
            bottom: 0,
            child: GestureDetector(
              onTap: _subiendoLogo ? null : _cambiarLogo,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  color: Colors.grey.shade200,
                ),
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (logoUrl != null && logoUrl.isNotEmpty)
                        Image.network(logoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Icon(Icons.storefront, color: primary))
                      else
                        Icon(Icons.storefront, color: primary),
                      if (_subiendoLogo)
                        const ColoredBox(
                          color: Colors.black38,
                          child: Center(
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            ),
                          ),
                        )
                      else
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.camera_alt,
                                size: 14, color: primary),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadisticas() {
    final puntosTotales = _tienda['puntos_totales'] ?? 0;
    final puntosSemanales = _tienda['puntos_semanales'] ?? 0;
    final estrellas =
        ((_tienda['promedio_estrellas'] as num?) ?? 0).toStringAsFixed(1);
    final totalValoraciones = _tienda['total_valoraciones'] ?? 0;

    return Row(
      children: [
        Expanded(
          child: _statBox('$puntosTotales', 'Puntos totales',
              Icons.stars_rounded, Colors.amber.shade700),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statBox('$puntosSemanales', 'Puntos semana',
              Icons.local_fire_department_rounded, Colors.deepOrange),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statBox('$estrellas ⭐', '$totalValoraciones reseñas',
              Icons.reviews_outlined, AppColors.primary),
        ),
      ],
    );
  }

  Widget _statBox(String valor, String etiqueta, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(valor,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 2),
          Text(etiqueta,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5, color: AppColors.inkSecundarioLight)),
        ],
      ),
    );
  }

  Widget _buildDatosBasicos(Color primary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Datos de la tienda',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  TextButton(
                    onPressed: _procesando
                        ? null
                        : () {
                            if (_editandoDatos) {
                              _guardarDatos();
                            } else {
                              setState(() => _editandoDatos = true);
                            }
                          },
                    child: Text(_editandoDatos ? 'Guardar' : 'Editar'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_editandoDatos) ...[
                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefonoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration:
                      const InputDecoration(labelText: 'Teléfono (WhatsApp)'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _provinciaCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Provincia'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Requerido'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _municipioCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Municipio'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Requerido'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descripcionCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
              ] else ...[
                _filaDato(Icons.storefront_outlined, _tienda['nombre'] ?? ''),
                _filaDato(
                    Icons.chat_outlined, _tienda['telefono_whatsapp'] ?? ''),
                _filaDato(Icons.location_on_outlined,
                    '${_tienda['municipio'] ?? ''}, ${_tienda['provincia'] ?? ''}'),
                if ((_tienda['descripcion'] ?? '').toString().isNotEmpty)
                  _filaDato(Icons.notes_outlined, _tienda['descripcion']),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _filaDato(IconData icon, String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.inkSecundarioLight),
          const SizedBox(width: 10),
          Expanded(
            child:
                Text(texto, style: GoogleFonts.plusJakartaSans(fontSize: 13.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildAccesos(Color primary) {
    return Column(
      children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: primary.withOpacity(0.1),
              child: Icon(Icons.receipt_long_outlined, color: primary),
            ),
            title: Text('Gestionar Ventas',
                style:
                    GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            subtitle: const Text('Solicitudes pendientes y ventas del mes'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GestionarVentasScreen(tienda: _tienda),
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
                style:
                    GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            subtitle: const Text('Editar, ocultar o eliminar productos'),
            trailing: const Icon(Icons.chevron_right_rounded),
            // Los productos ya se gestionan en PanelVendedorScreen (grid
            // + ProductEditModal al tocar uno). Esta pantalla está
            // apilada encima de esa, así que simplemente regresamos.
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
                style:
                    GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            subtitle: Text('Plan actual: ${_tienda['plan'] ?? 'Sin plan'}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GestionarPlanesScreen(tienda: _tienda),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEliminar() {
    return Card(
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
    );
  }
}
