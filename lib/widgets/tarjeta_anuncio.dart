// tarjeta_anuncio.dart
//
// REDISEÑO "VIDRIO VIVO" (2026-08):
// Segunda pasada sobre el vidrio flotante: la versión anterior ya
// tenía blur real + borde en degradado, pero se sentía "apagada" --
// un panel gris con un chip de color adentro. Esta versión toma
// prestado el lenguaje de los banners de delivery/promos (foto
// grande que se "asoma" fuera de la tarjeta, sello circular,
// llamado a la acción con flecha) pero sin salirse de la paleta
// AppColors ni del estilo vidrio esmerilado que ya usa el resto de
// la app:
//   - El propio VIDRIO se tiñe con el color del tipo de anuncio
//     (Color.alphaBlend sobre la superficie translúcida de siempre)
//     en vez de quedar gris neutro -- cada tipo tiene su "cristal".
//   - Dos manchas de color muy difusas detrás del contenido, como el
//     resplandor de un letrero de neón a través del vidrio.
//   - La foto ya no vive metida en un cuadrado quieto: se recorta en
//     una tarjeta redondeada que se asoma por arriba/abajo del borde
//     de la tarjeta (efecto "sticker"), con un sello circular
//     pulsante en la esquina (ícono según el tipo).
//   - El badge de etiqueta lleva un emoji + texto, y late suave
//     (opacidad + escala) los primeros segundos para captar el ojo
//     en el feed, luego se detiene (_Pulso) para no gastar batería
//     en sesiones de scroll largas.
//   - Nuevo botón/pill de llamado a la acción ("Ver oferta" / "Ver en
//     [tienda]") con flecha, mismo color de acento.
//
// REGLA DE COLOR POR TIPO (sin cambios respecto a la versión previa):
//   - Producto POTENCIADO (id_producto presente): degradado DORADO --
//     mismo lenguaje "premium/VIP" que el resto de la app (_kDorado
//     en mapa_tiendas_screen.dart, badge "TIENDA VIP" en
//     home_screen.dart). Etiqueta: "Promoción Pagada" + sello ⭐.
//   - Promo de tienda libre (tipo='producto' sin id_producto):
//     degradado AppColors.primary (coral de marca). Etiqueta:
//     "Promoción Pagada" + sello 🔥.
//   - Anuncio de NEGOCIO: degradado verde identidad (_kColorNegocio,
//     el mismo 0xFF0D9488 de negocio_screen.dart). Sello 📍.
//   - Anuncio ADMIN (carrusel superior, "Promoción de
//     Administración"): degradado morado (_kColorAdmin). Sello 📣.
//
// Reemplazo DROP-IN: mismas clases públicas (TarjetaAnuncio,
// TarjetaCarruselAnuncio), mismos parámetros, misma lógica de
// navegación/clic -- solo cambia la piel visual.

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../core/app_colors.dart';
import '../services/anuncios_service.dart';
import 'product_detail_modal.dart';

// ---------------------------------------------------------------------
// COLORES DE ACENTO POR TIPO
// ---------------------------------------------------------------------

/// Dorado premium -- mismo tono que las insignias VIP del resto de la
/// app (mapa_tiendas_screen._kDorado, home_screen._kGold), para que
/// "dorado" signifique siempre lo mismo en toda la interfaz.
const Color _kPremium = Color(0xFFF97316);
const Color _kPremiumClaro = Color(0xFFFDBA74);
const Color _kAdmin = Color(0xFF6D28D9);
const Color _kAdminClaro = Color(0xFFA78BFA);
const Color _kNegocio = Color(0xFF059669);
const Color _kNegocioClaro = Color(0xFF34D399);

/// ¿Este anuncio es un producto POTENCIADO (viene con id_producto)?
/// Esos son los que la tienda pagó para destacar un artículo puntual
/// -- se tratan como "premium" y llevan el borde dorado. La promo de
/// tienda "libre" (sin producto concreto) usa el color de marca.
bool _esPotenciado(Anuncio a) => a.tipo == 'producto' && a.idProducto != null;

/// Color de acento (badge, sello, CTA, resplandor) según el tipo real
/// del anuncio.
Color _colorAcento(Anuncio a) {
  if (_esPotenciado(a)) return _kPremium;
  switch (a.tipo) {
    case 'admin':
      return _kAdmin;
    case 'negocio':
      return _kNegocio;
    default:
      return AppColors.primary;
  }
}

