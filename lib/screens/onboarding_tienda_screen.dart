import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../services/location_service.dart';
import '../services/tiendas_service.dart';

class OnboardingTiendaScreen extends StatefulWidget {
  const OnboardingTiendaScreen({super.key});

  @override
  State<OnboardingTiendaScreen> createState() => _OnboardingTiendaScreenState();
}

class _OnboardingTiendaScreenState extends State<OnboardingTiendaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _locationService = LocationService();
  final _tiendasService = TiendasService();

  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _provinciaCtrl = TextEditingController(text: 'La Habana');
  final _municipioCtrl = TextEditingController();

  String _plan = 'basic';
  double? _lat;
  double? _lon;
  bool _capturandoGps = false;
  bool _guardando = false;

  Future<void> _capturarUbicacion() async {
    setState(() => _capturandoGps = true);
    try {
      final pos = await _locationService.obtenerUbicacionActual();
      setState(() {
        _lat = pos.latitude;
        _lon = pos.longitude;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo obtener tu ubicación: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturandoGps = false);
    }
  }

  Future<void> _guardarTienda() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lat == null || _lon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Captura la ubicación de tu negocio primero')),
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      final idTienda = await _tiendasService.crearTienda(
        nombre: _nombreCtrl.text.trim(),
        telefonoWhatsapp: _telefonoCtrl.text.trim(),
        provincia: _provinciaCtrl.text.trim(),
        municipio: _municipioCtrl.text.trim(),
        lat: _lat!,
        lon: _lon!,
        plan: _plan,
        codigoAfiliado: null,
      );

      if (mounted) {
        // Navegar al modal de pago del plan
        context.go('/pago-plan', extra: {'idTienda': idTienda, 'plan': _plan});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear la tienda: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final alternate = Colors.black12;
    final secondaryText = Colors.black54;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---------- Header: cerrar + título ----------
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: alternate)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                        Text(
                          'Registrar Tienda',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),
                ),

                // ---------- Indicador de un solo paso ----------
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepDot(
                        numero: '1',
                        titulo: 'Datos',
                        activo: true,
                        primary: primary,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Divider(height: 1, color: alternate),
                        ),
                      ),
                      _StepDot(
                        numero: '2',
                        titulo: 'Ubicación',
                        activo: _lat != null,
                        primary: primary,
                      ),
                    ],
                  ),
                ),

                Form(
                  key: _formKey,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ---------- Sección: Información de contacto ----------
                        Text(
                          'Información de Contacto',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _CampoTexto(
                          controller: _nombreCtrl,
                          label: 'Nombre del negocio',
                          hint: 'Ej: Cafetería El Rincón',
                          icon: Icons.storefront_outlined,
                        ),
                        const SizedBox(height: 16),
                        _CampoTexto(
                          controller: _telefonoCtrl,
                          label: 'WhatsApp de Negocio',
                          hint: '+53...',
                          icon: Icons.chat_outlined,
                          keyboardType: TextInputType.phone,
                          helper: 'Usa este número para recibir pedidos',
                        ),
                        const SizedBox(height: 16),
                        _CampoTexto(
                          controller: _provinciaCtrl,
                          label: 'Provincia',
                          hint: 'La Habana',
                          icon: Icons.map_outlined,
                        ),
                        const SizedBox(height: 16),
                        _CampoTexto(
                          controller: _municipioCtrl,
                          label: 'Municipio',
                          hint: 'Ej: Playa',
                          icon: Icons.location_city_outlined,
                        ),
                        const SizedBox(height: 16),

                        // ---------- Sección: Ubicación GPS ----------
                        Text(
                          'Ubicación GPS',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Marca el punto exacto de tu local en La Habana',
                          style: GoogleFonts.inter(
                            color: secondaryText,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: alternate),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                _lat != null
                                    ? Icons.location_on_rounded
                                    : Icons.map_outlined,
                                size: 48,
                                color: _lat != null
                                    ? Theme.of(context).colorScheme.error
                                    : Colors.black26,
                              ),
                              Positioned(
                                right: 16,
                                bottom: 16,
                                child: Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  elevation: 1,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: _capturandoGps
                                        ? null
                                        : _capturarUbicacion,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: _capturandoGps
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Icon(
                                              Icons.my_location_rounded,
                                              color: primary,
                                              size: 20,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: alternate),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.explore_rounded,
                                  color: secondaryText,
                                  size: 20,
                                ),
                                const SizedBox(width: 16),
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

                        const SizedBox(height: 32),

                        // ---------- Plan ----------
                        Text(
                          'Plan',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _PlanOption(
                          titulo: 'Basic',
                          subtitulo: '20 productos visibles, 20 fotos',
                          value: 'basic',
                          groupValue: _plan,
                          primary: primary,
                          onChanged: (v) => setState(() => _plan = v!),
                        ),
                        const SizedBox(height: 12),
                        _PlanOption(
                          titulo: 'Premium',
                          subtitulo:
                              '50 productos, 50 fotos, elegible para Portada Mensual',
                          value: 'premium',
                          groupValue: _plan,
                          primary: primary,
                          onChanged: (v) => setState(() => _plan = v!),
                        ),

                        const SizedBox(height: 32),

                        // ---------- Caja informativa de verificación ----------
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F7FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFD0E3F7)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.verified_user_rounded,
                                  color: Color(0xFF1565C0),
                                  size: 24,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Proceso de Verificación',
                                        style: GoogleFonts.inter(
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF1565C0),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tu tienda será revisada manualmente por el admin. '
                                        'Una vez aprobada, recibirás el sello de confianza.',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: const Color(0xFF1565C0),
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
),

                        const SizedBox(height: 24),

                        // ---------- Botón principal ----------
                        SizedBox(
                          height: 52,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _guardando ? null : _guardarTienda,
                            child: _guardando
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'Enviar solicitud',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ---------- Footer legal ----------
                        Center(
                          child: Text(
                            'Al registrarte, aceptas los Términos de Top Trading',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Punto del indicador de pasos (1. Datos — 2. Ubicación)
class _StepDot extends StatelessWidget {
  final String numero;
  final String titulo;
  final bool activo;
  final Color primary;

  const _StepDot({
    required this.numero,
    required this.titulo,
    required this.activo,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: activo ? primary : Colors.black12,
          child: Text(
            numero,
            style: GoogleFonts.inter(
              color: activo ? Colors.white : Colors.black45,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          titulo,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: activo ? FontWeight.w600 : FontWeight.normal,
            color: activo ? Colors.black87 : Colors.black45,
          ),
        ),
      ],
    );
  }
}

/// Campo de texto con label, ícono e ítem de ayuda, estilo tarjeta.
class _CampoTexto extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? helper;

  const _CampoTexto({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '*',
              style: GoogleFonts.inter(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          style: GoogleFonts.inter(),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
            filled: true,
            fillColor: const Color(0xFFF3F4F6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: 12,
            ),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(
            helper!,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.black54),
          ),
        ],
      ],
    );
  }
}

/// Tarjeta seleccionable de plan (Basic / Premium)
class _PlanOption extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final String value;
  final String groupValue;
  final Color primary;
  final ValueChanged<String?> onChanged;

  const _PlanOption({
    required this.titulo,
    required this.subtitulo,
    required this.value,
    required this.groupValue,
    required this.primary,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final seleccionado = value == groupValue;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(value),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: seleccionado ? primary.withOpacity(0.06) : Colors.white,
          border: Border.all(
            color: seleccionado ? primary : Colors.black12,
            width: seleccionado ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Radio<String>(
                value: value,
                groupValue: groupValue,
                activeColor: primary,
                onChanged: onChanged,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
