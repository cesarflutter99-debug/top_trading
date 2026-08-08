import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/tiendas_service.dart';

class AfiliadoDashboardScreen extends StatefulWidget {
  const AfiliadoDashboardScreen({super.key});

  @override
  State<AfiliadoDashboardScreen> createState() =>
      _AfiliadoDashboardScreenState();
}

class _AfiliadoDashboardScreenState extends State<AfiliadoDashboardScreen> {
  final _tiendasService = TiendasService();
  Map<String, dynamic>? _resumen;
  List<Map<String, dynamic>>? _comisiones;
  List<Map<String, dynamic>>? _retiros;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    setState(() => _cargando = true);
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _cargando = false);
        return;
      }
      final resumen = await _tiendasService.afiliadoDashboardResumen(uid);
      final comisiones = await _tiendasService.afiliadoComisiones(uid);
      final retiros = await _tiendasService.afiliadoRetiros(uid);
      if (mounted) {
        setState(() {
          _resumen = resumen;
          _comisiones = comisiones;
          _retiros = retiros;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Mi Perfil de Afiliado'),
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargarTodo,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _resumen == null
              ? const Center(child: Text('Sin datos'))
              : RefreshIndicator(
                  onRefresh: _cargarTodo,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildResumenCard(esOscuro),
                      const SizedBox(height: 16),
                      _buildSectionTitle('Comisiones'),
                      const SizedBox(height: 8),
                      _buildComisiones(esOscuro),
                      const SizedBox(height: 16),
                      _buildSectionTitle('Historial de retiros'),
                      const SizedBox(height: 8),
                      _buildRetiros(esOscuro),
                      const SizedBox(height: 88),
                    ],
                  ),
                ),
    );
  }

  Widget _buildResumenCard(bool esOscuro) {
    final r = _resumen!;
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r['nombre'] ?? 'Mi perfil',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Código: ${r['codigo'] ?? '-'}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: AppColors.inkSecundarioLight)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                      'Saldo',
                      '${r['saldo_cup'] ?? 0} CUP',
                      Icons.wallet),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Comisiones',
                      '\$${(r['comisiones_acumuladas'] ?? 0)}',
                      Icons.attach_money),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Mes',
                      '\$${(r['comisiones_mes'] ?? 0)}',
                      Icons.calendar_today),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                      'Pendientes',
                      '\$${(r['comisiones_pendientes'] ?? 0)}',
                      Icons.pending_actions),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Retiros',
                      '${r['retiros_pagados'] ?? 0}',
                      Icons.check_circle_outline),
                ),
                Expanded(
                  child: _buildStatItem(
                      'Referidos',
                      '${r['total_referidos'] ?? 0}',
                      Icons.people_outline),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  context.push('/afiliados/registro');
                },
                icon: const Icon(Icons.handshake_outlined),
                label: const Text('Programa de afiliados'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: GoogleFonts.plusJakartaSans(
            fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.inkLight));
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 18, color: AppColors.warm),
        const SizedBox(height: 4),
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

  Widget _buildComisiones(bool esOscuro) {
    if (_comisiones == null || _comisiones!.isEmpty) {
      return _emptyCard('Sin comisiones yet', esOscuro);
    }
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _comisiones!.length,
        itemBuilder: (context, i) {
          final c = _comisiones![i];
          return ListTile(
            leading: Icon(Icons.auto_awesome,
                size: 18, color: AppColors.warm),
            title: Text(c['tienda_nombre'] ?? '',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            subtitle: Text(
              'Código: ${c['codigo_usado'] ?? ''} · ${c['estado'] ?? ''}',
              style: GoogleFonts.plusJakartaSans(fontSize: 11),
            ),
            trailing: Text(
              '\$${(c['comision_cup'] ?? 0)} CUP',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, color: AppColors.warm),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRetiros(bool esOscuro) {
    if (_retiros == null || _retiros!.isEmpty) {
      return _emptyCard('Sin retiros', esOscuro);
    }
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _retiros!.length,
        itemBuilder: (context, i) {
          final r = _retiros![i];
          return ListTile(
            leading: Icon(
              r['estado'] == 'pagado'
                  ? Icons.check_circle_outline
                  : Icons.pending_actions,
              color: r['estado'] == 'pagado'
                  ? AppColors.success
                  : Colors.orange,
            ),
            title: Text(
              '${r['monto_cup'] ?? 0} CUP',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${r['estado'] ?? ''} · ${_formatDate(r['created_at'])}',
              style: GoogleFonts.plusJakartaSans(fontSize: 11),
            ),
            trailing: r['estado'] == 'pagado'
                ? Text(
                    'Pagado',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.success),
                  )
                : null,
          );
        },
      ),
    );
  }

  Widget _emptyCard(String texto, bool esOscuro) {
    return Card(
      color: esOscuro ? AppColors.cardTransparentDark : AppColors.cardTransparentLight,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(texto,
              style: GoogleFonts.plusJakartaSans(
                  color: AppColors.inkSecundarioLight)),
        ),
      ),
    );
  }

  String _formatDate(dynamic fecha) {
    if (fecha is String) return fecha;
    if (fecha is DateTime) return '${fecha.day}/${fecha.month}/${fecha.year}';
    return '';
  }
}