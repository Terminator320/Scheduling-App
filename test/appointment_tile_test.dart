// test/appointment_tile_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/features/calendar/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/appointment_tile.dart';
import 'package:scheduling/shared/widgets/status_chip.dart';

AppointmentRecord _fakeAppt({String status = 'confirmed'}) => AppointmentRecord(
  id: '1',
  title: 'Haircut',
  startTime: DateTime(2026, 5, 6, 9, 0),
  endTime: DateTime(2026, 5, 6, 9, 45),
  clientId: 'c1',
  clientName: 'Sarah Johnson',
  clientPhone: '514-555-0101',
  employeeIds: ['e1'],
  employeeNames: ['Alex'],
  address: '123 Main St',
  notes: '',
  materialsNeeded: '',
  status: status,
  pictures: [],
);

const _colorMap = {'e1': Color(0xFF6366F1)};

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_CA');
  });

  testWidgets('AppointmentTile shows service title', (tester) async {
    await tester.pumpWidget(_wrap(AppointmentTile(
      appointment: _fakeAppt(),
      employeeColorMap: _colorMap,
    )));
    expect(find.textContaining('Haircut'), findsOneWidget);
  });

  testWidgets('AppointmentTile shows StatusChip', (tester) async {
    await tester.pumpWidget(_wrap(AppointmentTile(
      appointment: _fakeAppt(),
      employeeColorMap: _colorMap,
    )));
    expect(find.byType(StatusChip), findsOneWidget);
  });

  testWidgets('AppointmentTile calls onOpen when tapped', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(_wrap(AppointmentTile(
      appointment: _fakeAppt(),
      employeeColorMap: _colorMap,
      onOpen: () async => tapped = true,
    )));
    await tester.tap(find.byType(AppointmentTile));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('AppointmentTile does not overflow at small size + large text', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(260 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
      child: _wrap(AppointmentTile(
        appointment: _fakeAppt(),
        employeeColorMap: _colorMap,
      )),
    ));
    expect(tester.takeException(), isNull);
  });
}
