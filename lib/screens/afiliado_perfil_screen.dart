// afiliado_perfil_screen.dart
//
// Pantalla profesional del afiliado (reemplaza el "diálogo simple" que
// vivía dentro de afiliado_registro_screen.dart cuando ya existía un
// registro). Muestra foto de Google, saldo, código para compartir,
// histórico de comisiones y retiros, edición de teléfono/tarjeta, y el
// flujo de solicitar retiro con las reglas de negocio:
//   - mínimo 1000 CUP por solicitud
//   - máximo 10,000 CUP acumulados por día (sumando lo ya solicitado)
//   - no puede exceder el saldo actual
//   - abre WhatsApp con el mensaje al admin al confirmar

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/tiendas_service.dart';

class AfiliadoPerfilScreen extends StatefulWidget {
  const AfiliadoPerfilScreen({super.key});

  @override
  State<AfiliadoPerfilScreen> createState() => _AfiliadoPerfilScreenState();
}

class _AfiliadoPerfilScreenState extends State<AfiliadoPerfilScreen> {
  final _tiendasService = TiendasService();

  Map<String, dynamic>? _afiliado;
  bool _cargando = true;
  bool _editando = false;
  bool _guardandoEdicion = false;
  bool _verTodasComisiones = false;
  bool _verTodosRetiros = false;

  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _tarjetaCtrl = TextEditingController();

