// tasa_cambio_screen.dart
//
// Muestra todas las monedas que trae la API de elTOQUE (USD, EUR, MLC,
// CAD, MXN, ZELLE, CLA), leyendo la tabla `tasas_cambio` de Supabase --
// que se actualiza sola cada 12 horas vía Edge Function. Esta pantalla
// NUNCA llama a elTOQUE directamente.
//
// Nota: dentro del resto de la app (precios de productos, carrito) el
// toggle de moneda sigue siendo solo USD/CUP (CurrencyService) -- esta
// pantalla es la única que muestra el resto de las monedas, a modo
// informativo, igual que la tabla que se ve en eltoque.com.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../services/tasa_cambio_service.dart';

class TasaCambioScreen extends StatefulWidget {
  const TasaCambioScreen({super.key});

  @override
  State<TasaCambioScreen> createState() => _TasaCambioScreenState();
}

class _TasaCambioScreenState extends State<TasaCambioScreen> {
  final _service = TasaCambioService();
  late Future<List<Map<String, dynamic>>> _tasas;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _tasas = _service.obtenerTasas();
  }

  String _formatFecha(String? iso) {
    if (iso == null) return '';
    final fecha = DateTime.tryParse(iso)?.toLocal();
    if (fecha == null) return '';
    final hh = fecha.hour.toString().padLeft(2, '0');
    final mm = fecha.minute.toString().padLeft(2, '0');
    return '${fecha.day}/${fecha.month}/${fecha.year} · $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Tasa de Cambio'),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: () => setState(_cargar),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_cargar),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _tasas,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _estadoVacio(
                icon: Icons.error_outline_rounded,
                titulo: 'No se pudo cargar la tasa de cambio',
                mensaje: '${snapshot.error}',
              );
            }
            final tasas = snapshot.data ?? [];
            if (tasas.isEmpty) {
              return _estadoVacio(
                icon: Icons.hourglass_top_rounded,
                titulo: 'Todavía no hay datos',
                mensaje:
                    'La tasa de cambio se actualiza automáticamente cada '
                    '12 horas. Vuelve a intentarlo un poco más tarde.',
              );
            }

            final ultimaActualizacion = tasas
                .map((t) => t['actualizado_en'] as String?)
                .whereType<String>()
                .fold<String?>(null, (max, actual) {
              if (max == null) return actual;
              return actual.compareTo(max) > 0 ? actual : max;
            });

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(kCardRadius),
                    border:
                        Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tasa Representativa del Mercado Informal (TRMI), '
                          'fuente: elTOQUE. Actualizado: '
                          '${_formatFecha(ultimaActualizacion)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: esOscuro
                                ? AppColors.inkSecundarioDark
                                : AppColors.inkSecundarioLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ...tasas.map((t) => _filaMoneda(t, esOscuro)),
                const SizedBox(height: 16),
                Text(
                  'Los valores son referenciales y pueden variar respecto '
                  'al mercado real. Datos proporcionados por elTOQUE.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppColors.inkSecundarioLight,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _filaMoneda(Map<String, dynamic> t, bool esOscuro) {
    final codigo = t['moneda'] as String? ?? '';
    final nombre = kNombresMonedas[codigo] ?? codigo;
    final valor = (t['valor_cup'] as num?)?.toDouble();
    final variacion = (t['variacion'] as num?)?.toDouble();

    final subiendo = (variacion ?? 0) >= 0;
    final hayVariacion = variacion != null && variacion != 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: esOscuro ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              codigo.length > 4 ? codigo.substring(0, 4) : codigo,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre,
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                Text('1 $codigo',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5, color: AppColors.inkSecundarioLight)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                valor != null ? '${valor.toStringAsFixed(2)} CUP' : '-- CUP',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w800, fontSize: 15),
              ),
              if (hayVariacion)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      subiendo
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 12,
                      color: subiendo ? AppColors.success : Colors.redAccent,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      variacion.abs().toStringAsFixed(2),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color:
                            subiendo ? AppColors.success : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _estadoVacio(
      {required IconData icon, required String titulo, required String mensaje}) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 40, color: AppColors.inkSecundarioLight),
                  const SizedBox(height: 12),
                  Text(titulo,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text(mensaje,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          color: AppColors.inkSecundarioLight)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
