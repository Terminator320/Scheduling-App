import 'dart:async';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/application/add_event_controller.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/data/appointment_image_upload_service.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/clients/application/clients_providers.dart';
import 'package:scheduling/features/clients/domain/clients_repository.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

class _MockAppointmentsRepo extends Mock implements AppointmentsRepository {}

class _MockClientsRepo extends Mock implements ClientsRepository {}

class _MockUploader extends Mock implements AppointmentImageUploadService {}

const _aClient = ClientRecord(
  id: 'c1',
  name: 'Jane Doe',
  phone: '555-0001',
  address: '123 Main St',
);

const _employeeA = EmployeeRecord(id: 'e1', name: 'Alex');
const _employeeB = EmployeeRecord(id: 'e2', name: 'Bea');

void main() {
  setUpAll(() {
    registerFallbackValue(
      AppointmentRecord(
        id: '_',
        startTime: DateTime(2026),
        endTime: DateTime(2026),
      ),
    );
    registerFallbackValue(<EmployeeRecord>[]);
    registerFallbackValue(DateTime(2026));
    registerFallbackValue(<AppointmentImage>[]);
    registerFallbackValue(<AppointmentRecord>[]);
  });

  late _MockAppointmentsRepo appointments;
  late _MockClientsRepo clients;
  late _MockUploader uploader;
  late ProviderContainer container;

  setUp(() {
    appointments = _MockAppointmentsRepo();
    clients = _MockClientsRepo();
    uploader = _MockUploader();

    when(appointments.newDocId).thenReturn('appt-1');
    when(() => appointments.addAppointment(any())).thenAnswer((_) async {});
    when(
      () => appointments.findBusyEmployees(
        candidates: any(named: 'candidates'),
        start: any(named: 'start'),
        end: any(named: 'end'),
      ),
    ).thenAnswer((_) async => const []);

    container = ProviderContainer(
      overrides: [
        appointmentsRepositoryProvider.overrideWithValue(appointments),
        clientsRepositoryProvider.overrideWithValue(clients),
        appointmentImageUploadProvider.overrideWithValue(uploader),
      ],
    );
    addTearDown(container.dispose);
  });

  AddEventController readNotifier([DateTime? initialDate]) =>
      container.read(addEventControllerProvider(initialDate).notifier);

  AddEventState readState([DateTime? initialDate]) =>
      container.read(addEventControllerProvider(initialDate));

  AddEventState fillValid(AddEventController c, {DateTime? initialDate}) {
    c
      ..selectDate(DateTime(2026, 5, 10))
      ..selectStartTime(const TimeOfDay(hour: 9, minute: 0))
      ..selectEndTime(const TimeOfDay(hour: 10, minute: 0))
      ..selectClient(_aClient)
      ..toggleEmployee(_employeeA);
    return readState(initialDate);
  }

  group('selectStartTime', () {
    test('auto-advances end by one hour when end was not picked manually', () {
      readNotifier().selectStartTime(const TimeOfDay(hour: 9, minute: 0));
      expect(readState().selectedEndTime, const TimeOfDay(hour: 10, minute: 0));
    });

    test('does not overwrite end after a manual end pick', () {
      readNotifier()
        ..selectStartTime(const TimeOfDay(hour: 9, minute: 0))
        ..selectEndTime(const TimeOfDay(hour: 14, minute: 0))
        ..selectStartTime(const TimeOfDay(hour: 11, minute: 0));
      expect(readState().selectedEndTime, const TimeOfDay(hour: 14, minute: 0));
    });
  });

  group('toggleEmployee', () {
    test('adds employees and removes them idempotently', () {
      final c = readNotifier()
        ..toggleEmployee(_employeeA)
        ..toggleEmployee(_employeeB);
      expect(readState().selectedEmployees, [_employeeA, _employeeB]);

      c.toggleEmployee(_employeeA);
      expect(readState().selectedEmployees, [_employeeB]);
    });
  });

  group('searchClients', () {
    test('clears results without hitting the repo on empty query', () async {
      final c = readNotifier();
      await c.searchClients('');
      verifyNever(() => clients.searchClients(any()));
      expect(readState().clientResults, isEmpty);
      expect(readState().isSearchingClient, isFalse);
    });

    test('populates results from the repo on non-empty query', () async {
      when(
        () => clients.searchClients('jan'),
      ).thenAnswer((_) async => const [_aClient]);
      final c = readNotifier();
      await c.searchClients('jan');
      expect(readState().clientResults, [_aClient]);
      expect(readState().isSearchingClient, isFalse);
    });

    test('a slow older search never overwrites a newer one', () async {
      const bClient = ClientRecord(
        id: 'c2',
        name: 'Marc Roy',
        phone: '555-0002',
        address: '9 Oak St',
      );
      final slow = Completer<List<ClientRecord>>();
      when(() => clients.searchClients('ma')).thenAnswer((_) => slow.future);
      when(
        () => clients.searchClients('mar'),
      ).thenAnswer((_) async => const [bClient]);

      final c = readNotifier();
      final first = c.searchClients('ma');
      await c.searchClients('mar');
      expect(readState().clientResults, [bClient]);

      // The older read resolving late must be discarded, not published.
      slow.complete(const [_aClient]);
      await first;
      expect(readState().clientResults, [bClient]);
      expect(readState().isSearchingClient, isFalse);
    });
  });

  group('submit', () {
    test(
      'returns AddEventInvalid and populates errors on empty form',
      () async {
        final outcome = await readNotifier().submit(
          title: '',
          address: '',
          notes: '',
          materialsNeeded: '',
        );
        expect(outcome, isA<AddEventInvalid>());
        expect(
          readState().errors.keys,
          containsAll(['title', 'client', 'employees']),
        );
        verifyNever(() => appointments.addAppointment(any()));
      },
    );

    test(
      'returns AddEventBusyEmployees when busy check finds conflicts',
      () async {
        when(
          () => appointments.findBusyEmployees(
            candidates: any(named: 'candidates'),
            start: any(named: 'start'),
            end: any(named: 'end'),
          ),
        ).thenAnswer((_) async => const [_employeeA]);

        final c = readNotifier();
        fillValid(c);

        final outcome = await c.submit(
          title: 'Leak fix',
          address: '999 Maple',
          notes: '',
          materialsNeeded: '',
        );

        expect(outcome, isA<AddEventBusyEmployees>());
        verifyNever(() => appointments.addAppointment(any()));
      },
    );

    test('writes appointment and kicks off photo upload on success', () async {
      final c = readNotifier();
      fillValid(c);

      final outcome = await c.submit(
        title: '  Leak fix  ',
        address: ' 999 Maple ',
        notes: ' bring towels ',
        materialsNeeded: ' wrench ',
      );

      expect(outcome, isA<AddEventSubmitted>());
      final saved = (outcome as AddEventSubmitted).appointment;
      expect(saved.id, 'appt-1');
      expect(saved.title, 'Leak fix');
      expect(saved.address, '999 Maple');
      expect(saved.notes, 'bring towels');
      expect(saved.materialsNeeded, 'wrench');
      expect(saved.clientId, _aClient.id);
      expect(saved.employeeIds, [_employeeA.id]);
      expect(saved.status, 'pending');

      verify(() => appointments.addAppointment(any())).called(1);
      // No images selected — uploader should not run.
      verifyNever(
        () => uploader.uploadInBackground(
          appointmentId: any(named: 'appointmentId'),
          newImages: any(named: 'newImages'),
        ),
      );
    });

    test('skips busy check on forceBusy and writes the appointment', () async {
      when(
        () => appointments.findBusyEmployees(
          candidates: any(named: 'candidates'),
          start: any(named: 'start'),
          end: any(named: 'end'),
        ),
      ).thenAnswer((_) async => const [_employeeA]);

      final c = readNotifier();
      fillValid(c);

      final outcome = await c.submit(
        title: 'Leak fix',
        address: '999 Maple',
        notes: '',
        materialsNeeded: '',
        forceBusy: true,
      );

      expect(outcome, isA<AddEventSubmitted>());
      verifyNever(
        () => appointments.findBusyEmployees(
          candidates: any(named: 'candidates'),
          start: any(named: 'start'),
          end: any(named: 'end'),
        ),
      );
      verify(() => appointments.addAppointment(any())).called(1);
    });

    test('books repeat occurrences atomically with the appointment', () async {
      var nextId = 0;
      when(appointments.newDocId).thenAnswer((_) => 'appt-${++nextId}');
      when(() => appointments.addAppointments(any())).thenAnswer((_) async {});

      final c = readNotifier();
      fillValid(c);
      c.selectRepeat(RepeatInterval.fourMonths);

      final outcome = await c.submit(
        title: 'Furnace check',
        address: '999 Maple',
        notes: '',
        materialsNeeded: '',
      );

      expect(outcome, isA<AddEventSubmitted>());
      // 60-month horizon / 4 = 15 future visits, booked across five years.
      expect((outcome as AddEventSubmitted).futureBookings, 15);

      final captured = verify(
        () => appointments.addAppointments(captureAny()),
      ).captured.single;
      final series = (captured as List).cast<AppointmentRecord>();
      expect(series, hasLength(16));
      expect(series.map((a) => a.id).toSet(), hasLength(16));
      expect(series[1].startTime, DateTime(2026, 9, 10, 9));
      expect(series[3].startTime, DateTime(2027, 5, 10, 9));
      expect(series[3].endTime, DateTime(2027, 5, 10, 10));
      expect(series.last.startTime, DateTime(2031, 5, 10, 9));
      expect(series.every((a) => a.status == 'pending'), isTrue);
      // Every visit in the series stores the rule, like a real calendar.
      expect(
        series.every((a) => a.repeat == RepeatInterval.fourMonths),
        isTrue,
      );
      // …and shares the series key (the first visit's doc id).
      expect(series.every((a) => a.seriesId == 'appt-1'), isTrue);
      verifyNever(() => appointments.addAppointment(any()));
    });

    test(
      'returns AddEventFailed and resets isSubmitting when repo throws',
      () async {
        when(
          () => appointments.addAppointment(any()),
        ).thenThrow(Exception('boom'));

        final c = readNotifier();
        fillValid(c);

        final outcome = await c.submit(
          title: 'Leak fix',
          address: '999 Maple',
          notes: '',
          materialsNeeded: '',
        );

        expect(outcome, isA<AddEventFailed>());
        expect(readState().isSubmitting, isFalse);
      },
    );
  });
}
