// fila_dato_copiable.dart
//
// Fila estándar "Etiqueta: valor" para TODOS los modales de pago de la
// app (plan, paquete de negocio, ranuras extra de tienda, independiente).
// Tocar la fila o su ícono copia el valor al portapapeles al instante
// (tarjeta, teléfono, código de referencia...) -- el SelectableText de
// debajo sigue estando para quien prefiera seleccionar a mano.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class FilaDatoCopiable extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const FilaDatoCopiable({
    super.key,
    required this.etiqueta,
    required this.valor,
  });

  Future<void> _copiar(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: valor));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$etiqueta copiado'),
          duration: const Duration(seconds: 1),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final esOscuro = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _copiar(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          child: Row(
            children: [
              Text(
                '$etiqueta: ',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              Expanded(
                child: SelectableText(
                  valor,
                  style: GoogleFonts.inter(fontSize: 13.5),
                ),
              ),
              Icon(
                Icons.copy_rounded,
                size: 15,
                color: esOscuro ? Colors.white54 : Colors.black38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}