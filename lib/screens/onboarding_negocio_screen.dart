// onboarding_negocio_screen.dart
//
// Formulario por steps para registrar un NEGOCIO de servicios (no
// vende productos en la app): barbería, taller, joyería, consultorio...
// o un EVENTO puntual (fiesta, venta de garaje, rifa...). Copia el
// estilo del onboarding de tiendas (PageView + barra de progreso) pero
// con la identidad verde del sistema de anuncios.
//
// Pasos:
//   0. Datos básicos (nombre + WhatsApp)
//   1. Qué es (categoría con sugerencias + descripción)
//   2. Fotos (logo + portada opcional -> bucket 'negocios')
//   3. Horario (por día, con franja abre/cierra)
//   4. Ubicación (dirección + GPS)
//   5. Lista de precios opcional
//   6. Pago: elige su primer PAQUETE DE ANUNCIO + cuenta (tarjeta/QR).
//      Al tocar "Ya pagué - Enviar": crea el negocio en 'pendiente',
//      registra la compra pendiente y abre WhatsApp con el mensaje
//      pre-armado (datos del negocio + paquete + código) para que el
//      admin lo encuentre y lo apruebe.
//
// El negocio nace estado='pendiente': queda visible para el dueño pero
// el admin debe aprobarlo antes de que aparezca en el mapa/reciba ads.
// Ruta: /registrar-negocio (requiere sesión).
//
// FIX (2026-08, bug "el botón del paquete no hace nada"): el paso 6
// (pago) llamaba a `_formKeyDatos.currentState!.validate()`, pero
// `_formKeyDatos` vive en el Form del PASO 0. Como este PageView tiene
// una lista fija de `children`, en Flutter todas las páginas quedan
// montadas -- PERO si en algún momento cualquier parte del árbol de
// ese Form se reconstruye fuera de sync (p. ej. tras un rebuild
// disparado por setState en otro paso), `currentState` puede llegar
// null momentáneamente, y `!.validate()` lanza una excepción dentro
// de un callback async (`onTap` sin await ni try/catch en la UI) que
// nadie captura -- el error se pierde en la consola y visualmente
// "no pasa nada" al tocar el paquete. Se reemplaza esa validación por
// una comprobación directa sobre los controllers (`_datosBasicosValidos`),
// que nunca depende de que un Form específico esté vivo.
//
// NUEVO (2026-08, flujo evento vs negocio): `tipoInicial` ('negocio' o
// 'evento') llega desde el selector en Mi Perfil. Si es 'evento', se
// precarga la categoría y se ajustan los textos de los primeros pasos
// para que el formulario se sienta hecho a medida (fiesta, venta de
// garaje, rifa...) en vez de un formulario genérico de "negocio fijo".

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/supabase_client.dart';
import '../services/anuncios_service.dart';
import '../services/location_service.dart';
import '../services/negocio_state_service.dart';
import '../services/negocios_service.dart';
import '../services/storage_service.dart';
import '../services/tiendas_service.dart';
import '../services/whatsapp_service.dart';
import '../widgets/paquetes_negocio_sheet.dart' show mostrarModalPagoPaquete;

const Color _kVerde = Color(0xFF0D9488);

/// Sugerencias de categoría -- el usuario puede escribir cualquier otra.
/// "Evento / Fiesta puntual" va primero para que sea fácil de encontrar
/// cuando alguien llega desde el flujo de evento en Mi Perfil.
const List<String> _kSugerenciasCategoria = [
  'Evento / Fiesta puntual',
  'Barbería', 'Peluquería', 'Taller mecánico', 'Taller de celulares',
  'Joyería', 'Consultorio médico', 'Consultorio odontológico',
  'Veterinaria', 'Restaurante', 'Cafetería', 'Pizzería', 'Gimnasio',
  'Lavandería', 'Repostería', 'Fotografía', 'Otros servicios',
];

class OnboardingNegocioScreen extends StatefulWidget {
  /// 'negocio' (default) o 'evento' -- viene del selector de Mi Perfil
  /// ("¿Quieres que te encuentren?"). Ajusta títulos, hints y precarga
  /// la categoría para que el formulario no se sienta genérico cuando
  /// en realidad es una fiesta, venta de garaje o rifa puntual.
  final String? tipoInicial;

  const OnboardingNegocioScreen({super.key, this.tipoInicial});

  @override
  State<OnboardingNegocioScreen> createState() =>
      _OnboardingNegocioScreenState();
}

