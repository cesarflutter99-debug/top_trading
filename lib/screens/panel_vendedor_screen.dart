// panel_vendedor_screen.dart
//
// INTEGRACIÓN CON TiendaStateService (2026-08):
//   - didUpdateWidget: MainShellScreen ahora reconstruye este widget
//     con datos frescos cada vez que TiendaStateService notifica un
//     cambio -- PERO Flutter reutiliza el State existente cuando el
//     tipo de widget coincide (no vuelve a llamar a initState()). Sin
//     este método, _tienda se quedaría con la copia vieja para
//     siempre, aunque widget.tienda sí llegara actualizado. Ahora se
//     sincroniza en cada rebuild del padre.
//   - _recargarTodo(): en vez de llamar directo a
//     _tiendasService.obtenerMiTienda(), delega en
//     TiendaStateService.instance.refrescar() y lee el resultado de
//     ahí -- así cualquier otra pantalla que esté escuchando el
//     servicio (mi perfil, home) también se entera.
//   - _cambiarLogo() y _abrirEdicion(): ya llamaban a _recargarTodo(),
//     así que heredan el fix sin cambios adicionales.

import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../main.dart' show AppBanner;
import '../services/anuncios_service.dart';
import '../services/storage_service.dart';
import '../services/tiendas_service.dart';
import '../services/tienda_state_service.dart';
import '../widgets/anuncios_tienda_sheet.dart';
import '../widgets/product_edit_modal.dart';
import '../widgets/modal_pago_plan.dart';
import 'agregar_producto_screen.dart';
import 'gestionar_planes_screen.dart';
import 'gestionar_tienda_screen.dart';
import 'vendedor_dashboard_screen.dart';
import 'welcome_screen.dart';

class PanelVendedorScreen extends StatefulWidget {
  final Map<String, dynamic> tienda;
  // FIX: permite llegar desde una notificación ("stock bajo",
  // "producto agotado") directo al panel del vendedor con el modal de
  // edición de ESE producto ya abierto, en vez de dejarlo en la
  // pantalla general teniendo que buscarlo él mismo entre todos sus
  // productos.
  final String? idProductoParaEditar;

  const PanelVendedorScreen({
    super.key,
    required this.tienda,
    this.idProductoParaEditar,
  });

  @override
  State<PanelVendedorScreen> createState() => _PanelVendedorScreenState();
}

class _PanelVendedorScreenState extends State<PanelVendedorScreen> {
  final _tiendasService = TiendasService();
  final _storageService = StorageService();
  final _anunciosService = AnunciosService();
  final _picker = ImagePicker();
  late Map<String, dynamic> _tienda;
  late Future<List<Map<String, dynamic>>> _productos;
  Map<String, dynamic>? _planActual;
  bool _subiendoLogo = false;
  bool _cargandoDatosPago = false;
  // Menú de acciones del FAB (agregar producto, potenciar, anuncios,
  // analíticas, cambiar plan) -- ver _buildFabMenu() más abajo.
  bool _fabExpandido = false;

