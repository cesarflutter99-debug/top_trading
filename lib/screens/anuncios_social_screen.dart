// anuncios_social_screen.dart
//
// Feed social de anuncios, estilo Facebook: tarjetas grandes en una
// sola columna, con foto, título, descripción, botón de "me gusta"
// (con contador visible en la tarjeta), botón de compartir, y al
// tocar la tarjeta se abre el detalle completo (misma info + like +
// compartir desde ahí también).
//
// AJUSTAR NOMBRES DE COLUMNA: esta pantalla consulta la tabla
// `anuncios` directamente por Supabase (no pasa por AnunciosService
// porque ese archivo no estaba disponible al escribir esto). Los
// nombres de columna usados abajo (titulo, texto, imagen_url,
// precio_usd, whatsapp, nombre_anunciante, id_anuncio, creado_en,
// activo) son la mejor suposición según el resto del código de la
// app (ver standalone_anuncio_screen.dart) -- revisa y ajusta si tu
// esquema real difiere.
//
// Requiere sql/anuncio_likes.sql aplicado en Supabase.
//
// Ruta sugerida: /anuncios-social (agregar en tu router.dart):
//   GoRoute(
//     path: '/anuncios-social',
//     builder: (context, state) => const AnunciosSocialScreen(),
//   ),

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/app_links_config.dart';
import '../core/auth_guard.dart';
import '../core/palabras_prohibidas.dart';
import '../core/supabase_client.dart';
import '../services/anuncio_comentarios_service.dart';
import '../services/anuncio_likes_service.dart';

const int _kTamPagina = 15;

class AnunciosSocialScreen extends StatefulWidget {
  const AnunciosSocialScreen({super.key});

  @override
  State<AnunciosSocialScreen> createState() => _AnunciosSocialScreenState();
}

class _AnunciosSocialScreenState extends State<AnunciosSocialScreen> {
  final _likesService = AnuncioLikesService();
  final _busquedaCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounceBusqueda;

  List<Map<String, dynamic>> _anuncios = [];
  final Set<String> _misLikes = {};
  bool _cargando = true;
  bool _cargandoMas = false;
  String? _error;

