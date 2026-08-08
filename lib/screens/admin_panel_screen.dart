// admin_panel_screen.dart
//
// Rediseño completo respecto a la versión anterior:
// 1. Se quitó el TabBar deslizante (isScrollable con 5 pestañas) y se
//    reemplazó por un NavigationBar (Material 3, la barra inferior
//    estándar) con 4 secciones -- más profesional, no se corta en
//    pantallas angostas.
// 2. Se fusionaron las pestañas "Pendientes" (tiendas nuevas) y
//    "Solicitudes" (cambios de plan) en una sola sección "Solicitudes"
//    -- cada tarjeta indica si es una Activación (tienda nueva) o un
//    Upgrade (cambio de plan), con el botón de acción correcto según
//    el tipo, en vez de dos pantallas separadas para dos variantes del
//    mismo concepto ("aprobar algo pendiente").
// 3. "Tiendas y Productos" ahora deja al admin ver las pantallas
//    REALES tal como las ve un cliente: tocar una tienda ofrece "Ver
//    como cliente" (abre StoreScreen, la pantalla real del
//    marketplace) o "Gestionar" (CRUD admin). Tocar un producto abre
//    el modal real de detalle (ProductDetailModal), no una fila
//    simple con nombre y precio.
// 4. Estilo de marca (AppColors, kCardRadius, tipografía) aplicado en
//    toda la pantalla.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:top_trading/widgets/product_detail_modal.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/storage_service.dart';
import '../services/tiendas_service.dart';
import '../services/currency_service.dart';
import 'panel_vendedor_screen.dart';
import 'store_screen_flow.dart';
import 'welcome_screen.dart';

const _kPrimary = AppColors.primary;
const _kWarm = AppColors.warm;

/// Permisos delegables a un admin normal. "Hacer admin" NO está en
/// esta lista a propósito: esa capacidad es exclusiva del superadmin y
/// nunca se puede otorgar a nadie más (validado también en la función
/// SQL, no solo aquí).
const Map<String, String> _permisosDisponibles = {
  'aprobar_tiendas': 'Aprobar/rechazar tiendas nuevas',
  'aprobar_planes': 'Aprobar/rechazar cambios de plan',
  'eliminar_tiendas': 'Eliminar tiendas',
  'gestionar_planes': 'Gestionar planes (crear/editar/desactivar)',
  'gestionar_whatsapp': 'Gestionar números de WhatsApp',
  'gestionar_afiliados': 'Gestionar afiliados y retiros',
};

