// modal_pago_plan.dart
//
// Extraído de gestionar_planes_screen.dart para poder reusarlo también
// en onboarding_tienda_screen.dart (flujo "Hacerte Vendedor" la primera
// vez). Antes era una clase privada (_ModalPagoPlan) y solo se podía
// usar dentro de ese archivo; ahora es pública (ModalPagoPlan).
//
// Requiere que la tienda YA EXISTA en Supabase (necesita tienda['id_tienda']
// real) -- si se usa en el flujo de registro nuevo, primero hay que crear
// la tienda y luego abrir este modal con la tienda ya creada.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/supabase_client.dart';
import '../services/tiendas_service.dart';

class ModalPagoPlan extends StatefulWidget {
  final Map<String, dynamic> tienda;
  final Map<String, dynamic> plan;
  final TiendasService tiendasService;
  final VoidCallback? onSolicitudCreada;
  // Si el vendedor aplicó un código de afiliado válido antes de llegar
  // aquí, ambos vienen no-nulos: se usan para mostrar el 10% de
  // descuento y para registrar la comisión al crear la solicitud.
  final String? idAfiliado;
  final String? codigoAfiliado;
  // true cuando el modal se muestra como ruta a pantalla completa
  // (flujo de registro: /pago-plan) en vez de como bottom sheet. En
  // ese caso no se hace Navigator.pop, porque la navegación ya la hace
  // onSolicitudCreada al ir a "/vendedor/mi-tienda".
  final bool esPantallaCompleta;
  // El campo de código de afiliado solo tiene sentido cuando se está
  // creando una tienda nueva (onboarding). En "Hacerte premium" desde
  // una tienda que ya existe (gestionar_planes_screen.dart) no debe
  // mostrarse.
  final bool mostrarCodigoAfiliado;

  const ModalPagoPlan({
    super.key,
    required this.tienda,
    required this.plan,
    required this.tiendasService,
    this.onSolicitudCreada,
    this.idAfiliado,
    this.codigoAfiliado,
    this.esPantallaCompleta = false,
    this.mostrarCodigoAfiliado = true,
  });

  @override
  State<ModalPagoPlan> createState() => _ModalPagoPlanState();
}

class _ModalPagoPlanState extends State<ModalPagoPlan> {
  bool _procesando = false;
  final _codigoAfiliadoCtrl = TextEditingController();
  Timer? _debounceTimer;
  // '', 'validando', 'valido', 'invalido', 'propio', 'usado'
  String _codigoEstado = '';
  // El id real del afiliado encontrado por la validación -- sin esto
  // no hay forma de acreditarle la comisión al aprobar (widget.idAfiliado
  // ya casi nunca viene precargado, así que hay que capturarlo aquí).
  String? _idAfiliadoEncontrado;

  bool get _tieneCupon =>
      widget.idAfiliado != null || _codigoEstado == 'valido';

  String get _codigoAfiliado => _codigoAfiliadoCtrl.text.trim().toUpperCase();

  double get _precioOriginal => (widget.plan['precio_usd'] as num).toDouble();

  double get _precioFinal =>
      _tieneCupon ? _precioOriginal * 0.9 : _precioOriginal;

  double get _comisionUsd => _precioOriginal * 0.10;