/// Segundo tono (más claro) para armar degradados de dos puntas --
/// bordes, sellos y CTAs siempre combinan estos dos, nunca un color
/// plano solo, para que se sientan "vivos" en vez de planos.
Color _colorAcentoClaro(Anuncio a) {
  if (_esPotenciado(a)) return _kPremiumClaro;
  switch (a.tipo) {
    case 'admin':
      return _kAdminClaro;
    case 'negocio':
      return _kNegocioClaro;
    default:
      return AppColors.primaryDark;
  }
}

/// Degradado del borde de vidrio.
List<Color> _degradadoBorde(Anuncio a) {
  final claro = _colorAcentoClaro(a);
  final base = _colorAcento(a);
  return [claro.withOpacity(1.0), base.withOpacity(0.80)];
}

/// Emoji del sello/etiqueta -- el mismo lenguaje "vivo" de los
/// banners de promos (🔥 Spicy Deals) pero con el significado de cada
/// tipo de anuncio de Al Lado.
String _emojiTipo(Anuncio a) {
  if (_esPotenciado(a)) return '⭐';
  switch (a.tipo) {
    case 'admin':
      return '📣';
    case 'negocio':
      return '📍';
    default:
      return '🔥';
  }
}

/// Ícono del sello circular sobre la foto.
IconData _iconoTipo(Anuncio a) {
  if (_esPotenciado(a)) return Icons.workspace_premium_rounded;
  switch (a.tipo) {
    case 'admin':
      return Icons.campaign_rounded;
    case 'negocio':
      return Icons.storefront_rounded;
    default:
      return Icons.local_fire_department_rounded;
  }
}

// ---------------------------------------------------------------------
// "VIDA": envoltorio reutilizable que respira (opacidad + escala) al
// aparecer y se detiene solo -- mismo criterio que ya usaba el badge
// potenciado, ahora compartido por todos los acentos animados (badge,
// sello circular, CTA) para no repetir el controller en cada uno.
// ---------------------------------------------------------------------
class _Pulso extends StatefulWidget {
  final Widget child;
  final Duration duracion;
  final Duration detenerTras;
  final double escalaMin;

  const _Pulso({
    required this.child,
    this.duracion = const Duration(milliseconds: 1300),
    this.detenerTras = const Duration(seconds: 7),
    this.escalaMin = 0.93,
  });

  @override
  State<_Pulso> createState() => _PulsoState();
}

class _PulsoState extends State<_Pulso> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  Timer? _detener;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duracion)
      ..repeat(reverse: true);
    _detener = Timer(widget.detenerTras, () {
      if (mounted) _c.stop();
    });
  }

  @override
  void dispose() {
    _detener?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        final escala = widget.escalaMin + (1 - widget.escalaMin) * t;
        return Opacity(
          opacity: 0.78 + 0.22 * t,
          child: Transform.scale(scale: escala, child: child),
        );
      },
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------
// ENVOLTORIO REUTILIZABLE DE VIDRIO FLOTANTE (ahora teñido + con
// manchas de color de fondo, en vez de gris neutro).
// ---------------------------------------------------------------------
class _VidrioFlotante extends StatelessWidget {
  final Widget child;
  final List<Color> colores;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry padding;
  final Color? colorFondo;
  final Color? tinte;
  final bool conBlobs;

  const _VidrioFlotante({
    required this.child,
    required this.colores,
    this.radius = 20,
    this.blur = 18,
    this.padding = EdgeInsets.zero,
    this.colorFondo,
    this.tinte,
    this.conBlobs = false,
  });

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final base = colorFondo ??
        (esOscuro
            ? AppColors.cardTransparentDark
            : AppColors.cardTransparentLight);
    // Vidrio "vivo": se mezcla una pizca del color de acento sobre la
    // superficie neutra de siempre -- sigue siendo translúcido y se
    // reconoce como el mismo vidrio flotante de toda la app, pero ya
    // no es gris inerte: cada tipo de anuncio tiñe su propio cristal.
    final fondo = tinte != null
        ? Color.alphaBlend(tinte!.withOpacity(esOscuro ? 0.30 : 0.18), base)
        : base;

