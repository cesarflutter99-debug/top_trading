// tasa_cambio_screen.dart
//
// Muestra todas las monedas que trae la API de elTOQUE (USD, EUR, MLC,
// CAD, MXN, ZELLE, CLA), leyendo la tabla `tasas_cambio` de Supabase --
// que se actualiza sola cada 12 horas vía Edge Function. Esta pantalla
// NUNCA llama a elTOQUE directamente.
//
// Nota: dentro del resto de la app (precios de productos, carrito) el
// toggle de moneda sigue siendo solo USD/CUP (CurrencyService) -- esta
// pantalla es la única que muestra el resto de las monedas, a modo
// informativo, igual que la tabla que se ve en eltoque.com.
//
// Diseño: réplica visual de la referencia (estilo iOS: scroll con rebote,
// refresco Cupertino, tarjetas muy redondeadas). Solo cambia lo visual; la
// lógica (servicio, estados, refrescar) es la misma de siempre.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../services/tasa_cambio_service.dart';

// ─── Paleta local de esta pantalla (claro / oscuro) ─────────────────────
class _Pal {
  _Pal(this.oscuro);
  final bool oscuro;

  Color get fondo =>
      oscuro ? const Color(0xFF0F1115) : const Color(0xFFF5F6FA);
  Color get ink => oscuro ? const Color(0xFFF2F4F8) : const Color(0xFF1B2540);
  Color get ink2 =>
      oscuro ? const Color(0xFF9AA3B5) : const Color(0xFF6B7385);

  Color get azul => oscuro ? const Color(0xFF4DA3FF) : const Color(0xFF1E88E5);
  Color get verde =>
      oscuro ? const Color(0xFF4CC97A) : const Color(0xFF2E9E57);

  Color get tarjetaBase =>
      oscuro ? const Color(0xFF1A1D24) : const Color(0xFFFFFFFF);
  Color get tintaAzul =>
      oscuro ? const Color(0xFF172B47) : const Color(0xFFE2EDFF);
  Color get tintaVerde =>
      oscuro ? const Color(0xFF16302A) : const Color(0xFFE1F4E7);

  Color get borde => oscuro
      ? Colors.white.withOpacity(0.07)
      : Colors.white.withOpacity(0.9);
}

class TasaCambioScreen extends StatefulWidget {
  const TasaCambioScreen({super.key});

  @override
  State<TasaCambioScreen> createState() => _TasaCambioScreenState();
}

