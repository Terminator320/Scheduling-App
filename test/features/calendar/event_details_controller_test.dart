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
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
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
    registerFallbackValue(<AppointmentRecord>[]);
    registerFallbackValue(<String>[]);
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

    when(
      () => clients.getClientById(any()),
    ).thenAnswer((_) async => _existingClient);
    when(
      employees.watchEmployees,
    ).thenAnswer((_) => Stream.value(const [_employeeA, _employeeB]));
    when(() => appointments.updateAppointment(any())).thenAnswer((_) async {});
    when(
      () => appointments.updateAppointmentStatus(
        id: any(named: 'id'),
        status: any(named: 'status'),
      ),
    ).thenAnswer((_) async {});
    when(() => appointments.deleteAppointment(any())).thenAnswer((_) async {});
    when(() => storage.deleteImages(any())).thenAnswer((_) async {});

    container =
        ProviderContainer(
            overrides: [
              appointmentsRepositoryProvider.overrideWithValue(appointments),
              clientsRepositoryProvider.overrideWithValue(clients),
              employeesRepositoryProvider.overrideWithValue(employees),
              appointmentImageUploadProvider.overrideWithValue(uploader),
              imageStorageProvider.overrideWithValue(storage),
            ],
          )
          // Keep the provider alive across reads so autoDispose doesn't tear
          // down the seeded state between assertions.
          ..listen(eventDetailsControllerProvider(_appointment), (_, _) {});
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
      readNotifier()
        ..enterEditing()
        ..exitEditing();
      expect(readState().isEditing, isFalse);
    });
  });

  group('toggleEmployee', () {
    test('toggles employees idempotently', () async {
      readNotifier();
      await waitForSeed();
      final c = readNotifier()..toggleEmployee(_employeeB);
      expect(readState().selectedEmployees.map((e) => e.id), ['e1', 'e2']);
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

    test(
      'cancelAppointment writes status="cancelled" and returns true',
      () async {
        final ok = await readNotifier().cancelAppointment(_appointment);
        expect(ok, isTrue);
        verify(
          () => appointments.updateAppointmentStatus(
            id: _appointment.id!,
            status: 'cancelled',
          ),
        ).called(1);
      },
    );

    test(
      'markAsDone returns false and resets isSaving when repo throws',
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
      },
    );
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
      final c = readNotifier()
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

    test('preserves a disabled assignee not in the active list (B1)', () async {
      final withDisabled = _appointment.copyWith(
        employeeIds: const ['e1', 'e9'],
        employeeNames: const ['Alex', 'Zoe'],
      );
      container.listen(
        eventDetailsControllerProvider(withDisabled),
        (_, _) {},
      );
      final c = container.read(
        eventDetailsControllerProvider(withDisabled).notifier,
      );
      await waitForSeed();
      // Only the active assignee is resolvable into the picker.
      expect(
        container
            .read(eventDetailsControllerProvider(withDisabled))
            .selectedEmployees
            .map((e) => e.id),
        ['e1'],
      );

      final outcome = await c.save(
        withDisabled,
        title: 'x',
        address: 'y',
        notes: '',
        materialsNeeded: '',
      );

      // e9 (disabled, never shown in the picker) is retained, not dropped.
      final saved = (outcome as EventDetailsSaved).appointment;
      expect(saved.employeeIds, ['e1', 'e9']);
      expect(saved.employeeNames, ['Alex', 'Zoe']);
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

    test('reports clientRequired after the client is cleared', () async {
      readNotifier();
      await waitForSeed();
      final c = readNotifier()..clearClient();

      final outcome = await c.save(
        _appointment,
        title: 'x',
        address: 'y',
        notes: '',
        materialsNeeded: '',
      );

      expect(outcome, isA<EventDetailsInvalid>());
      expect(readState().errors, contains('client'));
      verifyNever(() => appointments.updateAppointment(any()));
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
        ),
      );
    });

    test('rewrites the series when the repeat rule changes', () async {
      var nextId = 0;
      when(appointments.newDocId).thenAnswer((_) => 'copy-${++nextId}');
      when(
        () => appointments.rewriteSeries(
          updated: any(named: 'updated'),
          deleteIds: any(named: 'deleteIds'),
          copies: any(named: 'copies'),
        ),
      ).thenAnswer((_) async {});

      readNotifier();
      await waitForSeed();
      final c = readNotifier()..selectRepeat(RepeatInterval.sixMonths);

      final outcome = await c.save(
        _appointment,
        title: 'Furnace check',
        address: '99 New St',
        notes: '',
        materialsNeeded: '',
      );

      expect(outcome, isA<EventDetailsSaved>());
      // 60-month horizon / 6 = 10 future visits, booked across five years.
      expect((outcome as EventDetailsSaved).futureBookings, 10);
      expect(outcome.appointment.repeat, RepeatInterval.sixMonths);
      // A doc without a series gets one keyed by its own id.
      expect(outcome.appointment.seriesId, 'appt-1');

      final captured = verify(
        () => appointments.rewriteSeries(
          updated: captureAny(named: 'updated'),
          deleteIds: captureAny(named: 'deleteIds'),
          copies: captureAny(named: 'copies'),
        ),
      ).captured;
      expect((captured[1] as List).cast<String>(), isEmpty);
      final copies = (captured[2] as List).cast<AppointmentRecord>();
      expect(copies, hasLength(10));
      expect(copies.first.id, 'copy-1');
      expect(copies.last.id, 'copy-10');
      expect(copies[0].startTime, DateTime(2026, 11, 10, 9));
      expect(copies[1].startTime, DateTime(2027, 5, 10, 9));
      expect(copies.last.startTime, DateTime(2031, 5, 10, 9));
      expect(copies.every((a) => a.status == 'pending'), isTrue);
      expect(copies.every((a) => a.pictures.isEmpty), isTrue);
      expect(copies.every((a) => a.seriesId == 'appt-1'), isTrue);

      // The rule is now the baseline — a second save is a plain update.
      final second = await c.save(
        _appointment,
        title: 'Furnace check',
        address: '99 New St',
        notes: '',
        materialsNeeded: '',
      );
      expect((second as EventDetailsSaved).futureBookings, 0);
      verify(() => appointments.updateAppointment(any())).called(1);
    });

    test('deletes the old future visits when replacing a series', () async {
      var nextId = 0;
      when(appointments.newDocId).thenAnswer((_) => 'copy-${++nextId}');
      when(
        () => appointments.rewriteSeries(
          updated: any(named: 'updated'),
          deleteIds: any(named: 'deleteIds'),
          copies: any(named: 'copies'),
        ),
      ).thenAnswer((_) async {});

      final repeating = _appointment.copyWith(
        repeat: RepeatInterval.fourMonths,
        seriesId: 'series-1',
      );
      when(() => appointments.getSeries('series-1')).thenAnswer(
        (_) async => [
          repeating,
          repeating.copyWith(id: 'old-1', startTime: DateTime(2026, 9, 10, 9)),
          repeating.copyWith(id: 'old-2', startTime: DateTime(2027, 1, 10, 9)),
          repeating.copyWith(
            id: 'old-done',
            startTime: DateTime(2027, 5, 10, 9),
            status: 'done',
          ),
        ],
      );

      container.listen(eventDetailsControllerProvider(repeating), (_, _) {});
      final c = container.read(
        eventDetailsControllerProvider(repeating).notifier,
      );
      await waitForSeed();
      c.selectRepeat(RepeatInterval.oneYear);

      final outcome = await c.save(
        repeating,
        title: 'x',
        address: 'y',
        notes: '',
        materialsNeeded: '',
      );

      // 60-month horizon / 12 = 5 future visits across five years.
      expect((outcome as EventDetailsSaved).futureBookings, 5);
      expect(outcome.removedBookings, 2);

      final captured = verify(
        () => appointments.rewriteSeries(
          updated: captureAny(named: 'updated'),
          deleteIds: captureAny(named: 'deleteIds'),
          copies: captureAny(named: 'copies'),
        ),
      ).captured;
      // The edited doc itself and the done visit are preserved.
      expect((captured[1] as List).cast<String>(), ['old-1', 'old-2']);
      final copies = (captured[2] as List).cast<AppointmentRecord>();
      expect(copies, hasLength(5));
      expect(copies.first.startTime, DateTime(2027, 5, 10, 9));
      expect(copies.last.startTime, DateTime(2031, 5, 10, 9));
      expect(copies.every((a) => a.seriesId == 'series-1'), isTrue);
    });

    test(
      'applyToSeries propagates details + time of day to future visits, '
      'keeping each visit date',
      () async {
        when(
          () => appointments.updateAppointments(any()),
        ).thenAnswer((_) async {});

        final repeating = _appointment.copyWith(
          id: 'series-1',
          seriesId: 'series-1',
          repeat: RepeatInterval.sixMonths,
        );
        when(() => appointments.getSeries('series-1')).thenAnswer(
          (_) async => [
            repeating,
            repeating.copyWith(
              id: 'past',
              startTime: DateTime(2025, 11, 10, 9),
            ),
            repeating.copyWith(
              id: 'fut-1',
              startTime: DateTime(2026, 11, 10, 9),
              status: 'confirmed',
            ),
            repeating.copyWith(
              id: 'fut-2',
              startTime: DateTime(2027, 5, 10, 9),
              status: 'in_progress',
            ),
            repeating.copyWith(
              id: 'fut-done',
              startTime: DateTime(2027, 11, 10, 9),
              status: 'done',
            ),
          ],
        );

        container.listen(eventDetailsControllerProvider(repeating), (_, _) {});
        final c = container.read(
          eventDetailsControllerProvider(repeating).notifier,
        );
        await waitForSeed();
        // Move the time of day; the repeat rule is unchanged.
        c
          ..selectStartTime(const TimeOfDay(hour: 8, minute: 0))
          ..selectEndTime(const TimeOfDay(hour: 9, minute: 0));

        final outcome = await c.save(
          repeating,
          title: 'New title',
          address: 'New address',
          notes: 'n',
          materialsNeeded: 'm',
          applyToSeries: true,
        );

        // Two future non-terminal siblings updated; past and done preserved.
        expect((outcome as EventDetailsSaved).updatedSiblings, 2);

        final captured = verify(
          () => appointments.updateAppointments(captureAny()),
        ).captured.single;
        final batch = (captured as List).cast<AppointmentRecord>();
        // This visit plus the two future siblings, in order.
        expect(batch.map((a) => a.id), ['series-1', 'fut-1', 'fut-2']);
        expect(batch.every((a) => a.title == 'New title'), isTrue);
        expect(batch.every((a) => a.address == 'New address'), isTrue);
        expect(batch.every((a) => a.seriesId == 'series-1'), isTrue);
        // Status stays per-visit — never propagated across the series.
        expect(batch[1].status, 'confirmed');
        expect(batch[2].status, 'in_progress');
        // Each sibling keeps its own date but takes the new time of day.
        expect(batch[1].startTime, DateTime(2026, 11, 10, 8));
        expect(batch[1].endTime, DateTime(2026, 11, 10, 9));
        expect(batch[2].startTime, DateTime(2027, 5, 10, 8));
        expect(batch[2].endTime, DateTime(2027, 5, 10, 9));

        verifyNever(
          () => appointments.rewriteSeries(
            updated: any(named: 'updated'),
            deleteIds: any(named: 'deleteIds'),
            copies: any(named: 'copies'),
          ),
        );
      },
    );

    test('applyToSeries false edits only this visit', () async {
      final repeating = _appointment.copyWith(
        id: 'series-1',
        seriesId: 'series-1',
        repeat: RepeatInterval.sixMonths,
      );
      container.listen(eventDetailsControllerProvider(repeating), (_, _) {});
      final c = container.read(
        eventDetailsControllerProvider(repeating).notifier,
      );
      await waitForSeed();

      final outcome = await c.save(
        repeating,
        title: 'New title',
        address: 'New address',
        notes: '',
        materialsNeeded: '',
      );

      expect((outcome as EventDetailsSaved).updatedSiblings, 0);
      verify(() => appointments.updateAppointment(any())).called(1);
      verifyNever(() => appointments.getSeries(any()));
      verifyNever(() => appointments.updateAppointments(any()));
    });

    test('seeds the stored repeat and does not re-book it unchanged', () async {
      final repeating = _appointment.copyWith(
        repeat: RepeatInterval.sixMonths,
      );
      container.listen(eventDetailsControllerProvider(repeating), (_, _) {});
      final c = container.read(
        eventDetailsControllerProvider(repeating).notifier,
      );
      await waitForSeed();
      expect(
        container.read(eventDetailsControllerProvider(repeating)).repeat,
        RepeatInterval.sixMonths,
      );

      final outcome = await c.save(
        repeating,
        title: 'x',
        address: 'y',
        notes: '',
        materialsNeeded: '',
      );

      expect((outcome as EventDetailsSaved).futureBookings, 0);
      // The unchanged rule still persists on the saved doc.
      expect(outcome.appointment.repeat, RepeatInterval.sixMonths);
      verifyNever(
        () => appointments.rewriteSeries(
          updated: any(named: 'updated'),
          deleteIds: any(named: 'deleteIds'),
          copies: any(named: 'copies'),
        ),
      );
    });

    test('does not book copies when repeat stays none', () async {
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
        () => appointments.rewriteSeries(
          updated: any(named: 'updated'),
          deleteIds: any(named: 'deleteIds'),
          copies: any(named: 'copies'),
        ),
      );
    });

    test(
      'returns EventDetailsFailed and resets isSaving when repo throws',
      () async {
        when(
          () => appointments.updateAppointment(any()),
        ).thenThrow(Exception('boom'));
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
      },
    );
  });

  group('deleteAppointment', () {
    test(
      'returns null on repo success and calls the repo with the doc id',
      () async {
        final error = await readNotifier().deleteAppointment(_appointment);
        expect(error, isNull);
        verify(() => appointments.deleteAppointment('appt-1')).called(1);
      },
    );

    test('returns the error and resets isSaving when repo throws', () async {
      when(
        () => appointments.deleteAppointment(any()),
      ).thenThrow(Exception('boom'));
      final error = await readNotifier().deleteAppointment(_appointment);
      expect(error, isNotNull);
      expect(readState().isSaving, isFalse);
    });

    test('includeFuture deletes the series future visits too', () async {
      when(
        () => appointments.deleteAppointments(any()),
      ).thenAnswer((_) async {});
      final repeating = _appointment.copyWith(
        repeat: RepeatInterval.fourMonths,
        seriesId: 'series-1',
      );
      when(() => appointments.getSeries('series-1')).thenAnswer(
        (_) async => [
          repeating,
          repeating.copyWith(id: 'past-1', startTime: DateTime(2026, 1, 10, 9)),
          repeating.copyWith(id: 'old-1', startTime: DateTime(2026, 9, 10, 9)),
          repeating.copyWith(
            id: 'old-done',
            startTime: DateTime(2027, 1, 10, 9),
            status: 'done',
          ),
        ],
      );
      container.listen(eventDetailsControllerProvider(repeating), (_, _) {});
      final c = container.read(
        eventDetailsControllerProvider(repeating).notifier,
      );

      final error = await c.deleteAppointment(repeating, includeFuture: true);

      expect(error, isNull);
      final captured = verify(
        () => appointments.deleteAppointments(captureAny()),
      ).captured.single;
      // Past and done visits stay; itself plus the future pending one go.
      expect((captured as List).cast<String>(), ['appt-1', 'old-1']);
      verifyNever(() => appointments.deleteAppointment(any()));
    });

    test('includeFuture without a series is a single delete', () async {
      final error = await readNotifier().deleteAppointment(
        _appointment,
        includeFuture: true,
      );
      expect(error, isNull);
      verify(() => appointments.deleteAppointment('appt-1')).called(1);
    });
  });
}
