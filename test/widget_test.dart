import 'package:flutter_test/flutter_test.dart';
import 'package:top_trading/main.dart';

void main() {
  testWidgets('La app carga sin errores', (WidgetTester tester) async {
    await tester.pumpWidget(const TopTradingApp());
    expect(find.text('Top Trading'), findsOneWidget);
  });
}