// gestionar_anuncio_screen.dart
//
// Pantalla "Gestionar anuncio" del DUEÑO de un anuncio independiente.
// Se abre desde la lista "Mis anuncios independientes" con:
//
//     await abrirGestionarAnuncio(context, idAnuncio);
//     // ...y al volver, recargar la lista.
//
// Ruta: /mis-anuncios/:idAnuncio (ver router.dart; exige sesión).
//
// Qué muestra (todo con datos REALES de la base):
//   - Imagen + insignia de estado (En feed / Pausado / En revisión /
//     Rechazado / Vencido) y, según el caso, un aviso arriba (motivo del
//     rechazo, "en revisión", "venció").
//   - Título, texto, tipo y precio.
//   - Vigencia: fecha, días restantes y barra de progreso.
//   - Métricas: Vistas (veces_mostrado), Clics (veces_clickeado), CTR,
//     Me gusta y Comentarios (conteos en vivo).
//   - Comentarios con foto/nombre; el dueño puede borrarlos.
//   - Quién dio "me gusta" (con foto).
//   - Barra fija de acciones según el estado:
//         En feed   -> Editar | Pausar            | Eliminar
//         Pausado   -> Editar | Reactivar         | Eliminar
//         En revisión -> Editar | (En revisión)   | Eliminar
//         Rechazado -> Editar | Reenviar a revisión | Eliminar
//         Vencido   -> Editar | Renovar           | Eliminar
//
// NO incluye (a propósito, porque hoy no existen esos datos): gráfica
// por día ni contador de "Compartidos". Cuando se agreguen en backend,
// se suman como tarjetas nuevas sin tocar el resto.
//
// Requiere sql/gestion_anuncios_standalone.sql ejecutado en Supabase.
// Colores y tipografía salen de AppColors / el tema de la app, así que
// el modo claro y el oscuro funcionan solos.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_colors.dart';
import '../core/app_links_config.dart';
import '../services/anuncios_service.dart';
import '../services/currency_service.dart';
import 'editar_anuncio_standalone_screen.dart';
import 'standalone_anuncio_screen.dart';

/// Abre la pantalla de gestión. Completa cuando el usuario vuelve atrás:
/// el llamador debe recargar su lista después del `await`.
Future<void> abrirGestionarAnuncio(
    BuildContext context, String idAnuncio) async {
  await context.push('/mis-anuncios/$idAnuncio');
}

// Estado "visual" del anuncio (combina estado + vigencia).
enum _Vista { enFeed, pausado, pendiente, rechazado, vencido }

const Color _kAmbar = Color(0xFFFF9F0A);
const Color _kRojo = Color(0xFFFF3B30);
const Color _kGris = Color(0xFF8E8E93);

class GestionarAnuncioScreen extends StatefulWidget {
  final String idAnuncio;
  const GestionarAnuncioScreen({super.key, required this.idAnuncio});

  @override
  State<GestionarAnuncioScreen> createState() => _GestionarAnuncioScreenState();
}

class _GestionarAnuncioScreenState extends State<GestionarAnuncioScreen> {
  final _svc = AnunciosService();

  Map<String, dynamic>? _anuncio;
  List<Map<String, dynamic>> _likes = [];
  List<Map<String, dynamic>> _comentarios = [];
  int _totalLikes = 0;
  int _totalComentarios = 0;

