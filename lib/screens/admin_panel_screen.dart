import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/supabase_client.dart';
import '../services/tiendas_service.dart';
import 'panel_vendedor_screen.dart';
import 'welcome_screen.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen>
    with SingleTickerProviderStateMixin {
  final _tiendasService = TiendasService();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _irAMiTienda() async {
    final tienda = await _tiendasService.obtenerMiTienda();
    if (!mounted) return;
    if (tienda == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta cuenta admin no tiene tienda propia')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PanelVendedorScreen(tienda: tienda)),
    );
  }

  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text('Tendrás que volver a iniciar sesión con Google.'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Administrador'),
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: 'Mi tienda',
            onPressed: _irAMiTienda,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: _cerrarSesion,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.storefront_outlined), text: 'Pendientes'),
            Tab(icon: Icon(Icons.chat_outlined), text: 'WhatsApp'),
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Tiendas y Productos'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _TiendasPendientesTab(tiendasService: _tiendasService),
          _ContactosWhatsappTab(tiendasService: _tiendasService),
          _TiendasYProductosTab(tiendasService: _tiendasService),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// TAB 1: Tiendas pendientes de aprobación
// ---------------------------------------------------------------------

class _TiendasPendientesTab extends StatefulWidget {
  final TiendasService tiendasService;
  const _TiendasPendientesTab({required this.tiendasService});

  @override
  State<_TiendasPendientesTab> createState() => _TiendasPendientesTabState();
}

