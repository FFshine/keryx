import 'package:flutter_test/flutter_test.dart';

import 'package:keryx/main.dart';

void main() {
  testWidgets('Keryx app loads setup screen', (WidgetTester tester) async {
    await tester.pumpWidget(const KeryxApp());
    expect(find.text('Keryx'), findsOneWidget);
  });
}
