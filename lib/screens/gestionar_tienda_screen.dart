// gestionar_tienda_screen.dart
//
// INTEGRACIÓN CON TiendaStateService (2026-08):
//   - Al eliminar la tienda (_confirmarEliminarTienda), se llama a
//     TiendaStateService.instance.limpiar() justo después del delete
//     exitoso -- esto hace que MainShellScreen (y cualquier otra
//     pantalla que escuche el servicio) reaccione en el mismo frame,
//     sin esperar a que el usuario vuelva navegando ni a reiniciar la
//     app.
//   - Al cambiar logo/portada/datos básicos, además de actualizar el
//     Map local `_tienda` de esta pantalla, se refleja también en
//     TiendaStateService para que el resto de la app (panel del
//     vendedor, mi perfil) se entere sin esperar a volver atrás.

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/storage_service.dart';
import '../services/tiendas_service.dart';
import '../services/tienda_state_service.dart';
import 'gestionar_planes_screen.dart';
import 'gestionar_ventas_screen.dart';

class GestionarTiendaScreen extends StatefulWidget {
  final Map<String, dynamic> tienda;

  const GestionarTiendaScreen({
    super.key,
    required this.tienda,
  });

  @override
  State<GestionarTiendaScreen> createState() => _GestionarTiendaScreenState();
}

class _GestionarTiendaScreenState extends State<GestionarTiendaScreen> {
  final _storageService = StorageService();
  final _tiendasService = TiendasService();
  final _formKey = GlobalKey<FormState>();

  late Map<String, dynamic> _tienda;
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _telefonoCtrl;
  late final TextEditingController _provinciaCtrl;
  late final TextEditingController _municipioCtrl;
  late final TextEditingController _descripcionCtrl;
  String? _categoriaSeleccionada;

  bool _procesando = false;
  bool _subiendoLogo = false;
  bool _subiendoPortada = false;
  bool _editandoDatos = false;

  @override
  void initState() {
    super.initState();
    _tienda = Map<String, dynamic>.from(widget.tienda);
    _nombreCtrl = TextEditingController(text: _tienda['nombre'] ?? '');
    _telefonoCtrl =
        TextEditingController(text: _tienda['telefono_whatsapp'] ?? '');
    _provinciaCtrl = TextEditingController(text: _tienda['provincia'] ?? '');
    _municipioCtrl = TextEditingController(text: _tienda['municipio'] ?? '');
    _descripcionCtrl =
        TextEditingController(text: _tienda['descripcion'] ?? '');
    _categoriaSeleccionada = _tienda['categoria'] as String?;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _provinciaCtrl.dispose();
    _municipioCtrl.dispose();
    _descripcionCtrl.dispose();
    super.dispose();
  }

  Future<void> _cambiarLogo() async {
    final archivo = await _storageService.elegirFoto();
    if (archivo == null) return;
    setState(() => _subiendoLogo = true);
    try {
      final url = await _storageService.subirLogoTienda(
        archivo: archivo,
        idTienda: _tienda['id_tienda'],
      );
      await _tiendasService.actualizarLogoTienda(
        idTienda: _tienda['id_tienda'],
        logoUrl: url,
      );
      if (mounted) setState(() => _tienda['logo_url'] = url);
      // Propaga el cambio al resto de la app sin esperar a volver atrás.
      TiendaStateService.instance.actualizarLocal({'logo_url': url});
    } catch (e) {
      _mostrarError('No se pudo subir el logo: $e');
    } finally {
      if (mounted) setState(() => _subiendoLogo = false);
    }
  }

  Future<void> _cambiarPortada() async {
    final archivo = await _storageService.elegirFoto();
    if (archivo == null) return;
    setState(() => _subiendoPortada = true);
    try {
      final url = await _storageService.subirPortadaTienda(
        archivo: archivo,
        idTienda: _tienda['id_tienda'],
      );
      await _tiendasService.actualizarPortadaTienda(
        idTienda: _tienda['id_tienda'],
        portadaUrl: url,
      );
      if (mounted) setState(() => _tienda['imagen_portada'] = url);
      TiendaStateService.instance.actualizarLocal({'imagen_portada': url});
    } catch (e) {
      _mostrarError('No se pudo subir la portada: $e');
    } finally {
      if (mounted) setState(() => _subiendoPortada = false);
    }
  }

