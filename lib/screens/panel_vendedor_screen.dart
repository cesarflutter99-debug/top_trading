import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../core/supabase_client.dart';
import '../services/storage_service.dart';
import '../services/tiendas_service.dart';
import 'admin_panel_screen.dart';
import 'agregar_producto_screen.dart';
import 'gestionar_tienda_screen.dart';
import 'welcome_screen.dart';

class PanelVendedorScreen extends StatefulWidget {
  final Map<String, dynamic> tienda;

  const PanelVendedorScreen({super.key, required this.tienda});

  @override
  State<PanelVendedorScreen> createState() => _PanelVendedorScreenState();
}

class _PanelVendedorScreenState extends State<PanelVendedorScreen> {
  final _tiendasService = TiendasService();
  final _storageService = StorageService();
  final _picker = ImagePicker();
  late Map<String, dynamic> _tienda;
  late Future<List<Map<String, dynamic>>> _productos;
  bool _esAdmin = false;
  bool _subiendoLogo = false;

  @override
  void initState() {
    super.initState();
    _tienda = widget.tienda;
    _cargarProductos();
    _chequearAdmin();
  }

  Future<void> _chequearAdmin() async {
    final admin = await _tiendasService.esAdmin();
    if (mounted) setState(() => _esAdmin = admin);
  }

