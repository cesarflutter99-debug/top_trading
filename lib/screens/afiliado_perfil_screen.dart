// afiliado_perfil_screen.dart
//
// REDISEÑO (2026-08):
//   - Estética alineada al resto de la app (mi_perfil_screen.dart /
//     panel_vendedor_screen.dart): tarjetas "vidrio flotante", colores
//     adaptativos a modo oscuro, header con gradiente + avatar.
//   - NUEVO: sección "Tiendas referidas" -- se arma deduplicando el
//     historial de comisiones (_comisiones) por id_tienda, mostrando
//     hasta 5 con un botón "Ver todas" que abre
//     AfiliadoTiendasReferidasScreen con el listado completo. Antes
//     esta información solo vivía mezclada dentro de "Historial de
//     comisiones", sin agrupar por tienda.
//   - FIX eliminar cuenta: antes se asumía éxito con solo no atrapar
//     una excepción. Ahora, después de llamar a darDeBajaAfiliado(),
//     se vuelve a pedir obtenerMiAfiliado() para CONFIRMAR que
//     realmente desapareció -- si sigue existiendo, se avisa
//     explícitamente en vez de cerrar la pantalla como si hubiese
//     funcionado. Esto expone el bug real (que vive en
//     tiendas_service.dart / backend) en vez de ocultarlo.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/tiendas_service.dart';
import '../services/afiliado_state_service.dart';
import 'afiliado_tiendas_referidas_screen.dart';

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
  bool _eliminandoCuenta = false;
  bool _verTodosRetiros = false;

  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _tarjetaCtrl = TextEditingController();

  late Future<List<Map<String, dynamic>>> _comisiones;
  late Future<List<Map<String, dynamic>>> _retiros;

  bool get _esOscuro => Theme.of(context).brightness == Brightness.dark;
  Color get _colorTexto => _esOscuro ? const Color(0xFFF5F5F4) : AppColors.ink;
  Color get _colorTextoSecundario =>
      _esOscuro ? AppColors.inkSecundarioDark : AppColors.inkSecundarioLight;
  Color get _colorFondo => Theme.of(context).scaffoldBackgroundColor;
  Color get _colorSuperficie => _esOscuro
      ? AppColors.cardTransparentDark
      : AppColors.cardTransparentLight;
  Color get _colorBorde =>
      (_esOscuro ? AppColors.borderDark : AppColors.borderLight)
          .withOpacity(0.6);

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
      // FIX (persistencia): propaga el cambio al estado global para
      // que Home / Mi Perfil, que también muestran datos del
      // afiliado, se enteren sin tener que volver a entrar a la app.
      await AfiliadoStateService.instance.refrescar();
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
      '¡Únete a Al Lado! 🛍️\n'
      'Usa mi código de afiliado "$codigo" al registrar tu tienda y obtén '
      '10% de descuento en tu primer plan.\n\n'
      'Descarga la app y regístrate ahora.',
    );
  }

  /// Agrupa el historial de comisiones (_comisiones) por tienda para
  /// armar la lista de "Tiendas referidas" -- una fila por tienda,
  /// no una por cada uso/comisión.
  List<Map<String, dynamic>> _agruparPorTienda(
      List<Map<String, dynamic>> usos) {
    final Map<String, Map<String, dynamic>> agrupado = {};
    for (final u in usos) {
      final tienda = u['tiendas'] as Map<String, dynamic>? ?? {};
      final id = (tienda['id_tienda'] ?? u['id_tienda'] ?? tienda['nombre'])
          ?.toString();
      if (id == null) continue;
      final acumuladoPrevio =
          (agrupado[id]?['comision_acumulada'] as num?) ?? 0;
      final estaAprobado = u['estado'] == 'aprobado';
      agrupado[id] = {
        'id_tienda': id,
        'nombre': tienda['nombre'] ?? 'Tienda',
        'logo_url': tienda['logo_url'],
        'comision_acumulada': acumuladoPrevio +
            (estaAprobado ? (u['comision_cup_acreditada'] ?? 0) : 0),
        'estado': u['estado'],
        'creado_en': u['creado_en'],
      };
    }
    return agrupado.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        backgroundColor: _colorFondo,
        appBar: AppBar(title: const Text('Mi Perfil de Afiliado')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_afiliado == null) {
      return Scaffold(
        backgroundColor: _colorFondo,
        appBar: AppBar(title: const Text('Mi Perfil de Afiliado')),
        body: const Center(child: Text('Todavía no eres afiliado.')),
      );
    }

    final saldo = (_afiliado!['saldo_cup'] as num).toDouble();
    final puedeRetirar = saldo >= 1000;

    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        title: const Text('Mi Perfil de Afiliado'),
        backgroundColor: _colorFondo,
        foregroundColor: _colorTexto,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeader(),
            const SizedBox(height: 14),
            _buildSaldoCard(saldo, puedeRetirar),
            const SizedBox(height: 14),
            _buildDatosContacto(),
            const SizedBox(height: 20),
            _buildSectionTitle('Tiendas referidas', Icons.storefront_rounded),
            const SizedBox(height: 10),
            _buildTiendasReferidas(),
            const SizedBox(height: 20),
            _buildSectionTitle(
                'Historial de retiros', Icons.account_balance_wallet_rounded),
            const SizedBox(height: 10),
            _buildRetiros(),
            const SizedBox(height: 24),
            _buildEliminarCuenta(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
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
                ? const Icon(Icons.person, size: 40, color: AppColors.primary)
                : null,
          ),
          const SizedBox(height: 12),
          Text(_afiliado!['nombre'] ?? '',
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
            onPressed: _compartirCodigo,
            icon: const Icon(Icons.share_outlined,
                size: 16, color: Colors.white),
            label: Text('Compartir',
                style: GoogleFonts.plusJakartaSans(color: Colors.white)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white70),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaldoCard(double saldo, bool puedeRetirar) {
    return Container(
      decoration: BoxDecoration(
        color: _colorSuperficie,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: _colorBorde),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saldo actual',
              style: GoogleFonts.plusJakartaSans(
                  color: _colorTextoSecundario, fontSize: 13)),
          const SizedBox(height: 4),
          Text('${saldo.toStringAsFixed(0)} CUP',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                  color: _colorTexto)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: puedeRetirar ? _abrirModalRetiro : null,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(
                  puedeRetirar ? 'Solicitar retiro' : 'Necesitas mínimo 1000 CUP'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Mínimo 1000 CUP · máximo 10,000 CUP por día · el pago se '
            'coordina por WhatsApp.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, color: _colorTextoSecundario),
          ),
        ],
      ),
    );
  }

  Widget _buildDatosContacto() {
    return Container(
      decoration: BoxDecoration(
        color: _colorSuperficie,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: _colorBorde),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Datos de contacto',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                      color: _colorTexto)),
              TextButton.icon(
                onPressed: () => setState(() => _editando = !_editando),
                icon: Icon(_editando ? Icons.close : Icons.edit_outlined,
                    size: 16),
                label: Text(_editando ? 'Cancelar' : 'Editar'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_editando) ...[
            TextField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _telefonoCtrl,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: 'Teléfono (WhatsApp)'),
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
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _colorTextoSecundario),
        const SizedBox(width: 8),
        Text(title,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 15, fontWeight: FontWeight.w800, color: _colorTexto)),
      ],
    );
  }

  Widget _buildTiendasReferidas() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _comisiones,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _tarjetaVacia('No se pudieron cargar tus tiendas referidas.');
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final tiendas = _agruparPorTienda(snapshot.data!);
        if (tiendas.isEmpty) {
          return _tarjetaVacia(
              'Todavía nadie usó tu código. Comparte tu código para empezar '
              'a sumar tiendas referidas.');
        }
        final mostrar = tiendas.take(5).toList();
        return Container(
          decoration: BoxDecoration(
            color: _colorSuperficie,
            borderRadius: BorderRadius.circular(kCardRadius),
            border: Border.all(color: _colorBorde),
          ),
          child: Column(
            children: [
              ...mostrar.map((t) => _filaTiendaReferida(t)),
              if (tiendas.length > 5)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AfiliadoTiendasReferidasScreen(
                            tiendas: tiendas,
                          ),
                        ),
                      );
                    },
                    child: Text('Ver todas (${tiendas.length})'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _filaTiendaReferida(Map<String, dynamic> t) {
    final logo = t['logo_url'] as String?;
    final comision = (t['comision_acumulada'] as num?) ?? 0;
    final aprobado = t['estado'] == 'aprobado';
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.warm.withOpacity(0.1),
        backgroundImage:
            (logo != null && logo.isNotEmpty) ? NetworkImage(logo) : null,
        child: (logo == null || logo.isEmpty)
            ? const Icon(Icons.storefront_rounded, color: AppColors.warm)
            : null,
      ),
      title: Text(t['nombre'] ?? 'Tienda',
          style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w600, fontSize: 13.5, color: _colorTexto)),
      subtitle: Text(
        aprobado ? 'Comisión aprobada' : 'Pendiente de aprobación',
        style: GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            color: aprobado ? AppColors.success : Colors.orange),
      ),
      trailing: Text(
        '+${comision.toStringAsFixed(0)} CUP',
        style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700, color: AppColors.warm, fontSize: 13),
      ),
    );
  }

  Widget _buildRetiros() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _retiros,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _tarjetaVacia('No se pudieron cargar tus retiros.');
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final retiros = snapshot.data!;
        if (retiros.isEmpty) {
          return _tarjetaVacia('Aún no has solicitado retiros.');
        }
        final total = retiros.length;
        final mostrar = _verTodosRetiros ? retiros : retiros.take(5).toList();
        return Container(
          decoration: BoxDecoration(
            color: _colorSuperficie,
            borderRadius: BorderRadius.circular(kCardRadius),
            border: Border.all(color: _colorBorde),
          ),
          child: Column(
            children: [
              ...mostrar.map((r) {
                final pagado = r['estado'] == 'pagado';
                return ListTile(
                  leading: Icon(
                    pagado
                        ? Icons.check_circle_rounded
                        : Icons.schedule_rounded,
                    color: pagado ? AppColors.success : Colors.orange,
                  ),
                  title: Text(
                    '${(r['monto_cup'] as num).toStringAsFixed(0)} CUP',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, color: _colorTexto),
                  ),
                  trailing: Text(
                    pagado ? 'Pagado' : 'Pendiente',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: pagado ? AppColors.success : Colors.orange),
                  ),
                );
              }),
              if (total > 5)
                TextButton(
                  onPressed: () =>
                      setState(() => _verTodosRetiros = !_verTodosRetiros),
                  child:
                      Text(_verTodosRetiros ? 'Ver menos' : 'Ver todos ($total)'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _tarjetaVacia(String texto) {
    return Container(
      decoration: BoxDecoration(
        color: _colorSuperficie,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: _colorBorde),
      ),
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Text(texto,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                color: _colorTextoSecundario, fontSize: 13)),
      ),
    );
  }

  Widget _buildEliminarCuenta() {
    return Card(
      color: Colors.red.withOpacity(_esOscuro ? 0.10 : 0.05),
      child: ListTile(
        leading: _eliminandoCuenta
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const CircleAvatar(
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
        onTap: _eliminandoCuenta ? null : _confirmarEliminarCuenta,
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

    setState(() => _eliminandoCuenta = true);
    try {
      final idAfiliado = _afiliado!['id_afiliado'];
      await _tiendasService.darDeBajaAfiliado(idAfiliado);

      // FIX: no confiamos en que la llamada anterior no haya lanzado
      // una excepción -- volvemos a preguntar si el afiliado sigue
      // existiendo. Si sigue ahí, algo en el backend (RLS, un WHERE
      // que no matchea, la regla de "retiro pendiente") está
      // bloqueando la baja sin avisar, y hay que decirlo claro.
      final sigueExistiendo = await _tiendasService.obtenerMiAfiliado();
      if (!mounted) return;

      if (sigueExistiendo != null) {
        setState(() => _eliminandoCuenta = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo eliminar tu cuenta de afiliado. Es posible que '
              'tengas un retiro pendiente de aprobación -- espera a que se '
              'resuelva e inténtalo de nuevo.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }

      // FIX (persistencia): limpia el estado global YA, en el mismo
      // frame -- sin esto, Home/Mi Perfil seguían mostrando el chip
      // "Afiliado" y el acceso al perfil hasta reiniciar la app.
      AfiliadoStateService.instance.limpiar();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cuenta de afiliado eliminada')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _eliminandoCuenta = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Widget _filaDato(IconData icon, String etiqueta, String valor) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _colorTextoSecundario),
        const SizedBox(width: 10),
        Text('$etiqueta: ',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600, color: _colorTexto)),
        Expanded(
            child: Text(valor,
                style: GoogleFonts.plusJakartaSans(color: _colorTexto))),
      ],
    );
  }
}
