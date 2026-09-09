// servicios_negocio_sheet.dart
//
// Bottom sheet "Servicios y precios" del negocio propio. Permite EDITAR
// y ELIMINAR los servicios (lista_precios jsonb del registro `negocios`)
// después del onboarding -- antes solo se podían definir al registrarse
// y quedaban congelados.
//
// Guardado: reemplazo completo de la lista vía RLS del dueño; si todas
// las filas quedan vacías se ELIMINA la lista (null en jsonb).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../services/negocio_state_service.dart';
import '../services/negocios_service.dart';

const Color _kVerde = Color(0xFF0D9488);

/// Punto de entrada desde el perfil (negocio activo).
Future<void> mostrarServiciosNegocioSheet(
  BuildContext context,
  Map<String, dynamic> negocio,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ServiciosNegocioSheet(negocio: negocio),
  );
}

class _ServiciosNegocioSheet extends StatefulWidget {
  final Map<String, dynamic> negocio;
  const _ServiciosNegocioSheet({required this.negocio});

  @override
  State<_ServiciosNegocioSheet> createState() => _ServiciosNegocioSheetState();
}

class _ServiciosNegocioSheetState extends State<_ServiciosNegocioSheet> {
  final _negociosService = NegociosService();
  bool _guardando = false;
  String? _aviso;

  /// Cada fila: controlador de nombre + controlador de precio.
  final List<(TextEditingController, TextEditingController)> _filas = [];

  @override
  void initState() {
    super.initState();
    final raw = widget.negocio['lista_precios'];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        _filas.add((
          TextEditingController(text: item['nombre']?.toString() ?? ''),
          TextEditingController(text: item['precio']?.toString() ?? ''),
        ));
      }
    }
  }

  @override
  void dispose() {
    for (final f in _filas) {
      f.$1.dispose();
      f.$2.dispose();
    }
    super.dispose();
  }

  void _avisoMsg(String msg) {
    if (!mounted) return;
    setState(() => _aviso = msg);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _aviso == msg) setState(() => _aviso = null);
    });
  }

  void _agregarFila() => setState(() => _filas.add((
        TextEditingController(),
        TextEditingController(),
      )));

  void _quitarFila(int idx) {
    setState(() {
      _filas[idx].$1.dispose();
      _filas[idx].$2.dispose();
      _filas.removeAt(idx);
    });
  }

  Future<void> _guardar() async {
    // Filas válidas: nombre no vacío (el precio es opcional).
    final lista = _filas
        .map((f) => {
              'nombre': f.$1.text.trim(),
              'precio': f.$2.text.trim(),
            })
        .where((m) => (m['nombre'] as String).isNotEmpty)
        .toList();

    setState(() => _guardando = true);
    try {
      await _negociosService.actualizarListaPrecios(
          widget.negocio['id_negocio'] as String, lista);
      // La mini-página y el perfil leen de acá: notificamos el cambio.
      await NegocioStateService.instance.refrescar();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(lista.isEmpty
              ? 'Lista de servicios eliminada.'
              : 'Servicios actualizados.')));
    } catch (e) {
      _avisoMsg('No se pudo guardar: '
          '${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esOscuro = theme.brightness == Brightness.dark;

    InputDecoration decoracion(String hint, IconData icon) => InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, size: 18),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest
              .withOpacity(esOscuro ? 0.4 : 1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        );

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: esOscuro ? theme.colorScheme.surface : Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Servicios y precios',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: theme.textTheme.bodyLarge?.color)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_aviso != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warm.withOpacity(esOscuro ? 0.2 : 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.warm.withOpacity(0.45)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 17, color: AppColors.warm),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_aviso!,
                                  style: GoogleFonts.inter(fontSize: 12.5)),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      'Edita o borra libremente. El precio es opcional.',
                      style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: theme.textTheme.bodySmall?.color),
                    ),
                    const SizedBox(height: 14),
                    ..._filas.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final par = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: par.$1,
                                style: GoogleFonts.inter(
                                    color: theme.textTheme.bodyLarge?.color),
                                decoration: decoracion(
                                    'Servicio (ej: Corte)', Icons.spa_outlined),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: par.$2,
                                keyboardType: TextInputType.text,
                                style: GoogleFonts.inter(
                                    color: theme.textTheme.bodyLarge?.color),
                                decoration: decoracion(
                                    '\$ Precio', Icons.attach_money_rounded),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Eliminar servicio',
                              onPressed: () => _quitarFila(idx),
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: Colors.redAccent),
                            ),
                          ],
                        ),
                      );
                    }),
                    TextButton.icon(
                      onPressed: _agregarFila,
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          color: _kVerde),
                      label: Text('Agregar servicio',
                          style: GoogleFonts.inter(
                              color: _kVerde, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 50,
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _kVerde,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _guardando ? null : _guardar,
                        icon: _guardando
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_rounded, size: 19),
                        label: Text(_guardando ? 'Guardando...' : 'Guardar cambios',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
