// onboarding_tienda_screen.dart
//
// Registro de tienda dividido en 4 pasos (antes era un único
// formulario largo):
//   1. Datos básicos      -- nombre + WhatsApp (obligatorios)
//   2. Categoría           -- selector de categoría
//   3. Ubicación            -- provincia (dropdown), municipio (dropdown
//                              si es La Habana, texto libre para el
//                              resto), captura GPS
//   4. Plan                 -- Basic / Premium / Gratis (14 días, una
//                              sola vez por cuenta -- ver
//                              cuentas_beneficios en SQL)
//
// Al terminar:
//   - Basic/Premium: crea la tienda en estado 'pending' (como antes) y
//     navega a /pago-plan con context.push() (NO context.go() -- ver
//     el FIX de navegación en router.dart, era la causa de que "atrás"
//     sacara de la app).
//   - Gratis: crea la tienda YA activa (sin pasar por pago ni admin) y
//     navega directo a /home.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../core/provincias_cuba.dart';
import '../services/location_service.dart';
import '../services/tiendas_service.dart';

class OnboardingTiendaScreen extends StatefulWidget {
  const OnboardingTiendaScreen({super.key});

  @override
  State<OnboardingTiendaScreen> createState() =>
      _OnboardingTiendaScreenState();
}

class _OnboardingTiendaScreenState extends State<OnboardingTiendaScreen> {
  final _locationService = LocationService();
  final _tiendasService = TiendasService();
  final _pageController = PageController();

  int _paso = 0;
  static const _totalPasos = 4;

  // ---- Paso 1: datos básicos ----
  final _formKeyDatos = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();

  // ---- Paso 2: categoría ----
  String? _categoria;

  // ---- Paso 3: ubicación ----
  String? _provincia;
  String? _municipioSeleccionado; // cuando la provincia tiene dropdown
  final _municipioLibreCtrl = TextEditingController(); // texto libre
  double? _lat;
  double? _lon;
  bool _capturandoGps = false;

