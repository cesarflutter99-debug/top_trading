// afiliado_registro_screen.dart
//
// Formulario para que cualquier usuario logueado se registre como
// afiliado. Genera un código único de 6 caracteres y avisa al admin
// por WhatsApp (con el código incluido, para que lo pueda buscar).
//
// NOTA DE DIAGNÓSTICO (temporal): se agregaron debugPrint() dentro del
// try/catch del aviso por WhatsApp, para descubrir por qué no se
// estaba abriendo -- antes el catch era silencioso (catch (_) {}) y
// ocultaba el error real. Una vez confirmada la causa, se puede volver
// a dejar el catch silencioso o mostrar un SnackBar al usuario, según
// se decida.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/tiendas_service.dart';
import '../services/whatsapp_service.dart';

class AfiliadoRegistroScreen extends StatefulWidget {
  const AfiliadoRegistroScreen({super.key});

  @override
  State<AfiliadoRegistroScreen> createState() => _AfiliadoRegistroScreenState();
}

class _AfiliadoRegistroScreenState extends State<AfiliadoRegistroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tiendasService = TiendasService();
  final _whatsappService = WhatsappService();

  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _tarjetaCtrl = TextEditingController();

  bool _guardando = false;
  bool _verificandoExistente = true;
  Map<String, dynamic>? _miAfiliado;

  @override
  void initState() {
    super.initState();
    _verificarSiYaEsAfiliado();
  }

  Future<void> _verificarSiYaEsAfiliado() async {
    try {
      final existente = await _tiendasService.obtenerMiAfiliado();
      if (mounted) {
        setState(() {
          _miAfiliado = existente;
          _verificandoExistente = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _verificandoExistente = false);
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _tarjetaCtrl.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);
    try {
      final afiliado = await _tiendasService.registrarAfiliado(
        nombre: _nombreCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
        numeroTarjeta: _tarjetaCtrl.text.trim(),
      );

      // Avisamos al admin por WhatsApp con el código, si hay un
      // número activo configurado. Si no hay, el registro ya quedó
      // guardado igual -- no bloqueamos el flujo por esto.
      try {
        final telefonoAdmin =
            await _tiendasService.obtenerContactoWhatsappActivo();
        debugPrint('DEBUG AFILIADO: telefonoAdmin = $telefonoAdmin');
        if (telefonoAdmin != null) {
          await _whatsappService.notificarNuevoAfiliado(
            telefonoAdmin: telefonoAdmin,
            nombre: _nombreCtrl.text.trim(),
            telefonoAfiliado: _telefonoCtrl.text.trim(),
            codigo: afiliado['codigo'] as String,
          );
          debugPrint('DEBUG AFILIADO: notificarNuevoAfiliado terminó sin '
              'lanzar excepción (WhatsApp debería haberse abierto)');
        } else {
          debugPrint('DEBUG AFILIADO: telefonoAdmin llegó null -- no hay '
              'ningún contacto activo en contactos_whatsapp según la app');
        }
      } catch (e, st) {
        debugPrint('DEBUG AFILIADO: error real al notificar por WhatsApp '
            '-> $e');
        debugPrint('DEBUG AFILIADO: stacktrace -> $st');
      }

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kCardRadius)),
            title: const Text('¡Ya eres afiliado! 🎉'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tu código único es:'),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.mostazaLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.warm),
                  ),
                  child: Text(
                    afiliado['codigo'] as String,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      color: AppColors.warm,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Compártelo con nuevos vendedores. Cuando alguien lo '
                  'use al crear o renovar su tienda, tú ganas comisión.',
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensajeAmigable(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Traduce errores técnicos (PostgrestException, RLS, etc.) a
  /// mensajes que un usuario normal pueda entender -- nunca se debe
  /// mostrar el texto crudo de una excepción en pantalla.
  String _mensajeAmigable(Object e) {
    if (e is PostgrestException) {
      switch (e.code) {
        case '23505': // unique_violation -- user_id ya tiene afiliado
          return 'Ya estás registrado como afiliado con esta cuenta.';
        case '42501': // RLS forbidden
          return 'No tienes permiso para completar el registro. '
              'Cierra sesión y vuelve a intentar.';
        default:
          return 'No se pudo completar el registro. Intenta de nuevo.';
      }
    }
    return 'No se pudo completar el registro. Intenta de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    if (_verificandoExistente) {
      return Scaffold(
        appBar: AppBar(title: const Text('Programa de Afiliados')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_miAfiliado != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Programa de Afiliados')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_rounded, size: 56, color: AppColors.warm),
              const SizedBox(height: 16),
              Text('Ya eres afiliado',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w800, fontSize: 20)),
              const SizedBox(height: 20),
              const Text('Tu código único es:'),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.mostazaLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.warm),
                ),
                child: Text(
                  _miAfiliado!['codigo'] as String,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    color: AppColors.warm,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Saldo actual: ${_miAfiliado!['saldo_cup'] ?? 0} CUP',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Programa de Afiliados')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(kCardRadius),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('¿Cómo funciona?',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 8),
                    const Text(
                      '• Recibes un código único para compartir.\n'
                      '• Cada tienda nueva que use tu código al crearse '
                      'o renovar su plan te da comisión.\n'
                      '• Tu código solo puede usarse UNA vez por tienda '
                      '(la misma tienda no puede reutilizarlo).\n'
                      '• La comisión se acredita cuando el admin aprueba '
                      'esa tienda o plan.',
                      style: TextStyle(height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telefonoCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono (WhatsApp)',
                  hintText: '5355XXXXXXX',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tarjetaCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Número de tarjeta (para pagos)',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _guardando ? null : _registrar,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _guardando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Registrarme como afiliado'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
