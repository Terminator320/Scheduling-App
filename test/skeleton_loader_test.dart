// test/skeleton_loader_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/shared/widgets/feedback/skeleton_loader.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('SkeletonAppointmentRow renders without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const SizedBox(width: 400, child: SkeletonAppointmentRow())),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('SkeletonListTile renders without overflow', (tester) async {
    await tester.pumpWidget(
      _wrap(const SizedBox(width: 400, child: SkeletonListTile())),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shimmer runs by default', (tester) async {
    await tester.pumpWidget(_wrap(const SkeletonListTile()));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('reduce-motion renders a static skeleton (no shimmer)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const SkeletonListTile(), disableAnimations: true),
    );
    expect(tester.hasRunningAnimations, isFalse);
    // A repeating shimmer would make pumpAndSettle time out.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