    return Container(
      padding: const EdgeInsets.all(1.4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colores,
        ),
        boxShadow: [
          BoxShadow(
            color: colores.first.withOpacity(esOscuro ? 0.32 : 0.24),
            blurRadius: 24,
            offset: const Offset(0, 10),
            spreadRadius: -4,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(esOscuro ? 0.35 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1.4),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            decoration: BoxDecoration(
              color: fondo,
              borderRadius: BorderRadius.circular(radius - 1.4),
              // Brillo sutil arriba-izquierda, como un reflejo de
              // vidrio -- muy tenue para no tapar el contenido.
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(esOscuro ? 0.05 : 0.18),
                  Colors.white.withOpacity(0),
                ],
              ),
            ),
            child: Stack(
              children: [
                if (conBlobs) ..._blobs(colores.first, esOscuro),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Dos manchas de color muy difusas detrás del contenido -- el
  /// resplandor de neón a través del vidrio que hace que la tarjeta
  /// se sienta encendida, no solo "translúcida". Decorativas
  /// (IgnorePointer) y muy tenues para no competir con el texto.
  List<Widget> _blobs(Color color, bool esOscuro) {
    return [
      Positioned(
        top: -34,
        right: -18,
        child: IgnorePointer(
          child: Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                color.withOpacity(esOscuro ? 0.40 : 0.28),
                color.withOpacity(0),
              ]),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: -40,
        left: -26,
        child: IgnorePointer(
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                color.withOpacity(esOscuro ? 0.32 : 0.22),
                color.withOpacity(0),
              ]),
            ),
          ),
        ),
      ),
    ];
  }
}

// ---------------------------------------------------------------------
// TARJETA DEL FEED (horizontal, intercalada cada 3 bloques de tienda)
// ---------------------------------------------------------------------

class TarjetaAnuncio extends StatefulWidget {
  final Anuncio anuncio;
  const TarjetaAnuncio({super.key, required this.anuncio});

  @override
  State<TarjetaAnuncio> createState() => _TarjetaAnuncioState();
}

class _TarjetaAnuncioState extends State<TarjetaAnuncio> {
  Color get _colorTipo => _colorAcento(widget.anuncio);
  Color get _colorTipoClaro => _colorAcentoClaro(widget.anuncio);

