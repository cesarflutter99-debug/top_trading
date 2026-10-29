// tour_anchor.dart
//
// Sistema de anclas para los tours contextuales (coach marks).
//
// PROBLEMA que resuelve: antes, el foco del tour se calculaba a mano
// dividiendo el ancho de la barra de navegación entre 5 (o 6). La barra
// tiene padding lateral (SafeArea + Container), asi que el centro
// calculado NO coincidia con el icono real -> el tour "salia corrido".
//
// Aqui cada elemento a destacar se envuelve en un [TourAnchor] con un id
// unico. El anchor guarda su propia GlobalKey, de modo que el rect se
// puede resolver en el instante exacto de mostrar el tour (por el
// RenderBox real del widget), con precision de pixel.
//
// Uso:
//
//   TourAnchor(
//     id: TourAnclas.navMapa,
//     child: _ItemNav(...),
//   )
//
// y en el tour:
//
//   CoachStep(
//     titulo: 'Explorá el mapa',
//     descripcion: '...',
//     ancla: TourAnclas.navMapa,
//   )
import 'package:flutter/material.dart';

/// Registro global de anclas vivas. Cada [TourAnchor] publica aqui su
/// GlobalKey para que el tour pueda resolver el rect en el momento.
class TourRegistro {
  TourRegistro._();
  static final Map<String, GlobalKey> _anclas = {};

  static GlobalKey registrar(String id) {
    return _anclas.putIfAbsent(id, GlobalKey.new);
  }

  static GlobalKey? buscar(String id) => _anclas[id];

  /// Rect global (coordenadas de pantalla) del widget anclado, o null si
  /// no esta montado todavia. Se calcula en vivo desde el RenderBox.
  static Rect? rectDe(String id, {double padding = 0}) {
    final key = _anclas[id];
    if (key == null) return null;
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final render = ctx.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return null;
    final origen = render.localToGlobal(Offset.zero);
    final rect = origen & render.size;
    return padding == 0 ? rect : rect.inflate(padding);
  }
}

/// Envuelve un widget para que pueda ser destacado por un tour.
class TourAnchor extends StatelessWidget {
  final String id;
  final Widget child;

  const TourAnchor({super.key, required this.id, required this.child});

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: TourRegistro.registrar(id), child: child);
  }
}

/// Ids de todas las anclas usadas por los tours. Centralizados aqui
/// para que no haya typos y se puedan revisar de un vistazo.
class TourAnclas {
  // --- Barra de navegación inferior (orden visual) ---
  static const navMapa = 'nav_mapa';
  static const navAnuncios = 'nav_anuncios';
  static const navInicio = 'nav_inicio';
  static const navMiTienda = 'nav_mi_tienda';
  static const navPerfil = 'nav_perfil';

  // --- Home ---
  static const homeHamburguesa = 'home_hamburguesa';
  static const homeBuscador = 'home_buscador';
  static const homeCarrusel = 'home_carrusel';

  // --- Anuncios ---
  static const anunciosChips = 'anuncios_chips';
  static const anunciosFab = 'anuncios_fab';

  // --- Mapa ---
  static const mapaBuscador = 'mapa_buscador';
  static const mapaChips = 'mapa_chips';

  // --- Perfil ---
  static const perfilAvatar = 'perfil_avatar';
  static const perfilTabs = 'perfil_tabs';

  // --- Tienda ---
  static const tiendaAgregarCarrito = 'tienda_agregar_carrito';

  // --- Carrito ---
  static const carritoTotal = 'carrito_total';
  static const carritoConfirmar = 'carrito_confirmar';

  // --- Mis pedidos ---
  static const pedidosTabs = 'pedidos_tabs';

  // --- Asistente (Preguntas frecuentes) ---
  static const asistenteEntrada = 'asistente_entrada';
  static const asistenteTopics = 'asistente_topics';

  // --- Favoritos ---
  static const favoritosLista = 'favoritos_lista';

  // --- Mis pedidos ---
  static const pedidosLista = 'pedidos_lista';

  // --- Soporte ---
  static const soporteEntrada = 'soporte_entrada';

  // --- Mi Tienda ---
  static const miTiendaProductos = 'mi_tienda_productos';
  static const miTiendaNuevo = 'mi_tienda_nuevo';
}