class _OnboardingNegocioScreenState extends State<OnboardingNegocioScreen> {
  final _locationService = LocationService();
  final _negociosService = NegociosService();
  final _anunciosService = AnunciosService();
  final _whatsappService = WhatsappService();
  final _tiendasService = TiendasService();
  final _storageService = StorageService();
  final ImagePickerHost _pickerHost = ImagePickerHost();
  final _pageController = PageController();

  bool get _esEvento => widget.tipoInicial == 'evento';

  int _paso = 0;
  static const _totalPasos = 7;

  // Paso 0
  final _formKeyDatos = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();

  // Paso 1
  final _categoriaCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();

  // Paso 2
  File? _logoFile;
  File? _portadaFile;

  // Paso 3 -- horario: día activo + franja abre/cierra
  final Map<int, bool> _diaActivo = {
    for (var i = 0; i < 7; i++) i: false,
  };
  final Map<int, TimeOfDay> _abre = {
    for (var i = 0; i < 7; i++) i: const TimeOfDay(hour: 9, minute: 0),
  };
  final Map<int, TimeOfDay> _cierra = {
    for (var i = 0; i < 7; i++) i: const TimeOfDay(hour: 17, minute: 0),
  };

  // Paso 4
  final _direccionCtrl = TextEditingController();
  double? _lat;
  double? _lon;
  bool _capturandoGps = false;

  // Paso 5
  final List<(TextEditingController, TextEditingController)> _precios = [];

  // Paso 6 -- pago del primer paquete de anuncio. Los paquetes los
  // gestiona el admin desde su panel. La selección de CUENTA de pago
  // (tarjeta/QR) ya no vive acá -- al tocar un paquete se abre el
  // mismo modal de pago (mostrarModalPagoPaquete) que usa un negocio
  // ya existente al comprar un paquete adicional, y ese modal maneja
  // su propia lista de cuentas.
  late final Future<List<Map<String, dynamic>>> _paquetesFuture;
  List<Map<String, dynamic>> _paquetesCache = [];

  bool _guardando = false;

  static const _kClavesDias = [
    'lun', 'mar', 'mie', 'jue', 'vie', 'sab', 'dom'
  ];
  static const _kLabelsDias = [
    'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'
  ];

  @override
  void initState() {
    super.initState();
    // NUEVO: si viene del flujo "evento", precargamos la categoría
    // para que el paso 1 ya aparezca con la sugerencia correcta.
    if (_esEvento) {
      _categoriaCtrl.text = 'Evento / Fiesta puntual';
    }
    _paquetesFuture = _anunciosService.obtenerPaquetesActivos().then((lista) {
      _paquetesCache = lista;
      return lista;
    });
  }

  /// True solo si el admin todavía no crea ningún paquete activo.
  bool get _sinPaquetes => _paquetesCache.isEmpty;

