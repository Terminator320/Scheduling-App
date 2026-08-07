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

Widget _wrap(
  List<AppointmentRecord> history, {
  String searchQuery = '',
  AppointmentsRepository? repository,
  bool isAdmin = false,
}) {
  final repo = repository ?? _MockAppointmentsRepository();
  if (repository == null) {
    when(() => repo.onLocalWrite).thenAnswer((_) => const Stream<void>.empty());
    when(
      () => repo.fetchHistoryPage(
        limit: any(named: 'limit'),
        after: any(named: 'after'),
      ),
    ).thenAnswer((_) async => history);
  }
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
          body: AppointmentHistoryView(
            searchQuery: searchQuery,
            isAdmin: isAdmin,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group("the row opens the detail sheet with the caller's role", () {
    testWidgets("an admin reaches the completed job's edit button", (
      tester,
    ) async {
      await tester.pumpWidget(_wrap([_aliceJob], isAdmin: true));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice Job'));
      await tester.pumpAndSettle();

      // History holds only done and cancelled jobs, so this button is the one
      // affordance an admin needs here — and the only route back off Complete,
      // since the status picker lives in the edit form behind it.
      expect(find.text('Edit completed job'), findsOneWidget);
    });

    testWidgets('an employee gets the read-only sheet', (tester) async {
      await tester.pumpWidget(_wrap([_aliceJob]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice Job'));
      await tester.pumpAndSettle();

      // showActions defaults CLOSED. Offering an employee the edit route here
      // would only earn them an opaque permission-denied from the rules.
      expect(find.text('Edit completed job'), findsNothing);
      // "Complete" twice, not once: the header's status chip and the action
      // bar's disabled indicator both read it on a finished job.
      expect(find.text('Complete'), findsWidgets);
    });
  });

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

  testWidgets('first-page error offers a Retry that reloads history', (
    tester,
  ) async {
    final repo = _MockAppointmentsRepository();
    when(() => repo.onLocalWrite).thenAnswer((_) => const Stream<void>.empty());
    var calls = 0;
    when(
      () => repo.fetchHistoryPage(
        limit: any(named: 'limit'),
        after: any(named: 'after'),
      ),
    ).thenAnswer((_) async {
      if (calls++ == 0) throw Exception('boom');
      return [_aliceJob];
    });

    await tester.pumpWidget(_wrap(const [], repository: repo));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Couldn't load the appointment history"),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Alice Job'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search error offers a Retry that re-runs the search', (
    tester,
  ) async {
    final repo = _MockAppointmentsRepository();
    when(() => repo.onLocalWrite).thenAnswer((_) => const Stream<void>.empty());
    when(
      () => repo.fetchHistoryPage(
        limit: any(named: 'limit'),
        after: any(named: 'after'),
      ),
    ).thenAnswer((_) async => [_aliceJob]);
    when(() => repo.searchHistory(any())).thenThrow(Exception('boom'));

    // Start unfiltered, then type a query that no loaded row matches, so the
    // committed database search (and its failure) is what gets rendered.
    await tester.pumpWidget(_wrap(const [], repository: repo));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _wrap(const [], repository: repo, searchQuery: 'zzz'),
    );
    // Let the search debounce commit, then the provider fail.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Couldn't load the appointment history"),
      findsOneWidget,
    );

    when(() => repo.searchHistory(any())).thenAnswer((_) async => [_bobJob]);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Bob Job'), findsOneWidget);
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
