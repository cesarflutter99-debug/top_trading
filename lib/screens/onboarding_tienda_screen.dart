// onboarding_tienda_screen.dart
//
// INTEGRACIÓN CON TiendaStateService (2026-08):
//   - Al terminar _confirmar() (tanto la rama de plan gratis como la
//     de basic/premium con pago pendiente), se llama a
//     TiendaStateService.instance.refrescar() ANTES de navegar. Así,
//     cuando el usuario llega a /home (o vuelve de /pago-plan), la
//     pestaña "Mi Tienda" de MainShellScreen ya sabe que existe una
//     tienda nueva y muestra el panel del vendedor directamente --
//     antes había que salir y volver a entrar a la app para que
//     dejara de mostrar el CTA de "Hacerte vendedor".

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../core/provincias_cuba.dart';
import '../services/location_service.dart';
import '../services/tiendas_service.dart';
import '../services/tienda_state_service.dart';

class OnboardingTiendaScreen extends StatefulWidget {
  const OnboardingTiendaScreen({super.key});

  @override
  State<OnboardingTiendaScreen> createState() => _OnboardingTiendaScreenState();
}

class _OnboardingTiendaScreenState extends State<OnboardingTiendaScreen> {
  final _locationService = LocationService();
  final _tiendasService = TiendasService();
  final _pageController = PageController();

  int _paso = 0;
  static const _totalPasos = 5;

  final _formKeyDatos = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();

  final _formKeyPropietario = GlobalKey<FormState>();
  final _nombrePropietarioCtrl = TextEditingController();

  String? _categoria;

  String? _provincia;
  String? _municipioSeleccionado;
  final _municipioLibreCtrl = TextEditingController();
  double? _lat;
  double? _lon;
  bool _capturandoGps = false;

