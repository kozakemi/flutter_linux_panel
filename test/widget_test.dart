import 'package:flutter_test/flutter_test.dart';

import 'package:demo1/main.dart';

void main() {
  testWidgets('应用主页可以正常构建', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(ClockScreen), findsOneWidget);
  });
}