class _Seccion {
  final String titulo;
  final String etiqueta;
  final IconData icono;
  final IconData iconoActivo;
  final Widget child;
  const _Seccion({
    required this.titulo,
    required this.etiqueta,
    required this.icono,
    required this.iconoActivo,
    required this.child,
  });
}

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _tiendasService = TiendasService();
  int _seccion = 0;
  Map<String, dynamic>? _miAdminInfo;

  @override
  void initState() {
    super.initState();
    _cargarMiAdminInfo();
  }

  Future<void> _cargarMiAdminInfo() async {
    try {
      final info = await _tiendasService.obtenerMiAdminInfo();
      if (mounted) setState(() => _miAdminInfo = info);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar permisos de admin: $e')),
        );
      }
    }
  }

  bool get _esSuperadmin => _miAdminInfo?['es_superadmin'] == true;

  Map<String, dynamic> get _misPermisos =>
      (_miAdminInfo?['permisos'] as Map<String, dynamic>?) ?? {};

  bool _tienePermiso(String clave) {
    if (_misPermisos['todos'] == true) return true;
    return _misPermisos[clave] == true;
  }

  void _mostrarMisPermisos() {
    final tieneTodos = _misPermisos['todos'] == true;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mis permisos de administrador'),
        content: tieneTodos
            ? const Text('Tienes todos los permisos.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _permisosDisponibles.entries
                    .where((e) => _misPermisos[e.key] == true)
                    .map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  size: 16, color: Colors.green),
                              const SizedBox(width: 8),
                              Text(e.value),
                            ],
                          ),
                        ))
                    .toList(),
              ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Future<void> _irAMiTienda() async {
    final tienda = await _tiendasService.obtenerMiTienda();
    if (!mounted) return;
    if (tienda == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Esta cuenta admin no tiene tienda propia')),
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

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    }
  }

  bool get _tieneSolicitudes =>
      _esSuperadmin ||
      _tienePermiso('aprobar_tiendas') ||
      _tienePermiso('aprobar_planes');
  bool get _tieneTiendas => _esSuperadmin || _tienePermiso('eliminar_tiendas');
  bool get _tienePlanes => _esSuperadmin || _tienePermiso('gestionar_planes');
  bool get _tieneWhatsapp =>
      _esSuperadmin || _tienePermiso('gestionar_whatsapp');
  bool get _tieneAfiliados =>
      _esSuperadmin || _tienePermiso('gestionar_afiliados');

  List<_Seccion> _seccionesVisibles() {
    return [
      if (_tieneSolicitudes)
        _Seccion(
          titulo: 'Solicitudes',
          etiqueta: 'Solicitudes',
          icono: Icons.pending_actions_outlined,
          iconoActivo: Icons.pending_actions_rounded,
          child: _SolicitudesTab(
            tiendasService: _tiendasService,
            puedeAprobarTiendas:
                _esSuperadmin || _tienePermiso('aprobar_tiendas'),
            puedeAprobarPlanes:
                _esSuperadmin || _tienePermiso('aprobar_planes'),
          ),
        ),
      if (_tieneTiendas)
        _Seccion(
          titulo: 'Tiendas y Productos',
          etiqueta: 'Tiendas',
          icono: Icons.storefront_outlined,
          iconoActivo: Icons.storefront_rounded,
          child: _TiendasYProductosTab(
            tiendasService: _tiendasService,
            esSuperadmin: _esSuperadmin,
          ),
        ),
      if (_tienePlanes)
        _Seccion(
          titulo: 'Planes',
          etiqueta: 'Planes',
          icono: Icons.workspace_premium_outlined,
          iconoActivo: Icons.workspace_premium_rounded,
          child: _PlanesTab(tiendasService: _tiendasService),
        ),
      if (_tieneWhatsapp)
        _Seccion(
          titulo: 'Números WhatsApp',
          etiqueta: 'WhatsApp',
          icono: Icons.chat_outlined,
          iconoActivo: Icons.chat_rounded,
          child: _ContactosWhatsappTab(tiendasService: _tiendasService),
        ),
      if (_tieneAfiliados)
        _Seccion(
          titulo: 'Afiliados',
          etiqueta: 'Afiliados',
          icono: Icons.handshake_outlined,
          iconoActivo: Icons.handshake_rounded,
          child: _AfiliadosTab(tiendasService: _tiendasService),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final secciones = _seccionesVisibles();
    final seccion = _seccion < secciones.length ? _seccion : 0;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title:
            Text(secciones.isEmpty ? 'Panel Admin' : secciones[seccion].titulo),
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(
              _esSuperadmin
                  ? Icons.workspace_premium_rounded
                  : Icons.verified_user_outlined,
              color: _esSuperadmin ? const Color(0xFFD4AF37) : null,
            ),
            tooltip: 'Mis permisos',
            onPressed: _mostrarMisPermisos,
          ),
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
      ),
      body: _miAdminInfo == null
          ? const Center(child: CircularProgressIndicator())
          : secciones.isEmpty
              ? _estadoVacio(
                  icon: Icons.lock_outline,
                  texto: 'No tienes permisos asignados en el panel.\n'
                      'Contacta al superadministrador.',
                )
              : IndexedStack(
                  index: seccion,
                  children: [
                    for (final s in secciones) s.child,
                  ],
                ),
      bottomNavigationBar: secciones.length < 2
          ? null
          : NavigationBar(
              selectedIndex: seccion,
              onDestinationSelected: (i) => setState(() => _seccion = i),
              backgroundColor: AppColors.backgroundLight,
              indicatorColor: _kPrimary.withOpacity(0.15),
              destinations: [
                for (final s in secciones)
                  NavigationDestination(
                    icon: Icon(s.icono),
                    selectedIcon: Icon(s.iconoActivo),
                    label: s.etiqueta,
                  ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------
// Widget compartido: estado vacío centrado (usado en varias secciones)
// ---------------------------------------------------------------------

Widget _estadoVacio({required IconData icon, required String texto}) {
  return LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 40, color: AppColors.inkSecundarioLight),
                const SizedBox(height: 12),
                Text(
                  texto,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      color: AppColors.inkSecundarioLight),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------
// SECCIÓN 1: Solicitudes -- unifica tiendas nuevas (activación) y
// cambios de plan (upgrade) en una sola lista ordenada por fecha.
// ---------------------------------------------------------------------

class _ItemSolicitud {
  final bool esActivacion; // true = tienda nueva, false = cambio de plan
  final Map<String, dynamic> datos;
  final DateTime fecha;
  _ItemSolicitud(
      {required this.esActivacion, required this.datos, required this.fecha});
}

class _SolicitudesTab extends StatefulWidget {
  final TiendasService tiendasService;
  final bool puedeAprobarTiendas;
  final bool puedeAprobarPlanes;
  const _SolicitudesTab({
    required this.tiendasService,
    this.puedeAprobarTiendas = true,
    this.puedeAprobarPlanes = true,
  });

  @override
  State<_SolicitudesTab> createState() => _SolicitudesTabState();
}

class _SolicitudesTabState extends State<_SolicitudesTab> {
  late Future<List<_ItemSolicitud>> _items;
  final Set<String> _procesando = {};
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  String _nombreTiendaDe(_ItemSolicitud item) {
    return item.esActivacion
        ? (item.datos['nombre'] ?? '')
        : (item.datos['tienda_nombre'] ?? '');
  }

  void _cargar() {
    _items = _combinar();
  }

  Future<List<_ItemSolicitud>> _combinar() async {
    final tiendasPendientes =
        await widget.tiendasService.obtenerTiendasPendientes();
    final solicitudesPlan =
        await widget.tiendasService.obtenerSolicitudesPendientes();

    final items = <_ItemSolicitud>[
      if (widget.puedeAprobarTiendas)
        ...tiendasPendientes.map((t) => _ItemSolicitud(
              esActivacion: true,
              datos: t,
              fecha: DateTime.tryParse(t['ultima_activacion'] ?? '') ??
                  DateTime.now(),
            )),
      if (widget.puedeAprobarPlanes)
        ...solicitudesPlan.map((s) => _ItemSolicitud(
              esActivacion: false,
              datos: s,
              fecha: DateTime.tryParse(s['creado_en'] ?? '') ?? DateTime.now(),
            )),
    ];
    items.sort((a, b) => a.fecha.compareTo(b.fecha));
    return items;
  }

  Future<void> _aprobarActivacion(String idTienda) async {
    setState(() => _procesando.add(idTienda));
    try {
      await widget.tiendasService.aprobarTienda(
        idTienda,
        tasaCupUsd: CurrencyService.instance.tasa ?? 320,
      );
      _notificarYRecargar('Tienda aprobada ✅');
    } catch (e) {
      _notificarError(e);
    } finally {
      if (mounted) setState(() => _procesando.remove(idTienda));
    }
  }

  Future<void> _rechazarActivacion(String idTienda) async {
    setState(() => _procesando.add(idTienda));
    try {
      await widget.tiendasService.rechazarTienda(idTienda);
      _notificarYRecargar('Tienda rechazada');
    } catch (e) {
      _notificarError(e);
    } finally {
      if (mounted) setState(() => _procesando.remove(idTienda));
    }
  }

  Future<void> _aprobarUpgrade(Map<String, dynamic> solicitud) async {
    final id = solicitud['id_solicitud'] as String;
    setState(() => _procesando.add(id));
    try {
      final codigoPlan = solicitud['plan_nuevo_codigo'] ?? 'premium';
      // FIX: el RPC nunca devolvió una columna 'uso_afiliado' ni un
      // embed 'planes' -- devuelve los campos planos id_afiliado /
      // codigo_afiliado / comision_usd. Se arma el mapa acá solo si
      // hay afiliado asociado.
      final idAfiliado = solicitud['id_afiliado'] as String?;
      final usoAfiliado = idAfiliado != null
          ? {
              'id_afiliado': idAfiliado,
              'codigo': solicitud['codigo_afiliado'],
              'comision_usd': solicitud['comision_usd'],
            }
          : null;
      await widget.tiendasService.aprobarSolicitudCambioPlan(
        idSolicitud: id,
        idTienda: solicitud['id_tienda'],
        codigoPlanNuevo: codigoPlan,
        usoAfiliado: usoAfiliado,
        tasaCupUsd: CurrencyService.instance.tasa ?? 320,
      );
      _notificarYRecargar(usoAfiliado != null
          ? 'Plan activado ✅ y comisión acreditada al afiliado'
          : 'Plan activado ✅');
    } catch (e) {
      _notificarError(e);
    } finally {
      if (mounted) setState(() => _procesando.remove(id));
    }
  }

  Future<void> _rechazarUpgrade(String idSolicitud) async {
    setState(() => _procesando.add(idSolicitud));
    try {
      await widget.tiendasService.rechazarSolicitudCambioPlan(idSolicitud);
      _notificarYRecargar('Solicitud rechazada');
    } catch (e) {
      _notificarError(e);
    } finally {
      if (mounted) setState(() => _procesando.remove(idSolicitud));
    }
  }

  void _notificarYRecargar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
    setState(_cargar);
  }

  void _notificarError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Error: $e')));
  }

  Widget _filaDetalle(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(etiqueta,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    color: AppColors.inkSecundarioLight,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(valor.isEmpty ? '-' : valor,
                style: GoogleFonts.plusJakartaSans(fontSize: 13.5)),
          ),
        ],
      ),
    );
  }

  /// Detalle de una solicitud de ACTIVACIÓN (tienda nueva). Los datos
  /// ya vienen completos en `t` (viene de obtenerTiendasPendientes,
  /// que trae la fila entera de tiendas), no hace falta ir a buscar
  /// nada extra a Supabase.
  void _mostrarDetalleActivacion(Map<String, dynamic> t) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kCardRadius)),
        title: Text(t['nombre'] ?? 'Tienda',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _etiquetaTipo('ACTIVACIÓN', Icons.fiber_new_rounded, _kPrimary),
              const SizedBox(height: 8),
              _filaDetalle('Plan solicitado', t['plan'] ?? ''),
              _filaDetalle('Ubicación',
                  '${t['municipio'] ?? ''}, ${t['provincia'] ?? ''}'),
              _filaDetalle('WhatsApp', t['telefono_whatsapp'] ?? ''),
              _filaDetalle('Descripción', t['descripcion'] ?? ''),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  /// Detalle de una solicitud de CAMBIO DE PLAN. El RPC
  /// admin_solicitudes_plan_pendientes solo trae un resumen plano, así
  /// que acá se pide la tienda completa (descripción, ubicación,
  /// WhatsApp) para poder mostrarla en el modal.
  Future<void> _mostrarDetalleUpgrade(Map<String, dynamic> s) async {
    final idTienda = s['id_tienda'] as String?;
    Map<String, dynamic>? tienda;
    if (idTienda != null) {
      try {
        tienda = await widget.tiendasService.obtenerTiendaPorId(idTienda);
      } catch (_) {
        // Si falla la consulta extra, igual mostramos el detalle con
        // lo que ya teníamos del RPC -- no bloqueamos el diálogo.
      }
    }
    if (!mounted) return;

    final tieneCupon = s['id_afiliado'] != null;
    const dorado = Color(0xFFD4AF37);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kCardRadius)),
        title: Text(s['tienda_nombre'] ?? 'Tienda',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _etiquetaTipo('CAMBIO DE PLAN', Icons.upgrade_rounded, _kWarm),
              if (tieneCupon) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: dorado,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.card_giftcard_rounded,
                          size: 13, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'Código de afiliado · ${s['codigo_afiliado'] ?? ''}',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _filaDetalle('Plan anterior', s['plan_anterior'] ?? ''),
              _filaDetalle(
                  'Plan nuevo', s['plan_nuevo_nombre'] ?? 'Plan desconocido'),
              if (tieneCupon)
                _filaDetalle('Comisión',
                    '\$${((s['comision_usd'] as num?) ?? 0).toStringAsFixed(2)} USD'),
              if (tienda != null) ...[
                _filaDetalle('Ubicación',
                    '${tienda['municipio'] ?? ''}, ${tienda['provincia'] ?? ''}'),
                _filaDetalle('WhatsApp', tienda['telefono_whatsapp'] ?? ''),
                _filaDetalle('Descripción', tienda['descripcion'] ?? ''),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(_cargar),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _busquedaCtrl,
              onChanged: (v) => setState(() => _busqueda = v),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre de tienda...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _busqueda.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _busquedaCtrl.clear();
                          _busqueda = '';
                        }),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_ItemSolicitud>>(
              future: _items,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _estadoVacio(
                      icon: Icons.error_outline,
                      texto: 'Error al cargar: ${snapshot.error}');
                }
                var items = snapshot.data ?? [];
                if (_busqueda.trim().isNotEmpty) {
                  final q = _busqueda.trim().toLowerCase();
                  items = items
                      .where((item) =>
                          _nombreTiendaDe(item).toLowerCase().contains(q))
                      .toList();
                }
                if (items.isEmpty) {
                  return _estadoVacio(
                    icon: _busqueda.isEmpty
                        ? Icons.check_circle_outline_rounded
                        : Icons.search_off_rounded,
                    texto: _busqueda.isEmpty
                        ? 'No hay solicitudes pendientes.\n¡Todo al día!'
                        : 'Ninguna solicitud coincide con "$_busqueda"',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return item.esActivacion
                        ? _tarjetaActivacion(item.datos)
                        : _tarjetaUpgrade(item.datos);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _etiquetaTipo(String texto, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(texto,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _tarjetaActivacion(Map<String, dynamic> t) {
    final id = t['id_tienda'] as String;
    final procesando = _procesando.contains(id);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kCardRadius)),
      child: InkWell(
        borderRadius: BorderRadius.circular(kCardRadius),
        onTap: () => _mostrarDetalleActivacion(t),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _etiquetaTipo('ACTIVACIÓN', Icons.fiber_new_rounded, _kPrimary),
              const SizedBox(height: 8),
              Text(t['nombre'] ?? '',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text('${t['municipio'] ?? ''}, ${t['provincia'] ?? ''}',
                  style: GoogleFonts.plusJakartaSans(
                      color: AppColors.inkSecundarioLight, fontSize: 13)),
              const SizedBox(height: 2),
              Text('Plan solicitado: ${t['plan'] ?? ''}',
                  style: GoogleFonts.plusJakartaSans(
                      color: AppColors.inkSecundarioLight, fontSize: 13)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          procesando ? null : () => _rechazarActivacion(id),
                      style:
                          OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Rechazar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          procesando ? null : () => _aprobarActivacion(id),
                      child: procesando
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Aprobar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaUpgrade(Map<String, dynamic> s) {
    final id = s['id_solicitud'] as String;
    final procesando = _procesando.contains(id);
    final nombreTienda = s['tienda_nombre'] ?? 'Tienda desconocida';
    final nombrePlan = s['plan_nuevo_nombre'] ?? 'Plan desconocido';
    // FIX: antes se casteaba s['uso_afiliado'] as Map, columna que no
    // existe en el RPC. Ahora se detecta por id_afiliado (columna real)
    // y se leen codigo_afiliado / comision_usd directo del mapa plano.
    final tieneCupon = s['id_afiliado'] != null;
    const dorado = Color(0xFFD4AF37);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: tieneCupon ? dorado.withOpacity(0.07) : null,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kCardRadius),
          side: tieneCupon
              ? const BorderSide(color: dorado, width: 1.5)
              : BorderSide.none),
      child: InkWell(
        borderRadius: BorderRadius.circular(kCardRadius),
        onTap: () => _mostrarDetalleUpgrade(s),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _etiquetaTipo('CAMBIO DE PLAN', Icons.upgrade_rounded, _kWarm),
              if (tieneCupon) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: dorado,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.card_giftcard_rounded,
                          size: 13, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'Solicitud a través de código · ${s['codigo_afiliado']}',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(nombreTienda,
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text('${s['plan_anterior']} → $nombrePlan',
                  style: GoogleFonts.plusJakartaSans(
                      color: AppColors.inkSecundarioLight, fontSize: 13)),
              if (tieneCupon) ...[
                const SizedBox(height: 4),
                Text(
                  'Comisión al aprobar: \$${(s['comision_usd'] as num).toStringAsFixed(2)} USD → CUP',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: dorado.withOpacity(0.9)),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: procesando ? null : () => _rechazarUpgrade(id),
                      style:
                          OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Rechazar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: procesando ? null : () => _aprobarUpgrade(s),
                      child: procesando
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Activar plan'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// SECCIÓN 2: Tiendas y Productos -- ahora deja "entrar" a las
// pantallas reales, no solo administrar filas.
// ---------------------------------------------------------------------

class _TiendasYProductosTab extends StatefulWidget {
  final TiendasService tiendasService;
  final bool esSuperadmin;
  const _TiendasYProductosTab({
    required this.tiendasService,
    this.esSuperadmin = false,
  });

  @override
  State<_TiendasYProductosTab> createState() => _TiendasYProductosTabState();
}

class _TiendasYProductosTabState extends State<_TiendasYProductosTab> {
  late Future<List<Map<String, dynamic>>> _tiendas;
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
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
                  decoration:
                      const InputDecoration(labelText: 'Nombre de la tienda'),
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
                  onChanged: (v) =>
                      setDialogState(() => planSeleccionado = v ?? 'basic'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
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

  // Al tocar una tienda: elegir entre verla como la ve un cliente real
  // (StoreScreen completa) o entrar al modo de gestión admin.
  void _abrirTienda(Map<String, dynamic> tienda) {
    final id = tienda['id_tienda'] as String;
    final nombre = tienda['nombre'] ?? '';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nombre,
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: _kPrimary.withOpacity(0.12),
                  child:
                      const Icon(Icons.visibility_outlined, color: _kPrimary),
                ),
                title: const Text('Ver como cliente'),
                subtitle:
                    const Text('Abre la tienda tal como la ve un comprador'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StoreScreen(idTienda: id),
                    ),
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: _kPrimary.withOpacity(0.12),
                  child:
                      const Icon(Icons.inventory_2_outlined, color: _kPrimary),
                ),
                title: const Text('Gestionar productos'),
                subtitle: const Text('Ver, revisar y eliminar productos'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _ProductosDeTiendaScreen(
                        idTienda: id,
                        nombreTienda: nombre,
                        tiendasService: widget.tiendasService,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: _kPrimary.withOpacity(0.12),
                  child: const Icon(Icons.person_outline, color: _kPrimary),
                ),
                title: const Text('Información del vendedor'),
                subtitle:
                    const Text('Cuenta de Google, correo, fecha de registro'),
                onTap: () {
                  Navigator.pop(ctx);
                  _mostrarInfoVendedor(tienda);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarInfoVendedor(Map<String, dynamic> tienda) async {
    final ownerId = tienda['owner_id'] as String?;
    if (ownerId == null) return;

    showDialog(
      context: context,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    Map<String, dynamic>? info;
    try {
      info = await widget.tiendasService.obtenerInfoUsuario(ownerId);
    } catch (_) {
      info = null;
    }

    if (!mounted) return;
    Navigator.pop(context); // cierra el loading

    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se pudo cargar la información del vendedor')),
      );
      return;
    }

    final nombreGoogle = info['nombre_google'] as String? ?? 'Sin nombre';
    final fotoGoogle = info['foto_google'] as String?;
    final email = info['email'] as String? ?? '-';
    final creadoEn =
        info['creado_en'] != null ? DateTime.tryParse(info['creado_en']) : null;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage:
                        fotoGoogle != null ? NetworkImage(fotoGoogle) : null,
                    child: fotoGoogle == null ? const Icon(Icons.person) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nombreGoogle,
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(email,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12.5,
                                color: AppColors.inkSecundarioLight)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (creadoEn != null)
                Text(
                  'Cuenta creada: ${creadoEn.day}/${creadoEn.month}/${creadoEn.year}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5, color: AppColors.inkSecundarioLight),
                ),
              const SizedBox(height: 20),
              if (widget.esSuperadmin)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _abrirModalPermisos(ownerId, nombreGoogle);
                    },
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Hacer Admin'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirModalPermisos(String userId, String nombre) {
    bool todos = false;
    final Map<String, bool> seleccion = {
      for (final k in _permisosDisponibles.keys) k: false,
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Permisos para $nombre'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Todos los permisos'),
                  value: todos,
                  onChanged: (v) => setDialogState(() => todos = v),
                ),
                const Divider(),
                ..._permisosDisponibles.entries.map(
                  (e) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title:
                        Text(e.value, style: const TextStyle(fontSize: 13.5)),
                    value: todos ? true : seleccion[e.key]!,
                    onChanged: todos
                        ? null
                        : (v) => setDialogState(() => seleccion[e.key] = v),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final permisos = todos
                    ? <String, dynamic>{'todos': true}
                    : Map<String, dynamic>.from(seleccion);
                try {
                  await widget.tiendasService
                      .crearAdmin(userId: userId, permisos: permisos);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Permisos otorgados ✅')),
                    );
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarDialogoAgregarTienda,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Agregar tienda'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_cargar),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _busquedaCtrl,
                onChanged: (v) => setState(() => _busqueda = v),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre de tienda o municipio...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _busqueda.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _busquedaCtrl.clear();
                            _busqueda = '';
                          }),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _tiendas,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _estadoVacio(
                        icon: Icons.error_outline,
                        texto: 'Error: ${snapshot.error}');
                  }
                  var tiendas = snapshot.data ?? [];
                  if (_busqueda.trim().isNotEmpty) {
                    final q = _busqueda.trim().toLowerCase();
                    tiendas = tiendas.where((t) {
                      final nombre =
                          (t['nombre'] ?? '').toString().toLowerCase();
                      final municipio =
                          (t['municipio'] ?? '').toString().toLowerCase();
                      return nombre.contains(q) || municipio.contains(q);
                    }).toList();
                  }
                  if (tiendas.isEmpty) {
                    return _estadoVacio(
                      icon: _busqueda.isEmpty
                          ? Icons.storefront_outlined
                          : Icons.search_off_rounded,
                      texto: _busqueda.isEmpty
                          ? 'No hay tiendas registradas'
                          : 'Ninguna tienda coincide con "$_busqueda"',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    itemCount: tiendas.length,
                    itemBuilder: (context, i) {
                      final t = tiendas[i];
                      final id = t['id_tienda'] as String;
                      final nombre = t['nombre'] ?? '';
                      final activa = t['estado'] == 'active';
                      final logoUrl = t['logo_url'] as String?;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kCardRadius)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(kCardRadius),
                          onTap: () => _abrirTienda(t),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: activa
                                      ? Colors.green.withOpacity(0.15)
                                      : _kWarm.withOpacity(0.15),
                                  backgroundImage:
                                      (logoUrl != null && logoUrl.isNotEmpty)
                                          ? NetworkImage(logoUrl)
                                          : null,
                                  child: (logoUrl == null || logoUrl.isEmpty)
                                      ? Icon(
                                          Icons.storefront_outlined,
                                          color: activa ? Colors.green : _kWarm,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(nombre,
                                          style: GoogleFonts.plusJakartaSans(
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${activa ? "Activa" : t['estado'] ?? ''} · ${t['plan'] ?? ''} · '
                                        '${t['municipio'] ?? ''}',
                                        style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12.5,
                                            color:
                                                AppColors.inkSecundarioLight),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () =>
                                      _confirmarEliminarTienda(id, nombre),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Pantalla auxiliar: productos de una tienda -- grilla con fotos
// reales, tocar un producto abre el modal real de detalle
// (ProductDetailModal, el mismo que ve un comprador).
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
  State<_ProductosDeTiendaScreen> createState() =>
      _ProductosDeTiendaScreenState();
}

class _ProductosDeTiendaScreenState extends State<_ProductosDeTiendaScreen> {
  late Future<List<Map<String, dynamic>>> _productos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _productos =
        widget.tiendasService.obtenerProductosDeTienda(widget.idTienda);
  }

  Future<void> _confirmarEliminarProducto(
      String idProducto, String nombre) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar producto?'),
        content: Text('Se eliminará "$nombre" permanentemente.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
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
      if (mounted) setState(_cargar);
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
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(widget.nombreTienda),
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
      ),
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
              return _estadoVacio(
                  icon: Icons.inventory_2_outlined,
                  texto: 'Esta tienda no tiene productos');
            }
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              itemCount: productos.length,
              itemBuilder: (context, i) {
                final p = productos[i];
                final id = p['id_producto'] as String;
                final nombre = p['nombre'] ?? '';
                final imagenUrl = p['imagen_url'] as String?;
                final visible = p['es_visible'] != false;
                return GestureDetector(
                  // Tocar el producto abre el MISMO modal que ve un
                  // comprador navegando el marketplace -- "ver como se
                  // ven las pantallas principales" tal como se pidió.
                  onTap: () => showProductDetailModal(
                    context: context,
                    productId: id,
                    distanciaKm: null,
                  ),
                  onLongPress: () => _confirmarEliminarProducto(id, nombre),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(kCardRadius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(kCardRadius)),
                                child: SizedBox.expand(
                                  child: (imagenUrl != null &&
                                          imagenUrl.isNotEmpty)
                                      ? Image.network(imagenUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                              color: Colors.grey.shade200,
                                              child: const Icon(Icons
                                                  .image_not_supported_outlined)))
                                      : Container(
                                          color: Colors.grey.shade200,
                                          child:
                                              const Icon(Icons.image_outlined)),
                                ),
                              ),
                              if (!visible)
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text('Oculto',
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 10)),
                                  ),
                                ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Material(
                                  color: Colors.black45,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () =>
                                        _confirmarEliminarProducto(id, nombre),
                                    child: const Padding(
                                      padding: EdgeInsets.all(5),
                                      child: Icon(Icons.delete_outline,
                                          color: Colors.white, size: 16),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(nombre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              const SizedBox(height: 2),
                              Text('\$${p['precio_usd'] ?? '0'}',
                                  style: GoogleFonts.plusJakartaSans(
                                      color: _kPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
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
      ),
    );
  }
}

// ---------------------------------------------------------------------
// SECCIÓN 3: Números de WhatsApp de verificación
// ---------------------------------------------------------------------

class _ContactosWhatsappTab extends StatefulWidget {
  final TiendasService tiendasService;
  const _ContactosWhatsappTab({required this.tiendasService});

  @override
  State<_ContactosWhatsappTab> createState() => _ContactosWhatsappTabState();
}

class _ContactosWhatsappTabState extends State<_ContactosWhatsappTab> {
  late Future<List<Map<String, dynamic>>> _contactos;
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  void _cargar() {
    _contactos = widget.tiendasService.obtenerContactosWhatsapp();
  }

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
      backgroundColor: AppColors.backgroundLight,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarDialogoAgregar,
        icon: const Icon(Icons.add),
        label: const Text('Agregar número'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_cargar),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _busquedaCtrl,
                onChanged: (v) => setState(() => _busqueda = v),
                decoration: InputDecoration(
                  hintText: 'Buscar por teléfono o etiqueta...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _busqueda.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _busquedaCtrl.clear();
                            _busqueda = '';
                          }),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _contactos,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  var contactos = snapshot.data ?? [];
                  if (_busqueda.trim().isNotEmpty) {
                    final q = _busqueda.trim().toLowerCase();
                    contactos = contactos.where((c) {
                      final telefono =
                          (c['telefono'] ?? '').toString().toLowerCase();
                      final etiqueta =
                          (c['etiqueta'] ?? '').toString().toLowerCase();
                      return telefono.contains(q) || etiqueta.contains(q);
                    }).toList();
                  }
                  if (contactos.isEmpty) {
                    return _estadoVacio(
                      icon: _busqueda.isEmpty
                          ? Icons.chat_outlined
                          : Icons.search_off_rounded,
                      texto: _busqueda.isEmpty
                          ? 'Sin números configurados.\nAgrega uno con el botón +'
                          : 'Ningún número coincide con "$_busqueda"',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    itemCount: contactos.length,
                    itemBuilder: (context, i) {
                      final c = contactos[i];
                      final id = c['id'] as String;
                      final activo = c['activo'] as bool? ?? false;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kCardRadius)),
                        child: ListTile(
                          leading: Icon(
                            Icons.chat_rounded,
                            color: activo
                                ? Colors.green
                                : AppColors.inkSecundarioLight,
                          ),
                          title: Text(c['telefono'] ?? '',
                              style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            activo
                                ? '${c['etiqueta'] ?? 'Sin etiqueta'} · Activo (en uso)'
                                : c['etiqueta'] ?? 'Sin etiqueta',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12.5),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: activo,
                                onChanged: (_) => _toggleActivo(id, activo),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
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
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// SECCIÓN 4: CRUD de Planes
// ---------------------------------------------------------------------

class _PlanesTab extends StatefulWidget {
  final TiendasService tiendasService;
  const _PlanesTab({required this.tiendasService});

  @override
  State<_PlanesTab> createState() => _PlanesTabState();
}

class _PlanesTabState extends State<_PlanesTab> {
  final _storageService = StorageService();
  final _picker = ImagePicker();
  late Future<List<Map<String, dynamic>>> _planes;
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  void _cargar() {
    _planes = widget.tiendasService.obtenerTodosLosPlanes();
  }

  void _mostrarDialogoPlan({Map<String, dynamic>? planExistente}) {
    final esEdicion = planExistente != null;
    final nombreCtrl =
        TextEditingController(text: planExistente?['nombre'] ?? '');
    final codigoCtrl =
        TextEditingController(text: planExistente?['codigo'] ?? '');
    final precioCtrl = TextEditingController(
        text: planExistente != null ? '${planExistente['precio_usd']}' : '');
    final limiteCtrl = TextEditingController(
        text: planExistente != null
            ? '${planExistente['limite_productos']}'
            : '');
    final descripcionCtrl =
        TextEditingController(text: planExistente?['descripcion'] ?? '');
    final tarjetaCtrl =
        TextEditingController(text: planExistente?['numero_tarjeta'] ?? '');
    final telefonoCtrl = TextEditingController(
        text: planExistente?['numero_telefono_pago'] ?? '');
    bool esGratis = planExistente?['es_gratis'] as bool? ?? false;
    final duracionCtrl = TextEditingController(
        text: planExistente?['duracion_dias'] != null
            ? '${planExistente!['duracion_dias']}'
            : '');

    // QR de pago: qrUrlExistente es lo que ya está guardado en Supabase
    // (si se está editando); qrArchivoNuevo es la imagen recién elegida
    // de la galería, que aún no se ha subido. Solo se sube al presionar
    // Guardar/Crear, para no dejar basura en el bucket si el admin
    // cancela el diálogo.
    String? qrUrlExistente = planExistente?['qr_url'] as String?;
    File? qrArchivoNuevo;
    bool subiendoQr = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kCardRadius)),
          title: Text(esEdicion ? 'Editar plan' : 'Nuevo plan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Nombre del plan'),
                ),
                TextField(
                  controller: codigoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Código interno',
                    hintText: "Ej: basic, premium, gratis (sin espacios)",
                    helperText:
                        'Identifica el plan internamente. Debe ser único y '
                        'no debe cambiarse después si ya hay tiendas usándolo.',
                    helperMaxLines: 2,
                  ),
                ),
                TextField(
                  controller: precioCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Precio (USD)'),
                ),
                TextField(
                  controller: limiteCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Límite de productos'),
                ),
                TextField(
                  controller: descripcionCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Descripción / qué incluye',
                    hintText: 'Ej: 20 productos, portada mensual...',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: _kPrimary,
                  title: const Text('Es un plan gratuito'),
                  value: esGratis,
                  onChanged: (v) => setDialogState(() => esGratis = v),
                ),
                if (esGratis)
                  TextField(
                    controller: duracionCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Duración (días)',
                      hintText: 'Ej: 14',
                    ),
                  ),
                if (!esGratis) ...[
                  const Divider(height: 24),
                  TextField(
                    controller: tarjetaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Número de tarjeta',
                      hintText: 'Para el QR de pago',
                    ),
                  ),
                  TextField(
                    controller: telefonoCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono asociado al pago',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('QR de pago (foto)',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkSecundarioLight)),
                  const SizedBox(height: 8),
                  if (qrArchivoNuevo != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(qrArchivoNuevo!,
                          height: 140, fit: BoxFit.contain),
                    )
                  else if (qrUrlExistente != null && qrUrlExistente!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(qrUrlExistente!,
                          height: 140, fit: BoxFit.contain),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: subiendoQr
                        ? null
                        : () async {
                            final archivo = await _picker.pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 800,
                              imageQuality: 85,
                            );
                            if (archivo != null) {
                              setDialogState(
                                  () => qrArchivoNuevo = File(archivo.path));
                            }
                          },
                    icon: const Icon(Icons.qr_code_2_outlined, size: 18),
                    label: Text(qrUrlExistente == null && qrArchivoNuevo == null
                        ? 'Seleccionar foto del QR'
                        : 'Cambiar foto del QR'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final nombre = nombreCtrl.text.trim();
                final codigo = codigoCtrl.text.trim().toLowerCase();
                final precio = double.tryParse(precioCtrl.text.trim()) ?? 0;
                final limite = int.tryParse(limiteCtrl.text.trim());
                if (nombre.isEmpty || limite == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Completa nombre y límite correctamente')),
                  );
                  return;
                }
                if (codigo.isEmpty || codigo.contains(' ')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'El código interno es obligatorio y no puede tener espacios')),
                  );
                  return;
                }
                final duracion =
                    esGratis ? int.tryParse(duracionCtrl.text.trim()) : null;
                try {
                  // Si el admin eligió una foto nueva de QR, se sube
                  // primero. Para un plan nuevo (aún sin id_plan) se usa
                  // un identificador temporal solo para la ruta del
                  // archivo en el bucket -- no afecta al registro final.
                  String? qrUrlFinal = qrUrlExistente;
                  if (qrArchivoNuevo != null) {
                    setDialogState(() => subiendoQr = true);
                    final idParaRuta = esEdicion
                        ? planExistente['id_plan'] as String
                        : 'nuevo_${DateTime.now().millisecondsSinceEpoch}';
                    qrUrlFinal = await _storageService.subirQrPlan(
                      archivo: qrArchivoNuevo!,
                      idPlan: idParaRuta,
                    );
                    setDialogState(() => subiendoQr = false);
                  }

                  if (esEdicion) {
                    await widget.tiendasService.actualizarPlan(
                      idPlan: planExistente['id_plan'],
                      nombre: nombre,
                      codigo: codigo,
                      precioUsd: precio,
                      limiteProductos: limite,
                      descripcion: descripcionCtrl.text.trim().isEmpty
                          ? null
                          : descripcionCtrl.text.trim(),
                      numeroTarjeta: tarjetaCtrl.text.trim().isEmpty
                          ? null
                          : tarjetaCtrl.text.trim(),
                      numeroTelefonoPago: telefonoCtrl.text.trim().isEmpty
                          ? null
                          : telefonoCtrl.text.trim(),
                      qrUrl: qrUrlFinal,
                      esGratis: esGratis,
                      duracionDias: duracion,
                    );
                  } else {
                    await widget.tiendasService.crearPlan(
                      nombre: nombre,
                      codigo: codigo,
                      precioUsd: precio,
                      limiteProductos: limite,
                      descripcion: descripcionCtrl.text.trim().isEmpty
                          ? null
                          : descripcionCtrl.text.trim(),
                      numeroTarjeta: tarjetaCtrl.text.trim().isEmpty
                          ? null
                          : tarjetaCtrl.text.trim(),
                      numeroTelefonoPago: telefonoCtrl.text.trim().isEmpty
                          ? null
                          : telefonoCtrl.text.trim(),
                      qrUrl: qrUrlFinal,
                      esGratis: esGratis,
                      duracionDias: duracion,
                    );
                  }
                  if (mounted) {
                    Navigator.pop(ctx);
                    setState(_cargar);
                  }
                } catch (e) {
                  setDialogState(() => subiendoQr = false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: Text(esEdicion ? 'Guardar' : 'Crear'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleActivo(Map<String, dynamic> plan) async {
    final activo = plan['activo'] as bool? ?? true;
    try {
      if (activo) {
        await widget.tiendasService.eliminarPlan(plan['id_plan']);
      } else {
        await widget.tiendasService.reactivarPlan(plan['id_plan']);
      }
      setState(_cargar);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _mostrarDialogoPlan(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo plan'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_cargar),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _busquedaCtrl,
                onChanged: (v) => setState(() => _busqueda = v),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o código de plan...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _busqueda.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _busquedaCtrl.clear();
                            _busqueda = '';
                          }),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _planes,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  var planes = snapshot.data ?? [];
                  if (_busqueda.trim().isNotEmpty) {
                    final q = _busqueda.trim().toLowerCase();
                    planes = planes.where((p) {
                      final nombre =
                          (p['nombre'] ?? '').toString().toLowerCase();
                      final codigo =
                          (p['codigo'] ?? '').toString().toLowerCase();
                      return nombre.contains(q) || codigo.contains(q);
                    }).toList();
                  }
                  if (planes.isEmpty) {
                    return _estadoVacio(
                      icon: _busqueda.isEmpty
                          ? Icons.workspace_premium_outlined
                          : Icons.search_off_rounded,
                      texto: _busqueda.isEmpty
                          ? 'Sin planes configurados.\nCrea uno con el botón +'
                          : 'Ningún plan coincide con "$_busqueda"',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    itemCount: planes.length,
                    itemBuilder: (context, i) {
                      final p = planes[i];
                      final activo = p['activo'] as bool? ?? true;
                      final esGratis = p['es_gratis'] as bool? ?? false;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kCardRadius)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: activo
                                ? Colors.green.withOpacity(0.15)
                                : Colors.grey.withOpacity(0.15),
                            child: Icon(Icons.workspace_premium_outlined,
                                color: activo ? Colors.green : Colors.grey),
                          ),
                          title: Text(
                            esGratis
                                ? '${p['nombre']} · Gratis'
                                : '${p['nombre']} · \$${p['precio_usd']}',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                              'Código: ${p['codigo'] ?? '⚠️ sin código'} · '
                              '${p['limite_productos']} productos · '
                              '${activo ? "Activo" : "Desactivado"}',
                              style:
                                  GoogleFonts.plusJakartaSans(fontSize: 12.5)),
                          onTap: () => _mostrarDialogoPlan(planExistente: p),
                          trailing: Switch(
                            value: activo,
                            onChanged: (_) => _toggleActivo(p),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// SECCIÓN 5: Afiliados -- buscador por código + gestión de retiros
// pendientes. Solo lectura sobre los datos del afiliado (nombre,
// teléfono, tarjeta, saldo); la única acción disponible es marcar un
// retiro como pagado (vía RPC admin_marcar_retiro_pagado, que resta
// el saldo -- el admin no tiene permiso directo de UPDATE sobre
// 'afiliados').
// ---------------------------------------------------------------------

class _AfiliadosTab extends StatefulWidget {
  final TiendasService tiendasService;
  const _AfiliadosTab({required this.tiendasService});

  @override
  State<_AfiliadosTab> createState() => _AfiliadosTabState();
}

class _AfiliadosTabState extends State<_AfiliadosTab> {
  late Future<List<Map<String, dynamic>>> _retirosPendientes;
  final _busquedaCtrl = TextEditingController();
  final Set<String> _procesando = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  void _cargar() {
    _retirosPendientes = widget.tiendasService.obtenerRetirosPendientes();
  }

  void _notificarError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Error: $e')));
  }

  Future<void> _buscarPorCodigo() async {
    final codigo = _busquedaCtrl.text.trim();
    if (codigo.isEmpty) return;
    try {
      final afiliado =
          await widget.tiendasService.buscarAfiliadoPorCodigo(codigo);
      if (!mounted) return;
      if (afiliado == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No existe ningún afiliado con ese código')),
        );
        return;
      }
      _mostrarDetalleAfiliado(afiliado);
    } catch (e) {
      _notificarError(e);
    }
  }

  void _copiar(String etiqueta, String valor) {
    Clipboard.setData(ClipboardData(text: valor));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('$etiqueta copiado ✅'),
          duration: const Duration(seconds: 1)),
    );
  }

  void _mostrarDetalleAfiliado(Map<String, dynamic> afiliado,
      {double? montoRetiro}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.only(top: 20, bottom: 20),
              children: [
                Text(afiliado['nombre'] ?? '',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 4),
                Text('Código: ${afiliado['codigo']}',
                    style: GoogleFonts.plusJakartaSans(
                        color: AppColors.inkSecundarioLight, fontSize: 13)),
                const SizedBox(height: 4),
                Text('Saldo actual: ${afiliado['saldo_cup'] ?? 0} CUP',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const Divider(height: 28),
                _filaCopiable('Teléfono', afiliado['telefono'] ?? '-'),
                const SizedBox(height: 10),
                _filaCopiable('Tarjeta', afiliado['numero_tarjeta'] ?? '-'),
                if (montoRetiro != null) ...[
                  const SizedBox(height: 10),
                  _filaCopiable(
                      'Monto a pagar', '${montoRetiro.toStringAsFixed(0)} CUP'),
                ],
                const Divider(height: 28),
                Text('Historial de comisiones',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text('De qué tiendas salió el saldo de este afiliado',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: AppColors.inkSecundarioLight)),
                const SizedBox(height: 12),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: widget.tiendasService
                      .obtenerUsosDeAfiliado(afiliado['id_afiliado']),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final usos = snapshot.data!;
                    if (usos.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('Aún no tiene comisiones registradas.',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: AppColors.inkSecundarioLight)),
                      );
                    }
                    return Column(
                      children: usos.map((u) {
                        final aprobado = u['estado'] == 'aprobado';
                        final nombreTienda =
                            u['tiendas']?['nombre'] ?? 'Tienda eliminada';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                aprobado
                                    ? Icons.check_circle_rounded
                                    : Icons.schedule_rounded,
                                size: 18,
                                color: aprobado ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(nombreTienda,
                                        style: GoogleFonts.plusJakartaSans(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13)),
                                    Text(
                                      aprobado
                                          ? '+${u['comision_cup_acreditada'] ?? 0} CUP · código ${u['codigo']}'
                                          : 'Pendiente de aprobación · código ${u['codigo']}',
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11.5,
                                          color: AppColors.inkSecundarioLight),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filaCopiable(String etiqueta, String valor) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(etiqueta,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: AppColors.inkSecundarioLight)),
              Text(valor,
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600, fontSize: 15)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy_rounded, size: 20),
          onPressed: () => _copiar(etiqueta, valor),
        ),
      ],
    );
  }

  Future<void> _marcarPagado(Map<String, dynamic> retiro) async {
    final idRetiro = retiro['id_retiro'] as String;
    final afiliado = retiro['afiliados'] as Map<String, dynamic>?;
    if (afiliado == null) {
      _notificarError('No se encontró el afiliado de este retiro');
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar pago'),
        content: Text(
          '¿Confirmas que ya transferiste ${retiro['monto_cup']} CUP a '
          '${afiliado['nombre']}? Esto restará el monto de su saldo.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar pago')),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _procesando.add(idRetiro));
    try {
      await widget.tiendasService.marcarRetiroPagado(
        idRetiro: idRetiro,
        idAfiliado: afiliado['id_afiliado'] ?? retiro['id_afiliado'],
        montoCup: (retiro['monto_cup'] as num).toDouble(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Retiro marcado como pagado ✅')),
        );
        setState(_cargar);
      }
    } catch (e) {
      _notificarError(e);
    } finally {
      if (mounted) setState(() => _procesando.remove(idRetiro));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(_cargar),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Buscar afiliado',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _busquedaCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'Código de afiliado (ej: A3F9K2)',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  onSubmitted: (_) => _buscarPorCodigo(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _buscarPorCodigo,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16)),
                child: const Icon(Icons.search),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text('Retiros pendientes',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _retirosPendientes,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red)),
                );
              }
              final retiros = snapshot.data ?? [];
              if (retiros.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No hay retiros pendientes',
                        style: GoogleFonts.plusJakartaSans(
                            color: AppColors.inkSecundarioLight)),
                  ),
                );
              }
              return Column(
                children: retiros.map((r) {
                  final idRetiro = r['id_retiro'] as String;
                  final procesando = _procesando.contains(idRetiro);
                  final afiliado =
                      r['afiliados'] as Map<String, dynamic>? ?? {};
                  final monto = (r['monto_cup'] as num).toDouble();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kCardRadius)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(kCardRadius),
                      onTap: () =>
                          _mostrarDetalleAfiliado(afiliado, montoRetiro: monto),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(afiliado['nombre'] ?? 'Afiliado',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                Text('${monto.toStringAsFixed(0)} CUP',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: _kPrimary)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text('Código: ${afiliado['codigo'] ?? '-'}',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: AppColors.inkSecundarioLight)),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed:
                                    procesando ? null : () => _marcarPagado(r),
                                icon: procesando
                                    ? const SizedBox(
                                        height: 14,
                                        width: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.check_circle_outline,
                                        size: 18),
                                label: const Text('Marcar como Pagado'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