  String _planElegido = 'basic';
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
    _nombrePropietarioCtrl.dispose();
    _municipioLibreCtrl.dispose();
    super.dispose();
  }

  String get _municipioFinal => tieneMunicipiosCargados(_provincia ?? '')
      ? (_municipioSeleccionado ?? '')
      : _municipioLibreCtrl.text.trim();

  bool get _puedeAvanzarPaso3 => _categoria != null;
  bool get _puedeAvanzarPaso4 =>
      _provincia != null &&
      _municipioFinal.isNotEmpty &&
      _lat != null &&
      _lon != null;

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
    if (_paso == 1 && !_formKeyPropietario.currentState!.validate()) return;
    if (_paso == 2 && !_puedeAvanzarPaso3) {
      _mostrarError('Selecciona una categoría');
      return;
    }
    if (_paso == 3 && !_puedeAvanzarPaso4) {
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
          nombrePropietario: _nombrePropietarioCtrl.text.trim(),
          telefonoWhatsapp: _telefonoCtrl.text.trim(),
          provincia: _provincia!,
          municipio: _municipioFinal,
          lat: _lat!,
          lon: _lon!,
          categoria: _categoria!,
        );

        // FIX (persistencia): antes, al llegar a /home, la pestaña
        // "Mi Tienda" seguía mostrando "Hacerte vendedor" hasta
        // reiniciar la app -- porque nadie le avisaba a
        // MainShellScreen que ya existía una tienda nueva. Se
        // refresca el estado compartido ANTES de navegar.
        await TiendaStateService.instance.refrescar();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('¡Tu tienda ya está activa por 14 días! 🎉')),
          );
          context.go('/home');
        }
        return;
      }

      final idTienda = await _tiendasService.crearTienda(
        nombre: _nombreCtrl.text.trim(),
        nombrePropietario: _nombrePropietarioCtrl.text.trim(),
        telefonoWhatsapp: _telefonoCtrl.text.trim(),
        provincia: _provincia!,
        municipio: _municipioFinal,
        lat: _lat!,
        lon: _lon!,
        plan: _planElegido,
        categoria: _categoria,
      );

      // Mismo fix para el flujo basic/premium: la tienda queda en
      // 'pending', pero ya debe verse en el panel del vendedor (con
      // el banner de "en revisión") sin esperar a reiniciar la app.
      await TiendaStateService.instance.refrescar();

      if (mounted) {
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
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final fondo = theme.scaffoldBackgroundColor;
    final bordeSutil = theme.dividerColor;
    final textoSecundario = theme.textTheme.bodySmall?.color ??
        theme.colorScheme.onSurface.withOpacity(0.6);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: fondo,
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
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
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
                        margin:
                            EdgeInsets.only(right: i < _totalPasos - 1 ? 6 : 0),
                        height: 4,
                        decoration: BoxDecoration(
                          color: activo ? primary : bordeSutil,
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
                    style: GoogleFonts.inter(
                        fontSize: 12.5, color: textoSecundario),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _pasoDatos(theme),
                    _pasoPropietario(theme),
                    _pasoCategoria(theme),
                    _pasoUbicacion(theme),
                    _pasoPlan(theme),
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _guardando ? null : _siguiente,
                    child: _guardando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(
                            _paso < _totalPasos - 1
                                ? 'Siguiente'
                                : (_planElegido == 'gratis'
                                    ? 'Activar tienda gratis'
                                    : 'Enviar solicitud'),
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600, fontSize: 16),
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
        return 'Datos del negocio';
      case 1:
        return 'Propietario';
      case 2:
        return 'Categoría';
      case 3:
        return 'Ubicación';
      default:
        return 'Plan';
    }
  }

  Widget _pasoDatos(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKeyDatos,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tituloPasoTexto(theme, 'Información de Contacto',
                'Empecemos con lo básico de tu negocio.'),
            const SizedBox(height: 20),
            _campoTexto(
              theme: theme,
              controller: _nombreCtrl,
              label: 'Nombre del negocio',
              hint: 'Ej: Cafetería El Rincón',
              icon: Icons.storefront_outlined,
            ),
            const SizedBox(height: 16),
            _campoTexto(
              theme: theme,
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

  Widget _pasoPropietario(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKeyPropietario,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tituloPasoTexto(theme, '¿Quién eres?',
                'Nombre de la persona responsable de esta tienda.'),
            const SizedBox(height: 20),
            _campoTexto(
              theme: theme,
              controller: _nombrePropietarioCtrl,
              label: 'Nombre y apellido del propietario',
              hint: 'Ej: María Fernández López',
              icon: Icons.badge_outlined,
              helper: 'Es distinto del nombre del negocio -- este es tu '
                  'nombre real, para que el admin sepa con quién habla.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _pasoCategoria(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloPasoTexto(theme, '¿Qué categoría describe tu negocio?',
              'Ayuda a que compradores cercanos te encuentren más fácil.'),
          const SizedBox(height: 20),
          _labelCampo(theme, 'Categoría'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _categoria,
            isExpanded: true,
            style: GoogleFonts.inter(color: theme.textTheme.bodyLarge?.color),
            dropdownColor: theme.colorScheme.surface,
            decoration: _decoracionCampo(
              theme: theme,
              hint: 'Elige la categoría de tu negocio',
              icon: Icons.category_outlined,
            ),
            items: kCategoriasTienda
                .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _categoria = v),
          ),
        ],
      ),
    );
  }

  Widget _pasoUbicacion(ThemeData theme) {
    final tieneMunicipios = tieneMunicipiosCargados(_provincia ?? '');
    final primary = theme.colorScheme.primary;
    final textoSecundario = theme.textTheme.bodySmall?.color ??
        theme.colorScheme.onSurface.withOpacity(0.6);
    final campoDeshabilitadoBg = theme.colorScheme.surfaceContainerHighest
        .withOpacity(theme.brightness == Brightness.dark ? 0.4 : 1);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloPasoTexto(
            theme,
            'Ubicación de tu negocio',
            'Selecciona tu provincia y municipio, y marca el punto exacto '
                'en el mapa.',
          ),
          const SizedBox(height: 20),
          _labelCampo(theme, 'Provincia'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _provincia,
            isExpanded: true,
            style: GoogleFonts.inter(color: theme.textTheme.bodyLarge?.color),
            dropdownColor: theme.colorScheme.surface,
            decoration: _decoracionCampo(
                theme: theme,
                hint: 'Elige tu provincia',
                icon: Icons.map_outlined),
            items: kProvinciasCuba
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: (v) => setState(() {
              _provincia = v;
              _municipioSeleccionado = null;
              _municipioLibreCtrl.clear();
            }),
          ),
          const SizedBox(height: 16),
          _labelCampo(theme, 'Municipio'),
          const SizedBox(height: 8),
          if (_provincia == null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: campoDeshabilitadoBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Elige primero la provincia',
                  style: GoogleFonts.inter(color: textoSecundario)),
            )
          else if (tieneMunicipios)
            DropdownButtonFormField<String>(
              value: _municipioSeleccionado,
              isExpanded: true,
              style: GoogleFonts.inter(color: theme.textTheme.bodyLarge?.color),
              dropdownColor: theme.colorScheme.surface,
              decoration: _decoracionCampo(
                  theme: theme,
                  hint: 'Elige tu municipio',
                  icon: Icons.location_city_outlined),
              items: municipiosDe(_provincia!)
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => setState(() => _municipioSeleccionado = v),
            )
          else
            TextField(
              controller: _municipioLibreCtrl,
              style: GoogleFonts.inter(color: theme.textTheme.bodyLarge?.color),
              decoration: _decoracionCampo(
                  theme: theme,
                  hint: 'Escribe tu municipio',
                  icon: Icons.location_city_outlined),
              onChanged: (_) => setState(() {}),
            ),
          if (_provincia != null && !tieneMunicipios) ...[
            const SizedBox(height: 6),
            Text(
              'Aún no tenemos la lista de municipios de $_provincia -- '
              'escríbelo tal cual.',
              style: GoogleFonts.inter(fontSize: 11.5, color: textoSecundario),
            ),
          ],
          const SizedBox(height: 20),
          Text('Ubicación GPS',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: theme.textTheme.bodyLarge?.color)),
          const SizedBox(height: 4),
          Text('Marca el punto exacto de tu local.',
              style: GoogleFonts.inter(color: textoSecundario)),
          const SizedBox(height: 12),
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: campoDeshabilitadoBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  _lat != null ? Icons.location_on_rounded : Icons.map_outlined,
                  size: 44,
                  color: _lat != null
                      ? theme.colorScheme.error
                      : textoSecundario.withOpacity(0.5),
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: Material(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    elevation: 1,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _capturandoGps ? null : _capturarUbicacion,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: _capturandoGps
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Icon(Icons.my_location_rounded,
                                color: primary, size: 18),
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
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.explore_rounded, color: textoSecundario, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _lat != null
                          ? '${_lat!.toStringAsFixed(5)}, ${_lon!.toStringAsFixed(5)}'
                          : 'Aún no has capturado tu ubicación',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          color: theme.textTheme.bodyLarge?.color),
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

  Widget _pasoPlan(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final textoSecundario = theme.textTheme.bodySmall?.color ??
        theme.colorScheme.onSurface.withOpacity(0.6);
    final esOscuro = theme.brightness == Brightness.dark;
    final infoBg = esOscuro ? const Color(0xFF11304D) : const Color(0xFFF0F7FF);
    final infoBorde =
        esOscuro ? const Color(0xFF1D4E7A) : const Color(0xFFD0E3F7);
    final infoTexto =
        esOscuro ? const Color(0xFF8FC4F7) : const Color(0xFF1565C0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloPasoTexto(theme, 'Elige tu plan',
              'Puedes empezar gratis o ir directo a un plan de pago.'),
          const SizedBox(height: 20),
          if (_cargandoElegibilidadGratis)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _planOption(
              theme: theme,
              titulo: 'Gratis · 14 días',
              subtitulo: _puedeUsarGratis
                  ? 'Tu tienda queda activa de inmediato, sin pago. Válido '
                      'por 14 días, una sola vez por cuenta.'
                  : 'Ya usaste tu plan gratuito con esta cuenta. Elige '
                      'Basic o Premium para continuar.',
              value: 'gratis',
              habilitado: _puedeUsarGratis,
              primary: primary,
              textoSecundario: textoSecundario,
            ),
          const SizedBox(height: 12),
          _planOption(
            theme: theme,
            titulo: 'Basic',
            subtitulo:
                '20 productos visibles, 20 fotos. Requiere aprobación y pago.',
            value: 'basic',
            habilitado: true,
            primary: primary,
            textoSecundario: textoSecundario,
          ),
          const SizedBox(height: 12),
          _planOption(
            theme: theme,
            titulo: 'Premium',
            subtitulo: '50 productos, 50 fotos, elegible para Portada '
                'Mensual. Requiere aprobación y pago.',
            value: 'premium',
            habilitado: true,
            primary: primary,
            textoSecundario: textoSecundario,
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: infoBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: infoBorde),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_rounded, color: infoTexto, size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _planElegido == 'gratis'
                          ? 'Tu tienda gratuita queda activa de inmediato. '
                              '5 y 3 días antes de que venza tu plan, te '
                              'avisaremos para que puedas renovarlo.'
                          : 'Tu tienda será revisada manualmente por el '
                              'admin. Una vez aprobada y verificado el pago, '
                              'recibirás el sello de confianza. Si tienes un '
                              'código de afiliado, lo puedes aplicar en la '
                              'siguiente pantalla de pago.',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: infoTexto, height: 1.4),
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
    required ThemeData theme,
    required String titulo,
    required String subtitulo,
    required String value,
    required bool habilitado,
    required Color primary,
    required Color textoSecundario,
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
            color: seleccionado && habilitado
                ? primary.withOpacity(0.08)
                : theme.colorScheme.surface,
            border: Border.all(
              color: seleccionado && habilitado ? primary : theme.dividerColor,
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
                  onChanged: habilitado
                      ? (v) => setState(() => _planElegido = v!)
                      : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo,
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              color: theme.textTheme.bodyLarge?.color)),
                      const SizedBox(height: 2),
                      Text(subtitulo,
                          style: GoogleFonts.inter(
                              fontSize: 12, color: textoSecundario)),
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

  Widget _tituloPasoTexto(ThemeData theme, String titulo, String subtitulo) {
    final textoSecundario = theme.textTheme.bodySmall?.color ??
        theme.colorScheme.onSurface.withOpacity(0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo,
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: theme.textTheme.bodyLarge?.color)),
        const SizedBox(height: 4),
        Text(subtitulo,
            style: GoogleFonts.inter(color: textoSecundario, height: 1.4)),
      ],
    );
  }

  Widget _labelCampo(ThemeData theme, String texto) {
    return Text(
      texto,
      style: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: theme.textTheme.bodyLarge?.color),
    );
  }

  InputDecoration _decoracionCampo({
    required ThemeData theme,
    required String hint,
    required IconData icon,
  }) {
    final esOscuro = theme.brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
          color: theme.textTheme.bodySmall?.color ??
              theme.colorScheme.onSurface.withOpacity(0.5)),
      prefixIcon: Icon(icon, size: 20, color: theme.iconTheme.color),
      filled: true,
      fillColor: esOscuro ? theme.colorScheme.surface : const Color(0xFFF3F4F6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    );
  }

  Widget _campoTexto({
    required ThemeData theme,
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? helper,
  }) {
    final textoSecundario = theme.textTheme.bodySmall?.color ??
        theme.colorScheme.onSurface.withOpacity(0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: theme.textTheme.bodyLarge?.color)),
            const SizedBox(width: 4),
            Text('*',
                style: GoogleFonts.inter(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.inter(color: theme.textTheme.bodyLarge?.color),
          decoration: _decoracionCampo(theme: theme, hint: hint, icon: icon),
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(helper,
              style: GoogleFonts.inter(fontSize: 12, color: textoSecundario)),
        ],
      ],
    );
  }
}
