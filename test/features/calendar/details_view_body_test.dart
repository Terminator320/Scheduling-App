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

final _appointment = AppointmentRecord(
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
  status: 'booked',
);

final _appointmentWithNotes = AppointmentRecord(
  id: 'appt-2',
  title: 'Leak fix',
  startTime: DateTime(2026, 5, 10, 9),
  endTime: DateTime(2026, 5, 10, 10),
  clientId: 'c1',
  clientName: 'Existing Client',
  clientPhone: '555-1111',
  address: '1 First St',
  employeeIds: const ['e1'],
  employeeNames: const ['Alex'],
  notes: 'Gate code 4821',
  status: 'booked',
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

List<Override> _overrides(
  AppointmentsRepository appointments,
  ClientsRepository clients,
  EmployeesRepository employees,
  PhotoUploadNotifier uploadNotifier,
) => [
  appointmentsRepositoryProvider.overrideWithValue(appointments),
  clientsRepositoryProvider.overrideWithValue(clients),
  employeesRepositoryProvider.overrideWithValue(employees),
  photoUploadNotifierProvider.overrideWithValue(uploadNotifier),
];

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

  testWidgets(
    'photo-failure banner appears when notifier reports a failure for this id',
    (tester) async {
      uploadNotifier.reportFailure('appt-1', failedCount: 2);

      await tester.pumpWidget(
        _wrap(
          DetailsViewBody(
            appointment: _appointment,
            showActions: true,
            onClose: () {},
          ),
          overrides: [
            appointmentsRepositoryProvider.overrideWithValue(appointments),
            clientsRepositoryProvider.overrideWithValue(clients),
            employeesRepositoryProvider.overrideWithValue(employees),
            photoUploadNotifierProvider.overrideWithValue(uploadNotifier),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('failed to upload'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows the client phone number and address', (tester) async {
    await tester.pumpWidget(
      _wrap(
        DetailsViewBody(
          appointment: _appointment,
          showActions: true,
          onClose: () {},
        ),
        overrides: [
          appointmentsRepositoryProvider.overrideWithValue(appointments),
          clientsRepositoryProvider.overrideWithValue(clients),
          employeesRepositoryProvider.overrideWithValue(employees),
          photoUploadNotifierProvider.overrideWithValue(uploadNotifier),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Existing Client'), findsOneWidget);
    expect(find.text('555-1111'), findsOneWidget);
    expect(find.text('1 First St'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'no failure banner when notifier reports a failure for a different id',
    (tester) async {
      uploadNotifier.reportFailure('some-other-appt', failedCount: 5);

      await tester.pumpWidget(
        _wrap(
          DetailsViewBody(
            appointment: _appointment,
            showActions: true,
            onClose: () {},
          ),
          overrides: [
            appointmentsRepositoryProvider.overrideWithValue(appointments),
            clientsRepositoryProvider.overrideWithValue(clients),
            employeesRepositoryProvider.overrideWithValue(employees),
            photoUploadNotifierProvider.overrideWithValue(uploadNotifier),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('failed to upload'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renders the mono when-line in place of the icon rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        DetailsViewBody(
          appointment: _appointment,
          showActions: true,
          onClose: () {},
        ),
        overrides: _overrides(appointments, clients, employees, uploadNotifier),
      ),
    );
    await tester.pumpAndSettle();

    // "SUN 10 MAY · 9:00 AM – 10:00 AM" — one mono line, middot and en-dash.
    expect(find.textContaining('MAY'), findsOneWidget);
    expect(find.textContaining(' · '), findsOneWidget);
    expect(find.textContaining('–'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('omits the notes row entirely when there are no notes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        DetailsViewBody(
          appointment: _appointment,
          showActions: true,
          onClose: () {},
        ),
        overrides: _overrides(appointments, clients, employees, uploadNotifier),
      ),
    );
    await tester.pumpAndSettle();

    // Read-only bodies drop empty sections rather than showing a placeholder.
    expect(find.text('NOTES'), findsNothing);
  });

  testWidgets('shows the notes row inside the panel when notes exist', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        DetailsViewBody(
          appointment: _appointmentWithNotes,
          showActions: true,
          onClose: () {},
        ),
        overrides: _overrides(appointments, clients, employees, uploadNotifier),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NOTES'), findsOneWidget);
    expect(find.text('Gate code 4821'), findsOneWidget);
  });
}
