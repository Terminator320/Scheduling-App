// Day-cell accessibility: AppCalendar's markerBuilder announces the day's
// appointment count instead of exposing the colour-only marker dots.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/views/app_calendar_view.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:table_calendar/table_calendar.dart';

final _day = DateTime(2026, 5, 16);

AppointmentRecord _appointment(int id) => AppointmentRecord(
  id: 'a$id',
  title: 'Appt $id',
  startTime: _day.add(Duration(hours: 9 + id)),
  endTime: _day.add(Duration(hours: 10 + id)),
  employeeIds: const ['e1'],
);

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_CA');
  });

  testWidgets('day cells expose a full-date label and appointment count', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    final events = [_appointment(1), _appointment(2)];
    await tester.pumpWidget(
      _wrap(
        AppCalendar(
          focusedDay: _day,
          selectedDay: _day,
          onDaySelected: (_, _) {},
          eventLoader: (day) =>
              isSameDay(day, _day) ? events : const <AppointmentRecord>[],
          employeeColorMap: const {'e1': Colors.teal},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The cell announces table_calendar's built-in full date merged with the
    // pluralized appointment count contributed by the marker semantics.
    expect(
      find.bySemanticsLabel(
        RegExp('Saturday, May 16, 2026.*2 appointments', dotAll: true),
      ),
      findsOneWidget,
    );
    // A day without events keeps the plain full-date label.
    expect(
      find.bySemanticsLabel('Friday, May 15, 2026'),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('a single appointment uses the singular label', (tester) async {
    final handle = tester.ensureSemantics();

    final events = [_appointment(1)];
    await tester.pumpWidget(
      _wrap(
        AppCalendar(
          focusedDay: _day,
          selectedDay: _day,
          onDaySelected: (_, _) {},
          eventLoader: (day) =>
              isSameDay(day, _day) ? events : const <AppointmentRecord>[],
          employeeColorMap: const {'e1': Colors.teal},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(
        RegExp('Saturday, May 16, 2026.*1 appointment', dotAll: true),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('1 appointments')),
      findsNothing,
    );

    handle.dispose();
  });
}
