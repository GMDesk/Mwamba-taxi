import 'package:flutter_test/flutter_test.dart';

import 'package:mwamba_taxi/main.dart';

void main() {
  testWidgets('App smoke test - should build without errors',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MwambaTaxiApp());
    await tester.pumpAndSettle();

    // Verify the app renders successfully
    expect(find.byType(MwambaTaxiApp), findsOneWidget);
  });
}
