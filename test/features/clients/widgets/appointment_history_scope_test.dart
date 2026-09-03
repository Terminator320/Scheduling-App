import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/core/utils/debouncer.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/widgets/views/appointment_history_view.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockAppointmentsRepository extends Mock
    implements AppointmentsRepository {}

final _marcsJob = AppointmentRecord(
  id: '1',
  title: 'Leak fix',
  startTime: DateTime(2025, 5, 1, 9),
  endTime: DateTime(2025, 5, 1, 10),
  clientName: 'Sophie Tremblay',
  employeeIds: const ['e1'],
  employeeNames: const ['Marc'],
  status: 'done',
);

Widget _wrap(
  AppointmentsRepository repo, {
  String searchQuery = '',
  String? scopeEmployeeId,
}) => ProviderScope(
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
          scopeEmployeeId: scopeEmployeeId,
        ),
      ),
    ),
  ),
);

/// A technician's History is their own jobs.
void main() {
  late _MockAppointmentsRepository repo;

  setUp(() {
    repo = _MockAppointmentsRepository();
    when(() => repo.onLocalWrite).thenAnswer((_) => const Stream<void>.empty());
    when(
      () => repo.searchHistory(any(), employeeId: any(named: 'employeeId')),
    ).thenAnswer((_) async => const []);
  });

  void stubPage(List<AppointmentRecord> rows) {
    when(
      () => repo.fetchHistoryPage(
        limit: any(named: 'limit'),
        after: any(named: 'after'),
        employeeId: any(named: 'employeeId'),
      ),
    ).thenAnswer((_) async => rows);
  }

  testWidgets("a scoped view pages that person's history", (tester) async {
    stubPage([_marcsJob]);

    await tester.pumpWidget(_wrap(repo, scopeEmployeeId: 'e1'));
    await tester.pumpAndSettle();

    expect(find.text('Leak fix'), findsOneWidget);
    verify(
      () => repo.fetchHistoryPage(
        limit: any(named: 'limit'),
        after: any(named: 'after'),
        employeeId: 'e1',
      ),
    ).called(1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unscoped view pages the whole archive', (tester) async {
    stubPage([_marcsJob]);

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    verify(
      () => repo.fetchHistoryPage(
        limit: any(named: 'limit'),
        after: any(named: 'after'),
        // Spelled out even though null is the default: it is the assertion.
        // ignore: avoid_redundant_argument_values
        employeeId: null,
      ),
    ).called(1);
  });

  testWidgets('a scoped search carries the scope', (tester) async {
    stubPage([_marcsJob]);

    await tester.pumpWidget(_wrap(repo, scopeEmployeeId: 'e1'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _wrap(repo, scopeEmployeeId: 'e1', searchQuery: 'sophie'),
    );
    await tester.pump(kSearchDebounce + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    verify(() => repo.searchHistory('sophie', employeeId: 'e1')).called(1);
  });

  group('the empty state', () {
    testWidgets('tells a technician their closed jobs will appear here', (
      tester,
    ) async {
      stubPage(const []);

      await tester.pumpWidget(_wrap(repo, scopeEmployeeId: 'e1'));
      await tester.pumpAndSettle();

      expect(
        find.text('Your finished and cancelled jobs will appear here.'),
        findsOneWidget,
      );
      expect(find.textContaining('Tap'), findsNothing);
    });

    testWidgets('still tells an admin to book something', (tester) async {
      stubPage(const []);

      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      expect(
        find.text('Your finished and cancelled jobs will appear here.'),
        findsNothing,
      );
      expect(find.textContaining('Tap'), findsOneWidget);
    });
  });
}
