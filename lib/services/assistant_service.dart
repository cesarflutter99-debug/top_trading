// assistant_service.dart
//
// Servicio del Asistente Guiado (FAQ interactivo) 100% offline-first:
// el catálogo de preguntas/respuestas/atajos vive en el código (Dart),
// no se trae nada de la red. La búsqueda por palabras clave filtra
// localmente (sin acentos ni mayúsculas), así funciona también sin
// conexión y sin gastar datos.
//
// Patrón singleton (igual que CacheOfflineService / ConnectivityService).

import '../models/assistant_topic.dart';

class AssistantService {
  AssistantService._();
  static final instance = AssistantService._();

  /// Catálogo curado de FAQ de "Al Lado". Las rutas de los atajos deben
  /// existir en router.dart (solo las que NO requieren `extra` para que
  /// un push() desde una burbuja funcione directo).
  static final List<AssistantTopic> _catalogo = [
    const AssistantTopic(
      id: 'crear_tienda',
      pregunta: '¿Cómo creo mi tienda y empiezo a vender?',
      respuesta:
          'Para vender en "Al Lado" tocá "Hacerte vendedor" desde tu perfil. '
          'Elegís el plan, completás el registro y tras el pago tu tienda '
          'queda activa. Podés publicar productos, ver el panel de ventas y '
          'marcarlos como favoritos más fácil.',
      keywords: [
        'tienda',
        'vender',
        'vendedor',
        'crear',
        'registrar',
        'publicar',
        'plan',
        'vendedor',
      ],
      atajos: [
        AssistantShortcut(label: 'Crear mi tienda', ruta: '/crear-tienda'),
      ],
    ),
    const AssistantTopic(
      id: 'negocio',
      pregunta: 'Tengo un negocio de servicios, ¿cómo lo promociono?',
      respuesta:
          'Si tenés un negocio (barbería, taller, reparto...) registralo '
          'desde "Promociona tu negocio". Necesitás un permiso vigente: '
          'los anuncios de negocio pasan por moderación y luego se muestran '
          'solo en tu feed.',
      keywords: [
        'negocio',
        'servicio',
        'promocionar',
        'permiso',
        'anuncio',
        'barbería',
      ],
      atajos: [
        AssistantShortcut(label: 'Registrar mi negocio', ruta: '/registrar-negocio'),
      ],
    ),
    const AssistantTopic(
      id: 'comprar',
      pregunta: '¿Cómo compro un producto?',
      respuesta:
          'Buscá en el mapa o en la pestaña Inicio, entrá a la tienda, '
          'agregá productos al carrito y confirmá el pedido. El vendedor lo '
          've al instante y coordinan la entrega. Podés revisar tus pedidos '
          'en la sección "Mis pedidos".',
      keywords: [
        'comprar',
        'carrito',
        'pedido',
        'producto',
        'tienda',
        'pago',
        'entrega',
      ],
      atajos: [
        AssistantShortcut(label: 'Mapa de tiendas', ruta: '/mapa'),
        AssistantShortcut(label: 'Mis pedidos', ruta: '/mis-pedidos'),
      ],
    ),
    const AssistantTopic(
      id: 'precios',
      pregunta: '¿En qué moneda aparecen los precios?',
      respuesta:
          'Los precios se muestran en CUP y se convierten automáticamente '
          'según la tasa del día. Si la conversión no está disponible '
          '(sin conexión) se usa la última tasa guardada.',
      keywords: [
        'precio',
        'moneda',
        'cup',
        'usd',
        'tasa',
        'cambio',
        'dinero',
      ],
    ),
    const AssistantTopic(
      id: 'ubicacion',
      pregunta: '¿Cómo funciona la ubicación y el mapa?',
      respuesta:
          'El mapa muestra tiendas cerca de vos usando tu ubicación '
          'geográfica. Activá el permiso de ubicación cuando la app lo pida; '
          'si lo negás podés seguir buscando sin el mapa cercano.',
      keywords: [
        'mapa',
        'ubicación',
        'gps',
        'cerca',
        'distancia',
        'geolocalización',
        'municipio',
      ],
      atajos: [
        AssistantShortcut(label: 'Ver el mapa', ruta: '/mapa'),
      ],
    ),
    const AssistantTopic(
      id: 'anuncios',
      pregunta: '¿Qué son los anuncios de la app?',
      respuesta:
          'Son promociones que aparecen en el feed: de tiendas (productos), '
          'de negocios (servicios) y de la plataforma. Los anuncios de '
          'negocio pasan por moderación del administrador. Podés dar '
          '"me gusta" y comentar.',
      keywords: [
        'anuncio',
        'anuncios',
        'promoción',
        'feed',
        'likes',
        'comentarios',
        'moderación',
      ],
      atajos: [
        AssistantShortcut(label: 'Promocionar mi negocio', ruta: '/registrar-negocio'),
      ],
    ),
    const AssistantTopic(
      id: 'pagos_plan',
      pregunta: '¿Cómo pago mi plan o un paquete extra?',
      respuesta:
          'Los pagos se registran contra el administrador: elegís el plan, '
          'generás una solicitud y te abre el WhatsApp del admin para '
          'coordinar. Al aprobarlo, tu plan o permiso se activa solo. '
          'También podés comprar ranuras extra de anuncios por WhatsApp.',
      keywords: [
        'pago',
        'plan',
        'premium',
        'paquete',
        'whatsapp',
        'activar',
        'comprobante',
        'suscripción',
      ],
      atajos: [
        AssistantShortcut(label: 'Ir a mi perfil', ruta: '/mi-perfil'),
      ],
    ),
    const AssistantTopic(
      id: 'afiliados',
      pregunta: '¿Cómo puedo ganar dinero recomendando "Al Lado"?',
      respuesta:
          'Registrate como afiliado y compartí tu código al invitar vendedores. '
          'Cuando una tienda nueva se activa con tu código, vas sumando '
          'comisiones que podés ver y retirar desde tu panel de afiliado.',
      keywords: [
        'afiliado',
        'afiliados',
        'comisión',
        'referido',
        'invitar',
        'código',
        'ganar',
        'retiro',
      ],
      atajos: [
        AssistantShortcut(label: 'Registrarme como afiliado', ruta: '/afiliados/registro'),
        AssistantShortcut(label: 'Mi panel de afiliado', ruta: '/afiliados/perfil'),
      ],
    ),
    const AssistantTopic(
      id: 'perfil',
      pregunta: '¿Dónde veo mi cuenta y mis datos?',
      respuesta:
          'En la pestaña Perfil ves tu información, tus tiendas/negocios, '
          'los accesos rápidos y el modo oscuro. Si no aparecen tus datos, '
          'asegurate de haber iniciado sesión con Google.',
      keywords: ['perfil', 'cuenta', 'datos', 'sesión', 'google', 'login'],
      atajos: [
        AssistantShortcut(label: 'Ir a mi perfil', ruta: '/mi-perfil'),
      ],
    ),
    const AssistantTopic(
      id: 'notificaciones',
      pregunta: '¿Cómo funcionan las notificaciones push?',
      respuesta:
          'Recibís avisos de nuevos pedidos, mensajes y novedades de tus '
          'anuncios/pedidos. Aparecen aunque la app esté cerrada. Si no te '
          'llegan, revisá que la app tenga el permiso de notificaciones '
          'activado en tu teléfono.',
      keywords: ['notificación', 'notificaciones', 'push', 'aviso', 'permiso'],
      atajos: [
        AssistantShortcut(label: 'Ver notificaciones', ruta: '/notificaciones'),
      ],
    ),
  ];

