import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/application/event_details_save_pipeline.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';

class _UnusedRepo implements AppointmentsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// `buildUpdatedRecord` is pure — it never reaches the repo, storage or the
/// logger, which is the whole reason the write rules were split out here.
final _pipeline = EventDetailsSavePipeline(
  repo: _UnusedRepo(),
  resolveStorage: () => null,
  logger: AppLogger(),
);

final _start = DateTime(2026, 7, 8, 9);
final _end = DateTime(2026, 7, 8, 17);

final _client = ClientRecord.fromMap('c1', {
  'name': 'Acme Plumbing',
  'phone': '(514) 555-1234',
});

/// An ordinary client visit, carrying the denormalized client copies.
final _clientVisit = AppointmentRecord(
  id: 'a1',
  title: 'Boiler service',
  startTime: _start,
  endTime: _end,
  clientId: 'c1',
  clientName: 'Acme Plumbing',
  clientPhone: '(514) 555-1234',
  address: '12 Rue Principale',
  employeeIds: const ['e1'],
  employeeNames: const ['Jane'],
);

/// A personal block: no client anywhere, but an address it is entitled to keep.
final _personalBlock = AppointmentRecord(
  id: 'a2',
  title: 'Dentist',
  startTime: _start,
  endTime: _end,
  address: '400 Rue Sherbrooke',
  isPersonal: true,
  employeeIds: const ['e1'],
  employeeNames: const ['Jane'],
);

AppointmentRecord _build(
  AppointmentRecord appointment, {
  required bool isPersonal,
  ClientRecord? selectedClient,
  String address = '12 Rue Principale',
  bool isAllDay = false,
}) => _pipeline.buildUpdatedRecord(
  appointment,
  id: appointment.id ?? '',
  title: appointment.title,
  address: address,
  notes: '',
  materialsNeeded: '',
  start: _start,
  end: _end,
  assignees: (ids: appointment.employeeIds, names: appointment.employeeNames),
  selectedClient: selectedClient,
  status: 'pending',
  repeat: RepeatInterval.none,
  isPersonal: isPersonal,
  isAllDay: isAllDay,
);

void main() {
  group('client visit converted to personal', () {
    test('clears all three stored client fields', () {
      // Empty strings, not "left behind": the UI stops showing these fields, so
      // a stale value would be invisible and uneditable.
      final updated = _build(_clientVisit, isPersonal: true);

      expect(updated.isPersonal, isTrue);
      expect(updated.clientId, '');
      expect(updated.clientName, '');
      expect(updated.clientPhone, '');
    });

    test('clears them even while a client is still selected in the form', () {
      // The picker is hidden rather than unmounted, so its selection can
      // survive the switch being turned on.
      final updated = _build(
        _clientVisit,
        isPersonal: true,
        selectedClient: _client,
      );

      expect(updated.clientId, '');
      expect(updated.clientName, '');
      expect(updated.clientPhone, '');
    });

    test('KEEPS the address', () {
      // Owner call 2026-08-11, reversing the original "no address": a supply
      // run still happens somewhere and the crew wants directions to it.
      final updated = _build(
        _clientVisit,
        isPersonal: true,
        address: '400 Rue Sherbrooke',
      );

      expect(updated.address, '400 Rue Sherbrooke');
    });

    test('writes the address the user can see, trimmed', () {
      final updated = _build(
        _clientVisit,
        isPersonal: true,
        address: '  400 Rue Sherbrooke  ',
      );

      expect(updated.address, '400 Rue Sherbrooke');
    });

    test('an emptied address is stored empty rather than falling back', () {
      final updated = _build(_clientVisit, isPersonal: true, address: '   ');

      expect(updated.address, '');
    });
  });

  group('personal block converted to a client visit', () {
    test('takes the newly picked client', () {
      final updated = _build(
        _personalBlock,
        isPersonal: false,
        selectedClient: _client,
      );

      expect(updated.isPersonal, isFalse);
      expect(updated.clientId, 'c1');
      expect(updated.clientName, 'Acme Plumbing');
      expect(updated.clientPhone, '(514) 555-1234');
    });

    test('with no client picked it keeps the record it came from', () {
      // A personal block has empty client fields, so this stays empty — the
      // fallback must read the record, never resurrect a cleared value.
      final updated = _build(_personalBlock, isPersonal: false);

      expect(updated.clientId, '');
      expect(updated.clientName, '');
    });

    test('keeps its address', () {
      final updated = _build(
        _personalBlock,
        isPersonal: false,
        selectedClient: _client,
        address: '400 Rue Sherbrooke',
      );

      expect(updated.address, '400 Rue Sherbrooke');
    });
  });

  group('an unchanged client visit', () {
    test('keeps its client when the form has no selection', () {
      final updated = _build(_clientVisit, isPersonal: false);

      expect(updated.clientId, 'c1');
      expect(updated.clientName, 'Acme Plumbing');
      expect(updated.clientPhone, '(514) 555-1234');
    });
  });

  group('isAllDay survives both directions', () {
    // Turning Personal OFF must not clear the flag (2026-08-03): all-day is
    // offered on every job, so a client visit can legitimately run whole days.
    test('kept when converting to personal', () {
      expect(
        _build(_clientVisit, isPersonal: true, isAllDay: true).isAllDay,
        isTrue,
      );
    });

    test('kept when converting away from personal', () {
      expect(
        _build(_personalBlock, isPersonal: false, isAllDay: true).isAllDay,
        isTrue,
      );
    });
  });
}
