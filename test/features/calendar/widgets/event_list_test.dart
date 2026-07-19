// The empty state must not tell employees to "Tap +" — only admins have the
// add FAB. Admins keep the actionable copy; employees get a neutral message.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/views/event_list.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _wrap({
  required ValueNotifier<List<AppointmentRecord>> events,
  required bool isAdmin,
  Map<String, String> nameMap = const {},
  VoidCallback? onSchedule,
}) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Column(
      children: [
        EventList(
          events: events,
          nameMap: nameMap,
          colorMap: const {},
          isAdmin: isAdmin,
          onSchedule: onSchedule,
        ),
      ],
    ),
  ),
);

void main() {
  late ValueNotifier<List<AppointmentRecord>> events;

  setUpAll(() async {
    await initializeDateFormatting('en_CA');
  });

  setUp(() {
    events = ValueNotifier(const <AppointmentRecord>[]);
    addTearDown(events.dispose);
  });

  testWidgets('admin empty state suggests tapping the add FAB', (tester) async {
    await tester.pumpWidget(_wrap(events: events, isAdmin: true));
    await tester.pumpAndSettle();

    expect(find.text('No appointments found'), findsOneWidget);
    expect(find.text('Tap + to schedule an appointment.'), findsOneWidget);
  });

  testWidgets('employee empty state stays neutral (no + FAB to tap)', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(events: events, isAdmin: false));
    await tester.pumpAndSettle();

    expect(find.text('No appointments found'), findsOneWidget);
    expect(find.text('No appointments for this day.'), findsOneWidget);
    expect(find.text('Tap + to schedule an appointment.'), findsNothing);
  });

  testWidgets('admin empty state schedule button fires onSchedule', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      _wrap(events: events, isAdmin: true, onSchedule: () => tapped++),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(FilledButton, 'New Appointment');
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });

  testWidgets('employee empty state shows no schedule button', (tester) async {
    await tester.pumpWidget(
      _wrap(events: events, isAdmin: false, onSchedule: () {}),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'New Appointment'), findsNothing);
  });

  testWidgets('appointment card lists every assigned employee', (tester) async {
    events.value = [
      AppointmentRecord(
        id: '1',
        title: 'Kitchen sink',
        startTime: DateTime(2099, 5, 6, 9),
        endTime: DateTime(2099, 5, 6, 10),
        employeeIds: const ['e1', 'e2'],
        status: 'confirmed',
      ),
    ];
    await tester.pumpWidget(
      _wrap(
        events: events,
        isAdmin: true,
        nameMap: const {'e1': 'Alice', 'e2': 'Bob'},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice, Bob'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