  // ---- Paso 4: plan ----
  String _planElegido = 'basic';
  final _codigoAfiliadoCtrl = TextEditingController();
  bool _cargandoElegibilidadGratis = true;
  bool _puedeUsarGratis = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarElegibilidadGratis();
  }

  Future<void> _cargarElegibilidadGratis() async {
    final puede = await _tiendasService.puedeUsarPlanGratis();
    if (mounted) {
      setState(() {
        _puedeUsarGratis = puede;
        _cargandoElegibilidadGratis = false;
        if (!puede && _planElegido == 'gratis') _planElegido = 'basic';
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _municipioLibreCtrl.dispose();
    _codigoAfiliadoCtrl.dispose();
    super.dispose();
  }

  String get _municipioFinal => tieneMunicipiosCargados(_provincia ?? '')
      ? (_municipioSeleccionado ?? '')
      : _municipioLibreCtrl.text.trim();

  bool get _puedeAvanzarPaso2 => _categoria != null;
  bool get _puedeAvanzarPaso3 =>
      _provincia != null && _municipioFinal.isNotEmpty && _lat != null && _lon != null;

  void _irAPaso(int paso) {
    setState(() => _paso = paso);
    _pageController.animateToPage(
      paso,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _siguiente() {
    if (_paso == 0 && !_formKeyDatos.currentState!.validate()) return;
    if (_paso == 1 && !_puedeAvanzarPaso2) {
      _mostrarError('Selecciona una categoría');
      return;
    }
    if (_paso == 2 && !_puedeAvanzarPaso3) {
      _mostrarError(_lat == null
          ? 'Captura la ubicación de tu negocio primero'
          : 'Completa provincia y municipio');
      return;
    }
    if (_paso < _totalPasos - 1) {
      _irAPaso(_paso + 1);
    } else {
      _confirmar();
    }
  }

  void _anterior() {
    if (_paso > 0) {
      _irAPaso(_paso - 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _capturarUbicacion() async {
    setState(() => _capturandoGps = true);
    try {
      final pos = await _locationService.obtenerUbicacionActual();
      setState(() {
        _lat = pos.latitude;
        _lon = pos.longitude;
      });
    } catch (e) {
      if (mounted) _mostrarError('No se pudo obtener tu ubicación: $e');
    } finally {
      if (mounted) setState(() => _capturandoGps = false);
    }
  }

  Future<void> _confirmar() async {
    setState(() => _guardando = true);
    try {
      if (_planElegido == 'gratis') {
        await _tiendasService.crearTiendaConPlanGratis(
          nombre: _nombreCtrl.text.trim(),
          telefonoWhatsapp: _telefonoCtrl.text.trim(),
          provincia: _provincia!,
          municipio: _municipioFinal,
          lat: _lat!,
          lon: _lon!,
          categoria: _categoria!,
          codigoAfiliado: _codigoAfiliadoCtrl.text.trim().isEmpty
              ? null
              : _codigoAfiliadoCtrl.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('¡Tu tienda ya está activa por 14 días! 🎉')),
          );
          // Plan gratis: no hay pago que verificar -- punto final real
          // del flujo, se manda directo al shell principal.
          context.go('/home');
        }
        return;
      }

      // Basic / Premium: sigue el flujo existente (pending + pago).
      final idTienda = await _tiendasService.crearTienda(
        nombre: _nombreCtrl.text.trim(),
        telefonoWhatsapp: _telefonoCtrl.text.trim(),
        provincia: _provincia!,
        municipio: _municipioFinal,
        lat: _lat!,
        lon: _lon!,
        plan: _planElegido,
        categoria: _categoria,
        codigoAfiliado: _codigoAfiliadoCtrl.text.trim().isEmpty
            ? null
            : _codigoAfiliadoCtrl.text.trim(),
      );

      if (mounted) {
        // FIX de navegación: push (no go) para que /crear-tienda quede
        // debajo en el stack -- así "atrás" en /pago-plan funciona.
        context.push('/pago-plan', extra: {
          'idTienda': idTienda,
          'plan': _planElegido,
        });
      }
    } catch (e) {
      if (mounted) {
        _mostrarError('No se pudo crear la tienda: '
            '${e.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _guardando ? null : _anterior,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'Registrar Tienda',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: List.generate(_totalPasos, (i) {
                    final activo = i <= _paso;
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i < _totalPasos - 1 ? 6 : 0),
                        height: 4,
                        decoration: BoxDecoration(
                          color: activo ? primary : Colors.black12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Paso ${_paso + 1} de $_totalPasos · ${_tituloPaso(_paso)}',
                    style: GoogleFonts.inter(fontSize: 12.5, color: Colors.black54),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _pasoDatos(),
                    _pasoCategoria(),
                    _pasoUbicacion(primary),
                    _pasoPlan(primary),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _guardando ? null : _siguiente,
                    child: _guardando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(
                            _paso < _totalPasos - 1
                                ? 'Siguiente'
                                : (_planElegido == 'gratis'
                                    ? 'Activar tienda gratis'
                                    : 'Enviar solicitud'),
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _tituloPaso(int i) {
    switch (i) {
      case 0:
        return 'Datos básicos';
      case 1:
        return 'Categoría';
      case 2:
        return 'Ubicación';
      default:
        return 'Plan';
    }
  }

  Widget _pasoDatos() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKeyDatos,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Información de Contacto',
                style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 20)),
            const SizedBox(height: 4),
            Text('Empecemos con lo básico de tu negocio.',
                style: GoogleFonts.inter(color: Colors.black54)),
            const SizedBox(height: 20),
            _campoTexto(
              controller: _nombreCtrl,
              label: 'Nombre del negocio',
              hint: 'Ej: Cafetería El Rincón',
              icon: Icons.storefront_outlined,
            ),
            const SizedBox(height: 16),
            _campoTexto(
              controller: _telefonoCtrl,
              label: 'WhatsApp de Negocio',
              hint: '+53...',
              icon: Icons.chat_outlined,
              keyboardType: TextInputType.phone,
              helper: 'Usa este número para recibir pedidos',
            ),
          ],
        ),
      ),
    );
  }

  Widget _pasoCategoria() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('¿Qué categoría describe tu negocio?',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 20)),
          const SizedBox(height: 4),
          Text('Ayuda a que compradores cercanos te encuentren más fácil.',
              style: GoogleFonts.inter(color: Colors.black54)),
          const SizedBox(height: 20),
          ...kCategoriasTienda.map((c) {
            final seleccionada = c == _categoria;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _categoria = c),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: seleccionada
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.06)
                        : Colors.white,
                    border: Border.all(
                      color: seleccionada
                          ? Theme.of(context).colorScheme.primary
                          : Colors.black12,
                      width: seleccionada ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(c,
                            style: GoogleFonts.inter(
                                fontWeight: seleccionada ? FontWeight.w700 : FontWeight.normal)),
                      ),
                      if (seleccionada)
                        Icon(Icons.check_circle_rounded,
                            color: Theme.of(context).colorScheme.primary, size: 20),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _pasoUbicacion(Color primary) {
    final tieneMunicipios = tieneMunicipiosCargados(_provincia ?? '');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ubicación de tu negocio',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 20)),
          const SizedBox(height: 4),
          Text('Selecciona tu provincia y municipio, y marca el punto exacto en el mapa.',
              style: GoogleFonts.inter(color: Colors.black54, height: 1.4)),
          const SizedBox(height: 20),
          _labelCampo('Provincia'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _provincia,
            isExpanded: true,
            style: GoogleFonts.inter(color: Colors.black87),
            decoration: _decoracionCampo(hint: 'Elige tu provincia', icon: Icons.map_outlined),
            items: kProvinciasCuba.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
            onChanged: (v) => setState(() {
              _provincia = v;
              _municipioSeleccionado = null;
              _municipioLibreCtrl.clear();
            }),
          ),
          const SizedBox(height: 16),
          _labelCampo('Municipio'),
          const SizedBox(height: 8),
          if (_provincia == null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Elige primero la provincia', style: GoogleFonts.inter(color: Colors.black38)),
            )
          else if (tieneMunicipios)
            DropdownButtonFormField<String>(
              value: _municipioSeleccionado,
              isExpanded: true,
              style: GoogleFonts.inter(color: Colors.black87),
              decoration: _decoracionCampo(hint: 'Elige tu municipio', icon: Icons.location_city_outlined),
              items: municipiosDe(_provincia!).map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (v) => setState(() => _municipioSeleccionado = v),
            )
          else
            TextField(
              controller: _municipioLibreCtrl,
              style: GoogleFonts.inter(),
              decoration: _decoracionCampo(hint: 'Escribe tu municipio', icon: Icons.location_city_outlined),
              onChanged: (_) => setState(() {}),
            ),
          if (_provincia != null && !tieneMunicipios) ...[
            const SizedBox(height: 6),
            Text(
              'Aún no tenemos la lista de municipios de $_provincia -- escríbelo tal cual.',
              style: GoogleFonts.inter(fontSize: 11.5, color: Colors.black45),
            ),
          ],
          const SizedBox(height: 20),
          Text('Ubicación GPS', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text('Marca el punto exacto de tu local.', style: GoogleFonts.inter(color: Colors.black54)),
          const SizedBox(height: 12),
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  _lat != null ? Icons.location_on_rounded : Icons.map_outlined,
                  size: 44,
                  color: _lat != null ? Theme.of(context).colorScheme.error : Colors.black26,
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    elevation: 1,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _capturandoGps ? null : _capturarUbicacion,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: _capturandoGps
                            ? const SizedBox(
                                height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(Icons.my_location_rounded, color: primary, size: 18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.explore_rounded, color: Colors.black54, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _lat != null
                          ? '${_lat!.toStringAsFixed(5)}, ${_lon!.toStringAsFixed(5)}'
                          : 'Aún no has capturado tu ubicación',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pasoPlan(Color primary) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Elige tu plan', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 20)),
          const SizedBox(height: 4),
          Text('Puedes empezar gratis o ir directo a un plan de pago.',
              style: GoogleFonts.inter(color: Colors.black54)),
          const SizedBox(height: 20),
          if (_cargandoElegibilidadGratis)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _planOption(
              titulo: 'Gratis · 14 días',
              subtitulo: _puedeUsarGratis
                  ? 'Tu tienda queda activa de inmediato, sin pago. Válido por 14 días, una sola vez por cuenta.'
                  : 'Ya usaste tu plan gratuito con esta cuenta. Elige Basic o Premium para continuar.',
              value: 'gratis',
              habilitado: _puedeUsarGratis,
              primary: primary,
            ),
          const SizedBox(height: 12),
          _planOption(
            titulo: 'Basic',
            subtitulo: '20 productos visibles, 20 fotos. Requiere aprobación y pago.',
            value: 'basic',
            habilitado: true,
            primary: primary,
          ),
          const SizedBox(height: 12),
          _planOption(
            titulo: 'Premium',
            subtitulo: '50 productos, 50 fotos, elegible para Portada Mensual. Requiere aprobación y pago.',
            value: 'premium',
            habilitado: true,
            primary: primary,
          ),
          const SizedBox(height: 24),
          _labelCampo('Código de afiliado (opcional)'),
          const SizedBox(height: 8),
          TextField(
            controller: _codigoAfiliadoCtrl,
            textCapitalization: TextCapitalization.characters,
            style: GoogleFonts.inter(),
            decoration: _decoracionCampo(hint: 'Ej: A3F9K2', icon: Icons.card_giftcard_outlined),
          ),
          const SizedBox(height: 6),
          Text('Cada código solo puede usarse una vez por cuenta.',
              style: GoogleFonts.inter(fontSize: 11.5, color: Colors.black45)),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF0F7FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD0E3F7)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.verified_user_rounded, color: Color(0xFF1565C0), size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _planElegido == 'gratis'
                          ? 'Tu tienda gratuita queda activa de inmediato. 5 y 3 días antes de que venza tu plan, te avisaremos para que puedas renovarlo.'
                          : 'Tu tienda será revisada manualmente por el admin. Una vez aprobada y verificado el pago, recibirás el sello de confianza.',
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1565C0), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planOption({
    required String titulo,
    required String subtitulo,
    required String value,
    required bool habilitado,
    required Color primary,
  }) {
    final seleccionado = value == _planElegido;
    return Opacity(
      opacity: habilitado ? 1 : 0.55,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: habilitado ? () => setState(() => _planElegido = value) : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: seleccionado && habilitado ? primary.withOpacity(0.06) : Colors.white,
            border: Border.all(
              color: seleccionado && habilitado ? primary : Colors.black12,
              width: seleccionado && habilitado ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Radio<String>(
                  value: value,
                  groupValue: habilitado ? _planElegido : null,
                  activeColor: primary,
                  onChanged: habilitado ? (v) => setState(() => _planElegido = v!) : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(subtitulo, style: GoogleFonts.inter(fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _labelCampo(String texto) {
    return Text(texto, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14));
  }

  InputDecoration _decoracionCampo({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: const Color(0xFFF3F4F6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    );
  }

  Widget _campoTexto({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? helper,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(width: 4),
            Text('*', style: GoogleFonts.inter(color: Colors.red, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.inter(),
          decoration: _decoracionCampo(hint: hint, icon: icon),
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(helper, style: GoogleFonts.inter(fontSize: 12, color: Colors.black54)),
        ],
      ],
    );
  }
}
