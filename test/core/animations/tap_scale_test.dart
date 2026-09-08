import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/animations/tap_scale.dart';

/// The `AnimatedScale`'s own `Transform` - scoped, because the surrounding
/// Material chrome contributes `Transform`s of its own.
double _scaleX(WidgetTester tester) => tester
    .widgetList<Transform>(
      find.descendant(
        of: find.byType(AnimatedScale),
        matching: find.byType(Transform),
      ),
    )
    .first
    .transform
    .storage[0];

const _childKey = Key('tap-scale-child');

// A painted box, not a bare SizedBox: `TapScale`'s `Listener` defers hit
// testing to its child, and an empty SizedBox never receives the pointer.
Widget _host({required bool enabled}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: TapScale(
        enabled: enabled,
        child: const SizedBox(
          key: _childKey,
          width: 100,
          height: 40,
          child: ColoredBox(color: Color(0xFF112233)),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('pressing scales the child down', (tester) async {
    await tester.pumpWidget(_host(enabled: true));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_childKey)),
    );
    await tester.pumpAndSettle();

    expect(_scaleX(tester), lessThan(1));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_scaleX(tester), 1);
  });

  testWidgets('a press on a disabled TapScale does not scale', (tester) async {
    await tester.pumpWidget(_host(enabled: false));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_childKey)),
    );
    await tester.pumpAndSettle();

    expect(_scaleX(tester), 1);

    await gesture.up();
  });

  testWidgets('disabling while pressed clears the pressed scale', (tester) async {
    await tester.pumpWidget(_host(enabled: true));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_childKey)),
    );
    await tester.pumpAndSettle();
    expect(_scaleX(tester), lessThan(1));

    await tester.pumpWidget(_host(enabled: false));
    await tester.pumpAndSettle();

    expect(_scaleX(tester), 1);

    await gesture.up();
  });
}
