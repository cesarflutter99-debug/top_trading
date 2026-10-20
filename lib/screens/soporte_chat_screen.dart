// soporte_chat_screen.dart
//
// Chat de soporte entre el usuario y el equipo de Al Lado.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/soporte_service.dart';

class SoporteChatScreen extends StatefulWidget {
  const SoporteChatScreen({super.key});

  @override
  State<SoporteChatScreen> createState() => _SoporteChatScreenState();
}

class _SoporteChatScreenState extends State<SoporteChatScreen> {
  final _service = SoporteService.instance;
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  String? _idChat;
  List<Map<String, dynamic>> _mensajes = [];
  bool _cargando = true;
  bool _enviando = false;
  RealtimeChannel? _canal;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      final id = await _service.obtenerOCrearChat();
      final msgs = await _service.mensajes(id);
      _canal = _service.suscribir(id, _recargar);
      if (mounted) {
        setState(() {
          _idChat = id;
          _mensajes = msgs;
          _cargando = false;
        });
        _bajarAlFinal();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _recargar() async {
    if (_idChat == null) return;
    final msgs = await _service.mensajes(_idChat!);
    if (mounted) {
      setState(() => _mensajes = msgs);
      _bajarAlFinal();
    }
  }

  void _bajarAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _enviar() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty || _idChat == null || _enviando) return;
    setState(() => _enviando = true);
    _ctrl.clear();
    try {
      await _service.enviar(_idChat!, texto);
      await _recargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  void dispose() {
    _canal?.unsubscribe();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Soporte Al Lado'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: _mensajes.length,
                    itemBuilder: (context, i) {
                      final m = _mensajes[_mensajes.length - 1 - i];
                      final esAdmin = m['es_admin'] == true;
                      return Align(
                        alignment:
                            esAdmin ? Alignment.centerLeft : Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: esAdmin
                                ? (esOscuro
                                    ? const Color(0xFF2C2C2E)
                                    : const Color(0xFFF3F4F6))
                                : AppColors.primary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            m['contenido']?.toString() ?? '',
                            style: GoogleFonts.plusJakartaSans(
                              color: esAdmin
                                  ? (esOscuro
                                      ? Colors.white
                                      : Colors.black87)
                                  : Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: 'Escribe tu mensaje…',
                              filled: true,
                              fillColor: esOscuro
                                  ? Colors.white.withOpacity(0.06)
                                  : const Color(0xFFF3F4F6),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                            onSubmitted: (_) => _enviar(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: _enviando
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.send_rounded),
                          color: AppColors.primary,
                          onPressed: _enviar,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
