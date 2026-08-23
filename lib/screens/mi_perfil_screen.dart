// mi_perfil_screen.dart
//
// Rediseño (2026-08):
// 1. Modo oscuro corregido de raíz. Antes varios textos usaban
//    AppColors.inkLight / AppColors.inkSecundarioLight, que son
//    colores FIJOS (no cambian con el tema) -- por eso se veían textos
//    oscuros sobre fondos oscuros y era ilegible. Ahora todos los
//    colores de texto salen de getters (_colorTexto/_colorTextoSecundario)
//    calculados según Theme.of(context).brightness, igual que ya hace
//    home_screen.dart en el resto de la app.
// 2. Se quitó la tarjeta/botón de "Panel de administración" (esa
//    gestión se movió a una app aparte por separación de seguridad).
//    Se conserva el chip "Admin" en el header --esAdmin() sigue
//    siendo información válida de la cuenta, solo que ya no hay a
//    dónde navegar desde acá.
// 3. "Mi Tienda" pasó de una tarjeta plana a una sección más robusta:
//    header con logo + nombre + badge de plan (VIP dorado si premium)
//    + badge de estado (Activa / En revisión), stats, y la nueva barra
//    de vencimiento del plan.
// 4. NUEVO: barra "vidrio flotante" con el consumo del plan actual --
//    ancha y baja (no una barrita fina), con relleno animado y un
//    degradado de color que va de verde (recién activado) a rojo
//    (por vencer), igual que una barra de vida de videojuego. Se
//    calcula con tienda['plan_expira_en'] + la duración total del
//    plan (planes.duracion_dias). Si la tienda no tiene fecha de
//    vencimiento registrada, la barra simplemente no se muestra.

import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_colors.dart';
import '../core/auth_guard.dart';
import '../core/supabase_client.dart';
import '../services/storage_service.dart';
import '../services/tiendas_service.dart';
import '../services/tienda_state_service.dart';
import '../services/afiliado_state_service.dart';

class MiPerfilScreen extends StatefulWidget {
  const MiPerfilScreen({super.key});

  @override
  State<MiPerfilScreen> createState() => _MiPerfilScreenState();
}

class _MiPerfilScreenState extends State<MiPerfilScreen> {
  final _tiendasService = TiendasService();
  final _storageService = StorageService();
  final _picker = ImagePicker();
  User? _perfil;
  // FIX (persistencia): _miTienda / _miAfiliado YA NO se cachean como
  // campos locales -- antes esta pantalla guardaba su propia copia
  // con setState(), así que crear/editar/eliminar la tienda o el
  // afiliado desde otra pantalla no se veía reflejado acá hasta
  // cerrar y reabrir la app. Ahora se leen en vivo de los servicios
  // globales (getters abajo), y el build() escucha ambos con
  // AnimatedBuilder.
  Map<String, dynamic>? get _miTienda => TiendaStateService.instance.miTienda;
  Map<String, dynamic>? get _miAfiliado =>
      AfiliadoStateService.instance.miAfiliado;

  Map<String, dynamic>? _planActual; // fila de `planes` del plan activo
  String? _codigoPlanCacheado; // evita refetchear el plan si no cambió
  bool _esAdmin = false;
  bool _cargando = true;
  bool _subiendoAvatar = false;
  bool _subiendoPortada = false;

  @override
  void initState() {
    super.initState();
    if (supabase.auth.currentUser == null) {
      // Invitado: ni intentamos pedir tienda/afiliado/admin (esos
      // métodos asumen currentUser!.id y truenan) -- se corta acá y
      // el build() muestra el CTA de login en su lugar.
      _cargando = false;
    } else {
      _cargarTodo();
      // Si el plan de la tienda cambia desde OTRA pantalla (Gestionar
      // Planes, panel admin vía Realtime, etc.), TiendaStateService
      // notifica -- este listener resincroniza _planActual (la fila
      // completa de `planes`, con duracion_dias/limite_productos) sin
      // que el usuario tenga que salir y volver a esta pantalla.
      TiendaStateService.instance.addListener(_sincronizarPlanDesdeTienda);
    }
  }

