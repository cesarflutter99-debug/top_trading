import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_trading/main.dart';

void main() {
  testWidgets('AppBanner muestra su título y mensaje', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: AppBanner(
          icon: Icons.info_outline,
          titulo: 'Aviso',
          mensaje: 'Mensaje de prueba',
        ),
      ),
    ));
    expect(find.text('Aviso'), findsOneWidget);
    expect(find.text('Mensaje de prueba'), findsOneWidget);
  });
}
