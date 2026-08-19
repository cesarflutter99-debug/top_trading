// tasa_cambio_service.dart
//
// Lee la tabla `tasas_cambio` de Supabase -- la que llena la Edge
// Function `actualizar-tasa-cambio` cada 12 horas consultando la API de
// ElToque. La app NUNCA llama a ElToque directamente: todos los
// usuarios leen esta misma tabla ya cacheada, para no sobrecargar el
// servicio de ElToque con miles de peticiones individuales.

import '../core/supabase_client.dart';

/// Nombres amigables + orden de presentación para cada código de
/// moneda que guarda la Edge Function. Si en el futuro ElToque agrega
/// una moneda nueva, agregarla acá para que se muestre con buen
/// nombre; si no se agrega, igual se muestra con su código tal cual.
const Map<String, String> kNombresMonedas = {
  'USD': 'Dólar estadounidense',
  'EUR': 'Euro',
  'MLC': 'MLC',
  'CAD': 'Dólar canadiense',
  'MXN': 'Peso mexicano',
  'ZELLE': 'Zelle (USD)',
  'CLA': 'Tarjeta Clásica',
};

/// Orden en el que se muestran las monedas en la pantalla -- mismo
/// orden que usa la tabla de elTOQUE en su sitio.
const List<String> kOrdenMonedas = [
  'USD',
  'EUR',
  'MLC',
  'CAD',
  'MXN',
  'ZELLE',
  'CLA',
];

class TasaCambioService {
  /// Trae todas las filas de `tasas_cambio`, ya ordenadas según
  /// kOrdenMonedas. Si la tabla todavía no tiene datos (por ejemplo,
  /// antes de la primera ejecución de la Edge Function), devuelve
  /// una lista vacía -- la pantalla debe manejar ese caso mostrando
  /// un aviso, no un error.
  Future<List<Map<String, dynamic>>> obtenerTasas() async {
    final res = await supabase.from('tasas_cambio').select();
    final filas = List<Map<String, dynamic>>.from(res);

    filas.sort((a, b) {
      final ia = kOrdenMonedas.indexOf(a['moneda'] as String? ?? '');
      final ib = kOrdenMonedas.indexOf(b['moneda'] as String? ?? '');
      // Las que no están en la lista de orden van al final.
      final pa = ia == -1 ? 999 : ia;
      final pb = ib == -1 ? 999 : ib;
      return pa.compareTo(pb);
    });

    return filas;
  }

  /// Trae solo el valor USD -> CUP, usado por CurrencyService para el
  /// toggle de precios dentro de la app (que solo maneja USD/CUP).
  /// Devuelve null si todavía no hay datos.
  Future<double?> obtenerValorUsdCup() async {
    final res = await supabase
        .from('tasas_cambio')
        .select('valor_cup')
        .eq('moneda', 'USD')
        .maybeSingle();
    if (res == null || res['valor_cup'] == null) return null;
    return (res['valor_cup'] as num).toDouble();
  }
}