  int _offset = 0;
  bool _masDatos = true;
  bool _usarInteracciones = true;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _cargar();
  }

  @override
  void dispose() {
    _debounceBusqueda?.cancel();
    _busquedaCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.extentAfter < 400) {
      _cargarPagina();
    }
  }

  void _onBusquedaCambiada(String _) {
    _debounceBusqueda?.cancel();
    _debounceBusqueda = Timer(const Duration(milliseconds: 400), _cargar);
  }

  // En orden de interacciones el marketplace es un "ranking" (los más
  // comentados/reaccionados arriba). La columna `interacciones` viene
  // del parche SQL; si aún no existe, caemos a creado_en desc.
  Future<List<Map<String, dynamic>>> _consultaPagina(int offset) async {
    final b = _busquedaCtrl.text.trim();

    try {
      var q = supabase
          .from('anuncios')
          .select()
          .eq('estado', 'aprobado');
      if (b.isNotEmpty) {
        q = q.or('titulo.ilike.%$b%,texto.ilike.%$b%,etiqueta.ilike.%$b%');
      }
      final transform = q
          .order('interacciones', ascending: false)
          .order('creado_en', ascending: false);
      return List<Map<String, dynamic>>.from(
        await transform.range(offset, offset + _kTamPagina - 1),
      );
    } catch (e) {
      if (_usarInteracciones) {
        _usarInteracciones = false;
      }
      var q = supabase
          .from('anuncios')
          .select()
          .eq('estado', 'aprobado');
      if (b.isNotEmpty) {
        q = q.or('titulo.ilike.%$b%,texto.ilike.%$b%,etiqueta.ilike.%$b%');
      }
      final transform = q.order('creado_en', ascending: false);
      return List<Map<String, dynamic>>.from(
        await transform.range(offset, offset + _kTamPagina - 1),
      );
    }
  }

  Future<void> _cargar() => _cargarPagina(reset: true);

  Future<void> _cargarPagina({bool reset = false}) async {
    if (!reset && (_cargandoMas || !_masDatos)) return;
    if (reset) {
      _offset = 0;
      _masDatos = true;
      _anuncios = [];
      _misLikes.clear();
    }
    final esPrimera = _anuncios.isEmpty;
    setState(() {
      if (esPrimera) {
        _cargando = true;
        _error = null;
      } else {
        _cargandoMas = true;
      }
    });

    try {
      final datos = await _consultaPagina(_offset);
      final nuevos = datos.where((a) {
        final id = a['id_anuncio']?.toString();
        return id == null || !_anuncios.any((x) => x['id_anuncio']?.toString() == id);
      }).toList();
      final nuevosIds = nuevos
          .map((a) => a['id_anuncio']?.toString())
          .whereType<String>()
          .toList();
      final misLikes =
          nuevosIds.isEmpty ? <String>{} : await _likesService.misLikesDeLista(nuevosIds);

      if (!mounted) return;
      setState(() {
        _anuncios = [..._anuncios, ...nuevos];
        _misLikes.addAll(misLikes);
        _offset += nuevos.length;
        _masDatos = datos.length >= _kTamPagina;
        _cargando = false;
        _cargandoMas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
        _cargandoMas = false;
      });
    }
  }

  Future<void> _alternarLike(Map<String, dynamic> anuncio) async {
    if (!await requireAuth(context)) return;
    final id = anuncio['id_anuncio']?.toString();
    if (id == null) return;

    final teniaLike = _misLikes.contains(id);
    final totalActual = (anuncio['total_likes'] as num?)?.toInt() ?? 0;

    // Optimista: actualizamos la UI antes de esperar la respuesta del
    // servidor, y revertimos si falla.
    setState(() {
      if (teniaLike) {
        _misLikes.remove(id);
        anuncio['total_likes'] = (totalActual - 1).clamp(0, 1 << 30);
      } else {
        _misLikes.add(id);
        anuncio['total_likes'] = totalActual + 1;
      }
    });

    try {
      await _likesService.alternar(id, actualmenteConLike: teniaLike);
    } catch (e) {
      if (!mounted) return;
      // Revertir en caso de error.
      setState(() {
        if (teniaLike) {
          _misLikes.add(id);
          anuncio['total_likes'] = totalActual;
        } else {
          _misLikes.remove(id);
          anuncio['total_likes'] = totalActual;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo procesar el like: $e')),
      );
    }
  }

  void _compartir(Map<String, dynamic> anuncio) {
    final titulo = (anuncio['titulo'] as String?)?.trim() ?? 'Anuncio';
    final id = anuncio['id_anuncio']?.toString() ?? '';
    final link = kEnlaceAnuncio(id);
    Share.share('Mira este anuncio en Al Lado: "$titulo"\n$link');
  }

  Future<void> _contactar(Map<String, dynamic> anuncio) async {
    final telefono = (anuncio['whatsapp'] as String?)?.trim();
    if (telefono == null || telefono.isEmpty) return;
    final titulo = (anuncio['titulo'] as String?)?.trim() ?? '';
    final mensaje = Uri.encodeComponent(
        'Hola! Vi tu anuncio "$titulo" en Al Lado y quiero más información.');
    final url = Uri.parse('https://wa.me/$telefono?text=$mensaje');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp')),
      );
    }
  }

  void _abrirDetalle(Map<String, dynamic> anuncio) {
    final id = anuncio['id_anuncio']?.toString();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnuncioDetalleScreen(
          anuncio: anuncio,
          tieneLike: id != null && _misLikes.contains(id),
          onLikeCambiado: (conLike) {
            if (id == null) return;
            setState(() {
              final totalActual = (anuncio['total_likes'] as num?)?.toInt() ?? 0;
              if (conLike) {
                _misLikes.add(id);
                anuncio['total_likes'] = totalActual +
                    (_misLikes.contains(id) ? 0 : 1);
              } else {
                _misLikes.remove(id);
              }
            });
          },
          onTotalComentariosCambiado: (total) {
            if (!mounted) return;
            setState(() => anuncio['total_comentarios'] = total);
          },
        ),
      ),
    );
  }

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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        title: const Text('Marketplace'),
        backgroundColor: _colorFondo,
        foregroundColor: _colorTexto,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _busquedaCtrl,
              onChanged: _onBusquedaCambiada,
              style: GoogleFonts.plusJakartaSans(color: _colorTexto),
              decoration: InputDecoration(
                hintText: 'Buscar en el marketplace…',
                hintStyle: GoogleFonts.plusJakartaSans(
                    color: _colorTextoSecundario),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Color(0xFF98A2B3)),
                isDense: true,
                filled: true,
                fillColor: _colorSuperficie,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: _colorBorde),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ),
          Expanded(
            child: _cargando && _anuncios.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _anuncios.isEmpty
                    ? _estadoError()
                    : _anuncios.isEmpty
                        ? _estadoVacio()
                        : RefreshIndicator(
                            onRefresh: _cargar,
                            child: ListView.builder(
                              controller: _scrollCtrl,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(12, 12, 12, 24),
                              itemCount:
                                  _anuncios.length + (_cargandoMas ? 1 : 0),
                              itemBuilder: (context, i) {
                                if (i >= _anuncios.length) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 18),
                                    child: Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.4),
                                      ),
                                    ),
                                  );
                                }
                                final a = _anuncios[i];
                                final id = a['id_anuncio']?.toString() ?? '';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _TarjetaAnuncioSocial(
                                    anuncio: a,
                                    tieneLike: _misLikes.contains(id),
                                    colorSuperficie: _colorSuperficie,
                                    colorBorde: _colorBorde,
                                    colorTexto: _colorTexto,
                                    colorTextoSecundario: _colorTextoSecundario,
                                    onTap: () => _abrirDetalle(a),
                                    onLike: () => _alternarLike(a),
                                    onCompartir: () => _compartir(a),
                                    onContactar: () => _contactar(a),
                                    onComentar: () => _abrirDetalle(a),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _estadoVacio() {
    final buscando = _busquedaCtrl.text.trim().isNotEmpty;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Icon(Icons.campaign_outlined, size: 56, color: _colorTextoSecundario),
        const SizedBox(height: 16),
        Center(
          child: Text(
            buscando ? 'Sin resultados para tu búsqueda' : 'Todavía no hay anuncios',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, color: _colorTexto),
          ),
        ),
        if (buscando)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: Text('Prueba con otro término.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: _colorTextoSecundario)),
            ),
          ),
      ],
    );
  }

  Widget _estadoError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 40, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text('No se pudieron cargar los anuncios',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700, color: _colorTexto)),
            const SizedBox(height: 6),
            Text('$_error',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: _colorTextoSecundario)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta grande estilo publicación de red social.
