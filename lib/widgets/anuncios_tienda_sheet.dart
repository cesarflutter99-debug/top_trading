// anuncios_tienda_sheet.dart
//
// COMPATIBILIDAD. La antigua hoja "Anuncios y promociones" de la tienda
// (potenciar producto / crear anuncio / mis anuncios) se unificó con el
// anuncio independiente: ahora todo se publica desde
// StandaloneAnuncioScreen (con selector "Un producto mío / Mi tienda").
//
// Se conserva esta función con la MISMA firma para que los accesos que
// aún la llaman (menú de Mi Tienda, notificaciones) sigan funcionando.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/standalone_anuncio_screen.dart';
import '../services/storage_service.dart';

/// Con [destacarAnuncioId] abre la gestión de ESE anuncio; sin él, abre el
/// formulario unificado.
Future<void> mostrarAnunciosSheet(
  BuildContext context,
  Map<String, dynamic> tienda, {
  String? destacarAnuncioId,
}) async {
  final id = destacarAnuncioId;
  if (id != null && id.isNotEmpty) {
    await context.push('/mis-anuncios/$id');
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(
        builder: (_) =>
            const StandaloneAnuncioScreen(destinoInicial: 'producto')),
  );
}

/// Envoltura mínima sobre StorageService.elegirFoto().
class ImagePickerHost {
  final StorageService _storage = StorageService();

  Future<File?> elegirFoto({bool desdeCamara = false}) =>
      _storage.elegirFoto(desdeCamara: desdeCamara);
}
