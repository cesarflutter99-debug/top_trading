// paquete_anuncios_tienda_sheet.dart
//
// COMPATIBILIDAD. Las "ranuras extra de tienda" ya no son un sistema
// aparte: se compran como cualquier paquete de anuncio y suman al mismo
// pool de ranuras del usuario (plan + paquetes).

import 'package:flutter/material.dart';
import '../screens/standalone_anuncio_screen.dart';

Future<void> mostrarPaqueteAnunciosTiendaSheet(
  BuildContext context,
  Map<String, dynamic> tienda,
) {
  return mostrarPlanesStandaloneSheet(context);
}
