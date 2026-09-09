// negocio_screen.dart
//
// Mini-página del negocio (barbería, taller, joyería...): portada,
// logo, descripción, horario, lista de precios opcional y botones de
// contacto (WhatsApp). Sin productos ni carrito -- el objetivo es que
// el anuncio tenga a dónde llevar al usuario.
// Ruta pública: /negocio/:idNegocio (se puede abrir sin sesión).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/negocios_service.dart';
import '../services/negocio_state_service.dart';
import '../services/cache_offline_service.dart';
import '../widgets/servicios_negocio_sheet.dart';

// Mismo verde que el borde de los anuncios de negocio (tarjeta_anuncio).
const Color _kVerdeNegocio = Color(0xFF0D9488);

const List<String> _kDiasClave = [
  'lun',
  'mar',
  'mie',
  'jue',
  'vie',
  'sab',
  'dom'
];
const List<String> _kDiasLabel = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo'
];

class NegocioScreen extends StatefulWidget {
  final String idNegocio;
  const NegocioScreen({super.key, required this.idNegocio});

  @override
  State<NegocioScreen> createState() => _NegocioScreenState();
}

class _NegocioScreenState extends State<NegocioScreen> {
  final _service = NegociosService();
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.obtenerNegocio(widget.idNegocio);
  }

  // ---------- parsing defensivo del jsonb de horario ----------

  Map<String, dynamic>? get _horario {
    final raw = _datos?['horario'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decod = jsonDecode(raw);
        if (decod is Map) return Map<String, dynamic>.from(decod);
      } catch (_) {}
    }
    return null;
  }

  List<Map<String, dynamic>> get _precios {
    final raw = _datos?['lista_precios'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  /// Devuelve "09:00 - 17:00" o null si ese día está cerrado.
  String? _franjaDia(String clave) {
    final dia = _horario?[clave];
    if (dia == null) return null;
    if (dia is Map) {
      final m = Map<String, dynamic>.from(dia);
      if (m['descanso'] == true || m['cerrado'] == true) return null;
      final abre = m['abre']?.toString();
      final cierra = m['cierra']?.toString();
      if (abre != null &&
          abre.isNotEmpty &&
          cierra != null &&
          cierra.isNotEmpty) {
        return '$abre - $cierra';
      }
    }
    return null;
  }

  Map<String, dynamic>? _datosCache;
  Map<String, dynamic>? get _datos => _datosCache;

  Future<void> _abrirWhatsapp(String telefono, String nombreNegocio) async {
    final limpio = telefono.replaceAll(RegExp(r'[^\d]'), '');
    final mensaje = Uri.encodeComponent(
        'Hola! Vi "$nombreNegocio" en Al Lado y quiero más información.');
    final url = Uri.parse('https://wa.me/$limpio?text=$mensaje');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp')),
      );
    }
  }

  /// Confirmación + borrado del negocio propio. Persistente: la fila se
  /// elimina en Supabase y en cascada sus anuncios/permisos/compras.
  Future<void> _confirmarEliminar(
      BuildContext context, Map<String, dynamic> datos) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('¿Eliminar "${datos['nombre']}"?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        content: Text(
          'Se borrará tu negocio y TODO lo asociado: anuncios, paquetes '
          'comprados y su historial. Esta acción no se puede deshacer.',
          style: GoogleFonts.plusJakartaSans(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar definitivamente'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      // FIX (2026-08): antes esto no verificaba el resultado del
      // delete. En Supabase/PostgREST, si la política RLS bloquea la
      // fila, el DELETE NO lanza excepción -- simplemente borra 0
      // filas y responde 200 OK. Por eso el usuario veía "Tu negocio
      // fue eliminado" pero al volver a entrar el negocio seguía ahí:
      // el catch nunca se disparaba porque no había ningún error que
      // atrapar. Ahora se pide de vuelta la fila borrada con
      // .select() -- si vuelve vacía, sabemos que RLS bloqueó el
      // borrado (o la fila ya no existía) y avisamos explícitamente
      // en vez de mentir con un éxito falso.
      final borrados = await supabase
          .from('negocios')
          .delete()
          .eq('id_negocio', widget.idNegocio)
          .select('id_negocio');

      if (borrados.isEmpty) {
        throw Exception(
            'No se pudo eliminar: no tienes permiso sobre este negocio o '
            'ya no existe. Si el problema persiste, revisa que la '
            'política de seguridad (RLS) "neg_delete" esté aplicada en '
            'Supabase (parche_negocio_eliminar.sql).');
      }

      // El CTA "Promociona tu negocio" y el resto de la app se enteran
      // al instante (fuente única de verdad).
      await NegocioStateService.instance.refrescar();
      CacheOfflineService.instance.eliminar('negocio_${widget.idNegocio}');
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tu negocio fue eliminado.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${e.toString().replaceFirst('Exception: ', '')}'),
            duration: const Duration(seconds: 6)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).scaffoldBackgroundColor
          : const Color(0xFFFAFAF9),
      appBar: AppBar(title: const Text('Negocio')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final datos = snapshot.data;
          if (datos == null || datos['estado'] != 'activo') {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.storefront,
                        size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 14),
                    Text(
                      'Este negocio no está disponible',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ],
                ),
              ),
            );
          }
          _datosCache = datos;
          return _buildContenido(context, datos);
        },
      ),
    );
  }

  Widget _buildContenido(BuildContext context, Map<String, dynamic> datos) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final texto = oscuro ? const Color(0xFFF5F5F4) : AppColors.ink;
    final textoSec =
        oscuro ? const Color(0xFFA8A29E) : AppColors.inkSecundarioLight;

    final nombre = datos['nombre']?.toString() ?? '';
    final categoria = datos['categoria']?.toString();
    final descripcion = datos['descripcion']?.toString();
    final logo = datos['logo_url'] as String?;
    final portada = datos['portada_url'] as String?;
    final whatsapp = datos['whatsapp']?.toString();
    final direccion = datos['direccion']?.toString();

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        // ---------- Portada + logo ----------
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              height: 150,
              width: double.infinity,
              color: _kVerdeNegocio.withOpacity(0.12),
              child: (portada != null && portada.isNotEmpty)
                  ? Image.network(
                      portada,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    )
                  : null,
            ),
            Positioned(
              left: 20,
              bottom: -30,
              child: Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: _kVerdeNegocio, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: (logo != null && logo.isNotEmpty)
                      ? Image.network(
                          logo,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _logoPlaceholder(),
                        )
                      : _logoPlaceholder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 42),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nombre,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 22, fontWeight: FontWeight.w800, color: texto)),
              if (categoria != null && categoria.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kVerdeNegocio.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    categoria,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _kVerdeNegocio,
                    ),
                  ),
                ),
              ],
              if (descripcion != null && descripcion.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(descripcion,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13.5, height: 1.45, color: textoSec)),
              ],
              if (direccion != null && direccion.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.place_rounded, size: 15, color: _kVerdeNegocio),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(direccion,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5, color: textoSec)),
                    ),
                  ],
                ),
              ],

              // ---------- Gestión del dueño (solo visible para ti) ----------
              // FIX (2026-08): los servicios solo se definían en el
              // onboarding y quedaban congelados. Ahora el dueño puede
              // editarlos/eliminarlos también desde su propia mini-página.
              if (supabase.auth.currentUser?.id != null &&
                  supabase.auth.currentUser!.id == datos['id_dueno']) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kVerdeNegocio,
                      side: BorderSide(color: _kVerdeNegocio.withOpacity(0.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      await mostrarServiciosNegocioSheet(context, datos);
                      if (mounted) {
                        setState(() => _future =
                            _service.obtenerNegocio(widget.idNegocio));
                      }
                    },
                    icon: const Icon(Icons.spa_outlined, size: 18),
                    label: Text('Editar servicios y precios',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
                const SizedBox(height: 8),
                // Eliminar negocio: borrado REAL y persistente; los
                // anuncios, permisos y compras se van en cascada (FK).
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () => _confirmarEliminar(context, datos),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text('Eliminar mi negocio',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
              ],

              // ---------- Botón WhatsApp ----------
              if (whatsapp != null && whatsapp.trim().isNotEmpty) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _abrirWhatsapp(whatsapp, nombre),
                    icon: const Icon(Icons.chat_rounded, size: 19),
                    label: const Text('Contactar por WhatsApp'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _kVerdeNegocio,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],

              // ---------- Horario ----------
              if (_horario != null) ...[
                const SizedBox(height: 24),
                _tarjetaSeccion(
                  icono: Icons.schedule_rounded,
                  titulo: 'Horario',
                  hijo: Column(
                    children: List.generate(7, (i) {
                      // DateTime.weekday: 1=lunes ... 7=domingo
                      final hoy = DateTime.now().weekday - 1 == i;
                      final franja = _franjaDia(_kDiasClave[i]);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 84,
                              child: Text(_kDiasLabel[i],
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12.5,
                                    fontWeight:
                                        hoy ? FontWeight.w800 : FontWeight.w500,
                                    color: hoy ? _kVerdeNegocio : textoSec,
                                  )),
                            ),
                            Expanded(
                              child: Text(
                                franja ?? 'Cerrado',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5,
                                  fontWeight:
                                      hoy ? FontWeight.w700 : FontWeight.w400,
                                  color:
                                      franja == null ? Colors.redAccent : texto,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ],

              // ---------- Lista de precios (opcional) ----------
              if (_precios.isNotEmpty) ...[
                const SizedBox(height: 16),
                _tarjetaSeccion(
                  icono: Icons.receipt_long_rounded,
                  titulo: 'Precios',
                  hijo: Column(
                    children: _precios.map((p) {
                      final item = (p['item'] ?? p['nombre'] ?? '').toString();
                      final precio =
                          (p['precio'] ?? p['precio_texto'] ?? '').toString();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(item,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12.5, color: texto)),
                            ),
                            Text(precio,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: _kVerdeNegocio,
                                )),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _logoPlaceholder() => Container(
        color: _kVerdeNegocio.withOpacity(0.10),
        child: Icon(Icons.content_cut_rounded, size: 30, color: _kVerdeNegocio),
      );

  Widget _tarjetaSeccion({
    required IconData icono,
    required String titulo,
    required Widget hijo,
  }) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: oscuro ? Theme.of(context).colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: _kVerdeNegocio.withOpacity(oscuro ? 0.25 : 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 16, color: _kVerdeNegocio),
              const SizedBox(width: 6),
              Text(titulo,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          hijo,
        ],
      ),
    );
  }
}