  @override
  void dispose() {
    TiendaStateService.instance.removeListener(_sincronizarPlanDesdeTienda);
    super.dispose();
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
    } catch (_) {
      // Sin datos del plan (ej. código legado) -- la barra de
      // vencimiento simplemente no se muestra, el resto sigue.
    }
  }

  Future<void> _cargarTodo() async {
    setState(() => _cargando = true);
    try {
      final perfil = supabase.auth.currentUser;
      // Refresca los dos servicios globales -- cualquier otra
      // pantalla que los escuche se entera también.
      await Future.wait([
        TiendaStateService.instance.refrescar(),
        AfiliadoStateService.instance.refrescar(),
      ]);
      final admin = await _tiendasService.esAdmin();
      await _sincronizarPlanDesdeTienda();

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

  String _nombre() {
    final user = _perfil;
    if (user == null) return 'Usuario';
    return user.userMetadata?['full_name'] as String? ??
        user.userMetadata?['name'] as String? ??
        user.email ??
        'Usuario';
  }

  String _email() {
    return _perfil?.email ?? '';
  }

  // FIX: antes esto SIEMPRE mostraba la foto de Google (avatar_url),
  // sin ninguna forma de cambiarla. 'avatar_url_custom' es un campo
  // propio guardado en el user_metadata de Supabase Auth (no hace
  // falta tabla nueva) -- si el usuario subió una foto propia, esa
  // gana; si no, cae de vuelta a la de Google.
  String _fotoUrl() {
    final m = _perfil?.userMetadata;
    final custom = m?['avatar_url_custom'] as String?;
    if (custom != null && custom.isNotEmpty) return custom;
    return m?['avatar_url'] as String? ?? '';
  }

  // Portada del perfil -- no existe en Google, es 100% opcional y
  // solo se guarda si el usuario sube una.
  String _portadaUrl() {
    return _perfil?.userMetadata?['portada_url'] as String? ?? '';
  }

  /// Texto corto de "a qué se dedica" en la app -- se muestra debajo
  /// del nombre/correo en el header, para que el perfil se sienta más
  /// completo/profesional de un vistazo.
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

  Future<void> _cambiarPortada() async {
    final XFile? archivo = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      imageQuality: 80,
    );
    if (archivo == null) return;

    setState(() => _subiendoPortada = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      final url = await _storageService.subirPortadaPerfil(
        archivo: File(archivo.path),
        uid: uid,
      );
      final res = await supabase.auth.updateUser(
        UserAttributes(data: {'portada_url': url}),
      );
      if (mounted) setState(() => _perfil = res.user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo subir la portada: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _subiendoPortada = false);
    }
  }

  // -----------------------------------------------------------------
  // COLORES ADAPTATIVOS -- ver nota (1) al inicio del archivo. Nada de
  // texto en esta pantalla debe usar AppColors.ink* directamente.
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

  @override
  Widget build(BuildContext context) {
    // FIX (persistencia): escucha ambos servicios globales -- si la
    // tienda o el afiliado cambian desde cualquier otra pantalla, Mi
    // Perfil se repinta solo, en el mismo frame.
    return AnimatedBuilder(
      animation: TiendaStateService.instance,
      builder: (context, _) => AnimatedBuilder(
        animation: AfiliadoStateService.instance,
        builder: (context, __) => _buildScaffold(context),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
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
                    size: 56, color: _colorTextoSecundario),
                const SizedBox(height: 16),
                Text('Inicia sesión para ver tu perfil',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: _colorTexto)),
                const SizedBox(height: 8),
                Text(
                  'Accedé con Google para ver tu tienda, tus afiliados '
                  'y gestionar tu cuenta.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5, color: _colorTextoSecundario),
                ),
                const SizedBox(height: 20),
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
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarTodo,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  if (_miTienda != null) ...[
                    _buildSectionTitle('Mi Tienda', Icons.storefront_rounded),
                    const SizedBox(height: 10),
                    _buildTiendaSection(),
                    const SizedBox(height: 20),
                  ],
                  if (_miAfiliado != null) ...[
                    _buildSectionTitle(
                        'Mi Programa de Afiliados', Icons.handshake_rounded),
                    const SizedBox(height: 10),
                    _buildAfiliadoCard(),
                    const SizedBox(height: 20),
                  ],
                  if (_miTienda == null && _miAfiliado == null) ...[
                    _buildSectionTitle('Tu Cuenta', Icons.person_rounded),
                    const SizedBox(height: 10),
                    _buildCuentaVaciaCard(),
                    const SizedBox(height: 20),
                  ],
                  const SizedBox(height: 72),
                ],
              ),
            ),
    );
  }

  // -----------------------------------------------------------------
  // HEADER: portada + avatar (ambos editables) + nombre + "trabajo" +
  // email + chips de rol.
  //
  // FIX: antes esta cabecera era una franja de color sólido de 64px
  // con la foto de Google pegada arriba -- no había forma de subir
  // una foto propia ni una portada, y no se decía en ningún lado "a
  // qué te dedicas" en la app. Ahora:
  //   - La portada es una foto real (si el usuario subió una) con un
  //     degradado oscuro abajo para que el nombre siempre se lea bien,
  //     y cae a un degradado de marca si todavía no subió ninguna.
  //   - El avatar tiene una insignia de cámara -- tocarlo abre la
  //     galería y sube la foto al bucket "perfiles".
  //   - Debajo del nombre aparece _trabajo() (Vendedor/Afiliado/
  //     Comprador), antes de los chips de rol.
  // -----------------------------------------------------------------
  Widget _buildHeader() {
    final portada = _portadaUrl();
    return ClipRRect(
      borderRadius: BorderRadius.circular(kCardRadius),
      child: Container(
        decoration: BoxDecoration(
          color: _colorSuperficie,
          border: Border.all(color: _colorBorde),
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                // ---------- Portada ----------
                GestureDetector(
                  onTap: _subiendoPortada ? null : _cambiarPortada,
                  child: Container(
                    height: 150,
                    width: double.infinity,
                    decoration: portada.isEmpty
                        ? const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primaryDark
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          )
                        : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (portada.isNotEmpty)
                          Image.network(
                            portada,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary,
                                    AppColors.primaryDark
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                            ),
                          ),
                        // Degradado inferior -- asegura contraste para
                        // el avatar/nombre encima de cualquier foto.
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.28),
                              ],
                            ),
                          ),
                        ),
                        if (_subiendoPortada)
                          const ColoredBox(
                            color: Colors.black38,
                            child: Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white)),
                          )
                        else
                          Positioned(
                            right: 12,
                            top: 12,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.35),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt_rounded,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // ---------- Avatar ----------
                Positioned(
                  top: 106,
                  child: GestureDetector(
                    onTap: _subiendoAvatar ? null : _cambiarFotoPerfil,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircleAvatar(
                          radius: 44,
                          backgroundColor:
                              _esOscuro ? AppColors.surfaceDark : Colors.white,
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: AppColors.primary.withOpacity(0.1),
                            backgroundImage: _fotoUrl().isNotEmpty
                                ? NetworkImage(_fotoUrl())
                                : null,
                            child: _fotoUrl().isEmpty
                                ? const Icon(Icons.person,
                                    size: 40, color: AppColors.primary)
                                : null,
                          ),
                        ),
                        if (_subiendoAvatar)
                          const CircularProgressIndicator(strokeWidth: 2)
                        else
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: _esOscuro
                                        ? AppColors.surfaceDark
                                        : Colors.white,
                                    width: 2),
                              ),
                              child: const Icon(Icons.camera_alt,
                                  size: 13, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 48),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
              child: Column(
                children: [
                  Text(
                    _nombre(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _colorTexto,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // NUEVO: "a qué te dedicas" en la app, justo debajo
                  // del nombre -- lo que se pidió como "que salga tu
                  // trabajo".
                  Text(
                    _trabajo(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _email(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: _colorTextoSecundario,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_miTienda != null)
                        _buildRoleChip('Vendedor', Icons.storefront_rounded,
                            AppColors.primary),
                      if (_miAfiliado != null)
                        _buildRoleChip('Afiliado', Icons.handshake_outlined,
                            AppColors.warm),
                      if (_esAdmin)
                        _buildRoleChip('Admin', Icons.admin_panel_settings,
                            Colors.deepPurple),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(_esOscuro ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 17, color: _colorTextoSecundario),
        const SizedBox(width: 8),
        Text(title,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: _colorTexto)),
      ],
    );
  }

  // -----------------------------------------------------------------
  // MI TIENDA -- header con badges, stats, barra de plan, acciones.
  // -----------------------------------------------------------------
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
      padding: const EdgeInsets.all(16),
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
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFD4AF37).withOpacity(0.4),
                            blurRadius: 8,
                          ),
                        ],
                      )
                    : null,
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: (t['logo_url'] as String?) != null &&
                          (t['logo_url'] as String).isNotEmpty
                      ? NetworkImage(t['logo_url'] as String)
                      : null,
                  child: (t['logo_url'] as String?) == null ||
                          (t['logo_url'] as String).isEmpty
                      ? const Icon(Icons.storefront_rounded,
                          size: 24, color: AppColors.primary)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t['nombre'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: _colorTexto)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    context.push('/gestionar-tienda', extra: _miTienda);
                  },
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('Gestionar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    context.push('/vendedor/dashboard',
                        extra: {'id': _miTienda!['id_tienda']});
                  },
                  icon: const Icon(Icons.analytics_outlined, size: 18),
                  label: const Text('Analíticas'),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(_esOscuro ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(texto,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------
  // BARRA "VIDRIO FLOTANTE" DE VENCIMIENTO DEL PLAN
  //
  // Ancha y baja, con relleno animado y color que va de verde (plan
  // recién activado / con mucho tiempo) a rojo (por vencer), como una
  // barra de vida. Se apoya en tienda['plan_expira_en'] (fecha real
  // de vencimiento) y planes.duracion_dias (duración total del plan
  // contratado) para calcular el % consumido.
  // -----------------------------------------------------------------
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
      pctUsado = vencido ? 1.0 : 0.15; // sin duración conocida -> estimado leve
    }
    final fracRestante = 1 - pctUsado;
    final color = _colorBarraSegunRestante(fracRestante, vencido);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            decoration: BoxDecoration(
              color: (_esOscuro ? Colors.white : Colors.black)
                  .withOpacity(_esOscuro ? 0.06 : 0.035),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withOpacity(0.4), width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bolt_rounded, size: 15, color: color),
                        const SizedBox(width: 5),
                        Text('Uso del plan',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: _colorTexto)),
                      ],
                    ),
                    Text(
                      vencido
                          ? 'Plan vencido'
                          : diasRestantes == 1
                              ? 'Te queda 1 día'
                              : 'Te quedan $diasRestantes días',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: color),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    height: 10,
                    color: color.withOpacity(0.15),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: pctUsado),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) {
                          return FractionallySizedBox(
                            widthFactor: value.clamp(0.03, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: LinearGradient(
                                  colors: [
                                    color.withOpacity(0.65),
                                    color,
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  vencido
                      ? 'Renueva tu plan para seguir visible en el marketplace'
                      : duracionTotal != null
                          ? '${(pctUsado * 100).round()}% usado del plan'
                          : 'Plan activo',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: _colorTextoSecundario),
                ),
                if (vencido || diasRestantes <= 3) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        context.push('/gestionar-planes', extra: _miTienda);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: color,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        alignment: Alignment.centerLeft,
                      ),
                      icon: const Icon(Icons.autorenew_rounded, size: 16),
                      label: const Text('Renovar plan'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Interpola verde -> amarillo -> rojo según la fracción de tiempo
  /// que le queda al plan (1 = recién activado, 0 = vencido), como el
  /// indicador de vida de un videojuego.
  Color _colorBarraSegunRestante(double fracRestante, bool vencido) {
    const verde = Color(0xFF2ECC71);
    const amarillo = Color(0xFFFFC107);
    const rojo = Color(0xFFE53935);
    if (vencido) return rojo;
    if (fracRestante >= 0.5) {
      final t = ((fracRestante - 0.5) / 0.5).clamp(0.0, 1.0);
      return Color.lerp(amarillo, verde, t)!;
    }
    final t = (fracRestante / 0.5).clamp(0.0, 1.0);
    return Color.lerp(rojo, amarillo, t)!;
  }

  // -----------------------------------------------------------------
  // AFILIADOS
  // -----------------------------------------------------------------
  Widget _buildAfiliadoCard() {
    final a = _miAfiliado!;
    return Container(
      decoration: BoxDecoration(
        color: _colorSuperficie,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: _colorBorde),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warm.withOpacity(_esOscuro ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.handshake_outlined,
                    color: AppColors.warm, size: 18),
              ),
              const SizedBox(width: 10),
              Text('Mi programa de afiliados',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600, color: _colorTexto)),
            ],
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                context.push('/afiliados/perfil');
              },
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Ver perfil completo'),
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.storefront_outlined,
              size: 48, color: _colorTextoSecundario),
          const SizedBox(height: 12),
          Text(
            'Aún no tienes una tienda ni un programa de afiliados',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(color: _colorTextoSecundario),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                context.push('/crear-tienda');
              },
              icon: const Icon(Icons.add_business_outlined),
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
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(_esOscuro ? 0.18 : 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(height: 6),
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, fontSize: 16, color: _colorTexto)),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, color: _colorTextoSecundario)),
      ],
    );
  }
}
