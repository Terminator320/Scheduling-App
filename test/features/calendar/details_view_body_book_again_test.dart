import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/auth/application/active_user_identity_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_prefill.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/views/details_view_body.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockAppointmentsRepo extends Mock implements AppointmentsRepository {}

class _MockClientsRepo extends Mock implements ClientsRepository {}

class _MockEmployeesRepo extends Mock implements EmployeesRepository {}

const _client = ClientRecord(
  id: 'c1',
  name: 'Existing Client',
  phone: '555-1111',
  address: '1 First St',
);

const _employeeA = EmployeeRecord(id: 'e1', name: 'Alex');

final _open = AppointmentRecord(
  id: 'appt-1',
  title: 'Leak fix',
  startTime: DateTime(2026, 5, 10, 9),
  endTime: DateTime(2026, 5, 10, 10),
  clientId: 'c1',
  clientName: 'Existing Client',
  clientPhone: '555-1111',
  address: '1 First St',
  employeeIds: const ['e1'],
  employeeNames: const ['Alex'],
);

const _bookAgain = 'Book again';

/// [textScale] 2 at a 260px-wide view is the overflow worst case.
Widget _harness(
  Widget child, {
  required List<Override> overrides,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

/// The "Book again" action (2026-09-02, the audit's last I18 item): an admin's,
/// on any client job including a closed one, and nobody else's.
void main() {
  late _MockAppointmentsRepo appointments;
  late _MockClientsRepo clients;
  late _MockEmployeesRepo employees;
  late PhotoUploadNotifier uploadNotifier;

  setUp(() {
    appointments = _MockAppointmentsRepo();
    clients = _MockClientsRepo();
    employees = _MockEmployeesRepo();
    uploadNotifier = PhotoUploadNotifier();
    when(() => clients.getClientById(any())).thenAnswer((_) async => _client);
    when(
      employees.watchEmployees,
    ).thenAnswer((_) => Stream.value(const [_employeeA]));
    when(
      () => appointments.onLocalWrite,
    ).thenAnswer((_) => const Stream.empty());
  });

  List<Override> overrides({ActiveUserIdentity? identity}) => [
    appointmentsRepositoryProvider.overrideWithValue(appointments),
    clientsRepositoryProvider.overrideWithValue(clients),
    employeesRepositoryProvider.overrideWithValue(employees),
    photoUploadNotifierProvider.overrideWithValue(uploadNotifier),
    if (identity != null)
      activeUserIdentityProvider.overrideWith((ref) => identity),
  ];

  Future<void> pump(
    WidgetTester tester,
    AppointmentRecord appointment, {
    bool showActions = true,
    ActiveUserIdentity? identity,
    ValueChanged<AppointmentPrefill>? onBookAgain,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      _harness(
        DetailsViewBody(
          appointment: appointment,
          showActions: showActions,
          onClose: () {},
          onBookAgain: onBookAgain ?? (_) {},
        ),
        overrides: overrides(identity: identity),
        textScale: textScale,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an admin gets it on an open job', (tester) async {
    await pump(tester, _open);
    expect(find.text(_bookAgain), findsOneWidget);
  });

  testWidgets('a done job offers it — the repeat callback case', (
    tester,
  ) async {
    await pump(tester, _open.copyWith(status: 'done'));
    expect(find.text(_bookAgain), findsOneWidget);
  });

  testWidgets('a cancelled job offers it too', (tester) async {
    await pump(tester, _open.copyWith(status: 'cancelled'));
    expect(find.text(_bookAgain), findsOneWidget);
  });

  testWidgets('a personal block has no client to re-book', (tester) async {
    await pump(
      tester,
      _open.copyWith(isPersonal: true, clientId: '', clientName: ''),
    );
    expect(find.text(_bookAgain), findsNothing);
  });

  testWidgets('a read-only surface gets none', (tester) async {
    await pump(tester, _open, showActions: false);
    expect(find.text(_bookAgain), findsNothing);
  });

  testWidgets('a non-admin assignee gets none, even with their own actions', (
    tester,
  ) async {
    await pump(
      tester,
      _open,
      showActions: false,
      identity: (role: 'employee', docId: 'e1'),
    );
    // Start job proves this IS the assignee surface, not a read-only one.
    expect(find.text('Start job'), findsOneWidget);
    expect(find.text(_bookAgain), findsNothing);
  });

  testWidgets('tapping it hands the host a draft built from the job', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    AppointmentPrefill? handed;
    await pump(
      tester,
      _open.copyWith(status: 'done'),
      onBookAgain: (prefill) => handed = prefill,
    );

    await tester.tap(find.text(_bookAgain));
    await tester.pumpAndSettle();

    expect(handed?.client?.id, 'c1');
    expect(handed?.title, 'Leak fix');
    expect(handed?.employeeIds, ['e1']);
    expect(handed?.durationMinutes, 60);
  });

  testWidgets('does not overflow at 260px and 2x text on a done job', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pump(tester, _open.copyWith(status: 'done'), textScale: 2);

    expect(find.text(_bookAgain), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
