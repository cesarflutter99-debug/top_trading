// mi_perfil_screen.dart
//
// REDISEÑO (2026-09):
// 1. COMPACTO: se reemplazó la portada gigante + avatar flotante por un
//    header delgado (avatar chico + nombre + trabajo en una sola fila).
//    El contenido se organiza en 2 pestañas (TabBar bajo el AppBar) en
//    vez de un único scroll larguísimo: "Cuenta" (tienda/afiliado/
//    negocio) y "Anuncios" (ranuras de anuncio independiente, ahora con
//    datos reales -- ver más abajo). Cada pestaña sigue siendo
//    scrolleable como red de seguridad en pantallas chicas, pero con
//    paddings/tamaños reducidos entra sin scroll en la mayoría de los
//    teléfonos.
// 2. MODO OSCURO: se revisaron todos los colores -- todo sale de
//    getters (_colorTexto/_colorTextoSecundario/_colorSuperficie/
//    _colorBorde) calculados según Theme.of(context).brightness, sin
//    ningún AppColors.ink*/inkSecundario* fijo suelto en el árbol.
// 3. NUEVO: acceso rápido a cambiar el tema (ícono sol/luna en el
//    AppBar) -- antes solo se podía cambiar desde el Drawer de Home.
// 4. NUEVO: la sección "Anuncios independientes" ahora muestra
//    información REAL de ranuras compradas (ranurasStandalone()) con
//    una barra de uso, los permisos activos con su fecha de
//    vencimiento, y una barra de "vigencia" (días restantes hasta que
//    vence el permiso más próximo) -- mismo lenguaje visual que ya usa
//    la barra de plan/vencimiento de la tienda. Si no hay ninguna
//    ranura activa, se ofrece "Ver planes disponibles" (mismo flujo de
//    compra por WhatsApp que ya usa Gestionar Anuncios de tienda/
//    negocio, ver standalone_anuncio_screen.dart).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_colors.dart';
import '../core/auth_guard.dart';
import '../core/supabase_client.dart';
import '../services/anuncios_service.dart';
import '../services/negocio_state_service.dart';
import '../services/storage_service.dart';
import '../services/theme_provider.dart';
import '../services/tiendas_service.dart';
import '../services/tienda_state_service.dart';
import '../services/afiliado_state_service.dart';
import '../widgets/paquetes_negocio_sheet.dart';
import '../widgets/servicios_negocio_sheet.dart';
import 'onboarding_negocio_screen.dart';
import 'standalone_anuncio_screen.dart';

class MiPerfilScreen extends StatefulWidget {
  const MiPerfilScreen({super.key});

  @override
  State<MiPerfilScreen> createState() => _MiPerfilScreenState();
}