  @override
  void dispose() {
    _pageController.dispose();
    _nombreCtrl.dispose();
    _whatsappCtrl.dispose();
    _categoriaCtrl.dispose();
    _descripcionCtrl.dispose();
    _direccionCtrl.dispose();
    for (final par in _precios) {
      par.$1.dispose();
      par.$2.dispose();
    }
    super.dispose();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String? get _horarioJson {
    if (!_diaActivo.values.any((v) => v)) return null;
    final map = <String, dynamic>{};
    for (var i = 0; i < 7; i++) {
      map[_kClavesDias[i]] = (_diaActivo[i]!)
          ? {'abre': _fmt(_abre[i]!), 'cierra': _fmt(_cierra[i]!)}
          : {'descanso': true};
    }
    return jsonEncode(map);
  }

  List<Map<String, String>>? get _preciosJson {
    final limpios = _precios
        .where((p) => p.$1.text.trim().isNotEmpty)
        .map((p) => {
              'item': p.$1.text.trim(),
              'precio': p.$2.text.trim(),
            })
        .toList();
    return limpios.isEmpty ? null : limpios;
  }

  bool get _puedeAvanzarPasoUbicacion =>
      _lat != null && _lon != null && _direccionCtrl.text.trim().isNotEmpty;

  /// FIX (bug "el botón del paquete no hace nada"): antes se llamaba
  /// a `_formKeyDatos.currentState!.validate()` desde el paso 6 --
  /// pero ese Form pertenece al paso 0, y depender de que su
  /// `currentState` esté vivo es frágil (puede llegar null en ciertos
  /// rebuilds y el `!` lanza una excepción silenciosa que nadie
  /// atrapa). Esta validación es equivalente a la del Form del paso 0
  /// pero se apoya solo en los controllers, que siempre existen sin
  /// importar en qué página del PageView estemos.
  bool get _datosBasicosValidos {
    final nombreOk = _nombreCtrl.text.trim().isNotEmpty;
    final telLimpio = _whatsappCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    return nombreOk && telLimpio.length >= 8;
  }

  void _irAPaso(int paso) {
    setState(() => _paso = paso);
    _pageController.animateToPage(
      paso,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// true en el último paso cuando SÍ hay paquetes configurados -- en
  /// ese caso el envío ocurre al tocar una tarjeta de paquete (abre el
  /// modal de pago), no con este botón, así que el botón queda
  /// deshabilitado como pista visual en vez de duplicar el flujo.
  bool get _ultimoPasoRequiereTocarTarjeta =>
      _paso == _totalPasos - 1 && !_sinPaquetes;

  void _siguiente() {
    if (_paso == 0 && !_formKeyDatos.currentState!.validate()) return;
    if (_paso == 4 && !_puedeAvanzarPasoUbicacion) {
      _mostrarError(_lat == null
          ? 'Captura la ubicación de tu negocio primero'
          : 'Escribe la dirección');
      return;
    }
    if (_paso == _totalPasos - 1) {
      // Sin paquetes configurados: se envía directo, coordinando el
      // pago por WhatsApp (no hay nada que cobrar todavía). Con
      // paquetes configurados este botón no hace nada -- está
      // deshabilitado (ver _ultimoPasoRequiereTocarTarjeta).
      if (_sinPaquetes) _confirmarSinPaquete();
      return;
    }
    _irAPaso(_paso + 1);
  }

  void _anterior() {
    if (_paso > 0) {
      _irAPaso(_paso - 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _elegirFoto({required bool esPortada}) async {
    final file = await _pickerHost.elegirFoto();
    if (file == null) return;
    setState(() {
      if (esPortada) {
        _portadaFile = file;
      } else {
        _logoFile = file;
      }
    });
  }

  Future<void> _capturarUbicacion() async {
    setState(() => _capturandoGps = true);
    try {
      final pos = await _locationService.obtenerUbicacionActual();
      setState(() {
        _lat = pos.latitude;
        _lon = pos.longitude;
      });
    } catch (e) {
      if (mounted) _mostrarError('No se pudo obtener tu ubicación: $e');
    } finally {
      if (mounted) setState(() => _capturandoGps = false);
    }
  }

  String _generarCodigoCompra() {
    const alfabeto = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    return 'AN-' +
        List.generate(4, (_) => alfabeto[rnd.nextInt(alfabeto.length)]).join();
  }

  /// Inserta la fila del negocio en Supabase (nace 'pendiente').
  /// Lógica común a los dos caminos del último paso -- antes vivía
  /// duplicada dentro de _confirmar(); ahora se llama tanto desde
  /// _confirmarSinPaquete() (camino directo) como desde el
  /// onVerificar del modal de pago (_abrirModalPagoDeRegistro), recién
  /// cuando el usuario efectivamente confirma que va a pagar -- así no
  /// queda un negocio a medias si abre el modal y se arrepiente.
  Future<String> _crearNegocio() async {
    // ANTI-DUPLICADOS: aunque el CTA ya no se muestra a quien tiene
    // negocio, una pestaña vieja o deep link podría llegar acá.
    // Re-consultamos el estado real justo antes de insertar; si ya
    // existe uno (pendiente/activo/etc.) cortamos sin crear nada.
    await NegocioStateService.instance.refrescar();
    if (NegocioStateService.instance.tieneNegocio) {
      throw Exception('Ya tienes un negocio registrado -- espera su '
          'revisión o contáctanos por WhatsApp.');
    }

    final uid = supabase.auth.currentUser!.id;

    String? logoUrl;
    String? portadaUrl;
    if (_logoFile != null) {
      logoUrl = await _storageService.subirLogoNegocio(
          archivo: _logoFile!, uid: uid);
    }
    if (_portadaFile != null) {
      portadaUrl = await _storageService.subirPortadaNegocio(
          archivo: _portadaFile!, uid: uid);
    }

    final idNegocio = await _negociosService.crearNegocio(
      nombre: _nombreCtrl.text.trim(),
      whatsapp: _whatsappCtrl.text.trim(),
      lat: _lat!,
      lon: _lon!,
      categoria: _categoriaCtrl.text.trim(),
      descripcion: _descripcionCtrl.text.trim(),
      logoUrl: logoUrl,
      portadaUrl: portadaUrl,
      direccion: _direccionCtrl.text.trim(),
      horario: _horarioJson,
      listaPrecios: _preciosJson,
    );

    // Refresco global ANTES de salir: Mi Perfil y el banner del feed
    // se enteran al instante (dejan de ofrecer registro).
    await NegocioStateService.instance.refrescar();
    return idNegocio;
  }

  /// Camino cuando el admin todavía NO configuró ningún paquete: no
  /// hay nada que cobrar todavía, así que se crea el negocio directo y
  /// se ofrece avisar por WhatsApp para coordinar el pago a mano.
  Future<void> _confirmarSinPaquete() async {
    setState(() => _guardando = true);
    try {
      await _crearNegocio();
      if (!mounted) return;
      final mensajeWa = _armarMensajeWhatsapp();
      final quiereWhatsApp = await _dialogoSolicitudEnviada();

      if (quiereWhatsApp && mounted) {
        final telefono = await _resolverTelefonoAdmin();
        if (telefono == null) {
          _mostrarError('El admin aún no configuró un WhatsApp de contacto');
        } else {
          try {
            await _whatsappService.abrirTexto(
                telefono: telefono, mensaje: mensajeWa);
          } catch (_) {
            _mostrarError('No se pudo abrir WhatsApp');
          }
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        _mostrarError('No se pudo registrar el negocio: '
            '${e.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Camino normal: abre el MISMO modal de pago (QR, precio, pasos y
  /// botón "Verificar Pago") que usa un negocio ya aprobado al comprar
  /// un paquete adicional -- ver paquetes_negocio_sheet.dart. El
  /// negocio y la compra pendiente se crean recién dentro de
  /// onVerificar, cuando el usuario ya está seguro de pagar.
  ///
  /// FIX (2026-08): antes validaba con
  /// `_formKeyDatos.currentState!.validate()` -- el Form del PASO 0,
  /// al que se llega desde el paso 6 (pago). Cuando ese `currentState`
  /// llegaba null, el `!` lanzaba una excepción que ningún try/catch
  /// de la UI capturaba (el onTap de la tarjeta no es async-safe),
  /// así que tocar el paquete "no hacía nada" visualmente. Ahora se
  /// usa `_datosBasicosValidos`, que no depende de ningún Form vivo.
  Future<void> _abrirModalPagoDeRegistro(Map<String, dynamic> paquete) async {
    if (!_datosBasicosValidos) {
      _irAPaso(0);
      _mostrarError('Completa los datos del negocio primero');
      return;
    }
    if (!_puedeAvanzarPasoUbicacion) {
      _irAPaso(4);
      _mostrarError('Completa la ubicación primero');
      return;
    }

    final cuentas = await _anunciosService
        .obtenerCuentasDePaquete(paquete['id_paquete'] as String);
    if (!mounted) return;

    var seEnvio = false;
    await mostrarModalPagoPaquete(
      context: context,
      paquete: paquete,
      cuentas: cuentas,
      // Solo hace falta el nombre para armar el mensaje de WhatsApp --
      // el negocio real todavía no existe en la base de datos.
      negocio: {'nombre': _nombreCtrl.text.trim()},
      onVerificar: () async {
        final idNegocio = await _crearNegocio();
        final codigoRef = _generarCodigoCompra();
        await _anunciosService.crearCompraPendiente(
          idNegocio: idNegocio,
          idPaquete: paquete['id_paquete'] as String,
          codigoRef: codigoRef,
        );
        await NegocioStateService.instance.refrescar();
        seEnvio = true;
        return codigoRef;
      },
    );

    if (seEnvio && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tu negocio quedó en revisión ✅')));
      Navigator.of(context).pop();
    }
  }

  Future<bool> _dialogoSolicitudEnviada() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.mark_email_read_rounded, color: _kVerde),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('¡Solicitud enviada!',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800))),
              ],
            ),
            content: Text(
              'Tu negocio quedó EN REVISIÓN. Ahora manda el comprobante '
              'por WhatsApp para que el admin lo encuentre y lo apruebe.',
              style: GoogleFonts.plusJakartaSans(height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Después'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _kVerde),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('Abrir WhatsApp'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Teléfono destino del mensaje: primero el WhatsApp de pagos de
  /// anuncios definido por el admin (configuracion_app ->
  /// whatsapp_pagos); si no existe, el contacto genérico de la app.
  Future<String?> _resolverTelefonoAdmin() async {
    var telefono = await _anunciosService.obtenerWhatsappPagos();
    telefono ??= await _tiendasService.obtenerContactoWhatsappActivo();
    if (telefono == null || telefono.trim().isEmpty) return null;
    return telefono.trim();
  }

  /// Texto para el admin, con los datos para BUSCAR el negocio:
  /// nombre, cuenta y dirección. Solo se usa en el camino sin
  /// paquetes (_confirmarSinPaquete); cuando hay paquetes, el mensaje
  /// de WhatsApp lo arma el propio modal de pago con su código AN-XXXX.
  String _armarMensajeWhatsapp() {
    final buf = StringBuffer();
    buf.writeln(_esEvento
        ? 'Nueva solicitud de EVENTO en Al Lado:'
        : 'Nueva solicitud de NEGOCIO en Al Lado:');
    final cat = _categoriaCtrl.text.trim();
    buf.writeln('- ${_esEvento ? "Evento" : "Negocio"}: '
        '${_nombreCtrl.text.trim()}${cat.isNotEmpty ? ' ($cat)' : ''}');
    final email = supabase.auth.currentUser?.email;
    if (email != null && email.isNotEmpty) buf.writeln('- Cuenta: $email');
    if (_direccionCtrl.text.trim().isNotEmpty) {
      buf.writeln('- Dirección: ${_direccionCtrl.text.trim()}');
    }
    buf.write('Aún no pagué paquete (no hay paquetes configurados); '
        'coordino el pago contigo por aquí.');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fondo = theme.scaffoldBackgroundColor;
    final bordeSutil = theme.dividerColor;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: fondo,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _guardando ? null : _anterior,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        _esEvento ? 'Registrar Evento' : 'Registrar Negocio',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: List.generate(_totalPasos, (i) {
                    final activo = i <= _paso;
                    return Expanded(
                      child: Container(
                        margin:
                            EdgeInsets.only(right: i < _totalPasos - 1 ? 6 : 0),
                        height: 4,
                        decoration: BoxDecoration(
                          color: activo ? _kVerde : bordeSutil,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Paso ${_paso + 1} de $_totalPasos · ${_tituloPaso(_paso)}',
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: theme.textTheme.bodySmall?.color ??
                            theme.colorScheme.onSurface.withOpacity(0.6)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _pasoDatos(theme),
                    _pasoQueEs(theme),
                    _pasoFotos(theme),
                    _pasoHorario(theme),
                    _pasoUbicacion(theme),
                    _pasoPrecios(theme),
                    _pasoPago(theme),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kVerde,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _guardando ? null : _siguiente,
                    child: _guardando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(
                            _paso < _totalPasos - 1
                                ? 'Siguiente'
                                : 'Ya pagué - Enviar solicitud',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600, fontSize: 16),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _tituloPaso(int i) {
    switch (i) {
      case 0:
        return 'Datos básicos';
      case 1:
        return _esEvento ? 'Qué vas a promocionar' : 'Qué es tu negocio';
      case 2:
        return 'Fotos';
      case 3:
        return 'Horario';
      case 4:
        return 'Ubicación';
      case 5:
        return 'Precios';
      default:
        return 'Pago del anuncio';
    }
  }

  Widget _tituloPasoTexto(ThemeData theme, String titulo, String subtitulo) {
    final textoSecundario = theme.textTheme.bodySmall?.color ??
        theme.colorScheme.onSurface.withOpacity(0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo,
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: theme.textTheme.bodyLarge?.color)),
        const SizedBox(height: 4),
        Text(subtitulo,
            style: GoogleFonts.inter(color: textoSecundario, height: 1.4)),
      ],
    );
  }

  InputDecoration _decoracionCampo({
    required ThemeData theme,
    required String hint,
    required IconData icon,
  }) {
    final esOscuro = theme.brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
          color: theme.textTheme.bodySmall?.color ??
              theme.colorScheme.onSurface.withOpacity(0.5)),
      prefixIcon: Icon(icon, size: 20, color: theme.iconTheme.color),
      filled: true,
      fillColor: esOscuro ? theme.colorScheme.surface : const Color(0xFFF3F4F6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    );
  }

  Widget _campoTexto({
    required ThemeData theme,
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? helper,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    final textoSecundario = theme.textTheme.bodySmall?.color ??
        theme.colorScheme.onSurface.withOpacity(0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: theme.textTheme.bodyLarge?.color)),
            const SizedBox(width: 4),
            if (validator != null)
              Text('*',
                  style: GoogleFonts.inter(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.inter(color: theme.textTheme.bodyLarge?.color),
          decoration: _decoracionCampo(theme: theme, hint: hint, icon: icon),
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(helper,
              style: GoogleFonts.inter(fontSize: 12, color: textoSecundario)),
        ],
      ],
    );
  }

  // ---------------- PASO 0: datos ----------------

  Widget _pasoDatos(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKeyDatos,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tituloPasoTexto(
              theme,
              _esEvento ? 'Cuéntanos de tu evento' : 'Cuéntanos de tu negocio',
              _esEvento
                  ? 'Lo esencial para que la gente sepa de qué se trata.'
                  : 'Lo esencial para que los clientes te contacten.',
            ),
            const SizedBox(height: 20),
            _campoTexto(
              theme: theme,
              controller: _nombreCtrl,
              label: _esEvento ? 'Nombre del evento' : 'Nombre del negocio',
              hint: _esEvento
                  ? 'Ej: Fiesta de fin de año'
                  : 'Ej: Barbería El Estilo',
              icon: Icons.storefront_outlined,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            _campoTexto(
              theme: theme,
              controller: _whatsappCtrl,
              label: _esEvento
                  ? 'WhatsApp de contacto'
                  : 'WhatsApp del negocio',
              hint: 'Ej: 5351234567',
              icon: Icons.chat_outlined,
              keyboardType: TextInputType.phone,
              helper:
                  'Sin espacios ni guiones -- los interesados te escribirán aquí',
              validator: (v) {
                final limpio = (v ?? '').replaceAll(RegExp(r'[^\d]'), '');
                if (limpio.length < 8) return 'Número no válido';
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- PASO 1: qué es ----------------

  Widget _pasoQueEs(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloPasoTexto(
            theme,
            _esEvento ? '¿Qué vas a promocionar?' : '¿A qué te dedicas?',
            _esEvento
                ? 'Cuéntanos qué tipo de evento es (fiesta, rifa, venta de '
                    'garaje...).'
                : 'Escribe qué es tu negocio o elige una sugerencia.',
          ),
          const SizedBox(height: 20),
          Autocomplete<String>(
            optionsBuilder: (value) {
              final q = value.text.trim().toLowerCase();
              if (q.isEmpty) return _kSugerenciasCategoria.take(6);
              return _kSugerenciasCategoria.where((c) =>
                  c.toLowerCase().contains(q));
            },
            fieldViewBuilder: (context, ctrl, focus, onSubmit) {
              // El controller externo manda: sincronizamos ida y vuelta.
              if (ctrl.text != _categoriaCtrl.text &&
                  _categoriaCtrl.text.isNotEmpty) {
                ctrl.text = _categoriaCtrl.text;
              }
              ctrl.addListener(() {
                if (_categoriaCtrl.text != ctrl.text) {
                  _categoriaCtrl.text = ctrl.text;
                }
              });
              return TextField(
                controller: ctrl,
                focusNode: focus,
                onSubmitted: (_) => onSubmit(),
                style: GoogleFonts.inter(
                    color: theme.textTheme.bodyLarge?.color),
                decoration: _decoracionCampo(
                  theme: theme,
                  hint: _esEvento
                      ? 'Ej: Fiesta, rifa, venta de garaje...'
                      : 'Ej: Barbería, taller, joyería...',
                  icon: Icons.category_outlined,
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: options
                        .map((o) => ListTile(
                              dense: true,
                              title: Text(o,
                                  style: GoogleFonts.inter(fontSize: 13.5)),
                              onTap: () {
                                _categoriaCtrl.text = o;
                                onSelected(o);
                              },
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _campoTexto(
            theme: theme,
            controller: _descripcionCtrl,
            label: 'Descripción',
            hint: _esEvento
                ? 'Cuenta cuándo es, dónde, y qué lo hace especial...'
                : 'Cuenta qué ofreces, tu estilo, lo que te hace distinto...',
            icon: Icons.notes_rounded,
            maxLines: 4,
          ),
        ],
      ),
    );
  }

  // ---------------- PASO 2: fotos ----------------

  Widget _pasoFotos(ThemeData theme) {
    final textoSecundario = theme.textTheme.bodySmall?.color ??
        theme.colorScheme.onSurface.withOpacity(0.6);

    Widget preview(File? file, IconData icono, Color color) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 110,
          height: 110,
          color: color.withOpacity(0.08),
          child: file != null
              ? Image.file(file, fit: BoxFit.cover)
              : Icon(icono, size: 34, color: color),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloPasoTexto(theme, 'Una buena foto vende solo',
              'Logo obligatorio para el perfil; portada opcional.'),
          const SizedBox(height: 20),
          Text('LOGO *',
              style: GoogleFonts.inter(
                  fontSize: 11.5, fontWeight: FontWeight.w700,
                  color: textoSecundario)),
          const SizedBox(height: 8),
          Row(
            children: [
              preview(_logoFile, Icons.content_cut_rounded, _kVerde),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () => _elegirFoto(esPortada: false),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(_logoFile == null ? 'Elegir logo' : 'Cambiar'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('PORTADA (opcional)',
              style: GoogleFonts.inter(
                  fontSize: 11.5, fontWeight: FontWeight.w700,
                  color: textoSecundario)),
          const SizedBox(height: 8),
          Row(
            children: [
              preview(_portadaFile, Icons.wallpaper_rounded, _kVerde),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () => _elegirFoto(esPortada: true),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(_portadaFile == null ? 'Elegir' : 'Cambiar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- PASO 3: horario ----------------

  Future<TimeOfDay?> _elegirHora(BuildContext context, TimeOfDay inicial) =>
      showTimePicker(
        context: context,
        initialTime: inicial,
        builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(colorScheme: Theme.of(context)
              .colorScheme.copyWith(primary: _kVerde)),
          child: child!,
        ),
      );

  Widget _pasoHorario(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloPasoTexto(theme, 'Tu horario de atención',
              'Activa los días que abres y ajusta las horas.'),
          const SizedBox(height: 12),
          ...List.generate(7, (i) {
            final activo = _diaActivo[i]!;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: activo
                        ? _kVerde.withOpacity(0.5)
                        : theme.dividerColor),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    dense: true,
                    activeColor: _kVerde,
                    title: Text(_kLabelsDias[i],
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    value: activo,
                    onChanged: (v) => setState(() => _diaActivo[i] = v),
                  ),
                  if (activo)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          _botonHora(theme, 'Abre', _abre[i]!, (t) {
                            setState(() => _abre[i] = t);
                          }),
                          const SizedBox(width: 12),
                          _botonHora(theme, 'Cierra', _cierra[i]!, (t) {
                            setState(() => _cierra[i] = t);
                          }),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _botonHora(ThemeData theme, String label, TimeOfDay valor,
      ValueChanged<TimeOfDay> onPick) {
    final textoSecundario = theme.textTheme.bodySmall?.color ??
        theme.colorScheme.onSurface.withOpacity(0.6);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final t = await _elegirHora(context, valor);
          if (t != null) onPick(t);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _kVerde.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kVerde.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 10.5, color: textoSecundario)),
              Row(
                children: [
                  Text(_fmt(valor),
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const Spacer(),
                  const Icon(Icons.edit_rounded, size: 13, color: _kVerde),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- PASO 4: ubicación ----------------

  Widget _pasoUbicacion(ThemeData theme) {
    final textoSecundario = theme.textTheme.bodySmall?.color ??
        theme.colorScheme.onSurface.withOpacity(0.6);
    final campoBg = theme.colorScheme.surfaceContainerHighest
        .withOpacity(theme.brightness == Brightness.dark ? 0.4 : 1);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloPasoTexto(theme, '¿Dónde estás?',
              'Dirección legible y punto exacto en el GPS.'),
          const SizedBox(height: 20),
          _campoTexto(
            theme: theme,
            controller: _direccionCtrl,
            label: 'Dirección',
            hint: 'Ej: Calle 23 #456 entre L y M, Vedado',
            icon: Icons.place_outlined,
          ),
          const SizedBox(height: 20),
          Text('Ubicación GPS *',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: theme.textTheme.bodyLarge?.color)),
          const SizedBox(height: 4),
          Text('Marca el punto exacto de tu local.',
              style: GoogleFonts.inter(color: textoSecundario)),
          const SizedBox(height: 12),
          Container(
            height: 150,
            decoration: BoxDecoration(
              color: campoBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  _lat != null
                      ? Icons.location_on_rounded
                      : Icons.map_outlined,
                  size: 44,
                  color: _lat != null ? _kVerde : textoSecundario.withOpacity(0.5),
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: Material(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    elevation: 1,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _capturandoGps ? null : _capturarUbicacion,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: _capturandoGps
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.my_location_rounded,
                                color: _kVerde, size: 18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_lat != null) ...[
            const SizedBox(height: 10),
            Text('${_lat!.toStringAsFixed(5)}, ${_lon!.toStringAsFixed(5)}',
                style: GoogleFonts.inter(fontSize: 12, color: textoSecundario)),
          ],
        ],
      ),
    );
  }

  // ---------------- PASO 5: precios ----------------

  Widget _pasoPrecios(ThemeData theme) {
    final textoSecundario = theme.textTheme.bodySmall?.color ??
        theme.colorScheme.onSurface.withOpacity(0.6);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloPasoTexto(theme, 'Lista de precios',
              'Opcional -- ayuda a tus clientes a decidir antes de escribirte.'),
          const SizedBox(height: 20),
          ..._precios.asMap().entries.map((entry) {
            final idx = entry.key;
            final par = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: par.$1,
                      style: GoogleFonts.inter(
                          color: theme.textTheme.bodyLarge?.color),
                      decoration: _decoracionCampo(
                          theme: theme,
                          hint: 'Servicio (ej: Corte)',
                          icon: Icons.spa_outlined),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: par.$2,
                      style: GoogleFonts.inter(
                          color: theme.textTheme.bodyLarge?.color),
                      decoration: _decoracionCampo(
                          theme: theme,
                          hint: '\$ Precio',
                          icon: Icons.attach_money_rounded),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        par.$1.dispose();
                        par.$2.dispose();
                        _precios.removeAt(idx);
                      });
                    },
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.redAccent),
                  ),
                ],
              ),
            );
          }),
          TextButton.icon(
            onPressed: () => setState(() => _precios.add((
                  TextEditingController(),
                  TextEditingController(),
                ))),
            icon: const Icon(Icons.add_circle_outline_rounded,
                color: _kVerde),
            label: Text('Agregar servicio',
                style: GoogleFonts.inter(
                    color: _kVerde, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kVerde.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kVerde.withOpacity(0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: _kVerde, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Último paso: elegirás y pagarás tu paquete de '
                    'anuncio. Tu negocio queda en revisión hasta que '
                    'el admin lo apruebe.',
                    style: GoogleFonts.inter(
                        fontSize: 12.5, color: textoSecundario, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  // ---------------- PASO 6: pago del primer paquete ----------------
  //
  // Al tocar una tarjeta de paquete se abre el MISMO modal de pago que
  // usa un negocio ya aprobado (mostrarModalPagoPaquete): ahí se ve el
  // QR, los pasos y el botón "Verificar Pago" -- que es lo que crea el
  // negocio + la compra pendiente y abre WhatsApp. Sin pantallas de
  // selección de cuenta acá: las maneja el modal.

  Widget _pasoPago(ThemeData theme) {
    final textoSecundario = theme.textTheme.bodySmall?.color ??
        theme.colorScheme.onSurface.withOpacity(0.6);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloPasoTexto(theme, 'Activa tu anuncio',
              'Elige tu primer paquete y paga con una de sus cuentas. '
              'Tu negocio queda EN REVISIÓN hasta que el admin lo apruebe.'),
          const SizedBox(height: 16),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _paquetesFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final paquetes = snap.data ?? const <Map<String, dynamic>>[];
              if (paquetes.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade700.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.amber.shade700.withOpacity(0.35)),
                  ),
                  child: Text(
                    'El admin aún no ha configurado paquetes de anuncio. '
                    'Puedes enviar tu solicitud y coordinarás el pago '
                    'directamente por WhatsApp.',
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        color: textoSecundario,
                        height: 1.45),
                  ),
                );
              }
              return Column(
                children: [
                  ...paquetes.map(_tarjetaPaquete),
                  const SizedBox(height: 8),
                  Text(
                    'Toca un paquete para ver los datos de pago y '
                    'verificar tu transferencia.',
                    style: GoogleFonts.inter(
                        fontSize: 12.5, color: textoSecundario, height: 1.4),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kVerde.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kVerde.withOpacity(0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.payments_rounded, color: _kVerde, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Paga en la app o cajero, y al tocar "Ya pagué - Enviar '
                    'solicitud" te llevamos a WhatsApp con el mensaje listo '
                    'para que el admin verifique tu pago.',
                    style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: textoSecundario,
                        height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaPaquete(Map<String, dynamic> p) {
    final theme = Theme.of(context);
    final textoSecundario = theme.textTheme.bodySmall?.color ??
        theme.colorScheme.onSurface.withOpacity(0.6);

    return GestureDetector(
      onTap: () => _abrirModalPagoDeRegistro(p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Icon(
              Icons.touch_app_rounded,
              color: _kVerde,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['nombre'] ?? '',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: theme.textTheme.bodyLarge?.color)),
                  const SizedBox(height: 2),
                  Text(
                    '\$${p['precio_usd']} USD · ${p['duracion_dias']} días · '
                    '${p['max_anuncios']} anuncio${p['max_anuncios'] > 1 ? 's' : ''} a la vez',
                    style: GoogleFonts.inter(
                        fontSize: 12.5, color: textoSecundario),
                  ),
                  if ((p['descripcion'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(p['descripcion'],
                        style: GoogleFonts.inter(
                            fontSize: 11.5, color: textoSecundario)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Envoltura mínima sobre ImagePicker para no importar el paquete en
/// todo el archivo y mantener este screen enfocado en UI.
class ImagePickerHost {
  final StorageService _storage = StorageService();

  Future<File?> elegirFoto() => _storage.elegirFoto();
}