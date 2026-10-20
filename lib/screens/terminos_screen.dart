// terminos_screen.dart
//
// Pantalla de aceptación obligatoria de Términos y Condiciones y
// Política de Privacidad de Al Lado. Se muestra antes de que el usuario
// pueda usar la app (incluso antes de iniciar sesión). No se puede
// saltar: solo "Aceptar y continuar" habilita el acceso; "No acepto"
// cierra la aplicación.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';

const String kVersionTerminos = 'v1_2026';

class TerminosScreen extends StatefulWidget {
  /// Se llama cuando el usuario acepta los términos. El gate que la
  /// muestra se encarga de persistir la aceptación.
  final VoidCallback onAceptar;

  const TerminosScreen({super.key, required this.onAceptar});

  @override
  State<TerminosScreen> createState() => _TerminosScreenState();
}

class _TerminosScreenState extends State<TerminosScreen> {
  bool _acepto = false;
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final colorTexto = esOscuro ? AppColors.inkDark : AppColors.inkLight;
    final colorSec = esOscuro
        ? AppColors.inkSecundarioDark
        : AppColors.inkSecundarioLight;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Encabezado
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Icons.storefront_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Al Lado',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        )),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Términos y Condiciones y Políticas de Seguridad',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colorTexto,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _parrafo(
                      'Última actualización: 2026. Lee este documento con '
                      'atención. Para usar Al Lado debes aceptarlo. Si no '
                      'estás de acuerdo con alguna parte, no podrás utilizar '
                      'la aplicación.',
                      colorSec,
                    ),
                    _seccion('1. Qué es Al Lado', colorTexto, colorSec, [
                      'Al Lado conecta personas, tiendas, negocios y '
                      'anunciantes de Cuba. No es vendedor, ni banco, ni '
                      'procesa pagos de compras entre usuarios y tiendas: esas '
                      'compras se acuerdan directamente entre comprador y '
                      'vendedor, normalmente por WhatsApp.',
                    ]),
                    _seccion('2. Requisitos', colorTexto, colorSec, [
                      'Debes tener 18 años o más y datos veraces. Para comprar, '
                      'vender, anunciar o ser afiliado debes iniciar sesión con '
                      'Google.',
                      'Eres responsable de la seguridad de tu cuenta.',
                    ]),
                    _seccion('3. Conducta: seriedad y respeto', colorTexto,
                        colorSec, [
                      'Trata con respeto a todos, publica información real y '
                      'cumple lo acordado.',
                      'Prohibido: estafar, suplantar identidades, crear cuentas '
                      'falsas, insultar o acosar, publicar contenido ilegal u '
                      'ofensivo, manipular valoraciones, abusar de códigos o '
                      'planes gratuitos, o vulnerar la seguridad de la app.',
                    ]),
                    _seccion(
                        '4. Compras entre usuarios: cuidado con las estafas',
                        colorTexto,
                        colorSec, [
                      'No hagas pagos por adelantado a tiendas o vendedores. '
                      'Paga al recibir o verificar el producto.',
                      'Desconfía de precios demasiado buenos, de presiones para '
                      'transferir y de quien pida salir de lo acordado.',
                      'Revisa valoraciones y ubicación, y prefiere encuentros '
                      'en lugares seguros.',
                      'Vendedores: confirma una venta solo cuando el pedido '
                      'esté entregado y pagado.',
                      'Al Lado no se hace responsable de dinero entregado a '
                      'tiendas, vendedores, anunciantes u otros usuarios, ni '
                      'de la calidad, entrega o legalidad de los productos. Un '
                      'pago por adelantado o fuera de los pasos oficiales es '
                      'responsabilidad exclusiva del usuario.',
                    ]),
                    _seccion('5. Pagos de los que SÍ responde Al Lado',
                        colorTexto, colorSec, [
                      'Solo respondemos por los pagos hechos a Al Lado por '
                      'planes de tienda y paquetes de anuncios, siempre y '
                      'cuando se cumplan todos los pasos:',
                      '1. Elegir el plan o paquete dentro de la app.',
                      '2. Pagar el monto exacto solo a las cuentas o QR '
                      'oficiales que muestra la app. Pagos a terceros o a '
                      'números no oficiales no están cubiertos.',
                      '3. Pulsar "Verificar Pago" y enviar el comprobante por el '
                      'WhatsApp oficial con el código de referencia.',
                      '4. Esperar la verificación del administrador.',
                      'Si el pago es válido, el servicio se activa; si no, se '
                      'rechaza y se te avisa. Si cumpliste los pasos y el '
                      'servicio no se activa por error nuestro, lo '
                      'corregiremos o reembolsaremos. No respondemos por '
                      'montos incorrectos, comprobantes ilegibles o falsos, ni '
                      'falta del código. Reembolsos tras consumir el servicio: '
                      'a definir.',
                    ]),
                    _seccion('6. Planes, anuncios y afiliados', colorTexto,
                        colorSec, [
                      'Planes: el plan gratuito dura 14 días y se usa una sola '
                      'vez por cuenta. Si un plan vence y no se renueva, la '
                      'tienda puede eliminarse.',
                      'Anuncios: los de negocios pasan por moderación; Al Lado '
                      'puede rechazar, pausar o eliminar los que incumplan las '
                      'normas. El anunciante responde por su contenido.',
                      'Afiliados: la comisión se acredita cuando el '
                      'administrador aprueba la tienda o plan. Cada código se '
                      'usa una vez por tienda, no el propio. Retiros: mínimo '
                      '1,000 CUP y máximo 10,000 CUP por día. Las comisiones '
                      'fraudulentas se anulan.',
                      'Pedidos: el stock se reserva al pedir; los pedidos sin '
                      'confirmar en 72 horas pueden cancelarse automáticamente.',
                      'Precios: los precios en CUP usan una tasa de referencia '
                      '(elTOQUE) y son orientativos.',
                    ]),
                    _seccion('7. Privacidad', colorTexto, colorSec, [
                      'Recopilamos datos de tu cuenta de Google, ubicación, '
                      'datos de tiendas y negocios, pedidos, valoraciones, '
                      'anuncios y el token del dispositivo para notificaciones. '
                      'Los usamos para operar la app, verificar pagos, prevenir '
                      'fraudes y mejorar el servicio. Algunos datos son '
                      'visibles para otros usuarios (tienda, nombre en pedidos, '
                      'WhatsApp para coordinar). No vendemos tus datos. Puedes '
                      'pedir su corrección o eliminación y dar de baja tu '
                      'cuenta; podremos conservar registros de pagos por '
                      'seguridad o ley.',
                    ]),
                    _seccion('8. Suspensión y responsabilidad', colorTexto,
                        colorSec, [
                      'Podemos advertir, suspender o eliminar cuentas, tiendas, '
                      'anuncios o códigos que incumplan estos términos. La app '
                      'se ofrece "tal cual", y nuestra responsabilidad se '
                      'limita a lo indicado en la sección 5. Podemos actualizar '
                      'este documento y te avisaremos de cambios importantes.',
                    ]),
                    _seccion('9. Contacto', colorTexto, colorSec, [
                      'Dudas, fraudes o reclamos de pagos de planes y paquetes: '
                      '[número oficial de WhatsApp] / [correo de soporte].',
                    ]),
                    const SizedBox(height: 12),
                    // Checkbox de aceptación
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _acepto,
                          onChanged: (v) =>
                              setState(() => _acepto = v ?? false),
                          activeColor: AppColors.primary,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'He leído y acepto los Términos y la Política de '
                              'Privacidad de Al Lado. Entiendo que no debo '
                              'pagar por adelantado a tiendas o vendedores y '
                              'que Al Lado solo responde por pagos de planes y '
                              'paquetes de anuncios cuando se siguieron todos '
                              'los pasos de la app.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: colorTexto,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            // Botones
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => SystemNavigator.pop(),
                      child: const Text('No acepto'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _acepto ? widget.onAceptar : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Aceptar y continuar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _parrafo(String texto, Color colorSec) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(texto,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: colorSec, height: 1.45)),
    );
  }

  Widget _seccion(String titulo, Color colorTexto, Color colorSec,
      List<String> parrafos) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              )),
          const SizedBox(height: 6),
          ...parrafos.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(p,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: colorSec,
                      height: 1.45,
                    )),
              )),
        ],
      ),
    );
  }
}
