// anuncios_negocio_sheet.dart
//
// COMPATIBILIDAD. La antigua hoja de anuncios del negocio (anuncio
// automático + promos con moderación) se unificó con el anuncio
// independiente. Se conserva la función con la MISMA firma para que
// cualquier acceso existente (p. ej. notificaciones) siga funcionando.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/standalone_anuncio_screen.dart';

Future<void> mostrarAnunciosNegocioSheet(
  BuildContext context,
  Map<String, dynamic> negocio, {
  String? destacarAnuncioId,
}) async {
  final id = destacarAnuncioId;
  if (id != null && id.isNotEmpty) {
    await context.push('/mis-anuncios/$id');
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const StandaloneAnuncioScreen()),
  );
}
