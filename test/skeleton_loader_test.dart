// test/skeleton_loader_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/shared/widgets/skeleton_loader.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('SkeletonBox renders with given dimensions', (tester) async {
    await tester.pumpWidget(_wrap(const SkeletonBox(width: 120, height: 14)));
    expect(tester.getSize(find.byType(SkeletonBox)), const Size(120, 14));
  });

  testWidgets('SkeletonAppointmentRow renders without overflow', (tester) async {
    await tester.pumpWidget(_wrap(
      const SizedBox(width: 400, child: SkeletonAppointmentRow()),
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('SkeletonListTile renders without overflow', (tester) async {
    await tester.pumpWidget(_wrap(
      const SizedBox(width: 400, child: SkeletonListTile()),
    ));
    expect(tester.takeException(), isNull);
  });
}