  void _validarCodigoEnSegundoPlano() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () async {
      final codigo = _codigoAfiliado;
      if (codigo.isEmpty) {
        if (mounted) {
          setState(() {
            _codigoEstado = '';
            _idAfiliadoEncontrado = null;
          });
        }
        return;
      }
      if (mounted) setState(() => _codigoEstado = 'validando');
      try {
        final resultado =
            await widget.tiendasService.validarCodigoAfiliadoParaTienda(
          codigo: codigo,
          idTienda: widget.tienda['id_tienda'] as String?,
        );
        if (mounted) {
          setState(() {
            _codigoEstado = resultado['estado'] as String;
            _idAfiliadoEncontrado = resultado['id_afiliado'] as String?;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _codigoEstado = 'invalido';
            _idAfiliadoEncontrado = null;
          });
        }
      }
    });
  }

  String get _mensajeCodigo {
    switch (_codigoEstado) {
      case 'validando':
        return 'Verificando código...';
      case 'valido':
        return '✅ Código válido — se aplicará descuento del 10%';
      case 'invalido':
        return '❌ Código no válido';
      case 'propio':
        return '❌ No puedes usar tu propio código de afiliado';
      case 'usado':
        return '❌ Ya usaste este código antes. Consigue otro.';
      default:
        return '';
    }
  }

  Color get _colorCodigo {
    switch (_codigoEstado) {
      case 'valido':
        return Colors.green;
      case 'invalido':
      case 'propio':
      case 'usado':
        return Colors.red;
      default:
        return AppColors.inkSecundarioLight;
    }
  }

  // El QR de texto es un respaldo: si el admin todavía no subió la
  // foto real del QR de pago (plan['qr_url']), generamos uno legible
  // con los datos de tarjeta/teléfono/monto.
  String get _contenidoQr {
    final tarjeta = widget.plan['numero_tarjeta'] ?? 'No configurada';
    final telefono = widget.plan['numero_telefono_pago'] ?? 'No configurado';
    return 'Tarjeta: $tarjeta\nTeléfono: $telefono\nMonto: \$${_precioFinal.toStringAsFixed(2)} USD';
  }

  Future<void> _verificarPago() async {
    // Código de afiliado a usar: el escrito en vivo en este modal, o el
    // que vino precargado en el widget (si lo hay).
    var codigoAfiliado =
        _codigoAfiliado.isNotEmpty ? _codigoAfiliado : widget.codigoAfiliado;
    var idAfiliado = _idAfiliadoEncontrado ?? widget.idAfiliado;

    // FIX (comisión no acreditada): la validación del código es
    // asíncrona con debounce de 800ms -- si el vendedor escribe el
    // código y toca "Verificar Pago" antes de que termine, _codigoEstado
    // queda en 'validando' y _idAfiliadoEncontrado en null, así que la
    // solicitud se guardaba SIN id_afiliado ni comisión y al aprobar el
    // admin nunca se le acreditaba nada al afiliado. Resolvemos la
    // validación pendiente acá mismo antes de continuar.
    if (codigoAfiliado != null &&
        codigoAfiliado.isNotEmpty &&
        idAfiliado == null) {
      if (mounted) setState(() => _codigoEstado = 'validando');
      try {
        final resultado =
            await widget.tiendasService.validarCodigoAfiliadoParaTienda(
          codigo: codigoAfiliado,
          idTienda: widget.tienda['id_tienda'] as String?,
        );
        if (mounted) {
          setState(() {
            _codigoEstado = resultado['estado'] as String? ?? '';
            _idAfiliadoEncontrado = resultado['id_afiliado'] as String?;
          });
        }
        idAfiliado = resultado['id_afiliado'] as String?;
      } catch (_) {
        if (mounted) setState(() => _codigoEstado = 'invalido');
        idAfiliado = null;
      }
    }

    if (_codigoEstado == 'propio' ||
        _codigoEstado == 'usado' ||
        _codigoEstado == 'invalido') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensajeCodigo)),
        );
      }
      return;
    }
    // Escribió un código pero no resultó válido: no seguimos (evita
    // registrar solicitudes/tiendas sin comisión).
    if (codigoAfiliado != null &&
        codigoAfiliado.isNotEmpty &&
        idAfiliado == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El código de afiliado no es válido')),
        );
      }
      return;
    }

    setState(() => _procesando = true);
    try {
      // FIX (solicitud duplicada): cuando este modal se abre desde el
      // onboarding recién terminado (esPantallaCompleta == true), la
      // tienda YA se creó con su plan -- ya aparece en "Tiendas
      // Pendientes". Si además creáramos acá una solicitud_cambio_plan,
      // el admin vería la MISMA tienda dos veces (una como activación,
      // otra como "cambio de plan"), como si alguien ya activa estuviera
      // pidiendo un upgrade. Por eso esto solo corre para tiendas que YA
      // estaban activas y piden cambiar de plan (esPantallaCompleta ==
      // false).
      if (!widget.esPantallaCompleta) {
        await widget.tiendasService.crearSolicitudCambioPlan(
          idTienda: widget.tienda['id_tienda'],
          idPlanSolicitado: widget.plan['id_plan'],
          planAnterior: widget.tienda['plan'] ?? 'basic',
          idAfiliado: idAfiliado,
          comisionUsd: _tieneCupon ? _comisionUsd : null,
          codigoAfiliado: codigoAfiliado,
        );
      } else if (codigoAfiliado != null &&
          codigoAfiliado.isNotEmpty &&
          idAfiliado != null) {
        // FIX (comisión no acreditada en onboarding): la tienda nueva se
        // crea SIEMPRE con codigo_afiliado null (crearTienda lo recibe
        // hardcodeado en onboarding_tienda_screen.dart) y en este flujo
        // a pantalla completa no se crea ninguna solicitud -- así que el
        // código escrito aquí se perdía y, al aprobar la tienda,
        // admin_aprobar_tienda no encontraba afiliado que acreditar.
        // Guardamos el código en la tienda para que la comisión del 10%
        // sí se acredite cuando el admin la apruebe.
        await supabase
            .from('tiendas')
            .update({'codigo_afiliado': codigoAfiliado})
            .eq('id_tienda', widget.tienda['id_tienda']);
      }
      widget.onSolicitudCreada?.call();

      final numero = await supabase
          .from('contactos_whatsapp')
          .select('telefono')
          .eq('activo', true)
          .limit(1)
          .maybeSingle();

      // En el flujo de bottom sheet hay que cerrar el modal; en el flujo
      // a pantalla completa la navegación la hace onSolicitudCreada
      // (context.go a /vendedor/mi-tienda), así que no se hace pop.
      if (!widget.esPantallaCompleta && mounted) Navigator.pop(context);

      if (numero == null || numero['telefono'] == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Solicitud enviada. No hay número de WhatsApp configurado para el comprobante.'),
            ),
          );
        }
        return;
      }

      final idTienda = widget.tienda['id_tienda'] ?? '';
      // El UUID completo es incómodo de leer/copiar en un chat de
      // WhatsApp -- se usa un código corto (primeros 8 caracteres,
      // en mayúsculas) solo como referencia legible entre admin y
      // vendedor. No se usa para buscar en la base de datos en
      // ningún lado, así que no hace falta que sea único a nivel
      // global, solo suficientemente distinguible en una conversación.
      final codigoCorto = idTienda.toString().length >= 8
          ? idTienda.toString().substring(0, 8).toUpperCase()
          : idTienda.toString().toUpperCase();
      final nombreTienda = widget.tienda['nombre'] ?? 'mi tienda';
      final nombrePlan = widget.plan['nombre'] ?? '';

      final codigoAfiliadoMsg =
          _codigoAfiliado.isNotEmpty ? _codigoAfiliado : widget.codigoAfiliado;

      final afiliadoMsg =
          codigoAfiliadoMsg != null && codigoAfiliadoMsg.isNotEmpty
              ? 'Usé un código de afiliado ($codigoAfiliadoMsg). '
              : '';

      final mensaje = Uri.encodeComponent(
        'Hola, deseo verificar mi plan $nombrePlan. '
        'Tienda: $nombreTienda (Ref: $codigoCorto). '
        '$afiliadoMsg'
        'Realicé la transferencia de \$${_precioFinal.toStringAsFixed(2)} USD'
        '${_tieneCupon ? ' (con 10% de descuento aplicado)' : ''}. '
        'Adjunto la captura de pantalla de la transacción.',
      );
      final url =
          Uri.parse('https://wa.me/${numero['telefono']}?text=$mensaje');
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al procesar la solicitud: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // FIX: sin este padding, el modal (al vivir dentro de un
    // showModalBottomSheet y no de un Scaffold) no se ajusta cuando
    // aparece el teclado -- el campo de "Código de afiliado" y su
    // mensaje de válido/inválido, que están al final del formulario,
    // quedaban tapados por el teclado y parecía que no pasaba nada al
    // escribir.
    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pagar plan ${widget.plan['nombre']}',
                    style: GoogleFonts.inter(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                if (_tieneCupon) ...[
                  Row(
                    children: [
                      Text(
                        '\$${_precioOriginal.toStringAsFixed(2)} USD',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.black45,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('-10% cupón',
                            style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('\$${_precioFinal.toStringAsFixed(2)} USD',
                      style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green)),
                  const SizedBox(height: 4),
                  Text('Usaste un código de afiliado ✅',
                      style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600)),
                ] else
                  Text('\$${_precioFinal.toStringAsFixed(2)} USD',
                      style:
                          GoogleFonts.inter(fontSize: 16, color: Colors.green)),
                const SizedBox(height: 20),
                Center(
                  child: () {
                    final qrUrl = widget.plan['qr_url'] as String?;
                    if (qrUrl != null && qrUrl.isNotEmpty) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          qrUrl,
                          width: 180,
                          height: 180,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => QrImageView(
                            data: _contenidoQr,
                            size: 180,
                            backgroundColor: Colors.white,
                          ),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const SizedBox(
                              width: 180,
                              height: 180,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          },
                        ),
                      );
                    }
                    return QrImageView(
                      data: _contenidoQr,
                      size: 180,
                      backgroundColor: Colors.white,
                    );
                  }(),
                ),
                const SizedBox(height: 20),
                _filaDato('Tarjeta',
                    widget.plan['numero_tarjeta'] ?? 'No configurada'),
                const SizedBox(height: 8),
                _filaDato('Teléfono',
                    widget.plan['numero_telefono_pago'] ?? 'No configurado'),
                const SizedBox(height: 20),

                // ---------- Explicación paso a paso ----------
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(kCardRadius),
                    border:
                        Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cómo verificar tu pago',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 10),
                      _pasoNumerado(1,
                          'Abre Transfermóvil y transfiere \$${_precioFinal.toStringAsFixed(2)} USD a la tarjeta o número mostrados arriba.'),
                      _pasoNumerado(2,
                          'Toma una captura de pantalla de la confirmación de la transferencia.'),
                      _pasoNumerado(3,
                          'Presiona "Verificar Pago" abajo -- se abrirá WhatsApp con un mensaje ya redactado.'),
                      _pasoNumerado(4,
                          'Adjunta la captura de pantalla en ese chat de WhatsApp y envíala.'),
                      _pasoNumerado(5,
                          'El administrador revisará tu comprobante y activará tu plan.'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _procesando ? null : _verificarPago,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF25D366),
                    ),
                    child: _procesando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Verificar Pago'),
                  ),
                ),
                const SizedBox(height: 16),

                if (widget.mostrarCodigoAfiliado) ...[
                  // ---------- Código de afiliado (abajo) ----------
                  TextField(
                    controller: _codigoAfiliadoCtrl,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => _validarCodigoEnSegundoPlano(),
                    decoration: InputDecoration(
                      labelText: 'Código de afiliado (opcional)',
                      hintText: 'Ingresa tu código si lo tienes',
                      prefixIcon: const Icon(Icons.confirmation_number_outlined,
                          size: 20),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: const Color(0xFFF3F4F6),
                      suffixIcon: _codigoEstado == 'validando'
                          ? const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ))
                          : _codigoEstado == 'valido'
                              ? const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Icon(Icons.check_circle,
                                      color: Colors.green, size: 20))
                              : (_codigoEstado == 'invalido' ||
                                      _codigoEstado == 'propio' ||
                                      _codigoEstado == 'usado')
                                  ? const Padding(
                                      padding: EdgeInsets.only(right: 8),
                                      child: Icon(Icons.error_outlined,
                                          color: Colors.red, size: 20))
                                  : null,
                    ),
                  ),
                  if (_mensajeCodigo.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(_mensajeCodigo,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _colorCodigo,
                            fontWeight: FontWeight.w600)),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filaDato(String etiqueta, String valor) {
    return Row(
      children: [
        Text('$etiqueta: ',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        Expanded(child: SelectableText(valor)),
      ],
    );
  }

  Widget _pasoNumerado(int numero, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: AppColors.primary,
            child: Text('$numero',
                style: const TextStyle(fontSize: 11, color: Colors.white)),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(texto, style: GoogleFonts.inter(fontSize: 12.5))),
        ],
      ),
    );
  }
}
