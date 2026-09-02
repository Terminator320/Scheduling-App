import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
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

Widget _wrap(Widget child, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

/// The detail-sheet surfaces added 2026-09-01: the time record, the crew
/// signal line, Start job and the admin's Push back.
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
  });

  List<Override> overrides() => [
    appointmentsRepositoryProvider.overrideWithValue(appointments),
    clientsRepositoryProvider.overrideWithValue(clients),
    employeesRepositoryProvider.overrideWithValue(employees),
    photoUploadNotifierProvider.overrideWithValue(uploadNotifier),
  ];

  Future<void> pump(
    WidgetTester tester,
    AppointmentRecord appointment, {
    bool showActions = true,
  }) async {
    await tester.pumpWidget(
      _wrap(
        DetailsViewBody(
          appointment: appointment,
          showActions: showActions,
          onClose: () {},
        ),
        overrides: overrides(),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('time record', () {
    testWidgets('a finished job shows started, finished and elapsed', (
      tester,
    ) async {
      await pump(
        tester,
        _open.copyWith(
          status: 'done',
          startedAt: DateTime(2026, 5, 10, 9, 12),
          completedAt: DateTime(2026, 5, 10, 11, 40),
        ),
      );

      expect(find.textContaining('Started 9:12'), findsOneWidget);
      expect(find.textContaining('Finished 11:40'), findsOneWidget);
      expect(find.textContaining('2 h 28 min'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a job under way shows its start only', (tester) async {
      await pump(
        tester,
        _open.copyWith(
          status: 'in_progress',
          startedAt: DateTime(2026, 5, 10, 9, 12),
        ),
      );

      expect(find.textContaining('Started 9:12'), findsOneWidget);
      expect(find.textContaining('Finished'), findsNothing);
    });

    testWidgets('a job never started shows no record', (tester) async {
      await pump(tester, _open);
      expect(find.textContaining('Started'), findsNothing);
    });
  });

  group('crew signal', () {
    testWidgets('names the sender and the time on an open job', (
      tester,
    ) async {
      await pump(
        tester,
        _open.copyWith(
          crewStatus: 'runningLate',
          crewStatusAt: DateTime(2026, 5, 10, 8, 50),
          crewStatusBy: 'e1',
        ),
      );

      expect(find.textContaining('Alex is running late'), findsOneWidget);
      expect(find.textContaining('8:50'), findsOneWidget);
    });

    testWidgets('is dropped once the job is closed', (tester) async {
      await pump(
        tester,
        _open.copyWith(
          status: 'done',
          crewStatus: 'onMyWay',
          crewStatusAt: DateTime(2026, 5, 10, 8, 50),
          crewStatusBy: 'e1',
        ),
      );

      expect(find.textContaining('on the way'), findsNothing);
    });

    testWidgets('falls back to a generic name for an unknown sender', (
      tester,
    ) async {
      await pump(
        tester,
        _open.copyWith(
          crewStatus: 'onMyWay',
          crewStatusAt: DateTime(2026, 5, 10, 8, 50),
          crewStatusBy: 'someone-else',
        ),
      );

      expect(find.textContaining('Crew is on the way'), findsOneWidget);
    });
  });

  group('Start job', () {
    testWidgets('an admin sees Start on an open pending job', (tester) async {
      await pump(tester, _open);
      expect(find.text('Start job'), findsOneWidget);
    });

    testWidgets('a personal block has no arrival to record', (tester) async {
      await pump(
        tester,
        _open.copyWith(isPersonal: true, clientId: '', clientName: ''),
      );
      expect(find.text('Start job'), findsNothing);
    });

    testWidgets('a read-only surface gets no Start', (tester) async {
      await pump(tester, _open, showActions: false);
      expect(find.text('Start job'), findsNothing);
    });
  });

  group('Push back', () {
    testWidgets('an admin gets the quick action on an open timed job', (
      tester,
    ) async {
      await pump(tester, _open);
      expect(find.text('Push back'), findsOneWidget);
    });

    testWidgets('a read-only surface does not', (tester) async {
      await pump(tester, _open, showActions: false);
      expect(find.text('Push back'), findsNothing);
    });

    testWidgets('an all-day block has no clock to shift', (tester) async {
      await pump(tester, _open.copyWith(isAllDay: true));
      expect(find.text('Push back'), findsNothing);
    });

    testWidgets('a closed job has nothing to delay', (tester) async {
      await pump(tester, _open.copyWith(status: 'done'));
      expect(find.text('Push back'), findsNothing);
    });

    testWidgets('a job with no same-day offset left gets none', (
      tester,
    ) async {
      await pump(
        tester,
        _open.copyWith(
          startTime: DateTime(2026, 5, 10, 23, 50),
          endTime: DateTime(2026, 5, 11, 0, 30),
        ),
      );
      expect(find.text('Push back'), findsNothing);
    });
  });
}