class _TarjetaAnuncioSocial extends StatelessWidget {
  final Map<String, dynamic> anuncio;
  final bool tieneLike;
  final Color colorSuperficie;
  final Color colorBorde;
  final Color colorTexto;
  final Color colorTextoSecundario;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onCompartir;
  final VoidCallback onContactar;
  final VoidCallback? onComentar;

  const _TarjetaAnuncioSocial({
    required this.anuncio,
    required this.tieneLike,
    required this.colorSuperficie,
    required this.colorBorde,
    required this.colorTexto,
    required this.colorTextoSecundario,
    required this.onTap,
    required this.onLike,
    required this.onCompartir,
    required this.onContactar,
    this.onComentar,
  });

  @override
  Widget build(BuildContext context) {
    final titulo = (anuncio['titulo'] as String?) ?? '';
    final texto = (anuncio['texto'] as String?) ?? '';
    final imagen = anuncio['imagen_url'] as String?;
    final precio = (anuncio['precio_usd'] as num?)?.toDouble();
    final totalLikes = (anuncio['total_likes'] as num?)?.toInt() ?? 0;
    final totalComentarios = (anuncio['total_comentarios'] as num?)?.toInt() ?? 0;
    final nombreAnunciante =
        (anuncio['nombre_anunciante'] as String?) ?? 'Anuncio';
    final whatsapp = (anuncio['whatsapp'] as String?)?.trim();

    return Container(
      decoration: BoxDecoration(
        color: colorSuperficie,
        borderRadius: BorderRadius.circular(kCardRadiusLarge),
        border: Border.all(color: colorBorde),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Header: avatar + nombre ----
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary.withOpacity(0.12),
                  child: const Icon(Icons.storefront_rounded,
                      size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(nombreAnunciante,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: colorTexto)),
                ),
              ],
            ),
          ),

          // ---- Foto grande (tocar abre el detalle) ----
          GestureDetector(
            onTap: onTap,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: (imagen != null && imagen.isNotEmpty)
                  ? Image.network(
                      imagen,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: colorBorde.withOpacity(0.3),
                        child: Icon(Icons.image_not_supported_outlined,
                            size: 40, color: colorTextoSecundario),
                      ),
                    )
                  : Container(
                      color: colorBorde.withOpacity(0.3),
                      child: Icon(Icons.campaign_outlined,
                          size: 40, color: colorTextoSecundario),
                    ),
            ),
          ),

          // ---- Título + texto + precio ----
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (titulo.isNotEmpty)
                  Text(titulo,
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: colorTexto)),
                if (precio != null) ...[
                  const SizedBox(height: 4),
                  Text('\$${precio.toStringAsFixed(2)} USD',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.success)),
                ],
                if (texto.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(texto,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          height: 1.4,
                          color: colorTextoSecundario)),
                ],
              ],
            ),
          ),

          // ---- Contador de likes (arriba de los botones, como FB) ----
          if (totalLikes > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.favorite_rounded,
                        size: 10, color: Colors.white),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    totalLikes == 1
                        ? '1 persona le dio like'
                        : '$totalLikes personas le dieron like',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5, color: colorTextoSecundario),
                  ),
                  if (totalComentarios > 0) ...[
                    const SizedBox(width: 14),
                    const Icon(Icons.mode_comment_outlined,
                        size: 13, color: Color(0xFF98A2B3)),
                    const SizedBox(width: 5),
                    Text(
                      totalComentarios == 1
                          ? '1 comentario'
                          : '$totalComentarios comentarios',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5, color: colorTextoSecundario),
                    ),
                  ],
                ],
              ),
            )
          else if (totalComentarios > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Row(
                children: [
                  const Icon(Icons.mode_comment_outlined,
                      size: 13, color: Color(0xFF98A2B3)),
                  const SizedBox(width: 5),
                  Text(
                    totalComentarios == 1
                        ? '1 comentario'
                        : '$totalComentarios comentarios',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5, color: colorTextoSecundario),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
            child: Divider(height: 1, color: colorBorde),
          ),

          // ---- Botones de acción: Like / Compartir / Comentar / Contactar ----
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: _botonAccion(
                    icono: tieneLike
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: tieneLike ? Colors.redAccent : colorTextoSecundario,
                    texto: 'Me gusta',
                    onTap: onLike,
                    compacto: whatsapp != null && whatsapp.isNotEmpty,
                  ),
                ),
                Expanded(
                  child: _botonAccion(
                    icono: Icons.mode_comment_outlined,
                    color: colorTextoSecundario,
                    texto: 'Comentar',
                    onTap: onComentar ?? onTap,
                    compacto: whatsapp != null && whatsapp.isNotEmpty,
                  ),
                ),
                Expanded(
                  child: _botonAccion(
                    icono: Icons.share_outlined,
                    color: colorTextoSecundario,
                    texto: 'Compartir',
                    onTap: onCompartir,
                    compacto: whatsapp != null && whatsapp.isNotEmpty,
                  ),
                ),
                if (whatsapp != null && whatsapp.isNotEmpty)
                  Expanded(
                    child: _botonAccion(
                      icono: Icons.chat_rounded,
                      color: const Color(0xFF25D366),
                      texto: 'Contactar',
                      onTap: onContactar,
                      compacto: true,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonAccion({
    required IconData icono,
    required Color color,
    required String texto,
    required VoidCallback onTap,
    bool compacto = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: compacto ? 15 : 18, color: color),
              SizedBox(width: compacto ? 3 : 6),
              Flexible(
                child: Text(texto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: compacto ? 11 : 12.5,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// PANTALLA DE DETALLE -- lo que se muestra al tocar un anuncio.
// Misma información ampliada + like + compartir desde acá también.
// ===========================================================================

class AnuncioDetalleScreen extends StatefulWidget {
  final Map<String, dynamic> anuncio;
  final bool tieneLike;
  final ValueChanged<bool>? onLikeCambiado;
  final ValueChanged<int>? onTotalComentariosCambiado;

  const AnuncioDetalleScreen({
    super.key,
    required this.anuncio,
    required this.tieneLike,
    this.onLikeCambiado,
    this.onTotalComentariosCambiado,
  });

  @override
  State<AnuncioDetalleScreen> createState() => _AnuncioDetalleScreenState();
}

class _AnuncioDetalleScreenState extends State<AnuncioDetalleScreen> {
  final _likesService = AnuncioLikesService();
  final _comentariosService = AnuncioComentariosService();
  final _comentarioCtrl = TextEditingController();

  late bool _tieneLike;
  late int _totalLikes;
  bool _procesandoLike = false;

  List<Map<String, dynamic>> _comentarios = [];
  bool _cargandoComentarios = false;
  bool _enviandoComentario = false;

  @override
  void initState() {
    super.initState();
    _tieneLike = widget.tieneLike;
    _totalLikes = (widget.anuncio['total_likes'] as num?)?.toInt() ?? 0;
    _cargarComentarios();
  }

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarComentarios() async {
    final id = widget.anuncio['id_anuncio']?.toString();
    if (id == null) return;
    _cargandoComentarios = true;
    try {
      final lista = await _comentariosService.comentariosDe(id);
      if (!mounted) return;
      setState(() {
        _comentarios = lista;
        _cargandoComentarios = false;
        widget.anuncio['total_comentarios'] = lista.length;
      });
      widget.onTotalComentariosCambiado?.call(lista.length);
    } catch (e) {
      if (mounted) setState(() => _cargandoComentarios = false);
    }
  }

  Future<void> _enviarComentario() async {
    if (!await requireAuth(context)) return;
    if (!mounted) return;
    final texto = _comentarioCtrl.text.trim();
    if (texto.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe tu comentario antes de enviar.')),
      );
      return;
    }
    if (textoEsOfensivo(texto)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ese comentario contiene lenguaje ofensivo.')),
      );
      return;
    }
    final id = widget.anuncio['id_anuncio']?.toString();
    if (id == null || _enviandoComentario) return;

    setState(() => _enviandoComentario = true);
    try {
      await _comentariosService.agregarComentario(id, texto);
      _comentarioCtrl.clear();
      await _cargarComentarios();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo publicar el comentario: $e')),
      );
    } finally {
      if (mounted) setState(() => _enviandoComentario = false);
    }
  }

  Future<void> _borrarComentario(Map<String, dynamic> comentario) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar comentario?'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      await _comentariosService
          .eliminarComentario(comentario['id_comentario'].toString());
      await _cargarComentarios();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $e')),
      );
    }
  }

  /// Navegación real del anuncio: potenciado -> tienda con producto,
  /// negocio -> /negocio, tienda -> /tienda, standalone -> WhatsApp.
  Future<void> _verDestino() async {
    final idTienda = widget.anuncio['id_tienda']?.toString();
    final idProducto = widget.anuncio['id_producto']?.toString();
    final idNegocio = widget.anuncio['id_negocio']?.toString();

    if (idTienda != null && idTienda.isNotEmpty) {
      if (idProducto != null && idProducto.isNotEmpty) {
        await context.push('/tienda/$idTienda?producto=$idProducto');
      } else {
        await context.push('/tienda/$idTienda');
      }
      return;
    }
    if (idNegocio != null && idNegocio.isNotEmpty) {
      await context.push('/negocio/$idNegocio');
      return;
    }
    await _contactar();
  }

  Future<void> _alternarLike() async {
    if (!await requireAuth(context)) return;
    final id = widget.anuncio['id_anuncio']?.toString();
    if (id == null || _procesandoLike) return;

    final teniaLike = _tieneLike;
    setState(() {
      _procesandoLike = true;
      _tieneLike = !teniaLike;
      _totalLikes += teniaLike ? -1 : 1;
    });

    try {
      await _likesService.alternar(id, actualmenteConLike: teniaLike);
      widget.onLikeCambiado?.call(_tieneLike);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tieneLike = teniaLike;
        _totalLikes += teniaLike ? 1 : -1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo procesar el like: $e')),
      );
    } finally {
      if (mounted) setState(() => _procesandoLike = false);
    }
  }

  void _compartir() {
    final titulo = (widget.anuncio['titulo'] as String?)?.trim() ?? 'Anuncio';
    final id = widget.anuncio['id_anuncio']?.toString() ?? '';
    final link = kEnlaceAnuncio(id);
    Share.share('Mira este anuncio en Al Lado: "$titulo"\n$link');
  }

  Future<void> _contactar() async {
    final telefono = (widget.anuncio['whatsapp'] as String?)?.trim();
    if (telefono == null || telefono.isEmpty) return;
    final titulo = (widget.anuncio['titulo'] as String?)?.trim() ?? '';
    final mensaje = Uri.encodeComponent(
        'Hola! Vi tu anuncio "$titulo" en Al Lado y quiero más información.');
    final url = Uri.parse('https://wa.me/$telefono?text=$mensaje');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp')),
      );
    }
  }

  bool get _tieneDestino {
    final idTienda = widget.anuncio['id_tienda']?.toString();
    final idNegocio = widget.anuncio['id_negocio']?.toString();
    return (idTienda != null && idTienda.isNotEmpty) ||
        (idNegocio != null && idNegocio.isNotEmpty);
  }

  String get _labelDestino {
    final idTienda = widget.anuncio['id_tienda']?.toString();
    final idProducto = widget.anuncio['id_producto']?.toString();
    final idNegocio = widget.anuncio['id_negocio']?.toString();
    if (idTienda != null && idTienda.isNotEmpty) {
      return (idProducto != null && idProducto.isNotEmpty)
          ? 'Ver producto en la tienda'
          : 'Ver tienda';
    }
    if (idNegocio != null && idNegocio.isNotEmpty) return 'Ver negocio';
    return 'Contactar';
  }

  String _inicialNombre(String nombre) {
    final limpio = nombre.trim();
    if (limpio.isEmpty) return 'U';
    return limpio.substring(0, 1).toUpperCase();
  }

  /// Tiempo relativo ("hace 2 h", "hace 3 d"...).
  String _hace(DateTime? fecha) {
    if (fecha == null) return '';
    final d = DateTime.now().toUtc().difference(fecha);
    if (d.inMinutes < 1) return 'ahora mismo';
    if (d.inHours < 1) return 'hace ${d.inMinutes} min';
    if (d.inDays < 1) return 'hace ${d.inHours} h';
    if (d.inDays < 30) return 'hace ${d.inDays} d';
    return 'hace ${(d.inDays / 30).floor()} m';
  }

  Widget _itemComentario(Map<String, dynamic> c) {
    final texto = (c['texto'] as String?) ?? '';
    final nombre = (c['nombre_usuario'] as String?) ?? 'Usuario';
    final creado = DateTime.tryParse((c['creado_en'] as String?) ?? '');
    final esMio =
        c['id_usuario']?.toString() == supabase.auth.currentUser?.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primary.withOpacity(0.12),
            child: Text(_inicialNombre(nombre),
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: AppColors.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: _colorBorde.withOpacity(0.35),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                color: _colorTexto)),
                      ),
                      if (_hace(creado).isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text('· ${_hace(creado)}',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11, color: _colorTextoSecundario)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(texto,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5, height: 1.35, color: _colorTexto)),
                ],
              ),
            ),
          ),
          if (esMio) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Eliminar comentario',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              icon: Icon(Icons.delete_outline_rounded,
                  color: _colorTextoSecundario),
              onPressed: () => _borrarComentario(c),
            ),
          ],
        ],
      ),
    );
  }

  Widget _seccionComentarios() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: _colorBorde),
        const SizedBox(height: 4),
        Text('Comentarios (${_comentarios.length})',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 15, color: _colorTexto)),
        const SizedBox(height: 10),
        if (_cargandoComentarios)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          )
        else if (_comentarios.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Sé el primero en comentar.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: _colorTextoSecundario)),
          )
        else
          ..._comentarios.map(_itemComentario),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _comentarioCtrl,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5, color: _colorTexto),
                decoration: InputDecoration(
                  hintText: 'Escribe un comentario…',
                  hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: _colorTextoSecundario),
                  isDense: true,
                  filled: true,
                  fillColor: _colorBorde.withOpacity(0.35),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _enviandoComentario ? null : _enviarComentario,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _colorBorde,
              ),
              icon: _enviandoComentario
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
            ),
          ],
        ),
      ],
    );
  }

  bool get _esOscuro => Theme.of(context).brightness == Brightness.dark;
  Color get _colorTexto => _esOscuro ? const Color(0xFFF5F5F4) : AppColors.ink;
  Color get _colorTextoSecundario =>
      _esOscuro ? AppColors.inkSecundarioDark : AppColors.inkSecundarioLight;
  Color get _colorFondo => Theme.of(context).scaffoldBackgroundColor;
  Color get _colorBorde =>
      (_esOscuro ? AppColors.borderDark : AppColors.borderLight)
          .withOpacity(0.6);

  @override
  Widget build(BuildContext context) {
    final a = widget.anuncio;
    final titulo = (a['titulo'] as String?) ?? '';
    final texto = (a['texto'] as String?) ?? '';
    final imagen = a['imagen_url'] as String?;
    final precio = (a['precio_usd'] as num?)?.toDouble();
    final nombreAnunciante = (a['nombre_anunciante'] as String?) ?? 'Anuncio';
    final whatsapp = (a['whatsapp'] as String?)?.trim();

    return Scaffold(
      backgroundColor: _colorFondo,
      appBar: AppBar(
        title: const Text('Anuncio'),
        backgroundColor: _colorFondo,
        foregroundColor: _colorTexto,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: _compartir,
          ),
        ],
      ),
      body: ListView(
        children: [
          if (imagen != null && imagen.isNotEmpty)
            Image.network(
              imagen,
              width: double.infinity,
              height: 320,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 320,
                color: _colorBorde.withOpacity(0.3),
                child: Icon(Icons.image_not_supported_outlined,
                    size: 48, color: _colorTextoSecundario),
              ),
            )
          else
            Container(
              height: 220,
              color: _colorBorde.withOpacity(0.3),
              child: Icon(Icons.campaign_outlined,
                  size: 48, color: _colorTextoSecundario),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primary.withOpacity(0.12),
                      child: const Icon(Icons.storefront_rounded,
                          color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(nombreAnunciante,
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: _colorTexto)),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (titulo.isNotEmpty)
                  Text(titulo,
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          fontSize: 21,
                          color: _colorTexto)),
                if (precio != null) ...[
                  const SizedBox(height: 8),
                  Text('\$${precio.toStringAsFixed(2)} USD',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: AppColors.success)),
                ],
                if (texto.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(texto,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14.5, height: 1.5, color: _colorTexto)),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Icon(Icons.favorite_rounded,
                        size: 16, color: Colors.redAccent),
                    const SizedBox(width: 6),
                    Text(
                      _totalLikes == 1
                          ? '1 me gusta'
                          : '$_totalLikes me gusta',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _colorTextoSecundario),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: _colorBorde),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _procesandoLike ? null : _alternarLike,
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              _tieneLike ? Colors.redAccent : _colorTexto,
                          side: BorderSide(
                            color: _tieneLike
                                ? Colors.redAccent
                                : _colorBorde,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: Icon(_tieneLike
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded),
                        label: Text(_tieneLike ? 'Te gusta' : 'Me gusta'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _compartir,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _colorTexto,
                          side: BorderSide(color: _colorBorde),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Compartir'),
                      ),
                    ),
                  ],
                ),
                if (_tieneDestino) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _verDestino,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      icon: const Icon(Icons.storefront_rounded),
                      label: Text(_labelDestino),
                    ),
                  ),
                ],
                if (whatsapp != null && whatsapp.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _contactar,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      icon: const Icon(Icons.chat_rounded),
                      label: const Text('Contactar por WhatsApp'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _seccionComentarios(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