  late Future<List<Map<String, dynamic>>> _comisiones;
  late Future<List<Map<String, dynamic>>> _retiros;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _tarjetaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final afiliado = await _tiendasService.obtenerMiAfiliado();
    if (!mounted) return;
    setState(() {
      _afiliado = afiliado;
      _nombreCtrl.text = afiliado?['nombre'] ?? '';
      _telefonoCtrl.text = afiliado?['telefono'] ?? '';
      _tarjetaCtrl.text = afiliado?['numero_tarjeta'] ?? '';
      _cargando = false;
    });
    if (afiliado != null) {
      final id = afiliado['id_afiliado'] as String;
      setState(() {
        _comisiones = _tiendasService.obtenerUsosDeAfiliado(id);
        _retiros = _tiendasService.obtenerRetirosDeAfiliado(id);
      });
    }
  }

  String? get _fotoGoogle =>
      supabase.auth.currentUser?.userMetadata?['avatar_url'] as String?;

  Future<void> _guardarEdicion() async {
    if (_afiliado == null) return;
    setState(() => _guardandoEdicion = true);
    try {
      await _tiendasService.actualizarAfiliado(
        idAfiliado: _afiliado!['id_afiliado'],
        nombre: _nombreCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
        numeroTarjeta: _tarjetaCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos actualizados ✅')),
        );
        setState(() => _editando = false);
        await _cargar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _guardandoEdicion = false);
    }
  }

  Future<void> _abrirModalRetiro() async {
    if (_afiliado == null) return;
    final saldo = (_afiliado!['saldo_cup'] as num).toDouble();
    final retiradoHoy =
        await _tiendasService.obtenerRetiradoHoy(_afiliado!['id_afiliado']);
    final disponibleHoy = (10000 - retiradoHoy).clamp(0, 10000).toDouble();
    final maximoPermitido = saldo < disponibleHoy ? saldo : disponibleHoy;

    if (!mounted) return;

    if (maximoPermitido < 1000) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No puedes retirar ahora'),
          content: Text(saldo < 1000
              ? 'Necesitas al menos 1000 CUP de saldo para solicitar un retiro.'
              : 'Ya solicitaste el máximo de 10,000 CUP permitido hoy. Intenta mañana.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    final montoCtrl = TextEditingController();
    String? error;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Solicitar retiro',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 6),
                Text(
                  'Mínimo 1000 CUP · Máximo $maximoPermitido CUP ahora mismo '
                  '(según tu saldo y el tope diario de 10,000 CUP).',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5, color: AppColors.inkSecundarioLight),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: montoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Monto a retirar (CUP)',
                    border: const OutlineInputBorder(),
                    errorText: error,
                  ),
                  onChanged: (_) => setModalState(() => error = null),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final monto = double.tryParse(montoCtrl.text.trim());
                      if (monto == null) {
                        setModalState(() => error = 'Ingresa un monto válido');
                        return;
                      }
                      if (monto < 1000) {
                        setModalState(() => error = 'El mínimo es 1000 CUP');
                        return;
                      }
                      if (monto > maximoPermitido) {
                        setModalState(() => error =
                            'No puedes superar $maximoPermitido CUP ahora');
                        return;
                      }
                      Navigator.pop(ctx);
                      await _confirmarRetiro(monto);
                    },
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Solicitar retiro'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmarRetiro(double monto) async {
    try {
      await _tiendasService.solicitarRetiro(
        idAfiliado: _afiliado!['id_afiliado'],
        montoCup: monto,
      );

      final telefonoAdmin =
          await _tiendasService.obtenerContactoWhatsappActivo();
      if (telefonoAdmin != null) {
        final mensaje = Uri.encodeComponent(
          'Hola, soy ${_afiliado!['nombre']} y solicito retirar '
          '${monto.toStringAsFixed(0)} CUP de mis comisiones. '
          'Mi código de afiliado es: ${_afiliado!['codigo']}.',
        );
        final url = Uri.parse('https://wa.me/$telefonoAdmin?text=$mensaje');
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud de retiro enviada ✅')),
        );
        await _cargar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo solicitar el retiro: $e')),
        );
      }
    }
  }

  void _compartirCodigo() {
    if (_afiliado == null) return;
    final codigo = _afiliado!['codigo'] ?? '';
    Share.share(
      '¡Únete a Top Trading! 🛍️\n'
      'Usa mi código de afiliado "$codigo" al registrar tu tienda y obtén '
      '10% de descuento en tu primer plan.\n\n'
      'Descarga la app y regístrate ahora.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mi Perfil de Afiliado')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_afiliado == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mi Perfil de Afiliado')),
        body: const Center(
          child: Text('Todavía no eres afiliado.'),
        ),
      );
    }

    final saldo = (_afiliado!['saldo_cup'] as num).toDouble();
    final puedeRetirar = saldo >= 1000;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Mi Perfil de Afiliado'),
        backgroundColor: AppColors.backgroundLight,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ---------- Encabezado: foto + nombre + código ----------
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(kCardRadius),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    backgroundImage:
                        _fotoGoogle != null ? NetworkImage(_fotoGoogle!) : null,
                    child: _fotoGoogle == null
                        ? const Icon(Icons.person,
                            size: 40, color: AppColors.primary)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(_afiliado!['nombre'] ?? '',
                      style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18)),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Código: ${_afiliado!['codigo']}',
                      style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _compartirCodigo(),
                    icon: const Icon(Icons.share_outlined,
                        size: 16, color: Colors.white),
                    label: Text('Compartir',
                        style:
                            GoogleFonts.plusJakartaSans(color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white70),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ---------- Saldo + botón de retiro ----------
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(kCardRadius),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04), blurRadius: 10)
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Saldo actual',
                      style: GoogleFonts.plusJakartaSans(
                          color: AppColors.inkSecundarioLight, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('${saldo.toStringAsFixed(0)} CUP',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          fontSize: 30,
                          color: AppColors.ink)),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: puedeRetirar ? _abrirModalRetiro : null,
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: Text(puedeRetirar
                          ? 'Solicitar Retiro'
                          : 'Necesitas mínimo 1000 CUP'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: puedeRetirar
                            ? AppColors.primary
                            : Colors.grey.shade300,
                        foregroundColor:
                            puedeRetirar ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Reglas: mínimo 1000 CUP por solicitud · máximo 10,000 CUP '
                    'acumulados por día · el pago se coordina por WhatsApp.',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5, color: AppColors.inkSecundarioLight),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ---------- Datos de contacto/pago (editable) ----------
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(kCardRadius),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04), blurRadius: 10)
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Datos de contacto',
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      TextButton.icon(
                        onPressed: () => setState(() => _editando = !_editando),
                        icon: Icon(
                            _editando ? Icons.close : Icons.edit_outlined,
                            size: 16),
                        label: Text(_editando ? 'Cancelar' : 'Editar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_editando) ...[
                    TextField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _telefonoCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'Teléfono (WhatsApp)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tarjetaCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Número de tarjeta'),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _guardandoEdicion ? null : _guardarEdicion,
                        child: _guardandoEdicion
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Guardar cambios'),
                      ),
                    ),
                  ] else ...[
                    _filaDato(Icons.phone_outlined, 'Teléfono',
                        _afiliado!['telefono'] ?? '-'),
                    const SizedBox(height: 10),
                    _filaDato(Icons.credit_card_outlined, 'Tarjeta',
                        _afiliado!['numero_tarjeta'] ?? '-'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ---------- Histórico: comisiones ----------
            Text('Historial de comisiones',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _comisiones,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Error al cargar comisiones',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: Colors.red),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final usos = snapshot.data!;
                if (usos.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('Aún no tienes comisiones registradas.',
                        style: GoogleFonts.plusJakartaSans(
                            color: AppColors.inkSecundarioLight, fontSize: 13)),
                  );
                }
                final total = usos.length;
                final mostrar =
                    _verTodasComisiones ? usos : usos.take(5).toList();
                return Column(
                  children: [
                    ...mostrar.map((u) {
                      final aprobado = u['estado'] == 'aprobado';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              aprobado
                                  ? Icons.check_circle_rounded
                                  : Icons.schedule_rounded,
                              color: aprobado ? Colors.green : Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(u['tiendas']?['nombre'] ?? 'Tienda',
                                      style: GoogleFonts.plusJakartaSans(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13.5)),
                                  Text(
                                    aprobado
                                        ? '+${(u['comision_cup_acreditada'] ?? 0)} CUP'
                                        : 'Pendiente de aprobación',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: AppColors.inkSecundarioLight),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (total > 5)
                      TextButton(
                        onPressed: () => setState(
                            () => _verTodasComisiones = !_verTodasComisiones),
                        child: Text(_verTodasComisiones
                            ? 'Ver menos'
                            : 'Ver todos ($total)'),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // ---------- Histórico: retiros ----------
            Text('Historial de retiros',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _retiros,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Error al cargar retiros',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: Colors.red),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final retiros = snapshot.data!;
                if (retiros.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('Aún no has solicitado retiros.',
                        style: GoogleFonts.plusJakartaSans(
                            color: AppColors.inkSecundarioLight, fontSize: 13)),
                  );
                }
                final total = retiros.length;
                final mostrar =
                    _verTodosRetiros ? retiros : retiros.take(5).toList();
                return Column(
                  children: [
                    ...mostrar.map((r) {
                      final pagado = r['estado'] == 'pagado';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              pagado
                                  ? Icons.check_circle_rounded
                                  : Icons.schedule_rounded,
                              color: pagado ? Colors.green : Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${(r['monto_cup'] as num).toStringAsFixed(0)} CUP',
                                style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5),
                              ),
                            ),
                            Text(
                              pagado ? 'Pagado' : 'Pendiente',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: pagado
                                      ? Colors.green.shade700
                                      : Colors.orange.shade700,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (total > 5)
                      TextButton(
                        onPressed: () => setState(
                            () => _verTodosRetiros = !_verTodosRetiros),
                        child: Text(_verTodosRetiros
                            ? 'Ver menos'
                            : 'Ver todos ($total)'),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),

            // ---------- Eliminar cuenta ----------
            Card(
              color: Colors.red.withOpacity(0.05),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.red,
                  child: Icon(Icons.person_remove_outlined,
                      color: Colors.white, size: 18),
                ),
                title: Text(
                  'Eliminar cuenta de afiliado',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600, color: Colors.red),
                ),
                subtitle: const Text(
                    'Bloqueado si tienes un retiro pendiente de aprobación'),
                onTap: _confirmarEliminarCuenta,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarEliminarCuenta() async {
    if (_afiliado == null) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar cuenta de afiliado?'),
        content: const Text(
          'Esta acción desactiva tu perfil de afiliado. Tu código, saldo '
          'e historial se conservan -- si vuelves a registrarte con esta '
          'misma cuenta de Google, recuperas todo tal como lo dejaste.',
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

    try {
      await _tiendasService.darDeBajaAfiliado(_afiliado!['id_afiliado']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cuenta de afiliado eliminada')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Widget _filaDato(IconData icon, String etiqueta, String valor) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.inkSecundarioLight),
        const SizedBox(width: 10),
        Text('$etiqueta: ',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        Expanded(child: Text(valor, style: GoogleFonts.plusJakartaSans())),
      ],
    );
  }
}