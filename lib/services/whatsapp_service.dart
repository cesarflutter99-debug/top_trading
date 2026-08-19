import 'package:url_launcher/url_launcher.dart';

/// Abre WhatsApp con el número del vendedor y el desglose del pedido.
/// El pago y la entrega se coordinan directamente ahí, fuera de la app.
class WhatsappService {
  Future<void> abrirPedido({
    required String telefono, // formato: 5355XXXXXXX (sin '+')
    required List<Map<String, dynamic>> detalle,
    required double totalUsd,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('Hola! Quiero hacer este pedido:');
    for (final item in detalle) {
      buffer.writeln(
          '- ${item['cantidad']}x ${item['nombre']} (\$${item['precio_usd']})');
    }
    buffer.writeln('Total: \$${totalUsd.toStringAsFixed(2)} USD');

    final mensaje = Uri.encodeComponent(buffer.toString());
    final url = Uri.parse('https://wa.me/$telefono?text=$mensaje');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('No se pudo abrir WhatsApp');
    }
  }

  /// Notifica al admin (número de contactos_whatsapp) sobre una nueva
  /// tienda pendiente de validar. Flujo 1 del documento maestro:
  /// "Registro → datos y GPS → notificación WhatsApp al Admin → validación".
  Future<void> solicitarVerificacion({
    required String telefonoAdmin,
    required String nombreTienda,
    required String plan,
    required String municipio,
  }) async {
    final mensaje = Uri.encodeComponent(
      'Nueva tienda pendiente de aprobación en Al Lado:\n'
      '- Nombre: $nombreTienda\n'
      '- Municipio: $municipio\n'
      '- Plan solicitado: $plan\n'
      'Revísala en el panel de administración.',
    );
    final url = Uri.parse('https://wa.me/$telefonoAdmin?text=$mensaje');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('No se pudo abrir WhatsApp');
    }
  }

  /// Notifica al admin sobre un nuevo registro de afiliado, incluyendo
  /// su código para que el admin pueda buscarlo/verificarlo.
  Future<void> notificarNuevoAfiliado({
    required String telefonoAdmin,
    required String nombre,
    required String telefonoAfiliado,
    required String codigo,
  }) async {
    final mensaje = Uri.encodeComponent(
      'Nuevo afiliado registrado en Al Lado:\n'
      '- Nombre: $nombre\n'
      '- Teléfono: $telefonoAfiliado\n'
      '- Código: $codigo\n'
      'Puedes buscarlo por este código en el panel de administración.',
    );
    final url = Uri.parse('https://wa.me/$telefonoAdmin?text=$mensaje');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      throw Exception('No se pudo abrir WhatsApp');
    }
  }
}
