import 'package:flutter_test/flutter_test.dart';

import 'package:frt_test_app/main.dart';

void main() {
  testWidgets('test page starts ready', (WidgetTester tester) async {
    await tester.pumpWidget(const TestApp());
    expect(find.text('Ready'), findsOneWidget);
  });
}
