// assistant_screen.dart
//
// Asistente Guiado (FAQ interactivo) en formato chat: burbujas de
// mensaje como un chat real, buscador por palabras clave 100% local
// (offline-first, cero datos) y botones clicables que abren rutas de
// GoRouter directo. Reemplaza la "Sección en construcción" de las
// Preguntas Frecuentes (abierto con context.push('/asistente')) y se
// registra en router.dart.
//
// Entradas:
//   - el usuario escribe una consulta en el campo inferior,
//   - o toca una "opción" (pregunta sugerida) mostrada como chip.
// El asistente responde con la(s) respuesta(s) del catálogo local y,
// cuando el tema tiene atajos, con botones accionables.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../models/assistant_topic.dart';
import '../services/assistant_service.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

/// Un mensaje de la conversación.
class _Msg {
  final bool deUsuario;
  final String texto;
  final List<AssistantShortcut> atajos;
  final List<AssistantTopic> opciones;

  const _Msg(
    this.texto, {
    this.deUsuario = false,
    this.atajos = const [],
    this.opciones = const [],
  });
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _comentarioCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_Msg> _mensajes = [];
  bool _escribiendo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _recibirBienvenida();
    });
  }

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _recibirBienvenida() {
    final sugerencias = AssistantService.instance.sugerenciasIniciales;
    setState(() {
      _mensajes.add(_Msg(
        '¡Hola! Soy el asistente de Al Lado 😊 Contame qué querés hacer '
        'y te doy el paso a paso con botones directos. Por ejemplo: '
        '"cómo creo mi tienda", "quiero publicar un anuncio", '
        '"dónde veo mis pedidos"...',
        opciones: sugerencias,
      ));
    });
    _bajarAlFondo();
  }

  Future<void> _enviarConsulta(String consulta) async {
    final query = consulta.trim();
    if (query.isEmpty || _escribiendo) return;

    setState(() {
      _mensajes.add(_Msg(query, deUsuario: true));
      _escribiendo = true;
    });
    _bajarAlFondo();

    // Pequeña pausa para la sensación de chat (todo local, sin red).
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    _responder(query);
    setState(() => _escribiendo = false);
    _bajarAlFondo();
  }

  void _responder(String consulta) {
    // La búsqueda nunca viene vacía (AssistantService devuelve el
    // catálogo completo si nada matchea bien). El MEJOR resultado se
    // responde SIEMPRE con su solución y sus atajos accionables; el
    // resto queda como chips por si quiere ampliar otra opción.
    final resultados = AssistantService.instance.buscar(consulta);
    final principal = resultados.first;
    final extras = resultados.skip(1).take(3).toList();

    setState(() {
      _mensajes.add(_Msg(
        principal.respuesta,
        atajos: principal.atajos,
        opciones: extras,
      ));
    });
  }

  void _bajarAlFondo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  void _tocarOpcion(AssistantTopic topico) {
    _comentarioCtrl.clear();
    _enviarConsulta(topico.pregunta);
  }

  void _tocarAtajo(AssistantShortcut atajo) {
    context.push(atajo.ruta);
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistente'),
        actions: [
          IconButton(
            tooltip: 'Reiniciar',
            onPressed: () {
              _comentarioCtrl.clear();
              setState(_mensajes.clear);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _recibirBienvenida();
              });
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _mensajes.length + (_escribiendo ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= _mensajes.length) {
                  return const _BurbujaAsistenteEsperando();
                }
                final msg = _mensajes[i];
                if (msg.deUsuario) {
                  return _BurbujaUsuario(texto: msg.texto);
                }
                return _BurbujaAsistente(
                  texto: msg.texto,
                  atajos: msg.atajos,
                  opciones: msg.opciones,
                  onTocarAtajo: _tocarAtajo,
                  onTocarOpcion: _tocarOpcion,
                );
              },
            ),
          ),
          _barraEntrada(context, esOscuro),
        ],
      ),
    );
  }

  Widget _barraEntrada(BuildContext context, bool esOscuro) {
    final borde =
        esOscuro ? AppColors.borderDark : AppColors.borderLight;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: esOscuro ? const Color(0xFF2C2C2E) : const Color(0xFFF5F5F7),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: borde.withOpacity(0.6)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _comentarioCtrl,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (v) {
                    final q = v.trim();
                    if (q.isEmpty) return;
                    _enviarConsulta(q);
                  },
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'Escribí tu consulta...',
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  final q = _comentarioCtrl.text.trim();
                  if (q.isEmpty) return;
                  _comentarioCtrl.clear();
                  _enviarConsulta(q);
                },
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------- Burbujas ----------------------------------