  /// Todos los temas disponibles (catálogo offline).
  List<AssistantTopic> get todos => List.unmodifiable(_catalogo);

  /// Sugerencias para la primera burbuja del asistente.
  List<AssistantTopic> get sugerenciasIniciales =>
      _catalogo.take(4).toList(growable: false);

  /// Busca temas por palabras clave, filtrando TODO localmente.
  /// Matchea en ambas direcciones: el texto del tema que contiene la
  /// consulta (hacia adelante) y la consulta que contiene palabras del
  /// tema (hacia atrás, para "quiero publicar un anuncio" contra la
  /// keyword "publicar"). Sin distinción de mayúsculas ni acentos.
  /// NUNCA devuelve vacío: si nada matchea bien, devuelve el catálogo
  /// completo para que la pantalla siempre ofrezca opciones útiles.
  List<AssistantTopic> buscar(String consulta) {
    final normalizada = _normalizar(consulta);
    if (normalizada.isEmpty) return const [];

    final terminos =
        normalizada.split(RegExp(r'\s+')).where((t) => t.length > 1).toList();
    if (terminos.isEmpty) return const [];

    final resultados = <({AssistantTopic topico, int score})>[];
    for (final topico in _catalogo) {
      final enPregunta = _normalizar(topico.pregunta);
      final enKeywords = topico.keywords.map(_normalizar).toList();
      final enRespuesta = _normalizar(topico.respuesta);

      var score = 0;
      for (final t in terminos) {
        if (enPregunta.contains(t)) {
          score += 3;
        } else if (enKeywords.any((k) => k.contains(t))) {
          score += 2;
        } else if (enRespuesta.contains(t)) {
          score += 1;
        }
      }

      // Dirección inversa: vale que solo el TEMA contenga la palabra
      // ("exporto/tengo una tienda" -> "anuncio promoción"...). Las
      // keywords actúan como sinónimos del usuario.
      if (enKeywords.any((k) => normalizada.contains(k))) {
        score += 2;
      }
      if (enPregunta.length > 4 && normalizada.contains(enPregunta.substring(0, 4))) {
        score += 1;
      }

      if (score > 0) {
        resultados.add((topico: topico, score: score));
      }
    }

    resultados.sort((a, b) => b.score.compareTo(a.score));
    if (resultados.isEmpty) return _catalogo;
    return resultados.map((r) => r.topico).toList();
  }

  /// Quita acentos y pasa a minúsculas para comparar sin fricción.
  static String _normalizar(String texto) {
    const conAcentos =
        'áàäâéèëêíìïîóòöôúùüûñçÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑÇ';
    const sinAcentos = 'aaaaeeeeiiiioooouuuuncAAAAEEEEIIIIOOOOUUUUNC';
    final buffer = StringBuffer();
    for (final r in texto.toLowerCase().runes) {
      final i = conAcentos.indexOf(String.fromCharCode(r));
      buffer.write(i >= 0 ? sinAcentos[i] : String.fromCharCode(r));
    }
    return buffer.toString();
  }
}