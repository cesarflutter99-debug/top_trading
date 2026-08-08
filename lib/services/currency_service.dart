// currency_service.dart
//
// Un único toggle global USD/CUP que se comparte entre TODAS las
// pantallas (modal de producto, tienda, carrito), igual que pediste.
// El vendedor siempre publica en USD (regla de negocio); esto solo
// afecta cómo se muestra el precio al comprador.

import 'package:flutter/material.dart';

enum Moneda { usd, cup }

class CurrencyService extends ChangeNotifier {
  static final CurrencyService instance = CurrencyService._();
  CurrencyService._();

  Moneda _moneda = Moneda.usd;
  double? _tasaCupPorUsd;
  DateTime? _tasaActualizada;

  Moneda get moneda => _moneda;
  double? get tasa => _tasaCupPorUsd;

  void toggle() {
    _moneda = _moneda == Moneda.usd ? Moneda.cup : Moneda.usd;
    notifyListeners();
    if (_moneda == Moneda.cup && _tasaCupPorUsd == null) {
      _cargarTasa();
    }
  }

  /// Consulta la API externa de tasa de cambio (referencial del día,
  /// según el ERS). Cachea el valor para no pedirlo en cada widget.
  /// TODO: reemplazar la URL por el endpoint real que vayan a usar
  /// (ej. eltoque.com u otra fuente de tasa informal cubana).
  Future<void> _cargarTasa() async {
    try {
      // final res = await http.get(Uri.parse('https://TU_API_DE_TASA/hoy'));
      // _tasaCupPorUsd = jsonDecode(res.body)['usd_to_cup'];
      _tasaCupPorUsd ??= 320; // valor de respaldo si la API falla
      _tasaActualizada = DateTime.now();
      notifyListeners();
    } catch (_) {
      _tasaCupPorUsd ??= 320;
    }
  }

  String formatear(double montoUsd) {
    if (_moneda == Moneda.usd) {
      return '\$${montoUsd.toStringAsFixed(2)} USD';
    }
    final tasa = _tasaCupPorUsd ?? 320;
    final montoCup = montoUsd * tasa;
    return '${montoCup.toStringAsFixed(0)} CUP';
  }
}

/// Segmented control pequeño para poner en cualquier AppBar o header.
/// Mismo widget en modal, tienda y carrito -> mismo look siempre.
/// Ahora sigue el tema activo (antes usaba grey.shade200/blanco fijos,
/// por eso se veía mal -- una caja gris clara flotando -- en modo
/// oscuro).
class CurrencyToggle extends StatelessWidget {
  const CurrencyToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esOscuro = theme.brightness == Brightness.dark;
    final fondoPill = esOscuro
        ? Colors.white.withOpacity(0.10)
        : Colors.black.withOpacity(0.05);
    final activoBg = theme.cardTheme.color ?? theme.colorScheme.surface;
    final textoActivo = theme.textTheme.bodyMedium?.color ??
        (esOscuro ? Colors.white : Colors.black);
    final textoInactivo = esOscuro ? Colors.white60 : Colors.black45;

    return AnimatedBuilder(
      animation: CurrencyService.instance,
      builder: (context, _) {
        final esUsd = CurrencyService.instance.moneda == Moneda.usd;
        return GestureDetector(
          onTap: () => CurrencyService.instance.toggle(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: fondoPill,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _pill('USD', esUsd, activoBg, textoActivo, textoInactivo,
                    esOscuro),
                _pill('CUP', !esUsd, activoBg, textoActivo, textoInactivo,
                    esOscuro),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pill(
    String label,
    bool activo,
    Color activoBg,
    Color textoActivo,
    Color textoInactivo,
    bool esOscuro,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: activo ? activoBg : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        boxShadow: activo
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(esOscuro ? 0.4 : 0.12),
                  blurRadius: 4,
                ),
              ]
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: activo ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
          color: activo ? textoActivo : textoInactivo,
        ),
      ),
    );
  }
}

/// Precio formateado que se re-pinta solo cuando cambia el toggle o la
/// tasa. Úsalo en vez de escribir "$X USD" a mano en cualquier pantalla.
/// El verde se ajusta según el modo (uno más claro en oscuro) para
/// mantener buen contraste en ambos casos.
class PriceTag extends StatelessWidget {
  final double montoUsd;
  final TextStyle? style;
  const PriceTag({super.key, required this.montoUsd, this.style});

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    final verde = esOscuro ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
    return AnimatedBuilder(
      animation: CurrencyService.instance,
      builder: (context, _) => Text(
        CurrencyService.instance.formatear(montoUsd),
        style: style ??
            TextStyle(fontSize: 16, color: verde, fontWeight: FontWeight.w700),
      ),
    );
  }
}
