import 'package:flutter_test/flutter_test.dart';

import 'package:app_financeiro/app.dart';

void main() {
  testWidgets('O aplicativo inicia corretamente', (tester) async {
    await tester.pumpWidget(const FinanceApp());

    expect(find.text('MINHAS FINANÇAS'), findsOneWidget);
  });
}
