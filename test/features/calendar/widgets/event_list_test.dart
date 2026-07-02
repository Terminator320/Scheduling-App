// The empty state must not tell employees to "Tap +" — only admins have the
// add FAB. Admins keep the actionable copy; employees get a neutral message.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/views/event_list.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _wrap({
  required ValueNotifier<List<AppointmentRecord>> events,
  required bool isAdmin,
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
          nameMap: const {},
          colorMap: const {},
          isAdmin: isAdmin,
        ),
      ],
    ),
  ),
);

void main() {
  late ValueNotifier<List<AppointmentRecord>> events;

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
}
