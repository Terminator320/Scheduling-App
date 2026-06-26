import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/widgets/views/appointment_history_view.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockAppointmentsRepository extends Mock
    implements AppointmentsRepository {}

AppointmentRecord _appt({
  required String id,
  required String title,
  required DateTime start,
  required String employeeId,
  required String employeeName,
  String clientPhone = '',
}) => AppointmentRecord(
  id: id,
  title: title,
  startTime: start,
  endTime: start.add(const Duration(hours: 1)),
  clientName: 'Client $title',
  clientPhone: clientPhone,
  employeeIds: [employeeId],
  employeeNames: [employeeName],
  status: 'done',
);

final _aliceJob = _appt(
  id: '1',
  title: 'Alice Job',
  start: DateTime(2025, 5, 1, 9),
  employeeId: 'e1',
  employeeName: 'Alice',
);

final _bobJob = _appt(
  id: '2',
  title: 'Bob Job',
  start: DateTime(2024, 8, 3, 9),
  employeeId: 'e2',
  employeeName: 'Bob',
);

Widget _wrap(List<AppointmentRecord> history, {String searchQuery = ''}) {
  final repo = _MockAppointmentsRepository();
  when(
    () => repo.fetchHistoryPage(
      limit: any(named: 'limit'),
      after: any(named: 'after'),
    ),
  ).thenAnswer((_) async => history);
  return ProviderScope(
    overrides: [appointmentsRepositoryProvider.overrideWithValue(repo)],
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
          body: AppointmentHistoryView(searchQuery: searchQuery),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('groups appointments under a year header', (tester) async {
    await tester.pumpWidget(_wrap([_aliceJob, _bobJob]));
    await tester.pumpAndSettle();

    // The year is now surfaced as its own group header (not just month + day).
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
    expect(find.text('Alice Job'), findsOneWidget);
    expect(find.text('Bob Job'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('employee filter narrows the list to that employee', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap([_aliceJob, _bobJob]));
    await tester.pumpAndSettle();

    // Open the staff dropdown chip and pick Bob.
    await tester.tap(find.text('All staff'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    expect(find.text('Bob Job'), findsOneWidget);
    expect(find.text('Alice Job'), findsNothing);
    // 2025 was only Alice's year, so its header is gone too.
    expect(find.text('2025'), findsNothing);
    expect(find.text('2024'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search matches a client phone number', (tester) async {
    final aliceWithPhone = _appt(
      id: '1',
      title: 'Alice Job',
      start: DateTime(2025, 5, 1, 9),
      employeeId: 'e1',
      employeeName: 'Alice',
      clientPhone: '(514) 555-0199',
    );

    // Query is digits only, formatted differently than the stored number.
    await tester.pumpWidget(
      _wrap([aliceWithPhone, _bobJob], searchQuery: '5550199'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice Job'), findsOneWidget);
    expect(find.text('Bob Job'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an empty state with no history', (tester) async {
    await tester.pumpWidget(_wrap(const []));
    await tester.pumpAndSettle();

    expect(find.text('No appointments found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history view does not overflow on phone width at 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _wrap([_aliceJob, _bobJob]),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