class _TiendasPendientesTabState extends State<_TiendasPendientesTab> {
  late Future<List<Map<String, dynamic>>> _pendientes;
  final Set<String> _procesando = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _pendientes = widget.tiendasService.obtenerTiendasPendientes();
  }

  Future<void> _aprobar(String idTienda) async {
    setState(() => _procesando.add(idTienda));
    try {
      await widget.tiendasService.aprobarTienda(idTienda);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tienda aprobada ✅')),
        );
        setState(_cargar);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al aprobar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando.remove(idTienda));
    }
  }

  Future<void> _rechazar(String idTienda) async {
    setState(() => _procesando.add(idTienda));
    try {
      await widget.tiendasService.rechazarTienda(idTienda);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tienda rechazada')),
        );
        setState(_cargar);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al rechazar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando.remove(idTienda));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(_cargar),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _pendientes,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _mensajeVacio('Error al cargar: ${snapshot.error}');
          }
          final tiendas = snapshot.data ?? [];
          if (tiendas.isEmpty) {
            return _mensajeVacio('No hay tiendas pendientes de aprobación');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tiendas.length,
            itemBuilder: (context, i) {
              final t = tiendas[i];
              final id = t['id_tienda'] as String;
              final procesando = _procesando.contains(id);
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['nombre'] ?? '',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('${t['municipio'] ?? ''}, ${t['provincia'] ?? ''}',
                          style: GoogleFonts.inter(color: Colors.black54, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('Plan: ${t['plan'] ?? ''}',
                          style: GoogleFonts.inter(color: Colors.black54, fontSize: 13)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: procesando ? null : () => _rechazar(id),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                              child: const Text('Rechazar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: procesando ? null : () => _aprobar(id),
                              child: procesando
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Aprobar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _mensajeVacio(String texto) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Text(texto, style: GoogleFonts.inter(color: Colors.black54)),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// TAB 2: Números de WhatsApp de verificación
// ---------------------------------------------------------------------

class _ContactosWhatsappTab extends StatefulWidget {
  final TiendasService tiendasService;
  const _ContactosWhatsappTab({required this.tiendasService});

  @override
  State<_ContactosWhatsappTab> createState() => _ContactosWhatsappTabState();
}

class _ContactosWhatsappTabState extends State<_ContactosWhatsappTab> {
  late Future<List<Map<String, dynamic>>> _contactos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _contactos = widget.tiendasService.obtenerContactosWhatsapp();
  }

  // Al activar un número, desactivamos los demás para garantizar
  // que SOLO UNO quede activo (es el que usará gestionar_tienda_screen.dart)
  Future<void> _toggleActivo(String id, bool actual) async {
    try {
      if (!actual) {
        final todos = await widget.tiendasService.obtenerContactosWhatsapp();
        for (final c in todos) {
          if (c['id'] != id && (c['activo'] as bool? ?? false)) {
            await widget.tiendasService.actualizarActivoContactoWhatsapp(
              id: c['id'] as String,
              activo: false,
            );
          }
        }
      }
      await widget.tiendasService.actualizarActivoContactoWhatsapp(
        id: id,
        activo: !actual,
      );
      setState(_cargar);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _eliminar(String id) async {
    try {
      await widget.tiendasService.eliminarContactoWhatsapp(id);
      setState(_cargar);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _mostrarDialogoAgregar() {
    final telefonoCtrl = TextEditingController();
    final etiquetaCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nuevo número de WhatsApp'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: telefonoCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono',
                hintText: '5355XXXXXXX (sin +)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: etiquetaCtrl,
              decoration: const InputDecoration(
                labelText: 'Etiqueta (opcional)',
                hintText: 'Ej: Principal',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final telefono = telefonoCtrl.text.trim();
              if (telefono.isEmpty) return;
              try {
                await widget.tiendasService.agregarContactoWhatsapp(
                  telefono: telefono,
                  etiqueta: etiquetaCtrl.text.trim().isEmpty
                      ? null
                      : etiquetaCtrl.text.trim(),
                );
                if (mounted) {
                  Navigator.pop(context);
                  setState(_cargar);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarDialogoAgregar,
        icon: const Icon(Icons.add),
        label: const Text('Agregar número'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_cargar),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _contactos,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final contactos = snapshot.data ?? [];
            if (contactos.isEmpty) {
              return LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: Text(
                        'Sin números configurados.\nAgrega uno con el botón +',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(color: Colors.black54),
                      ),
                    ),
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: contactos.length,
              itemBuilder: (context, i) {
                final c = contactos[i];
                final id = c['id'] as String;
                final activo = c['activo'] as bool? ?? false;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      Icons.chat,
                      color: activo ? Colors.green : Colors.black26,
                    ),
                    title: Text(c['telefono'] ?? ''),
                    subtitle: Text(
                      activo
                          ? '${c['etiqueta'] ?? 'Sin etiqueta'} · Activo (en uso)'
                          : c['etiqueta'] ?? 'Sin etiqueta',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: activo,
                          onChanged: (_) => _toggleActivo(id, activo),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _eliminar(id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// TAB 3: Todas las tiendas y sus productos (agregar / eliminar)
// ---------------------------------------------------------------------

class _TiendasYProductosTab extends StatefulWidget {
  final TiendasService tiendasService;
  const _TiendasYProductosTab({required this.tiendasService});

  @override
  State<_TiendasYProductosTab> createState() => _TiendasYProductosTabState();
}

class _TiendasYProductosTabState extends State<_TiendasYProductosTab> {
  late Future<List<Map<String, dynamic>>> _tiendas;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _tiendas = widget.tiendasService.obtenerTodasLasTiendas();
  }

  Future<void> _confirmarEliminarTienda(String idTienda, String nombre) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar tienda?'),
        content: Text(
          'Se eliminará "$nombre" y todos sus productos. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await widget.tiendasService.eliminarTiendaComoAdmin(idTienda);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tienda eliminada')),
        );
        setState(_cargar);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e')),
        );
      }
    }
  }

  void _mostrarDialogoAgregarTienda() {
    final nombreCtrl = TextEditingController();
    final provinciaCtrl = TextEditingController();
    final municipioCtrl = TextEditingController();
    String planSeleccionado = 'basic';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Agregar tienda manualmente'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre de la tienda'),
                ),
                TextField(
                  controller: provinciaCtrl,
                  decoration: const InputDecoration(labelText: 'Provincia'),
                ),
                TextField(
                  controller: municipioCtrl,
                  decoration: const InputDecoration(labelText: 'Municipio'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: planSeleccionado,
                  decoration: const InputDecoration(labelText: 'Plan'),
                  items: const [
                    DropdownMenuItem(value: 'basic', child: Text('Basic')),
                    DropdownMenuItem(value: 'premium', child: Text('Premium')),
                  ],
                  onChanged: (v) => setDialogState(() => planSeleccionado = v ?? 'basic'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (nombreCtrl.text.trim().isEmpty) return;
                try {
                  await widget.tiendasService.crearTiendaManual(
                    nombre: nombreCtrl.text.trim(),
                    provincia: provinciaCtrl.text.trim(),
                    municipio: municipioCtrl.text.trim(),
                    plan: planSeleccionado,
                  );
                  if (mounted) {
                    Navigator.pop(ctx);
                    setState(_cargar);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirProductosDeTienda(String idTienda, String nombreTienda) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ProductosDeTiendaScreen(
          idTienda: idTienda,
          nombreTienda: nombreTienda,
          tiendasService: widget.tiendasService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarDialogoAgregarTienda,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Agregar tienda'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_cargar),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _tiendas,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final tiendas = snapshot.data ?? [];
            if (tiendas.isEmpty) {
              return LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: const Center(child: Text('No hay tiendas registradas')),
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: tiendas.length,
              itemBuilder: (context, i) {
                final t = tiendas[i];
                final id = t['id_tienda'] as String;
                final nombre = t['nombre'] ?? '';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: (t['estado'] == 'active')
                          ? Colors.green.withOpacity(0.15)
                          : Colors.orange.withOpacity(0.15),
                      child: Icon(
                        Icons.storefront_outlined,
                        color: (t['estado'] == 'active') ? Colors.green : Colors.orange,
                      ),
                    ),
                    title: Text(nombre, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${t['estado'] ?? ''} · ${t['plan'] ?? ''} · '
                      '${t['municipio'] ?? ''}, ${t['provincia'] ?? ''}',
                    ),
                    onTap: () => _abrirProductosDeTienda(id, nombre),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmarEliminarTienda(id, nombre),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Pantalla auxiliar: productos de una tienda específica (admin)
// ---------------------------------------------------------------------

class _ProductosDeTiendaScreen extends StatefulWidget {
  final String idTienda;
  final String nombreTienda;
  final TiendasService tiendasService;

  const _ProductosDeTiendaScreen({
    required this.idTienda,
    required this.nombreTienda,
    required this.tiendasService,
  });

  @override
  State<_ProductosDeTiendaScreen> createState() => _ProductosDeTiendaScreenState();
}

class _ProductosDeTiendaScreenState extends State<_ProductosDeTiendaScreen> {
  late Future<List<Map<String, dynamic>>> _productos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _productos = widget.tiendasService.obtenerProductosDeTienda(widget.idTienda);
  }

  Future<void> _confirmarEliminarProducto(String idProducto, String nombre) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar producto?'),
        content: Text('Se eliminará "$nombre" permanentemente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await widget.tiendasService.eliminarProducto(idProducto);
      if (mounted) {
        setState(_cargar);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Productos · ${widget.nombreTienda}')),
      body: RefreshIndicator(
        onRefresh: () async => setState(_cargar),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _productos,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final productos = snapshot.data ?? [];
            if (productos.isEmpty) {
              return LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: const Center(child: Text('Esta tienda no tiene productos')),
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: productos.length,
              itemBuilder: (context, i) {
                final p = productos[i];
                final id = p['id_producto'] as String;
                final nombre = p['nombre'] ?? '';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: p['imagen_url'] != null
                        ? CircleAvatar(backgroundImage: NetworkImage(p['imagen_url']))
                        : const CircleAvatar(child: Icon(Icons.image_outlined)),
                    title: Text(nombre),
                    subtitle: Text('\$${p['precio_usd'] ?? '0'} · '
                        '${(p['es_visible'] == true) ? "Visible" : "Oculto"}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmarEliminarProducto(id, nombre),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
