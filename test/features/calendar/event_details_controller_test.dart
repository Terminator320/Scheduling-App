import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/images/image_storage_service.dart';
import 'package:scheduling/core/images/images_providers.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/event_details_controller.dart';
import 'package:scheduling/features/calendar/data/appointment_image_upload_service.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

class _MockAppointmentsRepo extends Mock implements AppointmentsRepository {}

class _MockClientsRepo extends Mock implements ClientsRepository {}

class _MockEmployeesRepo extends Mock implements EmployeesRepository {}

class _MockUploader extends Mock implements AppointmentImageUploadService {}

class _MockStorage extends Mock implements ImageStorageService {}

const _existingClient = ClientRecord(
  id: 'c1',
  name: 'Existing Client',
  phone: '555-1111',
  address: '1 First St',
);

const _newClient = ClientRecord(
  id: 'c2',
  name: 'Different Client',
  phone: '555-2222',
  address: '2 Second St',
);

const _employeeA = EmployeeRecord(id: 'e1', name: 'Alex');
const _employeeB = EmployeeRecord(id: 'e2', name: 'Bea');

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
    registerFallbackValue(<AppointmentImage>[]);
  });

  late _MockAppointmentsRepo appointments;
  late _MockClientsRepo clients;
  late _MockEmployeesRepo employees;
  late _MockUploader uploader;
  late _MockStorage storage;
  late ProviderContainer container;

  setUp(() {
    appointments = _MockAppointmentsRepo();
    clients = _MockClientsRepo();
    employees = _MockEmployeesRepo();
    uploader = _MockUploader();
    storage = _MockStorage();

    when(() => clients.getClientById(any()))
        .thenAnswer((_) async => _existingClient);
    when(employees.watchEmployees)
        .thenAnswer((_) => Stream.value(const [_employeeA, _employeeB]));
    when(() => appointments.updateAppointment(any())).thenAnswer((_) async {});
    when(
      () => appointments.updateAppointmentStatus(
        id: any(named: 'id'),
        status: any(named: 'status'),
      ),
    ).thenAnswer((_) async {});
    when(() => appointments.deleteAppointment(any())).thenAnswer((_) async {});
    when(() => storage.deleteImages(any())).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [
        appointmentsRepositoryProvider.overrideWithValue(appointments),
        clientsRepositoryProvider.overrideWithValue(clients),
        employeesRepositoryProvider.overrideWithValue(employees),
        appointmentImageUploadProvider.overrideWithValue(uploader),
        imageStorageProvider.overrideWithValue(storage),
      ],
    );
    // Keep the provider alive across reads so autoDispose doesn't tear
    // down the seeded state between assertions.
    container.listen(
      eventDetailsControllerProvider(_appointment),
      (_, __) {},
    );
    addTearDown(container.dispose);
  });

  EventDetailsController readNotifier() =>
      container.read(eventDetailsControllerProvider(_appointment).notifier);

  EventDetailsState readState() =>
      container.read(eventDetailsControllerProvider(_appointment));

  Future<void> waitForSeed() async {
    // Allow microtasks for client + employee seeding to complete.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  group('build / seeding', () {
    test('seeds date, times, status from the appointment', () {
      final state = readState();
      expect(state.selectedDate, _appointment.startTime);
      expect(state.selectedStartTime, const TimeOfDay(hour: 9, minute: 0));
      expect(state.selectedEndTime, const TimeOfDay(hour: 10, minute: 0));
      expect(state.editingStatus, 'booked');
      expect(state.isEditing, isFalse);
    });

    test('loads client + selected employees on first build', () async {
      readNotifier(); // trigger build
      await waitForSeed();
      expect(readState().client, _existingClient);
      expect(readState().selectedEmployees, [_employeeA]);
    });
  });

  group('mode toggles', () {
    test('enterEditing flips isEditing and clears errors', () async {
      final c = readNotifier();
      await c.save(
        _appointment,
        title: '',
        address: '',
        notes: '',
        materialsNeeded: '',
      );
      expect(readState().errors, isNotEmpty);
      c.enterEditing();
      expect(readState().isEditing, isTrue);
      expect(readState().errors, isEmpty);
    });

    test('exitEditing flips isEditing back', () {
      final c = readNotifier();
      c
        ..enterEditing()
        ..exitEditing();
      expect(readState().isEditing, isFalse);
    });
  });

  group('toggleEmployee', () {
    test('toggles employees idempotently', () async {
      readNotifier();
      await waitForSeed();
      final c = readNotifier();
      c.toggleEmployee(_employeeB);
      expect(
        readState().selectedEmployees.map((e) => e.id),
        ['e1', 'e2'],
      );
      c.toggleEmployee(_employeeA);
      expect(readState().selectedEmployees.map((e) => e.id), ['e2']);
    });
  });

  group('markAsDone / cancelAppointment', () {
    test('markAsDone writes status="done" and returns true', () async {
      final ok = await readNotifier().markAsDone(_appointment);
      expect(ok, isTrue);
      verify(
        () => appointments.updateAppointmentStatus(
          id: _appointment.id!,
          status: 'done',
        ),
      ).called(1);
    });

    test('cancelAppointment writes status="cancelled" and returns true',
        () async {
      final ok = await readNotifier().cancelAppointment(_appointment);
      expect(ok, isTrue);
      verify(
        () => appointments.updateAppointmentStatus(
          id: _appointment.id!,
          status: 'cancelled',
        ),
      ).called(1);
    });

    test('markAsDone returns false and resets isSaving when repo throws',
        () async {
      when(
        () => appointments.updateAppointmentStatus(
          id: any(named: 'id'),
          status: any(named: 'status'),
        ),
      ).thenThrow(Exception('boom'));
      final ok = await readNotifier().markAsDone(_appointment);
      expect(ok, isFalse);
      expect(readState().isSaving, isFalse);
    });
  });

  group('save', () {
    test('reports validation errors and skips repo call', () async {
      readNotifier();
      await waitForSeed();
      final outcome = await readNotifier().save(
        _appointment,
        title: '',
        address: '',
        notes: '',
        materialsNeeded: '',
      );
      expect(outcome, isA<EventDetailsInvalid>());
      verifyNever(() => appointments.updateAppointment(any()));
    });

    test('writes updated appointment with edited values on success', () async {
      readNotifier();
      await waitForSeed();
      final c = readNotifier();
      c
        ..setStatus('done')
        ..selectStartTime(const TimeOfDay(hour: 14, minute: 0))
        ..selectEndTime(const TimeOfDay(hour: 16, minute: 0));

      final outcome = await c.save(
        _appointment,
        title: 'Updated title',
        address: '99 New St',
        notes: 'see notes',
        materialsNeeded: 'pliers',
      );

      expect(outcome, isA<EventDetailsSaved>());
      final saved = (outcome as EventDetailsSaved).appointment;
      expect(saved.title, 'Updated title');
      expect(saved.address, '99 New St');
      expect(saved.notes, 'see notes');
      expect(saved.materialsNeeded, 'pliers');
      expect(saved.status, 'done');
      expect(saved.startTime, DateTime(2026, 5, 10, 14));
      expect(saved.endTime, DateTime(2026, 5, 10, 16));

      verify(() => appointments.updateAppointment(any())).called(1);
    });

    test('uses freshly-picked client over the loaded one', () async {
      readNotifier();
      await waitForSeed();
      final c = readNotifier()..selectClient(_newClient);

      final outcome = await c.save(
        _appointment,
        title: 'x',
        address: 'y',
        notes: '',
        materialsNeeded: '',
      );
      final saved = (outcome as EventDetailsSaved).appointment;
      expect(saved.clientId, _newClient.id);
      expect(saved.clientName, _newClient.displayName);
      expect(saved.clientPhone, _newClient.phone);
    });

    test('does not call deleteImages when nothing was removed', () async {
      readNotifier();
      await waitForSeed();
      await readNotifier().save(
        _appointment,
        title: 'x',
        address: 'y',
        notes: '',
        materialsNeeded: '',
      );
      verifyNever(() => storage.deleteImages(any()));
    });

    test('does not run uploader when no new images are queued', () async {
      readNotifier();
      await waitForSeed();
      await readNotifier().save(
        _appointment,
        title: 'x',
        address: 'y',
        notes: '',
        materialsNeeded: '',
      );
      verifyNever(
        () => uploader.uploadInBackground(
          appointmentId: any(named: 'appointmentId'),
          newImages: any(named: 'newImages'),
          existingImages: any(named: 'existingImages'),
          toDelete: any(named: 'toDelete'),
        ),
      );
    });

    test('returns EventDetailsFailed and resets isSaving when repo throws',
        () async {
      when(() => appointments.updateAppointment(any()))
          .thenThrow(Exception('boom'));
      readNotifier();
      await waitForSeed();
      final outcome = await readNotifier().save(
        _appointment,
        title: 'x',
        address: 'y',
        notes: '',
        materialsNeeded: '',
      );
      expect(outcome, isA<EventDetailsFailed>());
      expect(readState().isSaving, isFalse);
    });
  });

  group('deleteAppointment', () {
    test('returns true on repo success and calls the repo with the doc id',
        () async {
      final ok = await readNotifier().deleteAppointment(_appointment);
      expect(ok, isTrue);
      verify(() => appointments.deleteAppointment('appt-1')).called(1);
    });

    test('returns false and resets isSaving when repo throws', () async {
      when(() => appointments.deleteAppointment(any()))
          .thenThrow(Exception('boom'));
      final ok = await readNotifier().deleteAppointment(_appointment);
      expect(ok, isFalse);
      expect(readState().isSaving, isFalse);
    });
  });
}
