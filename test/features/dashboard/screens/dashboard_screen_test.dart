import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/dashboard/application/dashboard_providers.dart';
import 'package:scheduling/features/dashboard/screens/dashboard_screen.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockClientsRepo extends Mock implements ClientsRepository {}

/// Fixed clock: Wednesday 2026-07-08, noon.
final _now = DateTime(2026, 7, 8, 12);

const _jane = EmployeeRecord(
  id: 'e1',
  name: 'Jane Doe',
  email: 'jane@example.com',
  status: 'active',
);

AppointmentRecord _appt({
  required String id,
  required DateTime start,
  String status = 'pending',
  List<String> employeeIds = const ['e1'],
}) => AppointmentRecord(
  id: id,
  title: 'Job $id',
  startTime: start,
  endTime: start.add(const Duration(hours: 1)),
  status: status,
  employeeIds: employeeIds,
);

Widget _wrap({
  required List<AppointmentRecord> appointments,
  required ClientsRepository clientsRepo,
  Object? appointmentsError,
}) {
  return ProviderScope(
    overrides: [
      dashboardClockProvider.overrideWithValue(() => _now),
      appointmentsInRangeProvider.overrideWith(
        (_, _) => appointmentsError != null
            ? Stream<List<AppointmentRecord>>.error(appointmentsError)
            : Stream.value(appointments),
      ),
      // Fresh stream per provider: Stream.value is single-subscription.
      employeesStreamProvider.overrideWith((_) => Stream.value(const [_jane])),
      allUsersStreamProvider.overrideWith((_) => Stream.value(const [_jane])),
      clientsRepositoryProvider.overrideWithValue(clientsRepo),
    ],
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
        home: const DashboardScreen(isAdmin: true, employeeId: 'admin1'),
      ),
    ),
  );
}

void main() {
  late _MockClientsRepo clientsRepo;

  setUpAll(() {
    registerFallbackValue(DateTime(2026));
  });

  setUp(() {
    clientsRepo = _MockClientsRepo();
    when(() => clientsRepo.fetchClientsCreatedSince(any())).thenAnswer(
      (_) async => [
        ClientRecord.fromMap('c1', {
          'name': 'Alice',
          'createdAt': DateTime(2026, 7, 7),
        }),
      ],
    );
  });

  Future<void> withPhoneViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('renders the hero, all section headers, and a workload row', (
    tester,
  ) async {
    await withPhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        appointments: [
          // Upcoming today AND pending-within-48h.
          _appt(id: 'up', start: DateTime(2026, 7, 8, 14)),
          // Ended yesterday, never closed.
          _appt(
            id: 'overdue',
            start: DateTime(2026, 7, 7, 9),
            status: 'in_progress',
          ),
        ],
        clientsRepo: clientsRepo,
      ),
    );
    await tester.pumpAndSettle();

    // Hero big-number label lives in a Text.rich span. Exactly one visit is
    // today (the overdue one is yesterday), so the label is singular.
    expect(
      find.textContaining('visit today', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('NEXT UP TODAY'), findsOneWidget);
    expect(find.text('EMPLOYEE WORKLOAD'), findsOneWidget);
    expect(find.text('BUSINESS TRENDS'), findsOneWidget);
    expect(find.text('NEEDS ATTENTION'), findsOneWidget);
    expect(find.text('Jane Doe'), findsWidgets);
    expect(
      find.text('1 pending visit starts within 48 hours'),
      findsOneWidget,
    );
    expect(find.text('1 past visit was never closed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the unassigned pill for an unassigned visit today', (
    tester,
  ) async {
    await withPhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        appointments: [
          _appt(
            id: 'open',
            start: DateTime(2026, 7, 8, 15),
            employeeIds: const [],
          ),
        ],
        clientsRepo: clientsRepo,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 unassigned job today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty data shows all-clear and no-visits states', (
    tester,
  ) async {
    await withPhoneViewport(tester);
    when(
      () => clientsRepo.fetchClientsCreatedSince(any()),
    ).thenAnswer((_) async => const []);
    await tester.pumpWidget(
      _wrap(appointments: const [], clientsRepo: clientsRepo),
    );
    await tester.pumpAndSettle();

    expect(find.text('No upcoming visits today'), findsOneWidget);
    expect(
      find.text('All clear — nothing needs attention'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stream error renders the error body without throwing', (
    tester,
  ) async {
    await withPhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(
        appointments: const [],
        clientsRepo: clientsRepo,
        appointmentsError: Exception('boom'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load the dashboard"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
