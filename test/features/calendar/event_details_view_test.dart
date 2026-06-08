import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/widgets/views/event_details_view.dart';
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

void main() {
  setUpAll(() {
    registerFallbackValue(
      AppointmentRecord(
        id: '_',
        startTime: DateTime(2026),
        endTime: DateTime(2026),
      ),
    );
  });

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
    when(() => appointments.updateAppointment(any())).thenAnswer((_) async {});
  });

  // Tall viewport so the whole lazily-built edit form lays out without scrolling.
  Future<void> pumpDetails(
    WidgetTester tester, {
    void Function(Object? result)? onClose,
  }) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appointmentsRepositoryProvider.overrideWithValue(appointments),
          clientsRepositoryProvider.overrideWithValue(clients),
          employeesRepositoryProvider.overrideWithValue(employees),
          photoUploadNotifierProvider.overrideWithValue(uploadNotifier),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: EventDetailsView(appointment: _appointment, onClose: onClose),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('view mode shows details with no editable text fields', (
    tester,
  ) async {
    await pumpDetails(tester);

    expect(find.text('Leak fix'), findsOneWidget);
    // View mode never builds the edit controllers/fields.
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping Edit builds the edit form prefilled from the '
      'appointment', (tester) async {
    await pumpDetails(tester);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    // The lazily-created title controller is seeded from the appointment.
    expect(find.widgetWithText(TextField, 'Leak fix'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing the title and saving writes the updated appointment', (
    tester,
  ) async {
    Object? closeResult;
    var closed = false;
    await pumpDetails(
      tester,
      onClose: (result) {
        closed = true;
        closeResult = result;
      },
    );

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Leak fix'),
      'Updated title',
    );
    // Let SheetFocusScroll's 280 ms focus-scroll timer fire.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final saved =
        verify(
              () => appointments.updateAppointment(captureAny()),
            ).captured.single
            as AppointmentRecord;
    expect(saved.title, 'Updated title');
    expect(closed, isTrue);
    expect(closeResult, isA<AppointmentRecord>());
    expect(tester.takeException(), isNull);
  });
}