  Future<void> _guardarDatos() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _procesando = true);
    try {
      await _tiendasService.actualizarTienda(
        idTienda: _tienda['id_tienda'],
        nombre: _nombreCtrl.text.trim(),
        telefonoWhatsapp: _telefonoCtrl.text.trim(),
        provincia: _provinciaCtrl.text.trim(),
        municipio: _municipioCtrl.text.trim(),
        descripcion: _descripcionCtrl.text.trim(),
        categoria: _categoriaSeleccionada,
      );
      final datosActualizados = {
        'nombre': _nombreCtrl.text.trim(),
        'telefono_whatsapp': _telefonoCtrl.text.trim(),
        'provincia': _provinciaCtrl.text.trim(),
        'municipio': _municipioCtrl.text.trim(),
        'descripcion': _descripcionCtrl.text.trim(),
        'categoria': _categoriaSeleccionada,
      };
      if (mounted) {
        setState(() {
          _tienda.addAll(datosActualizados);
          _editandoDatos = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos actualizados ✅')),
        );
      }
      // FIX (persistencia): antes había que salir y volver a entrar a
      // la app para que el nombre/teléfono/ubicación nuevos aparecieran
      // en el resto de la app (panel del vendedor, mi perfil). Ahora se
      // propaga en el momento.
      TiendaStateService.instance.actualizarLocal(datosActualizados);
    } catch (e) {
      _mostrarError('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _mostrarError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _confirmarEliminarTienda() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Eliminar tienda?'),
        content: const Text(
          'Esta acción es permanente. Se borrarán todos tus productos '
          'y no se puede deshacer.',
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

    setState(() => _procesando = true);
    try {
      final idTienda = _tienda['id_tienda'];
      await _storageService.borrarArchivosDeTienda(idTienda);
      await supabase.from('tiendas').delete().eq('id_tienda', idTienda);

      // FIX (persistencia) -- EL CAMBIO CLAVE: antes, al volver a
      // MainShellScreen, la pestaña "Mi Tienda" seguía mostrando el
      // panel del vendedor con datos viejos hasta reiniciar la app,
      // porque nadie le avisaba que la tienda ya no existía. Ahora se
      // limpia el estado compartido ANTES de cerrar esta pantalla --
      // para cuando el pop() llega a MainShellScreen, el
      // AnimatedBuilder que escucha TiendaStateService ya reconstruyó
      // esa pestaña mostrando el CTA de "Hacerte vendedor".
      TiendaStateService.instance.limpiar();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tienda eliminada')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _mostrarError('No se pudo eliminar la tienda: $e');
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final colorSuperficie = esOscuro
        ? AppColors.cardTransparentDark
        : AppColors.cardTransparentLight;
    final colorBorde = (esOscuro ? AppColors.borderDark : AppColors.borderLight)
        .withOpacity(0.6);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Gestionar Tienda'),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: AbsorbPointer(
        absorbing: _procesando,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _buildPortadaYLogo(primary, esOscuro),
                const SizedBox(height: 20),
                _buildEstadisticas(esOscuro),
                const SizedBox(height: 16),
                _buildDatosBasicos(
                    primary, esOscuro, colorSuperficie, colorBorde),
                const SizedBox(height: 16),
                _buildAccesos(primary, esOscuro, colorSuperficie, colorBorde),
                const SizedBox(height: 24),
                _buildEliminar(esOscuro),
              ],
            ),
            if (_procesando)
              ColoredBox(
                color: Colors.black.withOpacity(0.35),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortadaYLogo(Color primary, bool esOscuro) {
    final portadaUrl = _tienda['imagen_portada'] as String?;
    final logoUrl = _tienda['logo_url'] as String?;
    final placeholder =
        esOscuro ? const Color(0xFF2A2A2A) : Colors.grey.shade300;
    final anilloLogo = esOscuro ? AppColors.surfaceDark : Colors.white;

    return SizedBox(
      height: 196,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: _subiendoPortada ? null : _cambiarPortada,
            child: Container(
              height: 156,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(esOscuro ? 0.35 : 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                  BoxShadow(
                    color: primary.withOpacity(0.10),
                    blurRadius: 30,
                    offset: const Offset(0, 16),
                    spreadRadius: -8,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (portadaUrl != null && portadaUrl.isNotEmpty)
                      Image.network(portadaUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: placeholder))
                    else
                      Container(color: placeholder),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.32),
                          ],
                        ),
                      ),
                    ),
                    if (_subiendoPortada)
                      const Center(
                          child: CircularProgressIndicator(color: Colors.white))
                    else
                      const Center(
                        child: Icon(Icons.camera_alt_outlined,
                            color: Colors.white, size: 26),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 0,
            child: GestureDetector(
              onTap: _subiendoLogo ? null : _cambiarLogo,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: anilloLogo, width: 3.5),
                  color: placeholder,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (logoUrl != null && logoUrl.isNotEmpty)
                        Image.network(logoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Icon(Icons.storefront, color: primary))
                      else
                        Icon(Icons.storefront, color: primary),
                      if (_subiendoLogo)
                        const ColoredBox(
                          color: Colors.black38,
                          child: Center(
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            ),
                          ),
                        )
                      else
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: anilloLogo,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.camera_alt,
                                size: 14, color: primary),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadisticas(bool esOscuro) {
    final puntosTotales = _tienda['puntos_totales'] ?? 0;
    final puntosSemanales = _tienda['puntos_semanales'] ?? 0;
    final estrellas =
        ((_tienda['promedio_estrellas'] as num?) ?? 0).toStringAsFixed(1);
    final totalValoraciones = _tienda['total_valoraciones'] ?? 0;

    return Row(
      children: [
        Expanded(
          child: _statBox('$puntosTotales', 'Puntos totales',
              Icons.stars_rounded, Colors.amber.shade700, esOscuro),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statBox('$puntosSemanales', 'Puntos semana',
              Icons.local_fire_department_rounded, Colors.deepOrange, esOscuro),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statBox('$estrellas ⭐', '$totalValoraciones reseñas',
              Icons.reviews_outlined, AppColors.primary, esOscuro),
        ),
      ],
    );
  }

  Widget _statBox(String valor, String etiqueta, IconData icon, Color color,
      bool esOscuro) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(esOscuro ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(esOscuro ? 0.3 : 0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(valor,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 2),
          Text(etiqueta,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5, color: AppColors.inkSecundarioLight)),
        ],
      ),
    );
  }

  Widget _buildDatosBasicos(
      Color primary, bool esOscuro, Color colorSuperficie, Color colorBorde) {
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor:
              esOscuro ? Colors.white.withOpacity(0.06) : Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(kCardRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: colorSuperficie,
            borderRadius: BorderRadius.circular(kCardRadius),
            border: Border.all(color: colorBorde),
          ),
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Datos de la tienda',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    TextButton(
                      onPressed: _procesando
                          ? null
                          : () {
                              if (_editandoDatos) {
                                _guardarDatos();
                              } else {
                                setState(() => _editandoDatos = true);
                              }
                            },
                      child: Text(_editandoDatos ? 'Guardar' : 'Editar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_editandoDatos) ...[
                  TextFormField(
                    controller: _nombreCtrl,
                    decoration: deco('Nombre'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _telefonoCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: deco('Teléfono (WhatsApp)'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _provinciaCtrl,
                          decoration: deco('Provincia'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Requerido'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _municipioCtrl,
                          decoration: deco('Municipio'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Requerido'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descripcionCtrl,
                    maxLines: 3,
                    decoration: deco('Descripción'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _categoriaSeleccionada,
                    isExpanded: true,
                    decoration: deco('Categoría'),
                    items: kCategoriasTienda
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c,
                                  overflow: TextOverflow.ellipsis, maxLines: 1),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _categoriaSeleccionada = v),
                    validator: (v) =>
                        v == null ? 'Selecciona una categoría' : null,
                  ),
                ] else ...[
                  _filaDato(Icons.storefront_outlined, _tienda['nombre'] ?? ''),
                  _filaDato(
                      Icons.chat_outlined, _tienda['telefono_whatsapp'] ?? ''),
                  _filaDato(Icons.location_on_outlined,
                      '${_tienda['municipio'] ?? ''}, ${_tienda['provincia'] ?? ''}'),
                  if ((_tienda['descripcion'] ?? '').toString().isNotEmpty)
                    _filaDato(Icons.notes_outlined, _tienda['descripcion']),
                  if ((_tienda['categoria'] ?? '').toString().isNotEmpty)
                    _filaDato(Icons.category_outlined, _tienda['categoria']),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filaDato(IconData icon, String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.inkSecundarioLight),
          const SizedBox(width: 10),
          Expanded(
            child:
                Text(texto, style: GoogleFonts.plusJakartaSans(fontSize: 13.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildAccesos(
      Color primary, bool esOscuro, Color colorSuperficie, Color colorBorde) {
    return Column(
      children: [
        _accesoTile(
          icono: Icons.receipt_long_outlined,
          color: primary,
          titulo: 'Gestionar Ventas',
          subtitulo: 'Solicitudes pendientes y ventas del mes',
          colorSuperficie: colorSuperficie,
          colorBorde: colorBorde,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GestionarVentasScreen(tienda: _tienda),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _accesoTile(
          icono: Icons.inventory_2_outlined,
          color: primary,
          titulo: 'Gestionar Productos',
          subtitulo: 'Editar, ocultar o eliminar productos',
          colorSuperficie: colorSuperficie,
          colorBorde: colorBorde,
          onTap: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 12),
        _accesoTile(
          icono: Icons.workspace_premium_outlined,
          color: AppColors.primary,
          titulo: 'Cambiar Plan',
          subtitulo: 'Plan actual: ${_tienda['plan'] ?? 'Sin plan'}',
          colorSuperficie: colorSuperficie,
          colorBorde: colorBorde,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GestionarPlanesScreen(tienda: _tienda),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _accesoTile({
    required IconData icono,
    required Color color,
    required String titulo,
    required String subtitulo,
    required Color colorSuperficie,
    required Color colorBorde,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kCardRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: colorSuperficie,
          child: InkWell(
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kCardRadius),
                border: Border.all(color: colorBorde),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withOpacity(0.12),
                  child: Icon(icono, color: color),
                ),
                title: Text(titulo,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600)),
                subtitle: Text(subtitulo,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5, color: AppColors.inkSecundarioLight)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onTap,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEliminar(bool esOscuro) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kCardRadius),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(esOscuro ? 0.14 : 0.05),
          borderRadius: BorderRadius.circular(kCardRadius),
          border:
              Border.all(color: Colors.red.withOpacity(esOscuro ? 0.35 : 0.15)),
        ),
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Colors.red,
            child: Icon(Icons.delete_outline, color: Colors.white),
          ),
          title: Text(
            'Eliminar tienda',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600, color: Colors.red),
          ),
          subtitle: const Text('Acción permanente'),
          onTap: _confirmarEliminarTienda,
        ),
      ),
    );
  }
}
