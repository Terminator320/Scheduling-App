import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
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
        // Online by default here — the offline test below builds its own.
        isOfflineProvider.overrideWithValue(false),
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

  group('end date', () {
    test('mirrors the start date until it is touched', () {
      final c = readNotifier()..selectDate(DateTime(2026, 8));
      expect(readState().endDate, DateTime(2026, 8));

      c.selectDate(DateTime(2026, 8, 4));
      expect(readState().endDate, DateTime(2026, 8, 4));
    });

    test(
      'once touched, moving the start shifts the end by the same days',
      () {
        final c = readNotifier()
          ..selectDate(DateTime(2026, 8))
          ..selectEndDate(DateTime(2026, 8, 5));
        expect(readState().endDateTouched, isTrue);

        c.selectDate(DateTime(2026, 8, 3));
        expect(readState().endDate, DateTime(2026, 8, 7));
      },
    );

    test(
      'a start date moved past a touched end date drags the end along',
      () {
        readNotifier()
          ..selectDate(DateTime(2026, 8))
          ..selectEndDate(DateTime(2026, 8, 2))
          ..selectDate(DateTime(2026, 8, 10));
        expect(readState().endDate, DateTime(2026, 8, 11));
      },
    );

    test('selectEndDate clears any endDate error', () async {
      final c = readNotifier()
        ..selectDate(DateTime(2026, 8, 5))
        // Before the start date, so validate() flags it once submit() runs.
        ..selectEndDate(DateTime(2026, 8));
      await c.submit(title: '', address: '', notes: '', materialsNeeded: '');
      expect(readState().errors.containsKey('endDate'), isTrue);

      c.selectEndDate(DateTime(2026, 8, 10));
      expect(readState().errors.containsKey('endDate'), isFalse);
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

  group('selectClient', () {
    test('picking a normal client leaves the address in client mode', () {
      readNotifier().selectClient(_aClient);
      expect(readState().selectedClient, _aClient);
      expect(readState().clientResults, isEmpty);
      // _aClient has a real address, so the custom-address toggle stays off.
      expect(readState().useCustomAddress, isFalse);
    });

    test('picking a no-fixed-address client seeds the custom address on', () {
      const nomad = ClientRecord(
        id: 'c9',
        name: 'Nomad',
        phone: '555-0009',
        noFixedAddress: true,
      );
      readNotifier().selectClient(nomad);
      expect(readState().useCustomAddress, isTrue);
    });

    test('picking a client with a blank address seeds custom address on', () {
      const blank = ClientRecord(
        id: 'c8',
        name: 'Blank',
        phone: '555-0008',
        address: '   ',
      );
      readNotifier().selectClient(blank);
      expect(readState().useCustomAddress, isTrue);
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

    test(
      'a PERSONAL save never returns the busy outcome — the clash alert '
      'handles it after the write',
      () async {
        // Both would fire otherwise, giving two dialogs about the same clash
        // back to back. The alert is strictly more useful: it names the jobs
        // and offers a swap on each, where this prompt only names the person.
        when(
          () => appointments.findBusyEmployees(
            candidates: any(named: 'candidates'),
            start: any(named: 'start'),
            end: any(named: 'end'),
          ),
        ).thenAnswer((_) async => const [_employeeA]);

        final c = readNotifier();
        fillValid(c);
        c.setPersonal(value: true);

        final outcome = await c.submit(
          title: 'Dentist',
          address: '',
          notes: '',
          materialsNeeded: '',
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
      // No images were selected, so the uploader should never run.
      verifyNever(
        () => uploader.uploadInBackground(
          appointmentId: any(named: 'appointmentId'),
          newImages: any(named: 'newImages'),
        ),
      );
    });

    test('a personal job saves with no client, all day', () async {
      final c = readNotifier()
        ..selectDate(DateTime(2026, 5, 10))
        ..selectClient(_aClient)
        ..setPersonal(value: true)
        ..toggleEmployee(_employeeA);

      // No times were picked, so the block runs the whole day.
      expect(readState().isAllDay, isTrue);
      expect(readState().selectedClient, isNull);

      final outcome = await c.submit(
        title: 'Dentist',
        // The address field stays on screen for a personal job, so what it
        // holds is saved rather than dropped.
        address: '999 Maple',
        notes: '',
        materialsNeeded: '',
      );

      expect(outcome, isA<AddEventSubmitted>());
      final saved = (outcome as AddEventSubmitted).appointment;
      expect(saved.isPersonal, isTrue);
      expect(saved.isAllDay, isTrue);
      expect(saved.clientId, isEmpty);
      expect(saved.clientName, isEmpty);
      expect(saved.address, '999 Maple');
      expect(saved.startTime, DateTime(2026, 5, 10));
      expect(saved.endTime, DateTime(2026, 5, 10, 23, 59));
      expect(saved.status, 'pending');
    });

    test('a personal job with times keeps them', () async {
      final c = readNotifier()
        ..selectDate(DateTime(2026, 5, 10))
        ..selectStartTime(const TimeOfDay(hour: 9, minute: 0))
        ..setPersonal(value: true)
        ..toggleEmployee(_employeeA);

      // A time was already picked, so it does not silently become all-day.
      expect(readState().isAllDay, isFalse);

      final outcome = await c.submit(
        title: 'Dentist',
        address: '',
        notes: '',
        materialsNeeded: '',
      );

      final saved = (outcome as AddEventSubmitted).appointment;
      expect(saved.isAllDay, isFalse);
      expect(saved.startTime, DateTime(2026, 5, 10, 9));
    });

    test(
      'turning Personal on with no times picked still defaults to all-day',
      () {
        readNotifier().setPersonal(value: true);
        expect(readState().isAllDay, isTrue);
      },
    );

    test('turning Personal off KEEPS an explicitly set all-day', () {
      // Retired invariant: all-day used to be personal-only, so turning
      // Personal off cleared it. The switch is on every job now, so the flag
      // stays — clearing it would discard a deliberate choice.
      readNotifier()
        ..setPersonal(value: true)
        ..setAllDay(value: true)
        ..setPersonal(value: false);
      expect(readState().isAllDay, isTrue);
    });

    test('a day off saves as time off and never as a job', () async {
      final c = readNotifier()
        ..selectDate(DateTime(2026, 5, 10))
        ..setPersonal(value: true)
        ..setDayOff(value: true)
        ..toggleEmployee(_employeeA);

      final outcome = await c.submit(
        title: 'Vacation',
        address: '',
        notes: '',
        materialsNeeded: '',
      );

      final saved = (outcome as AddEventSubmitted).appointment;
      expect(saved.isDayOff, isTrue);
      expect(saved.isTimeOff, isTrue);
    });

    test(
      'ticking Day off forces all-day, so Save can never go inert',
      () async {
        // The form hides BOTH the all-day switch and the time rows behind
        // `isDayOff`, while the validator demands times whenever `!isAllDay`.
        // Reaching Day off with all-day off therefore left a block that could
        // neither satisfy the validator nor show the error — Save did nothing,
        // silently, with no way back that a user would find.
        final c = readNotifier()
          ..selectDate(DateTime(2026, 5, 10))
          ..setPersonal(value: true)
          ..setAllDay(value: false)
          ..setDayOff(value: true)
          ..toggleEmployee(_employeeA);

        expect(readState().isAllDay, isTrue);

        final outcome = await c.submit(
          title: 'Vacation',
          address: '',
          notes: '',
          materialsNeeded: '',
        );
        expect(outcome, isA<AddEventSubmitted>());
      },
    );

    test(
      'a day off picked after times is still all-day, never timed',
      () async {
        // The other half of the same hole: times chosen FIRST leave
        // `setPersonal` with nothing to default, so a timed day off used to be
        // storable — and `selectTravelCandidates` skips on `isAllDay` alone, so
        // it fired a "time to leave" push on somebody's day off.
        final c = readNotifier()
          ..selectDate(DateTime(2026, 5, 10))
          ..selectStartTime(const TimeOfDay(hour: 9, minute: 0))
          ..selectEndTime(const TimeOfDay(hour: 17, minute: 0))
          ..setPersonal(value: true)
          ..setDayOff(value: true)
          ..toggleEmployee(_employeeA);

        expect(readState().isAllDay, isTrue);

        final outcome = await c.submit(
          title: 'Vacation',
          address: '',
          notes: '',
          materialsNeeded: '',
        );
        final saved = (outcome as AddEventSubmitted).appointment;
        expect(saved.isAllDay, isTrue);
      },
    );

    test(
      'a day off drops a typed address rather than storing it unseen',
      () async {
        // The address field is dropped from the form on a day off, so a value
        // typed before the chip was ticked would be stored where no surface
        // renders it.
        final c = readNotifier()
          ..selectDate(DateTime(2026, 5, 10))
          ..setPersonal(value: true)
          ..setDayOff(value: true)
          ..toggleEmployee(_employeeA);

        final outcome = await c.submit(
          title: 'Vacation',
          address: '123 Rue Principale',
          notes: '',
          materialsNeeded: '',
        );
        expect((outcome as AddEventSubmitted).appointment.address, isEmpty);
      },
    );

    test('a double-tapped submit returns Busy, not Invalid', () async {
      // Both are no-ops at the call site, which is exactly why the difference
      // has to live in the type: a skipped write reported as `Invalid` is
      // indistinguishable from a form that failed validation.
      final gate = Completer<void>();
      when(
        () => appointments.addAppointment(any()),
      ).thenAnswer((_) => gate.future);

      final c = readNotifier()
        ..selectDate(DateTime(2026, 5, 10))
        ..setAllDay(value: true)
        ..selectClient(_aClient)
        ..toggleEmployee(_employeeA);

      final first = c.submit(
        title: 'Job',
        address: '1 Main',
        notes: '',
        materialsNeeded: '',
      );
      final second = await c.submit(
        title: 'Job',
        address: '1 Main',
        notes: '',
        materialsNeeded: '',
      );

      expect(second, isA<AddEventBusy>());
      gate.complete();
      await first;
      verify(() => appointments.addAppointment(any())).called(1);
    });

    test('turning Personal off clears the day-off flag', () {
      // The chip is hidden with the switch, so a surviving flag would be
      // unreachable — and would drop a real client job out of every count.
      readNotifier()
        ..setPersonal(value: true)
        ..setDayOff(value: true)
        ..setPersonal(value: false);
      expect(readState().isDayOff, isFalse);
    });

    test('turning a draft personal clears a chosen repeat', () async {
      readNotifier()
        ..selectRepeat(RepeatInterval.oneYear)
        ..setPersonal(value: true);
      expect(readState().repeat, RepeatInterval.none);
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
      // A 60-month horizon at every 4 months works out to 15 future visits,
      // spread across five years.
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

    test('checks repeat copies and reports a future conflict', () async {
      var nextId = 0;
      when(appointments.newDocId).thenAnswer((_) => 'appt-${++nextId}');
      when(
        () => appointments.findBusyEmployees(
          candidates: any(named: 'candidates'),
          start: any(named: 'start'),
          end: any(named: 'end'),
        ),
      ).thenAnswer((invocation) async {
        final start = invocation.namedArguments[#start] as DateTime;
        return start == DateTime(2026, 9, 10, 9)
            ? const [_employeeA]
            : const <EmployeeRecord>[];
      });

      final c = readNotifier();
      fillValid(c);
      c.selectRepeat(RepeatInterval.fourMonths);

      final outcome = await c.submit(
        title: 'Furnace check',
        address: '999 Maple',
        notes: '',
        materialsNeeded: '',
      );

      expect(outcome, isA<AddEventBusyEmployees>());
      final busy = outcome as AddEventBusyEmployees;
      expect(busy.busyEmployees, const [_employeeA]);
      expect(busy.start, DateTime(2026, 9, 10, 9));
      expect(busy.end, DateTime(2026, 9, 10, 10));
      verifyNever(() => appointments.addAppointment(any()));
      verifyNever(() => appointments.addAppointments(any()));
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

    test(
      'offline fails fast without touching the repo or the busy flag',
      () async {
        final offline = ProviderContainer(
          overrides: [
            appointmentsRepositoryProvider.overrideWithValue(appointments),
            clientsRepositoryProvider.overrideWithValue(clients),
            appointmentImageUploadProvider.overrideWithValue(uploader),
            isOfflineProvider.overrideWithValue(true),
          ],
        );
        addTearDown(offline.dispose);
        final c = offline.read(addEventControllerProvider(null).notifier)
          ..selectDate(DateTime(2026, 5, 10))
          ..selectStartTime(const TimeOfDay(hour: 9, minute: 0))
          ..selectEndTime(const TimeOfDay(hour: 10, minute: 0))
          ..selectClient(_aClient)
          ..toggleEmployee(_employeeA);

        final outcome = await c.submit(
          title: 'Leak fix',
          address: '999 Maple',
          notes: '',
          materialsNeeded: '',
        );

        expect(outcome, isA<AddEventFailed>());
        expect((outcome as AddEventFailed).error, isA<SocketException>());
        verifyNever(() => appointments.addAppointment(any()));
        verifyNever(
          () => appointments.findBusyEmployees(
            candidates: any(named: 'candidates'),
            start: any(named: 'start'),
            end: any(named: 'end'),
          ),
        );
        expect(
          offline.read(addEventControllerProvider(null)).isSubmitting,
          isFalse,
        );
      },
    );
  });

  group('multi-day runs', () {
    test('a 3-day job writes three linked one-day documents', () async {
      var nextId = 0;
      when(appointments.newDocId).thenAnswer((_) => 'appt-${++nextId}');
      when(() => appointments.addAppointments(any())).thenAnswer((_) async {});

      final c = readNotifier();
      fillValid(c);
      c.selectEndDate(DateTime(2026, 5, 12));

      final outcome = await c.submit(
        title: 'Repipe',
        address: '999 Maple',
        notes: '',
        materialsNeeded: '',
      );

      expect(outcome, isA<AddEventSubmitted>());
      expect((outcome as AddEventSubmitted).futureBookings, 2);

      final captured = verify(
        () => appointments.addAppointments(captureAny()),
      ).captured.single;
      final run = (captured as List).cast<AppointmentRecord>();
      expect(run, hasLength(3));
      expect(run.map((a) => a.id).toSet(), hasLength(3));

      final runId = run.first.id;
      for (var i = 0; i < 3; i++) {
        expect(run[i].seriesId, runId, reason: 'every day shares the run id');
        expect(run[i].dayIndex, i + 1);
        expect(run[i].dayCount, 3);
        expect(run[i].startTime, DateTime(2026, 5, 10 + i, 9));
        expect(run[i].endTime, DateTime(2026, 5, 10 + i, 10));
        expect(run[i].status, 'pending');
      }
    });

    test('a one-day job still writes a single unlinked document', () async {
      final c = readNotifier();
      fillValid(c);

      await c.submit(
        title: 'Leak',
        address: '999 Maple',
        notes: '',
        materialsNeeded: '',
      );

      final captured =
          verify(
                () => appointments.addAppointment(captureAny()),
              ).captured.single
              as AppointmentRecord;
      expect(captured.seriesId, '');
      expect(captured.dayIndex, 0);
      expect(captured.dayCount, 0);
    });

    test('a multi-day PERSONAL block stays one wide document', () async {
      // Times first: setPersonal defaults an as-yet-untimed block to all-day.
      final c = readNotifier()
        ..selectDate(DateTime(2026, 5, 10))
        ..selectStartTime(const TimeOfDay(hour: 9, minute: 0))
        ..selectEndTime(const TimeOfDay(hour: 10, minute: 0))
        ..setPersonal(value: true)
        ..toggleEmployee(_employeeA)
        ..selectEndDate(DateTime(2026, 5, 14));

      await c.submit(
        title: 'Vacation',
        address: '',
        notes: '',
        materialsNeeded: '',
      );

      final captured =
          verify(
                () => appointments.addAppointment(captureAny()),
              ).captured.single
              as AppointmentRecord;
      expect(captured.startTime, DateTime(2026, 5, 10, 9));
      expect(captured.endTime, DateTime(2026, 5, 14, 10));
      expect(captured.dayCount, 0);
    });
  });
}
