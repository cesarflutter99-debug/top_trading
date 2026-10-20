// assistant_topic.dart
//
// Modelo de datos del Asistente Guiado (FAQ interactivo offline).
// Un AssistantTopic es una pregunta/respuesta del catálogo local, con
// palabras clave para el buscador y una lista opcional de "atajos
// rápidos" que abren rutas de GoRouter directamente desde una burbuja.

/// Atajo accionable dentro de una respuesta del asistente: un label
/// visible y la ruta GoRouter a la que se navega al tocarlo.
class AssistantShortcut {
  final String label;
  final String ruta;

  const AssistantShortcut({required this.label, required this.ruta});

  Map<String, dynamic> toJson() => {'label': label, 'ruta': ruta};

  factory AssistantShortcut.fromJson(Map<String, dynamic> json) =>
      AssistantShortcut(
        label: json['label'] as String? ?? '',
        ruta: json['ruta'] as String? ?? '/',
      );
}

class AssistantTopic {
  final String id;
  final String pregunta;
  final String respuesta;

  /// Palabras clave para el buscador offline (se matchean sin normalizar
  /// acentos ni mayúsculas).
  final List<String> keywords;

  /// Botones accionables que aparecen junto a la respuesta.
  final List<AssistantShortcut> atajos;

  const AssistantTopic({
    required this.id,
    required this.pregunta,
    required this.respuesta,
    this.keywords = const [],
    this.atajos = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'pregunta': pregunta,
        'respuesta': respuesta,
        'keywords': keywords,
        'atajos': atajos.map((a) => a.toJson()).toList(),
      };

  factory AssistantTopic.fromJson(Map<String, dynamic> json) =>
      AssistantTopic(
        id: json['id'] as String? ?? '',
        pregunta: json['pregunta'] as String? ?? '',
        respuesta: json['respuesta'] as String? ?? '',
        keywords: List<String>.from(json['keywords'] as List? ?? const []),
        atajos: (json['atajos'] as List? ?? const [])
            .map((a) => AssistantShortcut.fromJson(Map<String, dynamic>.from(
                a as Map)))
            .toList(),
      );
}