  Future<void> _cambiarLogo() async {
    final XFile? archivo = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (archivo == null) return;

    setState(() => _subiendoLogo = true);
    try {
      final url = await _storageService.subirLogoTienda(
        archivo: File(archivo.path),
        idTienda: _tienda['id_tienda'] as String,
      );
      await _tiendasService.actualizarLogoTienda(
        idTienda: _tienda['id_tienda'] as String,
        logoUrl: url,
      );
      await _recargarTodo();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo subir el logo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _subiendoLogo = false);
    }
  }

  void _cargarProductos() {
    _productos = _tiendasService.obtenerProductosDeTienda(_tienda['id_tienda'] as String);
  }

  Future<void> _recargarTodo() async {
    final actualizada = await _tiendasService.obtenerMiTienda();
    if (actualizada != null && mounted) {
      setState(() {
        _tienda = actualizada;
        _cargarProductos();
      });
    } else {
      setState(_cargarProductos);
    }
  }

  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text('Tendrás que volver a iniciar sesión con Google para gestionar tu tienda.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (confirmar != true) return;

    await supabase.auth.signOut();

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    }
  }

  void _abrirEdicion() {
    final nombreCtrl = TextEditingController(text: _tienda['nombre'] ?? '');
    final telefonoCtrl = TextEditingController(text: _tienda['telefono_whatsapp'] ?? '');
    final provinciaCtrl = TextEditingController(text: _tienda['provincia'] ?? '');
    final municipioCtrl = TextEditingController(text: _tienda['municipio'] ?? '');
    bool guardando = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Editar tienda', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre del negocio', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: telefonoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'WhatsApp', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: provinciaCtrl,
                  decoration: const InputDecoration(labelText: 'Provincia', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: municipioCtrl,
                  decoration: const InputDecoration(labelText: 'Municipio', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: guardando ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: guardando
                  ? null
                  : () async {
                      setDialogState(() => guardando = true);
                      try {
                        await _tiendasService.actualizarTienda(
                          idTienda: _tienda['id_tienda'] as String,
                          nombre: nombreCtrl.text.trim(),
                          telefonoWhatsapp: telefonoCtrl.text.trim(),
                          provincia: provinciaCtrl.text.trim(),
                          municipio: municipioCtrl.text.trim(),
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          await _recargarTodo();
                        }
                      } catch (e) {
                        setDialogState(() => guardando = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error al guardar: $e')),
                          );
                        }
                      }
                    },
              child: guardando
                  ? const SizedBox(
                      height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final estado = _tienda['estado'] as String? ?? 'pending';
    final esPending = estado == 'pending';

    return Scaffold(
      appBar: AppBar(
        title: Text(_tienda['nombre'] ?? 'Mi tienda'),
        actions: [
          if (_esAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              tooltip: 'Panel Admin',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminPanelScreen()),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar información',
            onPressed: _abrirEdicion,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: _cerrarSesion,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AgregarProductoScreen(idTienda: _tienda['id_tienda'] as String),
            ),
          );
          await _recargarTodo();
        },
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Nuevo producto'),
      ),
      body: RefreshIndicator(
        onRefresh: _recargarTodo,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---------- Header visual: logo, nombre, VIP, estrellas, puntos ----------
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _subiendoLogo ? null : _cambiarLogo,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: Colors.grey[200],
                                backgroundImage: (_tienda['logo_url'] != null &&
                                        (_tienda['logo_url'] as String).isNotEmpty)
                                    ? NetworkImage(_tienda['logo_url'] as String)
                                    : null,
                                child: (_tienda['logo_url'] == null ||
                                        (_tienda['logo_url'] as String).isEmpty)
                                    ? const Icon(Icons.storefront_outlined, size: 32, color: Colors.grey)
                                    : null,
                              ),
                              if (_subiendoLogo)
                                const CircularProgressIndicator(strokeWidth: 2)
                              else
                                Positioned(
                                  bottom: -2,
                                  right: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                    child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _tienda['nombre'] ?? '',
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if ((_tienda['plan'] as String? ?? 'basic') == 'premium') ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.star_rounded, size: 12, color: Colors.white),
                                          SizedBox(width: 2),
                                          Text('VIP', style: TextStyle(
                                              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_tienda['municipio'] ?? ''}, ${_tienda['provincia'] ?? ''}',
                                style: GoogleFonts.inter(fontSize: 12, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _statChip(
                            icon: Icons.star_rounded,
                            color: Colors.amber[700]!,
                            valor: (_tienda['promedio_estrellas'] ?? 0).toString(),
                            etiqueta: 'Estrellas',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _statChip(
                            icon: Icons.bolt_rounded,
                            color: primary,
                            valor: (_tienda['puntos'] ?? 0).toString(),
                            etiqueta: 'Puntos',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => GestionarTiendaScreen(tienda: _tienda),
                            ),
                          );
                        },
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Gestionar Tienda'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ---------- Banner de estado ----------
            if (esPending)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFCC80)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.hourglass_top_rounded, color: Color(0xFFE65100)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tienda en revisión',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFFE65100)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tu tienda todavía no es visible en el marketplace. '
                              'Puedes gestionar tu información y subir productos mientras '
                              'el administrador la verifica; las fotos se harán públicas '
                              'una vez aprobada.',
                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFE65100), height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFA5D6A7)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_rounded, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Tienda activa y visible en el marketplace',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF2E7D32)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // ---------- Datos de la tienda ----------
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Plan', style: GoogleFonts.inter(color: Colors.black54)),
                        Text(
                          (_tienda['plan'] as String? ?? 'basic').toUpperCase(),
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: primary),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('WhatsApp', style: GoogleFonts.inter(color: Colors.black54)),
                        Text(_tienda['telefono_whatsapp'] ?? '-'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Ubicación', style: GoogleFonts.inter(color: Colors.black54)),
                        Text('${_tienda['municipio'] ?? ''}, ${_tienda['provincia'] ?? ''}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            Text('Mis productos', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 12),

            FutureBuilder<List<Map<String, dynamic>>>(
              future: _productos,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final productos = snapshot.data ?? [];
                if (productos.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'Aún no tienes productos. Toca "Nuevo producto" para agregar el primero.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(color: Colors.black54),
                      ),
                    ),
                  );
                }
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: productos.length,
                  itemBuilder: (context, i) {
                    final p = productos[i];
                    final visible = p['es_visible'] as bool? ?? true;
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  p['imagen_url'] ?? '',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.image_not_supported_outlined),
                                  ),
                                ),
                                if (esPending)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'No público',
                                        style: TextStyle(color: Colors.white, fontSize: 10),
                                      ),
                                    ),
                                  ),
                                if (!visible && !esPending)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'Oculto',
                                        style: TextStyle(color: Colors.white, fontSize: 10),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p['nombre'] ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                Text(
                                  '\$${p['precio_usd']}',
                                  style: GoogleFonts.inter(color: Colors.black54, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _statChip({
    required IconData icon,
    required Color color,
    required String valor,
    required String etiqueta,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 2),
          Text(valor, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
          Text(etiqueta, style: GoogleFonts.inter(fontSize: 11, color: Colors.black54)),
        ],
      ),
    );
  }
}