  void _abrir() {
    final a = widget.anuncio;
    AnunciosService().registrarClic(a.idAnuncio);

    if (a.idProducto != null) {
      showProductDetailModal(context: context, productId: a.idProducto!);
      return;
    }
    if (a.idTienda != null) {
      context.push('/tienda/${a.idTienda}');
      return;
    }
    if (a.idNegocio != null) {
      context.push('/negocio/${a.idNegocio}');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Perfil del negocio próximamente')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.anuncio;
    final oscuro = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GestureDetector(
        onTap: _abrir,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: oscuro
                ? const Color(0xFF1E1E2E)
                : Colors.white,
            boxShadow: [
              BoxShadow(
                color: _colorTipo.withOpacity(oscuro ? 0.18 : 0.12),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(oscuro ? 0.25 : 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _badge(a),
                            if (a.titulo != null && a.titulo!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                a.titulo!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                  color: oscuro
                                      ? Colors.white
                                      : const Color(0xFF1A1A2E),
                                ),
                              ),
                            ],
                            if (a.texto != null && a.texto!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                a.texto!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  height: 1.3,
                                  color: oscuro
                                      ? Colors.white54
                                      : const Color(0xFF6B7280),
                                ),
                              ),
                            ],
                            const Spacer(),
                            _botonCta(a),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 4, top: 4, bottom: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: (a.imagenUrl != null &&
                                    a.imagenUrl!.isNotEmpty)
                                ? Image.network(
                                    a.imagenUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _placeholderImagen(_colorTipo),
                                  )
                                : _placeholderImagen(_colorTipo),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: _Pulso(
                              escalaMin: 0.92,
                              child: Container(
                                padding: const EdgeInsets.all(4.5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [_colorTipoClaro, _colorTipo],
                                  ),
                                  border: Border.all(
                                      color: Colors.white, width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: Icon(_iconoTipo(a),
                                    size: 10, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        bottomLeft: Radius.circular(20),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [_colorTipoClaro, _colorTipo],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(Anuncio a) {
    final texto = '${_emojiTipo(a)}  ${a.etiquetaFinal.toUpperCase()}';
    return _Pulso(
      escalaMin: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [_colorTipoClaro, _colorTipo]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          texto,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _botonCta(Anuncio a) {
    final label = (a.destinoNombre != null && a.destinoNombre!.isNotEmpty)
        ? 'Ver en ${a.destinoNombre}'
        : 'Ver oferta';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_colorTipo, _colorTipoClaro],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _colorTipo.withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 3),
          const Icon(Icons.arrow_forward_rounded, size: 11, color: Colors.white),
        ],
      ),
    );
  }

  Widget _placeholderImagen(Color color) => Container(
        color: color.withOpacity(0.12),
        alignment: Alignment.center,
        child: Icon(Icons.campaign_rounded, color: color, size: 30),
      );
}

// ---------------------------------------------------------------------
// TARJETA DEL CARRUSEL SUPERIOR (solo tipo='admin', imagen grande)
// ---------------------------------------------------------------------

/// Versión para el carrusel superior de Home: imagen a sangre completa
/// con un panel de vidrio esmerilado abajo para el título/texto, una
/// insignia con emoji arriba-izquierda y un sello circular pulsante
/// arriba-derecha -- mismo remate visual que la tarjeta del feed, para
/// que ambas se sientan parte de la misma familia.
class TarjetaCarruselAnuncio extends StatelessWidget {
  final Anuncio anuncio;
  const TarjetaCarruselAnuncio({super.key, required this.anuncio});

  void _abrir(BuildContext context) {
    final a = anuncio;
    AnunciosService().registrarClic(a.idAnuncio);

    if (a.idProducto != null) {
      showProductDetailModal(context: context, productId: a.idProducto!);
      return;
    }
    if (a.idTienda != null) {
      context.push('/tienda/${a.idTienda}');
      return;
    }
    if (a.idNegocio != null) {
      context.push('/negocio/${a.idNegocio}');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Perfil del negocio próximamente')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = anuncio;
    final colorTipo = _colorAcento(a);
    final colorClaro = _colorAcentoClaro(a);
    final borde = _degradadoBorde(a);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => _abrir(context),
        child: Container(
          padding: const EdgeInsets.all(1.8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: borde,
            ),
            boxShadow: [
              BoxShadow(
                color: borde.first.withOpacity(0.4),
                blurRadius: 26,
                offset: const Offset(0, 12),
                spreadRadius: -6,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20.2),
            child: Stack(
              fit: StackFit.expand,
              children: [
                (a.imagenUrl != null && a.imagenUrl!.isNotEmpty)
                    ? Image.network(
                        a.imagenUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: colorTipo.withOpacity(0.12)),
                      )
                    : Container(color: colorTipo.withOpacity(0.12)),
                // Degradado teñido con el color del tipo -- ya no es
                // un negro plano abajo: se ve el "neón" de la
                // categoría incluso en la sombra que sostiene el
                // texto legible.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color.alphaBlend(
                            colorTipo.withOpacity(0.38),
                            Colors.black.withOpacity(0.55),
                          ),
                        ],
                        stops: const [0.35, 1.0],
                      ),
                    ),
                  ),
                ),
                // Panel de vidrio inferior (blur real) con título/texto.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          border: Border(
                            top: BorderSide(
                              color: Colors.white.withOpacity(0.14),
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((a.titulo ?? '').isNotEmpty)
                              Text(
                                a.titulo!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            if ((a.texto ?? '').isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                a.texto!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.white.withOpacity(0.85),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Insignia en vidrio -- emoji + etiqueta, late suave
                // los primeros segundos.
                Positioned(
                  top: 10,
                  left: 10,
                  child: _Pulso(
                    escalaMin: 0.96,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                colorClaro.withOpacity(0.75),
                                colorTipo.withOpacity(0.75),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.3)),
                          ),
                          child: Text(
                            '${_emojiTipo(a)}  ${a.etiquetaFinal.toUpperCase()}',
                            style: GoogleFonts.inter(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Sello circular -- remata la composición igual que
                // en la tarjeta del feed, mismo ícono por tipo.
                Positioned(
                  top: 10,
                  right: 10,
                  child: _Pulso(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [colorClaro, colorTipo],
                        ),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.85), width: 2),
                        boxShadow: [
                          BoxShadow(
                              color: colorTipo.withOpacity(0.55),
                              blurRadius: 12),
                        ],
                      ),
                      child: Icon(_iconoTipo(a), size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
