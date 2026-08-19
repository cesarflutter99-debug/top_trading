import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_colors.dart';
import '../core/auth_guard.dart';
import '../core/supabase_client.dart';
import '../services/tiendas_service.dart';
import 'admin_dashboard_screen.dart';
import 'panel_vendedor_screen.dart';

class MiPerfilScreen extends StatefulWidget {
  const MiPerfilScreen({super.key});

  @override
  State<MiPerfilScreen> createState() => _MiPerfilScreenState();
}

class _MiPerfilScreenState extends State<MiPerfilScreen> {
  final _tiendasService = TiendasService();
  User? _perfil;
  Map<String, dynamic>? _miTienda;
  Map<String, dynamic>? _miAfiliado;
  bool _esAdmin = false;
  bool _cargando = true;

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
    }
  }

  Future<void> _cargarTodo() async {
    setState(() => _cargando = true);
    try {
      final perfil = supabase.auth.currentUser;
      final tienda = await _tiendasService.obtenerMiTienda();
      final afiliado = await _tiendasService.obtenerMiAfiliado();
      final admin = await _tiendasService.esAdmin();
      if (mounted) {
        setState(() {
          _perfil = perfil;
          _miTienda = tienda;
          _miAfiliado = afiliado;
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

  String _fotoUrl() {
    return _perfil?.userMetadata?['avatar_url'] as String? ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;

    if (supabase.auth.currentUser == null) {
      return Scaffold(
        backgroundColor: AppColors.backgroundLight,
        appBar: AppBar(
          title: const Text('Mi Perfil'),
          backgroundColor: AppColors.backgroundLight,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_outline_rounded,
                    size: 56, color: AppColors.inkSecundarioLight),
                const SizedBox(height: 16),
                Text('Inicia sesión para ver tu perfil',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                Text(
                  'Accedé con Google para ver tu tienda, tus afiliados '
                  'y gestionar tu cuenta.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5, color: AppColors.inkSecundarioLight),
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
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        backgroundColor: AppColors.backgroundLight,
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
                  _buildHeader(esOscuro),
                  const SizedBox(height: 24),
                  if (_miTienda != null) ...[
                    _buildSectionTitle('Mi Tienda'),
                    const SizedBox(height: 8),
                    _buildTiendaCard(esOscuro),
                    const SizedBox(height: 16),
                  ],
                  if (_miAfiliado != null) ...[
                    _buildSectionTitle('Mi Programa de Afiliados'),
                    const SizedBox(height: 8),
                    _buildAfiliadoCard(esOscuro),
                    const SizedBox(height: 16),
                  ],
                  if (_esAdmin) ...[
                    _buildSectionTitle('Panel de Administración'),
                    const SizedBox(height: 8),
                    _buildAdminCard(esOscuro),
                    const SizedBox(height: 16),
                  ],
                  if (_miTienda == null &&
                      _miAfiliado == null &&
                      !_esAdmin) ...[
                    _buildSectionTitle('Tu Cuenta'),
                    const SizedBox(height: 8),
                    _buildCuentaVaciaCard(esOscuro),
                    const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 88),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(bool esOscuro) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kCardRadius),
      child: Container(
        decoration: BoxDecoration(
          color: esOscuro
              ? AppColors.cardTransparentDark
              : AppColors.cardTransparentLight,
          border: Border.all(
            color: (esOscuro ? AppColors.borderDark : AppColors.borderLight)
                .withOpacity(0.6),
          ),
        ),
        child: Column(
          children: [
            // ---- Franja degradada + avatar superpuesto encima, con
            // Stack/Positioned (no Transform.translate, que deja hueco
            // vacío porque no afecta el layout, solo el dibujo). ----
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Container(
                  height: 60,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                Positioned(
                  top: 20,
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor:
                        esOscuro ? AppColors.surfaceDark : Colors.white,
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
                ),
              ],
            ),
            // Reserva el espacio que el avatar sobresale por debajo de
            // la franja (top:20 + diámetro 88 - franja 60 = 48).
            const SizedBox(height: 48),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  Text(
                    _nombre(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkLight,
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
                      color: AppColors.inkSecundarioLight,
                    ),
                  ),
                  const SizedBox(height: 12),
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
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

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.inkLight));
  }

  Widget _buildTiendaCard(bool esOscuro) {
    final t = _miTienda!;
    return Card(
      color: esOscuro
          ? AppColors.cardTransparentDark
          : AppColors.cardTransparentLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['nombre'] ?? '',
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(
                        '${t['plan'] ?? 'basic'} · ${t['estado'] ?? ''}',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, color: AppColors.inkSecundarioLight),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                      'Productos',
                      '${_miTienda!['productos_count'] ?? 0}',
                      Icons.shopping_bag,
                      AppColors.primary),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Pedidos',
                      '${_miTienda!['pedidos_count'] ?? 0}',
                      Icons.shopping_cart,
                      AppColors.primary),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Ingresos',
                      '\$${_miTienda!['ingresos'] ?? 0}',
                      Icons.attach_money,
                      AppColors.primary),
                ),
              ],
            ),
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
      ),
    );
  }

  Widget _buildAfiliadoCard(bool esOscuro) {
    final a = _miAfiliado!;
    return Card(
      color: esOscuro
          ? AppColors.cardTransparentDark
          : AppColors.cardTransparentLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warm.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.handshake_outlined,
                      color: AppColors.warm, size: 18),
                ),
                const SizedBox(width: 10),
                Text('Mi programa de afiliados',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600)),
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
      ),
    );
  }

  Widget _buildAdminCard(bool esOscuro) {
    return Card(
      color: esOscuro
          ? AppColors.cardTransparentDark
          : AppColors.cardTransparentLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.admin_panel_settings,
                      color: Colors.deepPurple, size: 18),
                ),
                const SizedBox(width: 10),
                Text('Panel de administración',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  context.push('/admin/dashboard');
                },
                icon: const Icon(Icons.dashboard_outlined),
                label: const Text('Ver dashboard'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCuentaVaciaCard(bool esOscuro) {
    return Card(
      color: esOscuro
          ? AppColors.cardTransparentDark
          : AppColors.cardTransparentLight,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.storefront_outlined,
                size: 48, color: AppColors.inkSecundarioLight),
            const SizedBox(height: 12),
            Text(
              'Aún no tienes una tienda, programa de afiliados ni eres admin',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  color: AppColors.inkSecundarioLight),
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
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(height: 6),
        Text(value,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, color: AppColors.inkSecundarioLight)),
      ],
    );
  }
}
