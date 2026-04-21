import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/main.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const PaulApp());
    expect(tester.takeException(), isNull);
  });
}