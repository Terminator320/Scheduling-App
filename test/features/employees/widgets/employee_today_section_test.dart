import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/cards/appointment_card.dart';
import 'package:scheduling/features/employees/application/employee_schedule_providers.dart';
import 'package:scheduling/features/employees/widgets/sections/employee_today_section.dart';
import 'package:scheduling/l10n/l10n.dart';

AppointmentRecord _job(String id, int hour) => AppointmentRecord(
  id: id,
  title: 'Job $id',
  startTime: DateTime(2026, 8, 2, hour),
  endTime: DateTime(2026, 8, 2, hour + 1),
  employeeIds: const ['e1'],
  employeeNames: const ['Theo Roy'],
);

Widget _wrap(List<AppointmentRecord> jobs) => ProviderScope(
  overrides: [employeeTodayJobsProvider('e1').overrideWithValue(jobs)],
  child: ThemeNotifier(
    themeMode: ThemeMode.light,
    toggleTheme: () {},
    textScale: 1,
    setTextScale: (_) {},
    setLanguage: (_) {},
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: lightTheme(),
      home: Scaffold(
        body: EmployeeTodaySection(employeeId: 'e1', onJobTap: (_) {}),
      ),
    ),
  ),
);

void main() {
  testWidgets('renders a card per job, in the order given', (tester) async {
    await tester.pumpWidget(_wrap([_job('a', 9), _job('b', 14)]));
    await tester.pumpAndSettle();

    expect(find.byType(AppointmentCard), findsNWidgets(2));
    final ids = tester
        .widgetList<AppointmentCard>(find.byType(AppointmentCard))
        .map((card) => card.appointment.id)
        .toList();
    expect(ids, ['a', 'b']);
    expect(tester.takeException(), isNull);
  });

  // Deliberate exception to the omit-empty-sections rule: "nothing" is a real
  // answer an admin needs, and a missing section is indistinguishable from a
  // section that does not exist.
  testWidgets('says so when there is nothing booked', (tester) async {
    await tester.pumpWidget(_wrap(const []));
    await tester.pumpAndSettle();

    expect(find.text('No jobs today'), findsOneWidget);
    expect(find.byType(AppointmentCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
