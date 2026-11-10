// imagen_red.dart
//
// Imágenes de red CON CACHÉ EN DISCO (modo offline tipo Facebook).
//
// Problema que resuelve: Image.network y NetworkImage solo guardan la foto
// en memoria mientras la app está abierta; al cerrarla se pierde y sin
// internet las fotos salen en blanco. Estas piezas guardan cada foto en el
// disco del teléfono la primera vez que se ve con conexión, y las muestran
// desde ahí después, incluso en modo avión y tras reiniciar la app.
//
// USO (misma sintaxis que las originales, solo cambia el nombre):
//   Image.network(url, fit: BoxFit.cover)   ->  ImagenRed(url, fit: BoxFit.cover)
//   NetworkImage(url)                        ->  imagenRed(url)
//
// LÍMITE: se guardan hasta 1.000 imágenes durante 60 días; al pasarse se
// borran las menos usadas. Las fotos de ImageKit ya vienen comprimidas
// (unos 50-150 KB), así que el máximo ronda los 100 MB.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class AppImageCache {
  AppImageCache._();

  static const String clave = 'top_trading_imagenes';

  static final CacheManager instance = CacheManager(
    Config(
      clave,
      stalePeriod: const Duration(days: 60),
      maxNrOfCacheObjects: 1000,
    ),
  );

  /// Borra todas las imágenes guardadas (por si algún día hace falta
  /// liberar espacio, p. ej. desde un botón en Ajustes).
  static Future<void> vaciar() => instance.emptyCache();
}

/// Reemplazo de `NetworkImage(url)`: devuelve un ImageProvider que guarda
/// la imagen en disco. Sirve en CircleAvatar.backgroundImage,
/// DecorationImage.image, precacheImage, etc.
ImageProvider imagenRed(
  String url, {
  double scale = 1.0,
  Map<String, String>? headers,
}) {
  return CachedNetworkImageProvider(
    url,
    scale: scale,
    headers: headers,
    cacheManager: AppImageCache.instance,
  );
}

/// Reemplazo de `Image.network(url, ...)` con los mismos parámetros.
class ImagenRed extends StatelessWidget {
  const ImagenRed(
    this.src, {
    super.key,
    this.scale = 1.0,
    this.frameBuilder,
    this.loadingBuilder,
    this.errorBuilder,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.width,
    this.height,
    this.color,
    this.opacity,
    this.colorBlendMode,
    this.fit,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.centerSlice,
    this.matchTextDirection = false,
    this.gaplessPlayback = false,
    this.isAntiAlias = false,
    this.headers,
    this.cacheWidth,
    this.cacheHeight,
    this.filterQuality = FilterQuality.low,
  });

  final String src;
  final double scale;
  final ImageFrameBuilder? frameBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;
  final String? semanticLabel;
  final bool excludeFromSemantics;
  final double? width;
  final double? height;
  final Color? color;
  final Animation<double>? opacity;
  final BlendMode? colorBlendMode;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageRepeat repeat;
  final Rect? centerSlice;
  final bool matchTextDirection;
  final bool gaplessPlayback;
  final bool isAntiAlias;
  final Map<String, String>? headers;
  final int? cacheWidth;
  final int? cacheHeight;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    ImageProvider provider = imagenRed(src, scale: scale, headers: headers);
    if (cacheWidth != null || cacheHeight != null) {
      provider = ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, provider);
    }
    return Image(
      image: provider,
      frameBuilder: frameBuilder,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      width: width,
      height: height,
      color: color,
      opacity: opacity,
      colorBlendMode: colorBlendMode,
      fit: fit,
      alignment: alignment,
      repeat: repeat,
      centerSlice: centerSlice,
      matchTextDirection: matchTextDirection,
      gaplessPlayback: gaplessPlayback,
      isAntiAlias: isAntiAlias,
      filterQuality: filterQuality,
    );
  }
}