class _TasaCambioScreenState extends State<TasaCambioScreen> {
  final _service = TasaCambioService();
  late Future<List<Map<String, dynamic>>> _tasas;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _tasas = _service.obtenerTasas();
  }

  String _formatFecha(String? iso) {
    if (iso == null) return '';
    final fecha = DateTime.tryParse(iso)?.toLocal();
    if (fecha == null) return '';
    final hh = fecha.hour.toString().padLeft(2, '0');
    final mm = fecha.minute.toString().padLeft(2, '0');
    return '${fecha.day}/${fecha.month}/${fecha.year} · $hh:$mm';
  }

  Future<void> _refrescar() async {
    setState(_cargar);
    try {
      await _tasas;
    } catch (_) {
      // El error se muestra en el FutureBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final p = _Pal(esOscuro);
    final topPad = MediaQuery.of(context).padding.top + kToolbarHeight;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: esOscuro ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: esOscuro
            ? Theme.of(context).scaffoldBackgroundColor
            : p.fondo,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: p.ink,
          systemOverlayStyle:
              esOscuro ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          title: Text(
            'Tasa de Cambio',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: p.ink,
            ),
          ),
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Actualizar',
              onPressed: () => setState(_cargar),
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _FondoPainter(esOscuro)),
            ),
            CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(child: SizedBox(height: topPad)),
                CupertinoSliverRefreshControl(onRefresh: _refrescar),
                SliverToBoxAdapter(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _tasas,
                    builder: (context, snapshot) {
                      final alto = MediaQuery.of(context).size.height * 0.5;
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return SizedBox(
                          height: alto,
                          child: const Center(
                            child: CupertinoActivityIndicator(radius: 14),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return SizedBox(
                          height: alto,
                          child: _estadoVacio(
                            p,
                            icon: Icons.error_outline_rounded,
                            titulo: 'No se pudo cargar la tasa de cambio',
                            mensaje: '${snapshot.error}',
                          ),
                        );
                      }
                      final tasas = snapshot.data ?? [];
                      if (tasas.isEmpty) {
                        return SizedBox(
                          height: alto,
                          child: _estadoVacio(
                            p,
                            icon: Icons.hourglass_top_rounded,
                            titulo: 'Todavía no hay datos',
                            mensaje:
                                'La tasa de cambio se actualiza automáticamente cada '
                                '12 horas. Vuelve a intentarlo un poco más tarde.',
                          ),
                        );
                      }

                      final ultimaActualizacion = tasas
                          .map((t) => t['actualizado_en'] as String?)
                          .whereType<String>()
                          .fold<String?>(null, (max, actual) {
                        if (max == null) return actual;
                        return actual.compareTo(max) > 0 ? actual : max;
                      });

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _encabezado(p),
                            const SizedBox(height: 22),
                            ...tasas.map((t) => _filaMoneda(t, p)),
                            const SizedBox(height: 4),
                            _tarjetaInfo(p, ultimaActualizacion),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Encabezado: título + subtítulo + ilustración de monedas ──────────
  Widget _encabezado(_Pal p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tasa de cambio',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 30,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  color: p.ink,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Consulta el valor actualizado de las principales monedas.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                  color: p.ink2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 168, height: 150, child: _ilustracionMonedas(p)),
      ],
    );
  }

  Widget _ilustracionMonedas(_Pal p) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Flecha verde (arriba)
        Positioned(
          top: 0,
          right: 18,
          child: Transform.rotate(
            angle: -0.15,
            child: Icon(Icons.redo_rounded,
                size: 46, color: p.verde.withOpacity(0.85)),
          ),
        ),
        // Moneda con bandera
        Positioned(
          left: 0,
          top: 26,
          child: Container(
            width: 88,
            height: 88,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF7EBC4), Color(0xFFE2CF98)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(p.oscuro ? 0.35 : 0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipOval(
              child: CustomPaint(painter: _BanderaPainter()),
            ),
          ),
        ),
        // Moneda verde con $
        Positioned(
          right: 0,
          top: 40,
          child: Container(
            width: 94,
            height: 94,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8BE07A), Color(0xFF2E9E40)],
              ),
              border: Border.all(
                  color: Colors.white.withOpacity(0.35), width: 4),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2E9E40)
                      .withOpacity(p.oscuro ? 0.35 : 0.30),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              '\$',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 54,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1,
              ),
            ),
          ),
        ),
        // Flecha azul (abajo)
        Positioned(
          left: 30,
          bottom: 0,
          child: Transform.rotate(
            angle: -0.15,
            child: Icon(Icons.undo_rounded,
                size: 44, color: p.azul.withOpacity(0.75)),
          ),
        ),
      ],
    );
  }

  // ─── Tarjeta de cada moneda ───────────────────────────────────────────
  Widget _filaMoneda(Map<String, dynamic> t, _Pal p) {
    final codigo = t['moneda'] as String? ?? '';
    final nombre = kNombresMonedas[codigo] ?? codigo;
    final valor = (t['valor_cup'] as num?)?.toDouble();
    final variacion = (t['variacion'] as num?)?.toDouble();

    final subiendo = (variacion ?? 0) >= 0;
    final hayVariacion = variacion != null && variacion != 0;

    final esUsd = codigo == 'USD';
    final acento = esUsd ? p.azul : p.verde;
    final tinta = esUsd ? p.tintaAzul : p.tintaVerde;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: p.oscuro
                ? Colors.black.withOpacity(0.35)
                : acento.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.tarjetaBase, p.tarjetaBase, tinta],
              stops: const [0.0, 0.45, 1.0],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: p.borde, width: 1.2),
          ),
          child: Stack(
            children: [
              // Ola decorativa inferior
              Positioned.fill(
                child: CustomPaint(
                  painter: _OndaPainter(acento.withOpacity(p.oscuro ? 0.10 : 0.10)),
                ),
              ),
              // Icono decorativo (esquina inferior derecha)
              Positioned(
                right: 18,
                bottom: 10,
                child: Transform.rotate(
                  angle: esUsd ? 0 : -0.2,
                  child: Icon(
                    esUsd
                        ? Icons.account_balance_rounded
                        : (codigo == 'MLC'
                            ? Icons.credit_card_rounded
                            : Icons.payments_rounded),
                    size: esUsd ? 56 : 52,
                    color: acento.withOpacity(p.oscuro ? 0.22 : 0.28),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _iconoMoneda(codigo, esUsd, p),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nombre,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: p.ink,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '1 $codigo',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                  color: p.ink2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                valor != null
                                    ? valor.toStringAsFixed(2)
                                    : '--',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 30,
                                  height: 1.05,
                                  color: p.ink,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hayVariacion) ...[
                                  Icon(
                                    subiendo
                                        ? Icons.arrow_upward_rounded
                                        : Icons.arrow_downward_rounded,
                                    size: 13,
                                    color: subiendo
                                        ? AppColors.success
                                        : Colors.redAccent,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    (variacion ?? 0).abs().toStringAsFixed(2),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: subiendo
                                          ? AppColors.success
                                          : Colors.redAccent,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Text(
                                  'CUP',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: p.ink2,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _pastillaDetalles(acento, p),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconoMoneda(String codigo, bool esUsd, _Pal p) {
    if (esUsd) {
      return Container(
        width: 66,
        height: 66,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: p.oscuro ? const Color(0xFF232733) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(p.oscuro ? 0.35 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: CustomPaint(painter: _BanderaPainter()),
        ),
      );
    }
    return Container(
      width: 66,
      height: 66,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            p.verde.withOpacity(0.92),
            p.oscuro ? const Color(0xFF2A8F55) : const Color(0xFF2E9E57),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: p.verde.withOpacity(p.oscuro ? 0.25 : 0.30),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Text(
        codigo.length > 4 ? codigo.substring(0, 4) : codigo,
        style: GoogleFonts.plusJakartaSans(
          fontSize: codigo.length > 3 ? 15 : 19,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _pastillaDetalles(Color acento, _Pal p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: acento.withOpacity(p.oscuro ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_rounded, size: 22, color: acento),
          const SizedBox(width: 7),
          Text(
            'Ver detalles',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: acento,
            ),
          ),
          const SizedBox(width: 8),
          Icon(CupertinoIcons.chevron_right, size: 14, color: acento),
        ],
      ),
    );
  }

  // ─── Tarjeta "Información importante" ─────────────────────────────────
  Widget _tarjetaInfo(_Pal p, String? ultimaActualizacion) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.verde.withOpacity(p.oscuro ? 0.10 : 0.09),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.verde.withOpacity(p.oscuro ? 0.22 : 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.verde.withOpacity(p.oscuro ? 0.20 : 0.16),
            ),
            child: Icon(Icons.stacked_bar_chart_rounded,
                size: 28, color: p.verde),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Información importante',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Los valores son referenciales y pueden variar respecto '
                  'al mercado real. Datos proporcionados por elTOQUE.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: p.ink2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tasa Representativa del Mercado Informal (TRMI), '
                  'fuente: elTOQUE. Actualizado: '
                  '${_formatFecha(ultimaActualizacion)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: p.ink2.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _estadoVacio(
    _Pal p, {
    required IconData icon,
    required String titulo,
    required String mensaje,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: p.ink2),
            const SizedBox(height: 12),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: p.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                height: 1.4,
                color: p.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Fondo: manchas verdes arriba y ola inferior ────────────────────────
class _FondoPainter extends CustomPainter {
  _FondoPainter(this.oscuro);
  final bool oscuro;

  @override
  void paint(Canvas canvas, Size size) {
    final verde = const Color(0xFF3DBE6B);
    final a = oscuro ? 0.07 : 0.10;

    // Mancha arriba-izquierda
    canvas.drawCircle(
      Offset(size.width * 0.05, size.height * 0.03),
      size.width * 0.42,
      Paint()..color = verde.withOpacity(a),
    );
    // Mancha grande detrás de la ilustración
    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.17),
      size.width * 0.50,
      Paint()..color = verde.withOpacity(a * 0.8),
    );

    // Ola inferior
    final path = Path()
      ..moveTo(0, size.height * 0.87)
      ..cubicTo(
        size.width * 0.25, size.height * 0.84,
        size.width * 0.55, size.height * 0.95,
        size.width, size.height * 0.89,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = verde.withOpacity(a * 1.1));
  }

  @override
  bool shouldRepaint(covariant _FondoPainter old) => old.oscuro != oscuro;
}

// ─── Ola suave dentro de las tarjetas ───────────────────────────────────
class _OndaPainter extends CustomPainter {
  _OndaPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.80)
      ..cubicTo(
        size.width * 0.30, size.height * 0.62,
        size.width * 0.62, size.height * 1.02,
        size.width, size.height * 0.66,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _OndaPainter old) => old.color != color;
}

// ─── Bandera de EE. UU. dibujada (sin assets) ───────────────────────────
class _BanderaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final franja = h / 13;

    for (var i = 0; i < 13; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * franja, w, franja + 0.5),
        Paint()
          ..color =
              i.isEven ? const Color(0xFFD9363E) : const Color(0xFFFFFFFF),
      );
    }

    final canton = Rect.fromLTWH(0, 0, w * 0.52, franja * 7);
    canvas.drawRect(canton, Paint()..color = const Color(0xFF3C4FA0));

    final estrella = Paint()..color = Colors.white;
    const filas = 5;
    const cols = 6;
    for (var f = 0; f < filas; f++) {
      for (var c = 0; c < cols; c++) {
        canvas.drawCircle(
          Offset(
            canton.left + canton.width * (c + 0.7) / (cols + 0.4),
            canton.top + canton.height * (f + 0.6) / (filas + 0.2),
          ),
          w * 0.018,
          estrella,
        );
      }
    }

    // Brillo suave tipo icono 3D
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.18),
            Colors.transparent,
            Colors.black.withOpacity(0.05),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