class _BurbujaUsuario extends StatelessWidget {
  final String texto;
  const _BurbujaUsuario({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 6, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(
          texto,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            height: 1.4,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _BurbujaAsistente extends StatelessWidget {
  final String texto;
  final List<AssistantShortcut> atajos;
  final List<AssistantTopic> opciones;
  final void Function(AssistantShortcut) onTocarAtajo;
  final void Function(AssistantTopic) onTocarOpcion;

  const _BurbujaAsistente({
    required this.texto,
    required this.atajos,
    required this.opciones,
    required this.onTocarAtajo,
    required this.onTocarOpcion,
  });

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final fondoBurbuja = esOscuro ? const Color(0xFF26262A) : const Color(0xFFF0F0F5);
    final textoColor =
        esOscuro ? AppColors.inkDark : AppColors.inkLight;

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.assistant_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              margin: const EdgeInsets.only(right: 32),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: fondoBurbuja,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    texto,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      height: 1.45,
                      color: textoColor,
                    ),
                  ),
                  if (opciones.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _ChipsOpciones(opciones: opciones, onTap: onTocarOpcion),
                  ],
                  if (atajos.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _ChipsAtajos(atajos: atajos, onTap: onTocarAtajo),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BurbujaAsistenteEsperando extends StatefulWidget {
  const _BurbujaAsistenteEsperando();

  @override
  State<_BurbujaAsistenteEsperando> createState() =>
      _BurbujaAsistenteEsperandoState();
}

class _BurbujaAsistenteEsperandoState extends State<_BurbujaAsistenteEsperando> {
  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.assistant_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: (esOscuro ? const Color(0xFF26262A) : const Color(0xFFF0F0F5)),
              borderRadius: const BorderRadius.all(Radius.circular(18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Punto(vibrar: true),
                const SizedBox(width: 5),
                _Punto(retraso: const Duration(milliseconds: 150)),
                const SizedBox(width: 5),
                _Punto(retraso: const Duration(milliseconds: 300)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Puntito de "escribiendo..." con animación de pulso.
class _Punto extends StatefulWidget {
  final bool vibrar;
  final Duration? retraso;
  const _Punto({this.vibrar = false, this.retraso});

  @override
  State<_Punto> createState() => _PuntoState();
}

class _PuntoState extends State<_Punto> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.retraso != null) {
      Future.delayed(widget.retraso!, () {
        if (mounted) _ctrl.repeat(reverse: true);
      });
    } else {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vibrar) {
      // Vibra verticalmente (más parecido a WhatsApp).
      return AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => Transform.translate(
          offset: Offset(0, -2 * _ctrl.value),
          child: _Circulo(),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Opacity(
        opacity: 0.35 + 0.65 * _ctrl.value,
        child: _Circulo(),
      ),
    );
  }
}

class _Circulo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: AppColors.inkSecundarioLight,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Chips tipo pregunta (opciones para afinar la consulta).
class _ChipsOpciones extends StatelessWidget {
  final List<AssistantTopic> opciones;
  final void Function(AssistantTopic) onTap;

  const _ChipsOpciones({required this.opciones, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in opciones)
          ActionChip(
            label: Text(o.pregunta, maxLines: 1, overflow: TextOverflow.ellipsis),
            avatar: const Icon(Icons.question_answer_outlined, size: 16),
            onPressed: () => onTap(o),
          ),
      ],
    );
  }
}

/// Chips accionables: abren una ruta de GoRouter directo.
class _ChipsAtajos extends StatelessWidget {
  final List<AssistantShortcut> atajos;
  final void Function(AssistantShortcut) onTap;

  const _ChipsAtajos({required this.atajos, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in atajos)
          ActionChip(
            label: Text(a.label),
            avatar: const Icon(Icons.north_east_rounded, size: 16),
            onPressed: () => onTap(a),
            backgroundColor: AppColors.primary.withOpacity(0.12),
            labelStyle: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
              side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
            ),
          ),
      ],
    );
  }
}

