import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/animations/tap_scale.dart';

Matrix4 _transformOf(WidgetTester tester) =>
    tester.widget<Transform>(find.byType(Transform)).transform;

double _scaleX(WidgetTester tester) => _transformOf(tester).storage[0];

Widget _host({required bool enabled}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: TapScale(
        enabled: enabled,
        child: const SizedBox(width: 100, height: 40),
      ),
    ),
  ),
);

void main() {
  testWidgets('pressing scales the child down', (tester) async {
    await tester.pumpWidget(_host(enabled: true));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SizedBox)),
    );
    await tester.pump();

    expect(_scaleX(tester), lessThan(1));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_scaleX(tester), 1);
  });

  testWidgets('disabling while pressed clears the pressed scale', (tester) async {
    await tester.pumpWidget(_host(enabled: true));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SizedBox)),
    );
    await tester.pump();
    expect(_scaleX(tester), lessThan(1));

    await tester.pumpWidget(_host(enabled: false));
    await tester.pump();

    expect(_scaleX(tester), 1);

    await gesture.up();
  });
}