class _MiPerfilScreenState extends State<MiPerfilScreen>
    with SingleTickerProviderStateMixin {
  final _tiendasService = TiendasService();
  final _storageService = StorageService();
  final _anunciosService = AnunciosService();
  final _picker = ImagePicker();
  late final TabController _tabController;

  User? _perfil;
  Map<String, dynamic>? get _miTienda => TiendaStateService.instance.miTienda;
  Map<String, dynamic>? get _miAfiliado =>
      AfiliadoStateService.instance.miAfiliado;

  Map<String, dynamic>? _planActual;
  String? _codigoPlanCacheado;
  bool _esAdmin = false;
  bool _cargando = true;
  bool _subiendoAvatar = false;

  // Anuncios independientes (standalone) -- datos reales de ranuras.
  Future<({int usados, int max, DateTime? vigenteHasta})>? _ranurasStandaloneFuture;
  Future<List<Map<String, dynamic>>>? _permisosStandaloneFuture;
  Future<List<Map<String, dynamic>>>? _pendientesStandaloneFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (supabase.auth.currentUser == null) {
      _cargando = false;
    } else {
      _cargarTodo();
      TiendaStateService.instance.addListener(_sincronizarPlanDesdeTienda);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    TiendaStateService.instance.removeListener(_sincronizarPlanDesdeTienda);
    super.dispose();
  }

  void _cargarAnuncios() {
    _ranurasStandaloneFuture = _anunciosService.ranurasStandalone();
    _permisosStandaloneFuture = _anunciosService.misPermisosStandalone();
    _pendientesStandaloneFuture = _anunciosService.comprasPendientesStandalone();
  }

  Future<void> _sincronizarPlanDesdeTienda() async {
    final codigoPlan = TiendaStateService.instance.miTienda?['plan'] as String?;
    if (codigoPlan == _codigoPlanCacheado) return;
    _codigoPlanCacheado = codigoPlan;
    if (codigoPlan == null) {
      if (mounted) setState(() => _planActual = null);
      return;
    }
    try {
      final plan = await _tiendasService.obtenerPlanPorCodigo(codigoPlan);
      if (mounted) setState(() => _planActual = plan);
    } catch (_) {}
  }

  Future<void> _cargarTodo() async {
    setState(() => _cargando = true);
    try {
      final perfil = supabase.auth.currentUser;
      await Future.wait([
        TiendaStateService.instance.refrescar(),
        AfiliadoStateService.instance.refrescar(),
        NegocioStateService.instance.refrescar(),
      ]);
      final admin = await _tiendasService.esAdmin();
      await _sincronizarPlanDesdeTienda();
      _cargarAnuncios();

      if (mounted) {
        setState(() {
          _perfil = perfil;
          _esAdmin = admin;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _recargarAnuncios() async {
    setState(_cargarAnuncios);
  }

  String _nombre() {
    final user = _perfil;
    if (user == null) return 'Usuario';
    return user.userMetadata?['full_name'] as String? ??
        user.userMetadata?['name'] as String? ??
        user.email ??
        'Usuario';
  }

  String _email() => _perfil?.email ?? '';

  String _fotoUrl() {
    final m = _perfil?.userMetadata;
    final custom = m?['avatar_url_custom'] as String?;
    if (custom != null && custom.isNotEmpty) return custom;
    return m?['avatar_url'] as String? ?? '';
  }

  String _trabajo() {
    if (_miTienda != null) {
      final nombreTienda = (_miTienda!['nombre'] as String?) ?? 'tu tienda';
      return 'Vendedor · $nombreTienda';
    }
    if (_miAfiliado != null) return 'Afiliado del programa Al Lado';
    if (_esAdmin) return 'Administrador de la plataforma';
    return 'Comprador en Al Lado';
  }

  Future<void> _cambiarFotoPerfil() async {
    final XFile? archivo = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (archivo == null) return;

    setState(() => _subiendoAvatar = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      final url = await _storageService.subirFotoPerfil(
        archivo: File(archivo.path),
        uid: uid,
      );
      final res = await supabase.auth.updateUser(
        UserAttributes(data: {'avatar_url_custom': url}),
      );
      if (mounted) setState(() => _perfil = res.user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo subir la foto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _subiendoAvatar = false);
    }
  }

  // -----------------------------------------------------------------
  // COLORES ADAPTATIVOS -- únicos usados en todo el árbol de widgets.
  // -----------------------------------------------------------------
  bool get _esOscuro => Theme.of(context).brightness == Brightness.dark;
  Color get _colorTexto => _esOscuro ? const Color(0xFFF5F5F4) : AppColors.ink;
  Color get _colorTextoSecundario =>
      _esOscuro ? const Color(0xFFA8A29E) : Colors.black54;
  Color get _colorFondo => Theme.of(context).scaffoldBackgroundColor;
  Color get _colorSuperficie => _esOscuro
      ? AppColors.cardTransparentDark
      : AppColors.cardTransparentLight;
  Color get _colorBorde =>
      (_esOscuro ? AppColors.borderDark : AppColors.borderLight)
          .withOpacity(0.6);

  Color _colorFraccion(double fracLibre) {
    const verde = Color(0xFF2ECC71);
    const amarillo = Color(0xFFFFC107);
    const rojo = Color(0xFFE53935);
    if (fracLibre <= 0) return rojo;
    if (fracLibre >= 0.5) {
      final t = ((fracLibre - 0.5) / 0.5).clamp(0.0, 1.0);
      return Color.lerp(amarillo, verde, t)!;
    }
    final t = (fracLibre / 0.5).clamp(0.0, 1.0);
    return Color.lerp(rojo, amarillo, t)!;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: TiendaStateService.instance,
      builder: (context, _) => AnimatedBuilder(
        animation: AfiliadoStateService.instance,
        builder: (context, __) => _buildScaffold(context),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    if (supabase.auth.currentUser == null) {
      return Scaffold(
        backgroundColor: _colorFondo,
        appBar: AppBar(
          title: const Text('Mi Perfil'),
          backgroundColor: _colorFondo,
          foregroundColor: _colorTexto,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline_rounded,
                    size: 52, color: _colorTextoSecundario),
                const SizedBox(height: 14),
                Text('Inicia sesión para ver tu perfil',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        color: _colorTexto)),
                const SizedBox(height: 6),
                Text(
                  'Accedé con Google para ver tu tienda, tus afiliados '
                  'y gestionar tu cuenta.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5, color: _colorTextoSecundario),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => mostrarModalInicioSesion(context),
                  child: const Text('Iniciar sesión'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        backgroundColor: _colorFondo,
        foregroundColor: _colorTexto,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: themeProvider.isDarkMode ? 'Modo claro' : 'Modo oscuro',
            icon: Icon(themeProvider.isDarkMode
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
            onPressed: () => themeProvider.toggleTheme(),
          ),
        ],
        bottom: _cargando
            ? null
            : TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: _colorTextoSecundario,
                indicatorColor: AppColors.primary,
                labelStyle: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700, fontSize: 13),
                tabs: const [
                  Tab(text: 'Cuenta'),
                  Tab(text: 'Anuncios'),
                ],
              ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeaderCompacto(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTabCuenta(),
                      _buildTabAnuncios(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // -----------------------------------------------------------------
  // HEADER COMPACTO -- una sola fila: avatar chico + nombre/trabajo +
  // chips de rol. Reemplaza la portada + avatar flotante de antes.
  // -----------------------------------------------------------------
  Widget _buildHeaderCompacto() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: _colorSuperficie,
        border: Border(bottom: BorderSide(color: _colorBorde)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _subiendoAvatar ? null : _cambiarFotoPerfil,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage:
                      _fotoUrl().isNotEmpty ? NetworkImage(_fotoUrl()) : null,
                  child: _fotoUrl().isEmpty
                      ? const Icon(Icons.person,
                          size: 26, color: AppColors.primary)
                      : null,
                ),
                if (_subiendoAvatar)
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Positioned(
                    bottom: -1,
                    right: -1,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _esOscuro
                                ? AppColors.surfaceDark
                                : Colors.white,
                            width: 1.5),
                      ),
                      child: const Icon(Icons.camera_alt,
                          size: 10, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _nombre(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: _colorTexto),
                ),
                const SizedBox(height: 1),
                Text(
                  _trabajo(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              if (_miTienda != null)
                _miniChip(Icons.storefront_rounded, AppColors.primary),
              if (_miAfiliado != null)
                _miniChip(Icons.handshake_outlined, AppColors.warm),
              if (_esAdmin)
                _miniChip(Icons.admin_panel_settings, Colors.deepPurple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniChip(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: color.withOpacity(_esOscuro ? 0.2 : 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 13, color: color),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _colorTextoSecundario),
        const SizedBox(width: 6),
        Text(title,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: _colorTexto)),
      ],
    );
  }

  // ===================================================================
  // TAB 1: CUENTA -- tienda / afiliado / negocio / cuenta vacía
  // ===================================================================
  Widget _buildTabCuenta() {
    return RefreshIndicator(
      onRefresh: _cargarTodo,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          if (_miTienda != null) ...[
            _buildSectionTitle('Mi Tienda', Icons.storefront_rounded),
            const SizedBox(height: 8),
            _buildTiendaSection(),
            const SizedBox(height: 16),
          ],
          if (_miAfiliado != null) ...[
            _buildSectionTitle(
                'Mi Programa de Afiliados', Icons.handshake_rounded),
            const SizedBox(height: 8),
            _buildAfiliadoCard(),
            const SizedBox(height: 16),
          ],
          if (_miTienda == null && _miAfiliado == null) ...[
            _buildSectionTitle('Tu Cuenta', Icons.person_rounded),
            const SizedBox(height: 8),
            _buildCuentaVaciaCard(),
            const SizedBox(height: 16),
          ],
          _buildSectionTitle('Mi negocio', Icons.campaign_rounded),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: NegocioStateService.instance,
            builder: (_, __) => _buildNegocioSeccionContenido(),
          ),
        ],
      ),
    );
  }

  Widget _buildTiendaSection() {
    final t = _miTienda!;
    final esVip = (t['plan'] as String? ?? '').toLowerCase() == 'premium';
    final estado = t['estado'] as String? ?? 'pending';
    final activa = estado == 'active';

    return Container(
      decoration: BoxDecoration(
        color: _colorSuperficie,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: _colorBorde),
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(esVip ? 2 : 0),
                decoration: esVip
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        border: const Border.fromBorderSide(
                            BorderSide(color: Color(0xFFD4AF37), width: 1.5)),
                      )
                    : null,
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: (t['logo_url'] as String?) != null &&
                          (t['logo_url'] as String).isNotEmpty
                      ? NetworkImage(t['logo_url'] as String)
                      : null,
                  child: (t['logo_url'] as String?) == null ||
                          (t['logo_url'] as String).isEmpty
                      ? const Icon(Icons.storefront_rounded,
                          size: 20, color: AppColors.primary)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t['nombre'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: _colorTexto)),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 5,
                      runSpacing: 3,
                      children: [
                        _badgePequeno(
                          activa ? 'Activa' : 'En revisión',
                          activa ? AppColors.success : AppColors.warm,
                          activa
                              ? Icons.check_circle_rounded
                              : Icons.hourglass_top_rounded,
                        ),
                        _badgePequeno(
                          esVip ? 'PREMIUM' : 'BASIC',
                          esVip ? const Color(0xFFD4AF37) : AppColors.primary,
                          esVip
                              ? Icons.star_rounded
                              : Icons.storefront_outlined,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                    'Productos',
                    '${t['productos_count'] ?? 0}',
                    Icons.shopping_bag,
                    AppColors.primary),
              ),
              Expanded(
                child: _buildStatItem('Pedidos', '${t['pedidos_count'] ?? 0}',
                    Icons.shopping_cart, AppColors.primary),
              ),
              Expanded(
                child: _buildStatItem('Ingresos', '\$${t['ingresos'] ?? 0}',
                    Icons.attach_money, AppColors.primary),
              ),
            ],
          ),
          _buildBarraPlan(),
          _buildBarraRanurasTienda(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    context.push('/gestionar-tienda', extra: _miTienda);
                  },
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('Gestionar',
                      style: TextStyle(fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 9)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    context.push('/vendedor/dashboard',
                        extra: {'id': _miTienda!['id_tienda']});
                  },
                  icon: const Icon(Icons.analytics_outlined, size: 16),
                  label: const Text('Analíticas',
                      style: TextStyle(fontSize: 12.5)),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 9)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badgePequeno(String texto, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withOpacity(_esOscuro ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(texto,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 9.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  /// Barra genérica reutilizable (uso%) -- misma que ya usan
  /// tienda/anuncios, ahora en un solo lugar para no repetir.
  Widget _barraUso({
    required IconData icono,
    required String etiqueta,
    required String valorDerecha,
    required String detalle,
    required double pct,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: (_esOscuro ? Colors.white : Colors.black)
              .withOpacity(_esOscuro ? 0.05 : 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icono, size: 13, color: color),
                    const SizedBox(width: 5),
                    Text(etiqueta,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _colorTexto)),
                  ],
                ),
                Text(valorDerecha,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                height: 7,
                color: color.withOpacity(0.15),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: pct.clamp(0.03, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient:
                            LinearGradient(colors: [color.withOpacity(0.65), color]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(detalle,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10, color: _colorTextoSecundario)),
          ],
        ),
      ),
    );
  }

  Widget _buildBarraPlan() {
    final expiraStr = _miTienda?['plan_expira_en'] as String?;
    if (expiraStr == null) return const SizedBox.shrink();
    final expira = DateTime.tryParse(expiraStr);
    if (expira == null) return const SizedBox.shrink();

    final ahora = DateTime.now();
    final restante = expira.difference(ahora);
    final diasRestantes =
        restante.isNegative ? 0 : (restante.inHours / 24).ceil();
    final vencido = diasRestantes <= 0;

    final duracionTotal = (_planActual?['duracion_dias'] as num?)?.toInt();
    double pctUsado;
    if (duracionTotal != null && duracionTotal > 0) {
      pctUsado = vencido
          ? 1.0
          : ((duracionTotal - diasRestantes) / duracionTotal)
              .clamp(0.0, 1.0)
              .toDouble();
    } else {
      pctUsado = vencido ? 1.0 : 0.15;
    }
    final color = _colorFraccion(vencido ? 0 : 1 - pctUsado);

    return Column(
      children: [
        _barraUso(
          icono: Icons.bolt_rounded,
          etiqueta: 'Vigencia del plan',
          valorDerecha: vencido
              ? 'Vencido'
              : diasRestantes == 1
                  ? '1 día'
                  : '$diasRestantes días',
          detalle: vencido
              ? 'Renueva tu plan para seguir visible en el marketplace'
              : duracionTotal != null
                  ? '${(pctUsado * 100).round()}% usado'
                  : 'Plan activo',
          pct: pctUsado,
          color: color,
        ),
        if (vencido || diasRestantes <= 3)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                context.push('/gestionar-planes', extra: _miTienda);
              },
              style: TextButton.styleFrom(
                foregroundColor: color,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.autorenew_rounded, size: 14),
              label: const Text('Renovar plan', style: TextStyle(fontSize: 11.5)),
            ),
          ),
      ],
    );
  }

  Widget _buildBarraRanurasTienda() {
    final idTienda = _miTienda?['id_tienda'] as String?;
    if (idTienda == null) return const SizedBox.shrink();
    return FutureBuilder<({int usados, int max, int maxPlan, int maxExtra})>(
      future: _anunciosService.ranurasDeTienda(idTienda),
      builder: (context, snap) {
        final r = snap.data;
        if (r == null || r.max <= 0) return const SizedBox.shrink();
        final pct = (r.usados / r.max).clamp(0.0, 1.0);
        final restantes = (r.max - r.usados).clamp(0, r.max);
        final color = _colorFraccion(1 - pct);
        final detalle = r.maxExtra > 0
            ? '${r.usados}/${r.max} · ${r.maxPlan} plan + ${r.maxExtra} extra'
            : '${r.usados}/${r.max} ranuras de tu plan';
        return _barraUso(
          icono: Icons.campaign_rounded,
          etiqueta: 'Ranuras de anuncio',
          valorDerecha: restantes <= 0 ? 'Máximo' : '$restantes libres',
          detalle: detalle,
          pct: pct,
          color: color,
        );
      },
    );
  }

  Widget _buildAfiliadoCard() {
    final a = _miAfiliado!;
    return Container(
      decoration: BoxDecoration(
        color: _colorSuperficie,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: _colorBorde),
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.warm.withOpacity(_esOscuro ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.handshake_outlined,
                    color: AppColors.warm, size: 16),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text('Mi programa de afiliados',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: _colorTexto)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildStatItem('Código', a['codigo'] ?? '-',
                    Icons.confirmation_number, AppColors.warm),
              ),
              Expanded(
                child: _buildStatItem('Saldo', '${a['saldo_cup'] ?? 0} CUP',
                    Icons.wallet, AppColors.warm),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/afiliados/perfil'),
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('Ver perfil completo',
                  style: TextStyle(fontSize: 12.5)),
              style:
                  OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 9)),
            ),
          ),
        ],
      ),
    );
  }

  static const Color _kVerdeNegocio = Color(0xFF0D9488);

  Widget _buildNegocioSeccionContenido() {
    final svc = NegocioStateService.instance;
    if (svc.cargando) {
      return const SizedBox(
        height: 70,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final n = svc.miNegocio;
    if (n == null) return _buildNegocioCtaCard();

    switch (svc.estado) {
      case 'activo':
        return _buildNegocioEstadoCard(
          color: AppColors.success,
          icono: Icons.check_circle_rounded,
          titulo: '"${n['nombre']}" está aprobado',
          texto: 'Ya aparece en el mapa y, si tienes paquete vigente, '
              'también rota en el feed.',
          botonTexto: 'Ver mi mini-página',
          accion: () => context.push('/negocio/${n['id_negocio']}'),
          accionesSecundarias: [
            (
              icono: Icons.spa_outlined,
              texto: 'Servicios y precios',
              accion: () => mostrarServiciosNegocioSheet(context, n),
            ),
            (
              icono: Icons.campaign_rounded,
              texto: 'Anuncios y promociones',
              accion: () => mostrarPaquetesNegocioSheet(context, n),
            ),
          ],
        );
      case 'rechazado':
        final motivo = n['motivo_rechazo'] as String?;
        return _buildNegocioEstadoCard(
          color: Theme.of(context).colorScheme.error,
          icono: Icons.cancel_rounded,
          titulo: '"${n['nombre']}" fue rechazado',
          texto: motivo == null || motivo.isEmpty
              ? 'El admin rechazó tu negocio. Contáctanos por WhatsApp.'
              : 'Motivo: $motivo',
        );
      case 'suspendido':
        return _buildNegocioEstadoCard(
          color: Theme.of(context).colorScheme.error,
          icono: Icons.pause_circle_rounded,
          titulo: '"${n['nombre']}" está suspendido',
          texto: 'No es visible temporalmente. Contáctanos por WhatsApp.',
        );
      default:
        return _buildNegocioEstadoCard(
          color: AppColors.warm,
          icono: Icons.hourglass_top_rounded,
          titulo: '"${n['nombre']}" está en revisión',
          texto: 'Te llegará una notificación cuando sea aprobado.',
        );
    }
  }

  Widget _buildNegocioEstadoCard({
    required Color color,
    required IconData icono,
    required String titulo,
    String? texto,
    String? botonTexto,
    VoidCallback? accion,
    List<({IconData icono, String texto, VoidCallback accion})>?
        accionesSecundarias,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(_esOscuro ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withOpacity(_esOscuro ? 0.25 : 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icono, color: color, size: 16),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(titulo,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        color: _colorTexto,
                        fontSize: 13)),
              ),
            ],
          ),
          if (texto != null) ...[
            const SizedBox(height: 6),
            Text(texto,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: _colorTextoSecundario, height: 1.4)),
          ],
          if (botonTexto != null && accion != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                ),
                onPressed: accion,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(botonTexto, style: const TextStyle(fontSize: 12.5)),
              ),
            ),
          ],
          if (accionesSecundarias != null && accionesSecundarias.isNotEmpty)
            for (final a in accionesSecundarias) ...[
              const SizedBox(height: 7),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                  onPressed: a.accion,
                  icon: Icon(a.icono, size: 16),
                  label: Text(a.texto, style: const TextStyle(fontSize: 12.5)),
                ),
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildNegocioCtaCard() {
    return Container(
      decoration: BoxDecoration(
        color: _kVerdeNegocio.withOpacity(_esOscuro ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: _kVerdeNegocio.withOpacity(0.35)),
      ),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _kVerdeNegocio.withOpacity(_esOscuro ? 0.25 : 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.campaign_rounded,
                    color: _kVerdeNegocio, size: 16),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text('¿Quieres que te encuentren?',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        color: _colorTexto,
                        fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Registra tu negocio o un evento puntual para aparecer en el '
            'mapa y en el feed.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: _colorTextoSecundario, height: 1.4),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _kVerdeNegocio,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 9),
              ),
              onPressed: _elegirTipoYRegistrar,
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Empezar', style: TextStyle(fontSize: 12.5)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _elegirTipoYRegistrar() async {
    final tipo = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('¿Qué quieres promocionar?',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: _colorTexto)),
              const SizedBox(height: 14),
              _opcionTipoNegocio(
                icono: Icons.storefront_rounded,
                titulo: 'Mi negocio',
                subtitulo: 'Barbería, taller, consultorio... permanente.',
                onTap: () => Navigator.of(ctx).pop('negocio'),
              ),
              const SizedBox(height: 10),
              _opcionTipoNegocio(
                icono: Icons.celebration_rounded,
                titulo: 'Un evento o fiesta',
                subtitulo: 'Fiesta, venta de garaje, rifa... puntual.',
                onTap: () => Navigator.of(ctx).pop('evento'),
              ),
            ],
          ),
        ),
      ),
    );
    if (tipo == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingNegocioScreen(tipoInicial: tipo),
      ),
    );
    await NegocioStateService.instance.refrescar();
  }

  Widget _opcionTipoNegocio({
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _kVerdeNegocio.withOpacity(_esOscuro ? 0.12 : 0.07),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kVerdeNegocio.withOpacity(_esOscuro ? 0.25 : 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icono, color: _kVerdeNegocio, size: 18),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: _colorTexto)),
                    const SizedBox(height: 2),
                    Text(subtitulo,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color: _colorTextoSecundario,
                            height: 1.3)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCuentaVaciaCard() {
    return Container(
      decoration: BoxDecoration(
        color: _colorSuperficie,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: _colorBorde),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.storefront_outlined,
              size: 40, color: _colorTextoSecundario),
          const SizedBox(height: 10),
          Text(
            'Aún no tienes una tienda ni un programa de afiliados',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                color: _colorTextoSecundario, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push('/crear-tienda'),
              icon: const Icon(Icons.add_business_outlined, size: 18),
              label: const Text('Crear tienda'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon,
      [Color color = AppColors.primary]) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withOpacity(_esOscuro ? 0.18 : 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(height: 4),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, fontSize: 13.5, color: _colorTexto)),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 9.5, color: _colorTextoSecundario)),
      ],
    );
  }

  // ===================================================================
  // TAB 2: ANUNCIOS -- ranuras REALES de anuncio independiente
  // ===================================================================
  Widget _buildTabAnuncios() {
    return RefreshIndicator(
      onRefresh: _recargarAnuncios,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(_esOscuro ? 0.12 : 0.07),
              borderRadius: BorderRadius.circular(kCardRadius),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.rocket_launch_rounded,
                    color: AppColors.primary, size: 17),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '¿Vas a vender algo puntual? Publica un anuncio '
                    'independiente sin tienda ni negocio.',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        color: _colorTextoSecundario,
                        height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ---------- Compras pendientes de verificación ----------
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _pendientesStandaloneFuture,
            builder: (context, snap) {
              final pends = snap.data ?? const [];
              if (pends.isEmpty) return const SizedBox.shrink();
              final codigo = (pends.first['codigo_ref'] as String?) ?? '';
              final extra =
                  pends.length > 1 ? ' (y ${pends.length - 1} más)' : '';
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warm.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.warm.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded,
                        size: 18, color: AppColors.warm),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Compra ${codigo.trim().isEmpty ? 'registrada' : codigo}'
                        '$extra en revisión.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _colorTexto),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          _buildSectionTitle(
              'Ranuras de anuncio independiente', Icons.campaign_rounded),
          const SizedBox(height: 8),
          FutureBuilder<({int usados, int max, DateTime? vigenteHasta})>(
            future: _ranurasStandaloneFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final r = snap.data;
              final max = r?.max ?? 0;
              final usados = r?.usados ?? 0;

              if (max <= 0) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _colorSuperficie,
                    borderRadius: BorderRadius.circular(kCardRadius),
                    border: Border.all(color: _colorBorde),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.workspace_premium_rounded,
                              size: 17, color: AppColors.warm),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text('No tienes ranuras activas',
                                style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: _colorTexto)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Compra un paquete para poder publicar tu anuncio '
                        'independiente.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11.5,
                            color: _colorTextoSecundario,
                            height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () async {
                            await mostrarPlanesStandaloneSheet(context,
                                onCompraRegistrada: _recargarAnuncios);
                          },
                          icon:
                              const Icon(Icons.local_offer_rounded, size: 17),
                          label: const Text('Ver planes disponibles',
                              style: TextStyle(fontSize: 12.5)),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final pct = (usados / max).clamp(0.0, 1.0);
              final restantes = (max - usados).clamp(0, max);
              final color = _colorFraccion(1 - pct);
              final vigenteHasta = r?.vigenteHasta;

              double? pctVigencia;
              int? diasRestantesVigencia;
              if (vigenteHasta != null) {
                final restante = vigenteHasta.difference(DateTime.now());
                diasRestantesVigencia =
                    restante.isNegative ? 0 : (restante.inHours / 24).ceil();
              }

              return Container(
                decoration: BoxDecoration(
                  color: _colorSuperficie,
                  borderRadius: BorderRadius.circular(kCardRadius),
                  border: Border.all(color: _colorBorde),
                ),
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _barraUso(
                      icono: Icons.campaign_rounded,
                      etiqueta: 'Ranuras en uso',
                      valorDerecha: restantes <= 0
                          ? 'Sin libres'
                          : '$restantes libre${restantes == 1 ? '' : 's'}',
                      detalle: '$usados de $max en uso',
                      pct: pct,
                      color: color,
                    ),
                    if (diasRestantesVigencia != null)
                      _barraUso(
                        icono: Icons.schedule_rounded,
                        etiqueta: 'Vence tu próxima ranura',
                        valorDerecha: diasRestantesVigencia <= 0
                            ? 'Hoy'
                            : diasRestantesVigencia == 1
                                ? '1 día'
                                : '$diasRestantesVigencia días',
                        detalle:
                            '${vigenteHasta!.day}/${vigenteHasta.month}/${vigenteHasta.year}',
                        pct: diasRestantesVigencia <= 0
                            ? 1.0
                            : (1 - (diasRestantesVigencia / 30))
                                .clamp(0.0, 1.0)
                                .toDouble(),
                        color: _colorFraccion(
                            (diasRestantesVigencia / 30).clamp(0.0, 1.0)),
                      ),
                    const SizedBox(height: 10),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _permisosStandaloneFuture,
                      builder: (context, psnap) {
                        final permisos = psnap.data ?? const [];
                        if (permisos.isEmpty) return const SizedBox.shrink();
                        return Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: permisos.map((p) {
                            final paquete =
                                p['paquetes_anuncio'] as Map<String, dynamic>?;
                            final nombre =
                                paquete?['nombre'] as String? ?? 'Paquete';
                            final hasta =
                                DateTime.tryParse(p['hasta'] as String? ?? '');
                            final txt = hasta != null
                                ? '$nombre · ${hasta.day}/${hasta.month}'
                                : nombre;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(txt,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: color)),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await mostrarPlanesStandaloneSheet(context,
                                  onCompraRegistrada: _recargarAnuncios);
                            },
                            icon: const Icon(Icons.add_rounded, size: 15),
                            label: const Text('Más ranuras',
                                style: TextStyle(fontSize: 11.5)),
                            style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const StandaloneAnuncioScreen(),
                                ),
                              );
                              await _recargarAnuncios();
                            },
                            icon: const Icon(Icons.add_circle_outline_rounded,
                                size: 15),
                            label: const Text('Crear anuncio',
                                style: TextStyle(fontSize: 11.5)),
                            style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}