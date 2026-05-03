import 'package:flutter_test/flutter_test.dart';

import 'package:keryx/main.dart';

void main() {
  testWidgets('Keryx app loads', (WidgetTester tester) async {
    // Test only verifies the app can be constructed
    await tester.pumpWidget(const KeryxApp(initialRoute: '/setup'));
  });
}