  bool _cargando = true;
  Object? _error;
  bool _trabajando = false; // una acción (pausar, eliminar...) en curso
  bool _verTodosComentarios = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  // ------------------------------------------------------------------
  // CARGA
  // ------------------------------------------------------------------

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final r = await _svc.obtenerGestionAnuncio(widget.idAnuncio);
      if (!mounted) return;
      List<Map<String, dynamic>> lista(dynamic v) => (v as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _anuncio = Map<String, dynamic>.from(r['anuncio'] as Map);
        _likes = lista(r['likes']);
        _comentarios = lista(r['comentarios']);
        _totalLikes = (r['total_likes'] as num?)?.toInt() ?? _likes.length;
        _totalComentarios =
            (r['total_comentarios'] as num?)?.toInt() ?? _comentarios.length;
        _cargando = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_anuncio == null) {
        setState(() {
          _cargando = false;
          _error = e;
        });
      } else {
        setState(() => _cargando = false);
        _snack('No se pudo actualizar. Revisa tu conexión.');
      }
    }
  }

  // ------------------------------------------------------------------
  // HELPERS DE DATOS
  // ------------------------------------------------------------------

  bool get _oscuro => Theme.of(context).brightness == Brightness.dark;
  Color get _superficie =>
      _oscuro ? AppColors.surfaceDark : AppColors.surfaceLight;
  Color get _borde => _oscuro ? AppColors.borderDark : AppColors.borderLight;
  Color get _texto => _oscuro ? AppColors.inkDark : AppColors.inkLight;
  Color get _secundario => AppColors.inkSecundarioLight;

  bool get _esStandalone => _anuncio?['tipo'] == 'standalone';

  /// Etiqueta del tipo de anuncio (independiente / de tienda / de negocio).
  String get _etiquetaTipo {
    switch (_anuncio?['tipo'] as String?) {
      case 'standalone':
        return 'Anuncio independiente';
      case 'negocio':
        return 'Anuncio de negocio';
      default:
        return 'Anuncio de producto';
    }
  }

  DateTime? _fecha(dynamic v) =>
      DateTime.tryParse(v?.toString() ?? '')?.toLocal();

  DateTime? get _vence => _fecha(_anuncio?['vigencia_hasta']);

  bool get _vigenciaPasada {
    final h = _vence;
    return h != null && !h.isAfter(DateTime.now());
  }

  _Vista get _vista {
    final estado = _anuncio?['estado'] as String? ?? '';
    if (estado == 'expirado') return _Vista.vencido;
    if ((estado == 'aprobado' || estado == 'pausado') && _vigenciaPasada) {
      return _Vista.vencido;
    }
    switch (estado) {
      case 'aprobado':
        return _Vista.enFeed;
      case 'pausado':
        return _Vista.pausado;
      case 'rechazado':
        return _Vista.rechazado;
      default:
        return _Vista.pendiente;
    }
  }

  int get _vistas => (_anuncio?['veces_mostrado'] as num?)?.toInt() ?? 0;
  int get _clics => (_anuncio?['veces_clickeado'] as num?)?.toInt() ?? 0;

  String _fechaCorta(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _compacto(int n) {
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')} M';
    }
    if (n >= 10000) {
      return '${(n / 1000).toStringAsFixed(1).replaceAll('.', ',')} k';
    }
    return n.toString();
  }

  String _ctr() {
    if (_vistas <= 0) return '0 %';
    final v = (_clics / _vistas) * 100;
    return '${v.toStringAsFixed(1).replaceAll('.', ',')} %';
  }

  String _hace(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays < 30) return 'hace ${diff.inDays} d';
    return _fechaCorta(d);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String _mensajeError(Object e) {
    final s = e.toString();
    if (s.contains('CUPO_ANUNCIOS')) {
      return 'No tienes ranuras libres para reactivarlo. Compra un paquete '
          'o pausa otro anuncio activo.';
    }
    if (s.contains('ANUNCIO_VENCIDO')) {
      return 'Este anuncio ya venció. Elimínalo y publica uno nuevo.';
    }
    if (s.contains('ESTADO_INVALIDO')) {
      return 'El anuncio cambió de estado. Actualizamos la pantalla.';
    }
    if (s.contains('CAMPO_PROTEGIDO')) {
      return 'Ese cambio solo lo puede hacer el administrador.';
    }
    if (s.contains('NO_AUTORIZADO')) {
      return 'Este anuncio no existe o ya no es tuyo.';
    }
    if (s.contains('SESION_REQUERIDA')) {
      return 'Inicia sesión de nuevo e inténtalo otra vez.';
    }
    return 'No se pudo completar la acción. Intenta de nuevo.';
  }

  // ------------------------------------------------------------------
  // ACCIONES
  // ------------------------------------------------------------------

  /// Ejecuta una acción con bloqueo de botones, mensaje y recarga.
  Future<void> _ejecutar(
    Future<void> Function() accion, {
    required String exito,
  }) async {
    if (_trabajando) return;
    setState(() => _trabajando = true);
    try {
      await accion();
      _snack(exito);
      await _cargar(silencioso: true);
    } catch (e) {
      _snack(_mensajeError(e));
      // Si el estado cambió por otro lado, refrescar para no mostrar
      // botones que ya no aplican.
      if (e.toString().contains('ESTADO_INVALIDO')) {
        await _cargar(silencioso: true);
      }
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<bool> _confirmar({
    required String titulo,
    required String mensaje,
    required String textoOk,
    bool peligro = false,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: peligro
                ? TextButton.styleFrom(foregroundColor: _kRojo)
                : null,
            child: Text(textoOk),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _editar() async {
    final a = _anuncio;
    if (a == null || _trabajando) return;
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditarAnuncioStandaloneScreen(anuncio: a),
      ),
    );
    if (guardado == true && mounted) {
      await _cargar(silencioso: true);
      _snack(_vista == _Vista.rechazado
          ? 'Cambios guardados. Ahora puedes reenviarlo a revisión.'
          : 'Cambios guardados.');
    }
  }

  Future<void> _pausar() async {
    final ok = await _confirmar(
      titulo: '¿Pausar anuncio?',
      mensaje: 'Dejará de aparecer en el feed y liberarás su ranura. '
          'Podrás reactivarlo cuando quieras mientras siga vigente.',
      textoOk: 'Pausar',
    );
    if (!ok) return;
    await _ejecutar(
      () => _svc.pausarAnuncio(widget.idAnuncio),
      exito: 'Anuncio pausado.',
    );
  }

  Future<void> _reactivar() => _ejecutar(
        () => _svc.activarAnuncio(widget.idAnuncio),
        exito: 'Anuncio reactivado. Ya está en el feed.',
      );

  Future<void> _reenviar() async {
    final ok = await _confirmar(
      titulo: 'Reenviar a revisión',
      mensaje: 'El administrador volverá a revisar tu anuncio. '
          'Te avisaremos cuando tenga respuesta.',
      textoOk: 'Reenviar',
    );
    if (!ok) return;
    await _ejecutar(
      () => _svc.reenviarARevision(widget.idAnuncio),
      exito: 'Anuncio reenviado a revisión.',
    );
  }

  Future<void> _renovar() async {
    if (_trabajando) return;
    setState(() => _trabajando = true);
    try {
      await _svc.renovarAnuncioStandalone(widget.idAnuncio);
      _snack('¡Anuncio renovado! Ya está de nuevo en el feed.');
      await _cargar(silencioso: true);
    } catch (e) {
      if (e.toString().contains('SIN_RANURA_LIBRE')) {
        await _ofrecerPaquetes();
      } else {
        _snack(_mensajeError(e));
        if (e.toString().contains('ESTADO_INVALIDO')) {
          await _cargar(silencioso: true);
        }
      }
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _ofrecerPaquetes() async {
    final ver = await _confirmar(
      titulo: 'Necesitas una ranura vigente',
      mensaje: 'Para renovar este anuncio hace falta un paquete vigente con '
          'espacio libre. Puedes comprar uno ahora y, cuando el administrador '
          'lo apruebe, volver aquí y renovar.',
      textoOk: 'Ver paquetes',
    );
    if (!ver || !mounted) return;
    await mostrarPlanesStandaloneSheet(context, onCompraRegistrada: () {});
    if (mounted) await _cargar(silencioso: true);
  }

  Future<void> _eliminar() async {
    final ok = await _confirmar(
      titulo: '¿Eliminar anuncio?',
      mensaje: 'Se borrará de forma definitiva, con su imagen. '
          'Esta acción no se puede deshacer.',
      textoOk: 'Eliminar',
      peligro: true,
    );
    if (!ok || _trabajando) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _trabajando = true);
    try {
      await _svc.eliminarAnuncio(widget.idAnuncio);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Anuncio eliminado.')));
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    } catch (e) {
      _snack(_mensajeError(e));
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _borrarComentario(Map<String, dynamic> c) async {
    final ok = await _confirmar(
      titulo: '¿Eliminar comentario?',
      mensaje: 'Se quitará de tu anuncio para todos.',
      textoOk: 'Eliminar',
      peligro: true,
    );
    if (!ok) return;
    try {
      await _svc.eliminarComentarioDeMiAnuncio(c['id_comentario'].toString());
      if (!mounted) return;
      setState(() {
        _comentarios.removeWhere(
            (x) => x['id_comentario'].toString() == c['id_comentario'].toString());
        _totalComentarios = math.max(0, _totalComentarios - 1);
      });
    } catch (_) {
      _snack('No se pudo eliminar el comentario.');
    }
  }

  void _compartir() {
    final a = _anuncio;
    if (a == null) return;
    final titulo = (a['titulo'] as String?)?.trim() ?? 'Anuncio';
    Share.share(
        'Mira este anuncio en Al Lado: "$titulo"\n${kEnlaceAnuncio(widget.idAnuncio)}');
  }

  // ------------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final puedeCompartir = _anuncio != null && _vista == _Vista.enFeed;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar anuncio'),
        actions: [
          if (puedeCompartir)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'compartir') _compartir();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'compartir', child: Text('Compartir')),
              ],
            ),
        ],
      ),
      body: _cuerpo(),
      bottomNavigationBar: (_anuncio != null && _esStandalone)
          ? _barraAcciones()
          : null,
    );
  }

  Widget _cuerpo() {
    if (_cargando && _anuncio == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _anuncio == null) {
      final noEsMio = _error.toString().contains('NO_AUTORIZADO');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: _secundario),
              const SizedBox(height: 12),
              Text(
                noEsMio
                    ? 'Este anuncio no existe o no es tuyo.'
                    : 'No se pudo cargar el anuncio. Revisa tu conexión.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(color: _texto),
              ),
              if (!noEsMio) ...[
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: _cargar,
                  child: const Text('Reintentar'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final a = _anuncio!;
    final titulo = (a['titulo'] as String?)?.trim() ?? '';
    final texto = (a['texto'] as String?)?.trim() ?? '';
    final precio = (a['precio_usd'] as num?)?.toDouble();

    return RefreshIndicator(
      onRefresh: () => _cargar(silencioso: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _aviso(),
          _imagenConBadge(),
          const SizedBox(height: 14),
          Text(
            titulo.isEmpty ? 'Sin título' : titulo,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _texto,
            ),
          ),
          if (texto.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              texto,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                height: 1.4,
                color: _oscuro ? const Color(0xFFD1D1D6) : const Color(0xFF3A3A3C),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _chip(_etiquetaTipo, AppColors.primary),
              if (precio != null)
                _chip(CurrencyService.instance.formatear(precio),
                    AppColors.success),
            ],
          ),
          const SizedBox(height: 14),
          _tarjetaVigencia(),
          const SizedBox(height: 12),
          _metricas(),
          const SizedBox(height: 12),
          _seccionComentarios(),
          const SizedBox(height: 12),
          _seccionLikes(),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // BLOQUES DE UI
  // ------------------------------------------------------------------

  Color _colorVista(_Vista v) {
    switch (v) {
      case _Vista.enFeed:
        return AppColors.success;
      case _Vista.pausado:
        return _kAmbar;
      case _Vista.pendiente:
        return AppColors.primary;
      case _Vista.rechazado:
        return _kRojo;
      case _Vista.vencido:
        return _kGris;
    }
  }

  String _textoVista(_Vista v) {
    switch (v) {
      case _Vista.enFeed:
        return 'EN FEED';
      case _Vista.pausado:
        return 'PAUSADO';
      case _Vista.pendiente:
        return 'EN REVISIÓN';
      case _Vista.rechazado:
        return 'RECHAZADO';
      case _Vista.vencido:
        return 'VENCIDO';
    }
  }

  Widget _tarjeta({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borde),
        boxShadow: _oscuro
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: child,
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(_oscuro ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  /// Aviso superior según el estado (rechazado / en revisión / vencido).
  Widget _aviso() {
    final v = _vista;
    String? titulo;
    String? mensaje;
    IconData icono = Icons.info_outline_rounded;
    Color color = _kGris;
    VoidCallback? onTap;

    if (v == _Vista.rechazado) {
      final motivo = (_anuncio?['motivo_rechazo'] as String?)?.trim();
      titulo = 'Anuncio rechazado';
      mensaje = (motivo == null || motivo.isEmpty)
          ? 'No pasó la revisión. Edítalo y reenvíalo.'
          : 'Motivo: $motivo';
      icono = Icons.error_rounded;
      color = _kRojo;
      onTap = () => showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Anuncio rechazado'),
              content: Text((motivo == null || motivo.isEmpty)
                  ? 'El administrador no indicó un motivo. Edita tu anuncio y reenvíalo a revisión.'
                  : motivo),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
    } else if (v == _Vista.pendiente) {
      titulo = 'En revisión';
      mensaje = 'Aparecerá en el feed cuando el administrador lo apruebe.';
      icono = Icons.hourglass_top_rounded;
      color = AppColors.primary;
    } else if (v == _Vista.vencido) {
      titulo = 'Anuncio vencido';
      mensaje = 'Ya no aparece en el feed. Renuévalo con una ranura vigente.';
      icono = Icons.schedule_rounded;
      color = _kGris;
    }
    if (titulo == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(_oscuro ? 0.16 : 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Icon(icono, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mensaje!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        height: 1.3,
                        color: _oscuro
                            ? const Color(0xFFD1D1D6)
                            : const Color(0xFF3A3A3C),
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagenConBadge() {
    final url = (_anuncio?['imagen_url'] as String?)?.trim();
    final color = _colorVista(_vista);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 8,
        child: Stack(
          fit: StackFit.expand,
          children: [
            (url != null && url.isNotEmpty)
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholderImagen(),
                  )
                : _placeholderImagen(),
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _textoVista(_vista),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: Colors.white,
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

  Widget _placeholderImagen() => Container(
        color: AppColors.primary.withOpacity(0.10),
        alignment: Alignment.center,
        child: const Icon(Icons.campaign_rounded,
            size: 40, color: AppColors.primary),
      );

  Widget _tarjetaVigencia() {
    final hasta = _vence;
    final creado = _fecha(_anuncio?['creado_en']);
    final ahora = DateTime.now();

    String fechaTxt;
    String? pillTxt;
    Color pillColor = AppColors.success;
    double? progreso;

    if (hasta == null) {
      fechaTxt = 'Sin fecha de vencimiento';
    } else if (!hasta.isAfter(ahora)) {
      fechaTxt = 'Venció el ${_fechaCorta(hasta)}';
      pillTxt = 'Vencido';
      pillColor = _kGris;
      progreso = 1;
    } else {
      fechaTxt = 'Vence ${_fechaCorta(hasta)}';
      final restante = hasta.difference(ahora);
      final dias = (restante.inHours / 24).ceil();
      if (dias <= 1) {
        pillTxt = 'Vence hoy';
        pillColor = _kRojo;
      } else {
        pillTxt = 'Quedan $dias días';
        pillColor = dias <= 7 ? _kAmbar : AppColors.success;
      }
      if (creado != null && hasta.isAfter(creado)) {
        final total = hasta.difference(creado).inSeconds;
        final usado = ahora.difference(creado).inSeconds;
        progreso = (usado / total).clamp(0.0, 1.0);
      }
    }

    return _tarjeta(
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  fechaTxt,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _texto,
                  ),
                ),
              ),
              if (pillTxt != null) _chip(pillTxt, pillColor),
            ],
          ),
          if (progreso != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progreso,
                minHeight: 6,
                color: pillColor,
                backgroundColor: pillColor.withOpacity(0.16),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metrica(IconData icono, String etiqueta, String valor) {
    return Expanded(
      child: _tarjeta(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(_oscuro ? 0.20 : 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icono, size: 15, color: AppColors.primary),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    etiqueta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: _secundario,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              valor,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _texto,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricas() {
    return Column(
      children: [
        Row(
          children: [
            _metrica(Icons.visibility_outlined, 'Vistas', _compacto(_vistas)),
            const SizedBox(width: 10),
            _metrica(Icons.ads_click_rounded, 'Clics', _compacto(_clics)),
            const SizedBox(width: 10),
            _metrica(Icons.insights_rounded, 'CTR', _ctr()),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _metrica(Icons.favorite_rounded, 'Me gusta', _compacto(_totalLikes)),
            const SizedBox(width: 10),
            _metrica(Icons.chat_bubble_outline_rounded, 'Comentarios',
                _compacto(_totalComentarios)),
          ],
        ),
      ],
    );
  }

  Widget _tituloSeccion(String titulo, int total) {
    return Row(
      children: [
        Text(
          titulo,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: _texto,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '($total)',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13.5,
            color: _secundario,
          ),
        ),
      ],
    );
  }

  Widget _seccionComentarios() {
    final visibles =
        _verTodosComentarios ? _comentarios : _comentarios.take(2).toList();
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion('Comentarios', _totalComentarios),
          const SizedBox(height: 10),
          if (_comentarios.isEmpty)
            Text(
              'Todavía no hay comentarios.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: _secundario),
            )
          else
            ...visibles.map(_filaComentario),
          if (_comentarios.length > 2)
            InkWell(
              onTap: () =>
                  setState(() => _verTodosComentarios = !_verTodosComentarios),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(_oscuro ? 0.16 : 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  _verTodosComentarios ? 'Ver menos' : 'Ver todos',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filaComentario(Map<String, dynamic> c) {
    final nombre = (c['nombre_usuario'] as String?)?.trim();
    final texto = (c['texto'] as String?) ?? '';
    final hace = _hace(_fecha(c['creado_en']));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(
            nombre: (nombre == null || nombre.isEmpty) ? 'Usuario' : nombre,
            foto: c['foto'] as String?,
            radius: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        (nombre == null || nombre.isEmpty) ? 'Usuario' : nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _texto,
                        ),
                      ),
                    ),
                    if (hace.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        hace,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: _secundario),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  texto,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    height: 1.35,
                    color: _texto,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Eliminar comentario',
            visualDensity: VisualDensity.compact,
            iconSize: 19,
            icon: Icon(Icons.delete_outline_rounded,
                color: _kRojo.withOpacity(0.85)),
            onPressed: () => _borrarComentario(c),
          ),
        ],
      ),
    );
  }

  Widget _seccionLikes() {
    final mostrados = _likes.take(7).toList();
    final resto = math.max(0, _totalLikes - mostrados.length);
    const paso = 26.0;
    return _tarjeta(
      child: InkWell(
        onTap: _likes.isEmpty ? null : _abrirListaLikes,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _tituloSeccion('Me gusta', _totalLikes)),
                if (_likes.isNotEmpty)
                  Icon(Icons.chevron_right_rounded, color: _secundario),
              ],
            ),
            const SizedBox(height: 10),
            if (_likes.isEmpty)
              Text(
                'Todavía nadie le ha dado me gusta.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: _secundario),
              )
            else
              SizedBox(
                height: 36,
                width: double.infinity,
                child: Stack(
                  children: [
                    for (var i = 0; i < mostrados.length; i++)
                      Positioned(
                        left: i * paso,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _superficie, width: 2),
                          ),
                          child: _Avatar(
                            nombre: (mostrados[i]['nombre'] as String?) ??
                                'Usuario',
                            foto: mostrados[i]['foto'] as String?,
                            radius: 16,
                          ),
                        ),
                      ),
                    if (resto > 0)
                      Positioned(
                        left: mostrados.length * paso,
                        child: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _oscuro
                                ? const Color(0xFF2C2C2E)
                                : const Color(0xFFF2F2F7),
                            border: Border.all(color: _superficie, width: 2),
                          ),
                          child: Text(
                            '+$resto',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _secundario,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _abrirListaLikes() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.35,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _tituloSeccion('Me gusta', _totalLikes),
            ),
            for (final l in _likes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _Avatar(
                  nombre: (l['nombre'] as String?) ?? 'Usuario',
                  foto: l['foto'] as String?,
                  radius: 20,
                ),
                title: Text(
                  (l['nombre'] as String?) ?? 'Usuario',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
                trailing: Text(
                  _hace(_fecha(l['creado_en'])),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5, color: _secundario),
                ),
              ),
            if (_totalLikes > _likes.length)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Mostrando los ${_likes.length} más recientes.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: _secundario),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // BARRA FIJA DE ACCIONES
  // ------------------------------------------------------------------

  Widget _barraAcciones() {
    final v = _vista;
    final bloqueado = _trabajando;

    // Acción central según el estado.
    late final IconData icono;
    late final String etiqueta;
    VoidCallback? accion;
    var destacada = false;
    switch (v) {
      case _Vista.enFeed:
        icono = Icons.pause_circle_outline_rounded;
        etiqueta = 'Pausar';
        accion = _pausar;
        break;
      case _Vista.pausado:
        icono = Icons.play_circle_outline_rounded;
        etiqueta = 'Reactivar';
        accion = _reactivar;
        break;
      case _Vista.pendiente:
        icono = Icons.hourglass_top_rounded;
        etiqueta = 'En revisión';
        accion = null; // nada que hacer: espera al admin
        break;
      case _Vista.rechazado:
        icono = Icons.send_rounded;
        etiqueta = 'Reenviar a revisión';
        accion = _reenviar;
        destacada = true;
        break;
      case _Vista.vencido:
        icono = Icons.autorenew_rounded;
        etiqueta = 'Renovar';
        accion = _renovar;
        destacada = true;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: _superficie,
        border: Border(top: BorderSide(color: _borde)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: _boton(
                  icono: Icons.edit_outlined,
                  texto: 'Editar',
                  onPressed: bloqueado ? null : _editar,
                  tipo: destacada ? _TipoBoton.contorno : _TipoBoton.lleno,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _boton(
                  icono: icono,
                  texto: etiqueta,
                  onPressed: (bloqueado || accion == null) ? null : accion,
                  tipo: destacada ? _TipoBoton.lleno : _TipoBoton.contorno,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _boton(
                  icono: Icons.delete_outline_rounded,
                  texto: 'Eliminar',
                  onPressed: bloqueado ? null : _eliminar,
                  tipo: _TipoBoton.peligro,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boton({
    required IconData icono,
    required String texto,
    required VoidCallback? onPressed,
    required _TipoBoton tipo,
  }) {
    final label = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(texto, maxLines: 1),
    );
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 12);
    final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final estiloTexto = GoogleFonts.plusJakartaSans(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
    );
    switch (tipo) {
      case _TipoBoton.lleno:
        return FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icono, size: 17),
          label: label,
          style: FilledButton.styleFrom(
            padding: padding,
            shape: forma,
            textStyle: estiloTexto,
          ),
        );
      case _TipoBoton.contorno:
        return OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icono, size: 17),
          label: label,
          style: OutlinedButton.styleFrom(
            padding: padding,
            shape: forma,
            textStyle: estiloTexto,
          ),
        );
      case _TipoBoton.peligro:
        return OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icono, size: 17),
          label: label,
          style: OutlinedButton.styleFrom(
            padding: padding,
            shape: forma,
            textStyle: estiloTexto,
            foregroundColor: _kRojo,
            backgroundColor: _kRojo.withOpacity(_oscuro ? 0.14 : 0.07),
            side: BorderSide(color: _kRojo.withOpacity(0.55)),
          ),
        );
    }
  }
}

enum _TipoBoton { lleno, contorno, peligro }

/// Avatar con foto de red; si no hay foto (o falla al cargar) muestra la
/// inicial del nombre sobre el azul de marca.
class _Avatar extends StatelessWidget {
  final String nombre;
  final String? foto;
  final double radius;
  const _Avatar({required this.nombre, this.foto, required this.radius});

  @override
  Widget build(BuildContext context) {
    final inicial =
        nombre.trim().isEmpty ? '?' : nombre.trim()[0].toUpperCase();
    final tieneFoto = foto != null && foto!.trim().isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withOpacity(0.14),
      foregroundImage: tieneFoto ? NetworkImage(foto!.trim()) : null,
      onForegroundImageError: tieneFoto ? (_, __) {} : null,
      child: Text(
        inicial,
        style: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.8,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