  @override
  void initState() {
    super.initState();
    _tienda = widget.tienda;
    _cargarProductos();
    _cargarPlanActual();

    // FIX: si llegamos acá desde una notificación de stock (bajo o
    // agotado), abrimos directo el modal de edición de ESE producto
    // apenas la pantalla termina de montarse, sin esperar a que el
    // vendedor lo busque manualmente en la grilla.
    if (widget.idProductoParaEditar != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _abrirEdicionDesdeNotificacion(widget.idProductoParaEditar!);
      });
    }
  }

  /// Busca el producto puntual y abre su modal de edición. Independiente
  /// de _productos (que puede tardar en cargar) -- consulta directo por
  /// id, así el modal aparece apenas la pantalla está lista.
  Future<void> _abrirEdicionDesdeNotificacion(String idProducto) async {
    try {
      final producto = await _tiendasService.obtenerProductoPorId(idProducto);
      if (producto == null || !mounted) return;
      await _editarProducto(producto);
    } catch (_) {
      // Si el producto ya no existe (se borró) o falla la carga, no
      // hacemos nada -- el vendedor igual ve el panel normal.
    }
  }

  @override
  void didUpdateWidget(covariant PanelVendedorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // FIX (persistencia): si el padre (MainShellScreen, escuchando
    // TiendaStateService) reconstruye este widget con una tienda
    // distinta -- por ejemplo porque se aprobó el plan desde el panel
    // admin, o porque otra pantalla llamó a
    // TiendaStateService.refrescar() -- hay que copiar esos datos
    // nuevos a nuestro estado local. Sin esto, como Flutter reutiliza
    // el mismo State, _tienda se quedaría congelada con los datos del
    // primer initState() para siempre.
    if (!_mismaTienda(oldWidget.tienda, widget.tienda)) {
      setState(() => _tienda = widget.tienda);
      _cargarProductos();
      _cargarPlanActual();
    }
  }

  bool _mismaTienda(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _cargarPlanActual() async {
    final codigo = _tienda['plan'] as String?;
    if (codigo == null) return;
    try {
      final plan = await _tiendasService.obtenerPlanPorCodigo(codigo);
      if (mounted) setState(() => _planActual = plan);
    } catch (_) {
      // Sin datos del plan -- las barras de uso simplemente no se muestran.
    }
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
    _productos = _tiendasService
        .obtenerProductosDeTienda(_tienda['id_tienda'] as String);
  }

  Future<void> _verDatosPago() async {
    final codigoPlan = _tienda['plan'] as String?;
    if (codigoPlan == null || codigoPlan == 'gratis') return;

    setState(() => _cargandoDatosPago = true);
    try {
      final plan = await _tiendasService.obtenerPlanPorCodigo(codigoPlan);
      if (!mounted) return;
      if (plan == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No se encontraron los datos de este plan')),
        );
        return;
      }
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => ModalPagoPlan(
          tienda: _tienda,
          plan: plan,
          tiendasService: _tiendasService,
          onSolicitudCreada: () async => await _recargarTodo(),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('No se pudieron cargar los datos de pago: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cargandoDatosPago = false);
    }
  }

  Future<void> _recargarTodo() async {
    // FIX (persistencia): en vez de pedirle directo a TiendasService
    // los datos de la tienda (lo que solo actualizaba esta pantalla),
    // se delega en TiendaStateService.refrescar() -- que además de
    // traer los datos nuevos, notifica a CUALQUIER otra pantalla que
    // esté escuchando (mi perfil, home, main shell).
    await TiendaStateService.instance.refrescar();
    final actualizada = TiendaStateService.instance.miTienda;
    if (actualizada != null && mounted) {
      setState(() {
        _tienda = actualizada;
        _cargarProductos();
      });
      await _cargarPlanActual();
    } else if (mounted) {
      setState(_cargarProductos);
    }
  }

  Future<void> _editarProducto(Map<String, dynamic> producto) async {
    final actualizado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProductEditModal(
        producto: producto,
        esPremium: (_tienda['plan'] as String? ?? 'basic') == 'premium',
      ),
    );
    if (actualizado == true && mounted) {
      setState(_cargarProductos);
    }
  }

  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text(
            'Tendrás que volver a iniciar sesión con Google para gestionar tu tienda.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (confirmar != true) return;

    await supabase.auth.signOut();
    // La sesión cambió -- limpiamos el estado compartido para que no
    // quede "colgada" la tienda de la cuenta anterior.
    TiendaStateService.instance.limpiar();

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    }
  }

  Future<String?> _elegirCategoria(BuildContext context, String? actual) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Elige una categoría',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800, fontSize: 17)),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: kCategoriasTienda.map((c) {
                  final seleccionada = c == actual;
                  return ListTile(
                    title: Text(c),
                    trailing: seleccionada
                        ? Icon(Icons.check_rounded,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () => Navigator.pop(ctx, c),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirEdicion() {
    final nombreCtrl = TextEditingController(text: _tienda['nombre'] ?? '');
    final telefonoCtrl =
        TextEditingController(text: _tienda['telefono_whatsapp'] ?? '');
    final provinciaCtrl =
        TextEditingController(text: _tienda['provincia'] ?? '');
    final municipioCtrl =
        TextEditingController(text: _tienda['municipio'] ?? '');
    final descripcionCtrl =
        TextEditingController(text: _tienda['descripcion'] ?? '');
    String? categoriaSeleccionada = _tienda['categoria'] as String?;
    bool guardando = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Editar tienda',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nombre del negocio',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: telefonoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'WhatsApp', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: provinciaCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Provincia', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: municipioCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Municipio', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descripcionCtrl,
                  maxLines: 3,
                  maxLength: 200,
                  decoration: const InputDecoration(
                      labelText: 'Descripción',
                      hintText: 'Cuéntale a tus clientes qué vendes',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    final elegida =
                        await _elegirCategoria(context, categoriaSeleccionada);
                    if (elegida != null) {
                      setDialogState(() => categoriaSeleccionada = elegida);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Categoría',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            categoriaSeleccionada ?? 'Elige una categoría',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: categoriaSeleccionada == null
                                  ? Colors.black45
                                  : null,
                            ),
                          ),
                        ),
                        const Icon(Icons.expand_more_rounded,
                            size: 20, color: Colors.black45),
                      ],
                    ),
                  ),
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
                          descripcion: descripcionCtrl.text.trim(),
                          categoria: categoriaSeleccionada,
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
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  // ======================================================================
  // MENÚ DEL FAB (2026-08)
  //
  // El FAB dejó de ser un botón único de "Agregar producto" -- ahora es
  // un menú desplegable (speed-dial) con las acciones rápidas del día a
  // día del vendedor: Agregar producto, Potenciar producto, Gestionar
  // anuncios, Ver analíticas y Cambiar plan. "Gestionar Tienda" (portada,
  // logo, datos básicos, ventas, eliminar) sigue siendo la pantalla
  // aparte de siempre -- ya no repite estos accesos.
  // ======================================================================

  void _alternarMenuFab() => setState(() => _fabExpandido = !_fabExpandido);

  Future<void> _accionAgregarProducto() async {
    setState(() => _fabExpandido = false);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgregarProductoScreen(
          idTienda: _tienda['id_tienda'] as String,
          plan: _tienda['plan'] as String?,
        ),
      ),
    );
    await _recargarTodo();
  }

  /// Deja elegir uno de los productos ya publicados para potenciarlo,
  /// sin pasar por el sheet completo de "Anuncios y Promociones" --
  /// mismo servicio (AnunciosService.potenciarProducto) y misma regla de
  /// cupo (ranurasDeTienda) que usa ese sheet.
  Future<void> _accionPotenciarProducto() async {
    setState(() => _fabExpandido = false);
    final productos = await _productos;
    if (!mounted) return;
    if (productos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Agrega un producto primero para poder potenciarlo')));
      return;
    }
    final elegido = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Elige el producto a potenciar',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800, fontSize: 17)),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: productos.map((p) {
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: (p['imagen_url'] as String?)?.isNotEmpty == true
                            ? Image.network(p['imagen_url'], fit: BoxFit.cover)
                            : Container(
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.image_outlined)),
                      ),
                    ),
                    title: Text(p['nombre'] ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('\$${p['precio_usd']} USD'),
                    onTap: () => Navigator.pop(ctx, p),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
    if (elegido == null || !mounted) return;
    await _confirmarYPotenciar(elegido);
  }

  Future<void> _confirmarYPotenciar(Map<String, dynamic> producto) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Potenciar "${producto['nombre']}"?',
            style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
        content: Text(
          'Se publicará como "Promoción Pagada" en el feed de inicio. '
          'No pasa por moderación: sale al instante si tu plan tiene '
          'ranura libre.',
          style: GoogleFonts.inter(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Potenciar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    try {
      final r = await _anunciosService
          .ranurasDeTienda(_tienda['id_tienda'] as String);
      if (r.max > 0 && r.usados >= r.max) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Tu plan no tiene ranuras libres. Sube de plan o pon en '
                      'pausa otro anuncio desde "Gestionar anuncios".')));
        }
        return;
      }
      await _anunciosService.potenciarProducto(
        idTienda: _tienda['id_tienda'] as String,
        idProducto: producto['id_producto'] as String,
        titulo: '${producto['nombre']}',
        texto: 'Ahora \$${producto['precio_usd']} en '
            '${_tienda['nombre'] ?? 'nuestra tienda'}. ¡Pídelo ya!',
        imagenUrl: producto['imagen_url'] as String?,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('¡Producto potenciado! Ya está corriendo en el feed.')));
      }
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      final msg = s.contains('CUPO_ANUNCIOS')
          ? 'Tu plan no tiene ranuras libres. Sube de plan o pon en pausa '
              'otro anuncio.'
          : 'No se pudo potenciar el producto: '
              '${s.replaceFirst('Exception: ', '')}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _accionGestionarAnuncios() {
    setState(() => _fabExpandido = false);
    mostrarAnunciosSheet(context, _tienda);
  }

  void _accionVerAnaliticas() {
    setState(() => _fabExpandido = false);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            VendedorDashboardScreen(idTienda: _tienda['id_tienda'] as String),
      ),
    );
  }

  void _accionCambiarPlan() {
    setState(() => _fabExpandido = false);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GestionarPlanesScreen(tienda: _tienda),
      ),
    );
  }

  /// Una fila "etiqueta + botón circular" del menú desplegable.
  Widget _miniAccionFab({
    required IconData icono,
    required String etiqueta,
    required Color color,
    required VoidCallback onTap,
  }) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: esOscuro ? const Color(0xFF2A2A2A) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            elevation: 3,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Text(
                  etiqueta,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: esOscuro ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: color,
            shape: const CircleBorder(),
            elevation: 3,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(icono, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// FAB principal + menú desplegable. Al tocarlo alterna entre + y X;
  /// cada acción se cierra sola al elegirse.
  Widget _buildFabMenu(Color primary) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_fabExpandido) ...[
          _miniAccionFab(
            icono: Icons.workspace_premium_outlined,
            etiqueta: 'Cambiar plan',
            color: primary,
            onTap: _accionCambiarPlan,
          ),
          _miniAccionFab(
            icono: Icons.analytics_outlined,
            etiqueta: 'Ver analíticas',
            color: primary,
            onTap: _accionVerAnaliticas,
          ),
          _miniAccionFab(
            icono: Icons.campaign_outlined,
            etiqueta: 'Gestionar anuncios',
            color: const Color(0xFF0D9488),
            onTap: _accionGestionarAnuncios,
          ),
          _miniAccionFab(
            icono: Icons.rocket_launch_outlined,
            etiqueta: 'Potenciar producto',
            color: const Color(0xFF0D9488),
            onTap: _accionPotenciarProducto,
          ),
          _miniAccionFab(
            icono: Icons.add_a_photo_outlined,
            etiqueta: 'Agregar producto',
            color: primary,
            onTap: _accionAgregarProducto,
          ),
        ],
        Material(
          color: primary,
          elevation: 4,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _alternarMenuFab,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 220),
                turns: _fabExpandido ? 0.125 : 0,
                child: Icon(
                  _fabExpandido ? Icons.close_rounded : Icons.add_rounded,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
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
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 70,
        ),
        child: _buildFabMenu(primary),
      ),
      body: RefreshIndicator(
        onRefresh: _recargarTodo,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
                                        (_tienda['logo_url'] as String)
                                            .isNotEmpty)
                                    ? NetworkImage(
                                        _tienda['logo_url'] as String)
                                    : null,
                                child: (_tienda['logo_url'] == null ||
                                        (_tienda['logo_url'] as String).isEmpty)
                                    ? const Icon(Icons.storefront_outlined,
                                        size: 32, color: Colors.grey)
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
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                    ),
                                    child: const Icon(Icons.camera_alt,
                                        size: 14, color: Colors.white),
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
                                      style: GoogleFonts.inter(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 18),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if ((_tienda['plan'] as String? ?? 'basic') ==
                                      'premium') ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFFFFD700),
                                            Color(0xFFB8860B)
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.star_rounded,
                                              size: 12, color: Colors.white),
                                          SizedBox(width: 2),
                                          Text('VIP',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_tienda['municipio'] ?? ''}, ${_tienda['provincia'] ?? ''}',
                                style: GoogleFonts.inter(
                                    fontSize: 12, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    _buildMiniEstadisticasProductos(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _statChip(
                            icon: Icons.star_rounded,
                            color: Colors.amber[700]!,
                            valor:
                                (_tienda['promedio_estrellas'] ?? 0).toString(),
                            etiqueta: 'Estrellas',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _statChip(
                            icon: Icons.local_fire_department_rounded,
                            color: primary,
                            valor:
                                (_tienda['puntos_semanales'] ?? 0).toString(),
                            etiqueta: 'Popular esta semana',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _statChip(
                            icon: Icons.bolt_rounded,
                            color: primary,
                            valor: (_tienda['puntos_totales'] ?? 0).toString(),
                            etiqueta: 'Puntos totales',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  GestionarTiendaScreen(tienda: _tienda),
                            ),
                          );
                          // Por si se editó/eliminó algo en Gestionar
                          // Tienda y volvemos con "atrás" en vez de con
                          // el popUntil de eliminar.
                          await _recargarTodo();
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
            if (esPending) ...[
              AppBanner(
                icon: Icons.hourglass_top_rounded,
                titulo: 'Tienda en revisión',
                mensaje: 'Tu tienda todavía no es visible en el marketplace. '
                    'Puedes gestionar tu información y subir productos mientras '
                    'el administrador la verifica; las fotos se harán públicas '
                    'una vez aprobada.',
                accion: (_tienda['plan'] != null && _tienda['plan'] != 'gratis')
                    ? SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _cargandoDatosPago ? null : _verDatosPago,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.warm,
                            side: BorderSide(color: AppColors.warm),
                          ),
                          icon: _cargandoDatosPago
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.qr_code_rounded, size: 18),
                          label: const Text('Ver datos de pago / WhatsApp'),
                        ),
                      )
                    : null,
              ),
            ] else
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(kCardRadius),
                  border: Border.all(color: const Color(0xFFA5D6A7)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_rounded,
                          color: Color(0xFF2E7D32)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Tienda activa y visible en el marketplace',
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF2E7D32)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _productos,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final seccion = _buildUsoDePlan(snapshot.data!.length);
                if (seccion is SizedBox) return seccion;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: seccion,
                );
              },
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Plan',
                            style: GoogleFonts.inter(color: Colors.black54)),
                        Text(
                          (_tienda['plan'] as String? ?? 'basic').toUpperCase(),
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold, color: primary),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('WhatsApp',
                            style: GoogleFonts.inter(color: Colors.black54)),
                        Text(_tienda['telefono_whatsapp'] ?? '-'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Ubicación',
                            style: GoogleFonts.inter(color: Colors.black54)),
                        Text(
                            '${_tienda['municipio'] ?? ''}, ${_tienda['provincia'] ?? ''}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Mis productos',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800, fontSize: 18)),
                Text(
                  'Toca un producto para editarlo',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
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
                    final sinStock =
                        (p['cantidad_disponible'] as num? ?? 0) <= 0;
                    return GestureDetector(
                      onTap: () => _editarProducto(p),
                      child: Card(
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
                                      child: const Icon(
                                          Icons.image_not_supported_outlined),
                                    ),
                                  ),
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.edit,
                                          size: 14, color: Colors.white),
                                    ),
                                  ),
                                  if (esPending)
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'No público',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10),
                                        ),
                                      ),
                                    ),
                                  if (!visible && !esPending)
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'Oculto',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10),
                                        ),
                                      ),
                                    ),
                                  if (sinStock)
                                    Positioned(
                                      bottom: 6,
                                      left: 6,
                                      right: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withOpacity(0.85),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'Sin stock',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold),
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
                                    style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13),
                                  ),
                                  Text(
                                    '\$${p['precio_usd']}',
                                    style: GoogleFonts.inter(
                                        color: Colors.black54, fontSize: 12),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    sinStock
                                        ? 'Sin stock'
                                        : '${(p['cantidad_disponible'] as num? ?? 0).toInt()} en stock',
                                    style: GoogleFonts.inter(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: sinStock
                                            ? Colors.red
                                            : ((p['cantidad_disponible']
                                                            as num? ??
                                                        0) <
                                                    10
                                                ? Colors.orange.shade800
                                                : Colors.black45)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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

  Color _colorBarraSegunFraccion(double fracLibre) {
    const verde = Color(0xFF2ECC71);
    const amarillo = Color(0xFFFFC107);
    const rojo = Color(0xFFE53935);
    if (fracLibre >= 0.5) {
      final t = ((fracLibre - 0.5) / 0.5).clamp(0.0, 1.0);
      return Color.lerp(amarillo, verde, t)!;
    }
    final t = (fracLibre / 0.5).clamp(0.0, 1.0);
    return Color.lerp(rojo, amarillo, t)!;
  }

  Widget _barraUso({
    required IconData icono,
    required String etiqueta,
    required String valorDerecha,
    required String detalle,
    required double pct,
    required Color color,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.035),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.4), width: 1.1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(icono, size: 14, color: color),
                      const SizedBox(width: 5),
                      Text(etiqueta,
                          style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87)),
                    ],
                  ),
                  Text(valorDerecha,
                      style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: color)),
                ],
              ),
              const SizedBox(height: 9),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  height: 9,
                  color: color.withOpacity(0.15),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: pct),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => FractionallySizedBox(
                        widthFactor: value.clamp(0.03, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LinearGradient(
                                colors: [color.withOpacity(0.65), color]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(detalle,
                  style:
                      GoogleFonts.inter(fontSize: 10.5, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsoDePlan(int productosPublicados) {
    final limite = (_planActual?['limite_productos'] as num?)?.toInt();
    final expiraStr = _tienda['plan_expira_en'] as String?;
    final expira = expiraStr != null ? DateTime.tryParse(expiraStr) : null;

    final filas = <Widget>[];

    if (limite != null && limite > 0) {
      final pct = (productosPublicados / limite).clamp(0.0, 1.0);
      final restantes = (limite - productosPublicados).clamp(0, limite);
      final color = _colorBarraSegunFraccion(1 - pct);
      filas.add(_barraUso(
        icono: Icons.inventory_2_rounded,
        etiqueta: 'Productos publicados',
        valorDerecha: restantes <= 0
            ? 'Límite alcanzado'
            : '$restantes espacio${restantes == 1 ? '' : 's'} libre${restantes == 1 ? '' : 's'}',
        detalle:
            '$productosPublicados de $limite productos · ${(pct * 100).round()}% usado',
        pct: pct,
        color: color,
      ));
    }

    if (expira != null) {
      final ahora = DateTime.now();
      final restante = expira.difference(ahora);
      final dias = restante.isNegative ? 0 : (restante.inHours / 24).ceil();
      final duracionTotal = (_planActual?['duracion_dias'] as num?)?.toInt();
      double pctD;
      if (duracionTotal != null && duracionTotal > 0) {
        pctD = dias <= 0
            ? 1.0
            : ((duracionTotal - dias) / duracionTotal).clamp(0.0, 1.0);
      } else {
        pctD = dias <= 0 ? 1.0 : 0.15;
      }
      final colorD = _colorBarraSegunFraccion(1 - pctD);
      filas.add(_barraUso(
        icono: Icons.bolt_rounded,
        etiqueta: 'Vigencia del plan',
        valorDerecha: dias <= 0
            ? 'Vencido'
            : (dias == 1 ? '1 día restante' : '$dias días restantes'),
        detalle: duracionTotal != null
            ? '${(pctD * 100).round()}% del período usado'
            : 'Plan activo',
        pct: pctD,
        color: colorD,
      ));
    }

    // NUEVO: barra de RANURAS DE ANUNCIO -- plan + extra compradas
    // aparte (ver ranurasDeTienda() en anuncios_service.dart). Se
    // pinta con FutureBuilder porque, a diferencia de las dos barras
    // de arriba (que ya vienen resueltas en _tienda/_planActual), esto
    // requiere una consulta aparte a permisos_tienda_anuncios.
    filas.add(
      FutureBuilder<({int usados, int max, int maxPlan, int maxExtra})>(
        future:
            _anunciosService.ranurasDeTienda(_tienda['id_tienda'] as String),
        builder: (context, snap) {
          final r = snap.data;
          if (r == null || r.max <= 0) return const SizedBox.shrink();
          final pct = (r.usados / r.max).clamp(0.0, 1.0);
          final restantes = (r.max - r.usados).clamp(0, r.max);
          final color = _colorBarraSegunFraccion(1 - pct);
          final detalle = r.maxExtra > 0
              ? '${r.usados} de ${r.max} ranuras · ${r.maxPlan} del plan + ${r.maxExtra} extra'
              : '${r.usados} de ${r.max} ranuras de tu plan';
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _barraUso(
              icono: Icons.campaign_rounded,
              etiqueta: 'Ranuras de anuncio',
              valorDerecha: restantes <= 0
                  ? 'Máximo alcanzado'
                  : '$restantes libre${restantes == 1 ? '' : 's'}',
              detalle: detalle,
              pct: pct,
              color: color,
            ),
          );
        },
      ),
    );

    if (filas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Uso de tu plan',
            style:
                GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 10),
        for (int i = 0; i < filas.length; i++) ...[
          filas[i],
          if (i != filas.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildMiniEstadisticasProductos() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _productos,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final productos = snapshot.data!;
        final total = productos.length;
        final sinStock = productos
            .where((p) => (p['cantidad_disponible'] as num? ?? 0) <= 0)
            .length;
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _miniStatPill(
                icon: Icons.inventory_2_outlined,
                texto: '$total producto${total == 1 ? '' : 's'}',
                color: Theme.of(context).colorScheme.primary,
              ),
              if (sinStock > 0)
                _miniStatPill(
                  icon: Icons.warning_amber_rounded,
                  texto:
                      '$sinStock producto${sinStock == 1 ? '' : 's'} sin stock',
                  color: Colors.red,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _miniStatPill({
    required IconData icon,
    required String texto,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            texto,
            style: GoogleFonts.inter(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
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
          Text(valor,
              style:
                  GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(etiqueta,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    GoogleFonts.inter(fontSize: 10.5, color: Colors.black54)),
          ),
        ],
      ),
    );
  }
}
