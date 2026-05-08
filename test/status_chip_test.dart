// test/status_chip_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/shared/widgets/status_chip.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('StatusChip renders Confirmed label', (tester) async {
    await tester.pumpWidget(_wrap(const StatusChip(status: AppointmentStatus.confirmed)));
    expect(find.text('Confirmed'), findsOneWidget);
  });

  testWidgets('StatusChip renders Done label', (tester) async {
    await tester.pumpWidget(_wrap(const StatusChip(status: AppointmentStatus.done)));
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('StatusChip renders Pending label', (tester) async {
    await tester.pumpWidget(_wrap(const StatusChip(status: AppointmentStatus.pending)));
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('StatusChip renders Cancelled label', (tester) async {
    await tester.pumpWidget(_wrap(const StatusChip(status: AppointmentStatus.cancelled)));
    expect(find.text('Cancelled'), findsOneWidget);
  });

  testWidgets('StatusChip renders Active label', (tester) async {
    await tester.pumpWidget(_wrap(const StatusChip(status: AppointmentStatus.active)));
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('StatusChip renders Invited label', (tester) async {
    await tester.pumpWidget(_wrap(const StatusChip(status: AppointmentStatus.invited)));
    expect(find.text('Invited'), findsOneWidget);
  });

  testWidgets('StatusChip renders Disabled label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StatusChip(status: AppointmentStatus.disabled))),
    );
    expect(find.text('Disabled'), findsOneWidget);
  });

  testWidgets('StatusChip renders In Progress label', (tester) async {
    await tester.pumpWidget(_wrap(const StatusChip(status: AppointmentStatus.inProgress)));
    expect(find.text('In Progress'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
