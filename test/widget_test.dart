import 'package:flutter_test/flutter_test.dart';
import 'package:pricex/main.dart';

void main() {
  testWidgets('PriceX app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const PriceXApp());

    // Verificar que o app carrega com o titulo PriceX
    expect(find.text('PriceX'), findsOneWidget);
  });
}
