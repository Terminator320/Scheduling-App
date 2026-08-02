import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/policies/appointment_form_validator.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

const _aClient = ClientRecord(id: 'c1', name: 'Jane');
const _anEmployee = EmployeeRecord(id: 'e1', name: 'Bob');

AppointmentFormInput _input({
  String title = 'Kitchen leak',
  DateTime? date,
  TimeOfDay? startTime,
  TimeOfDay? endTime,
  ClientRecord? client = _aClient,
  List<EmployeeRecord> employees = const [_anEmployee],
  bool isPersonal = false,
  bool isAllDay = false,
}) {
  return AppointmentFormInput(
    title: title,
    date: date ?? DateTime(2026, 5, 10),
    startTime: startTime ?? const TimeOfDay(hour: 10, minute: 0),
    endTime: endTime ?? const TimeOfDay(hour: 11, minute: 0),
    client: client,
    selectedEmployees: employees,
    isPersonal: isPersonal,
    isAllDay: isAllDay,
  );
}

void main() {
  group('AppointmentFormValidator.validate', () {
    test('valid form returns empty map', () {
      expect(AppointmentFormValidator.validate(_input()), isEmpty);
    });

    test('an all-day block ignores stale times left over from before', () {
      // Regression: times picked BEFORE all-day was switched on stay in state.
      // An equal start/end pair used to re-raise endTimeMustBeAfterStart, so
      // Save failed against time rows that were no longer on screen.
      final errors = AppointmentFormValidator.validate(
        _input(
          isPersonal: true,
          isAllDay: true,
          client: null,
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 9, minute: 0),
        ),
      );
      expect(errors, isEmpty);
    });

    test('a timed job still rejects an end that is not after the start', () {
      final errors = AppointmentFormValidator.validate(
        _input(
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 9, minute: 0),
        ),
      );
      expect(errors['endTime'], AppointmentFormError.endTimeMustBeAfterStart);
    });

    test('reports titleRequired on empty / whitespace title', () {
      for (final t in ['', '   ', '\t']) {
        final errors = AppointmentFormValidator.validate(_input(title: t));
        expect(
          errors['title'],
          AppointmentFormError.titleRequired,
          reason: 'title=${t.codeUnits}',
        );
      }
    });

    test('reports dateRequired when date is null', () {
      final errors = AppointmentFormValidator.validate(
        const AppointmentFormInput(
          title: 't',
          date: null,
          startTime: TimeOfDay(hour: 9, minute: 0),
          endTime: TimeOfDay(hour: 10, minute: 0),
          client: _aClient,
          selectedEmployees: [_anEmployee],
        ),
      );
      expect(errors['date'], AppointmentFormError.dateRequired);
    });

    test('reports startTimeRequired and endTimeRequired independently', () {
      final errors = AppointmentFormValidator.validate(
        AppointmentFormInput(
          title: 't',
          date: DateTime(2026, 5, 10),
          startTime: null,
          endTime: null,
          client: _aClient,
          selectedEmployees: const [_anEmployee],
        ),
      );
      expect(errors['startTime'], AppointmentFormError.startTimeRequired);
      expect(errors['endTime'], AppointmentFormError.endTimeRequired);
    });

    test('clientRequired when client is null', () {
      final errors = AppointmentFormValidator.validate(_input(client: null));
      expect(errors['client'], AppointmentFormError.clientRequired);
    });

    test('a personal job needs no client', () {
      final errors = AppointmentFormValidator.validate(
        _input(client: null, isPersonal: true),
      );
      expect(errors, isEmpty);
    });

    test('a personal job still needs its assignees', () {
      final errors = AppointmentFormValidator.validate(
        _input(client: null, employees: const [], isPersonal: true),
      );
      expect(errors['employees'], AppointmentFormError.employeesRequired);
      expect(errors.containsKey('client'), isFalse);
    });

    test('employeesRequired when no employees selected', () {
      final errors = AppointmentFormValidator.validate(
        _input(employees: const []),
      );
      expect(errors['employees'], AppointmentFormError.employeesRequired);
    });

    test('overnight appointment (end < start) is valid (auto-bumped)', () {
      final errors = AppointmentFormValidator.validate(
        _input(
          startTime: const TimeOfDay(hour: 23, minute: 0),
          endTime: const TimeOfDay(hour: 1, minute: 0),
        ),
      );
      // end 1am is after start 11pm via the next-day bump in
      // combineEndDateAndTime, so no error.
      expect(errors, isEmpty);
    });

    test('end equal to start triggers endTimeMustBeAfterStart', () {
      // Equal times must NOT get the overnight next-day bump (that would
      // silently book a ~24h appointment) — they surface the validation
      // error instead.
      final errors = AppointmentFormValidator.validate(
        _input(
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 9, minute: 0),
        ),
      );
      expect(
        errors['endTime'],
        AppointmentFormError.endTimeMustBeAfterStart,
      );
    });

    test('reports multiple errors at once', () {
      final errors = AppointmentFormValidator.validate(
        const AppointmentFormInput(
          title: '',
          date: null,
          startTime: null,
          endTime: null,
          client: null,
          selectedEmployees: [],
        ),
      );
      expect(errors.keys.toSet(), {
        'title',
        'date',
        'startTime',
        'endTime',
        'client',
        'employees',
      });
    });
  });

  group('combineDateAndTime', () {
    test('composes date + time into a single DateTime', () {
      final r = combineDateAndTime(
        DateTime(2026, 5, 10),
        const TimeOfDay(hour: 9, minute: 30),
      );
      expect(r, DateTime(2026, 5, 10, 9, 30));
    });
  });

  group('combineEndDateAndTime', () {
    test('returns same-day end when after start', () {
      final r = combineEndDateAndTime(
        DateTime(2026, 5, 10),
        const TimeOfDay(hour: 11, minute: 0),
        const TimeOfDay(hour: 9, minute: 0),
      );
      expect(r, DateTime(2026, 5, 10, 11));
    });

    test('bumps to next day only when end is strictly before start', () {
      final r = combineEndDateAndTime(
        DateTime(2026, 5, 10),
        const TimeOfDay(hour: 1, minute: 0),
        const TimeOfDay(hour: 23, minute: 0),
      );
      expect(r, DateTime(2026, 5, 11, 1));
    });

    test('keeps a same-day end when end equals start (no 24h bump)', () {
      final r = combineEndDateAndTime(
        DateTime(2026, 5, 10),
        const TimeOfDay(hour: 9, minute: 0),
        const TimeOfDay(hour: 9, minute: 0),
      );
      expect(r, DateTime(2026, 5, 10, 9));
    });

    test('returns same-day end when no startTime supplied', () {
      final r = combineEndDateAndTime(
        DateTime(2026, 5, 10),
        const TimeOfDay(hour: 9, minute: 0),
      );
      expect(r, DateTime(2026, 5, 10, 9));
    });
  });

  group('allDaySpan / appointmentSpan', () {
    test('an all-day block spans midnight to 23:59 of the same date', () {
      // Real instants, not sentinels — every range query and the overdue
      // sweep keep treating it as an ordinary appointment.
      final span = allDaySpan(DateTime(2026, 5, 10, 14, 37));

      expect(span.start, DateTime(2026, 5, 10));
      expect(span.end, DateTime(2026, 5, 10, 23, 59));
    });

    test('appointmentSpan picks the all-day pair and ignores the times', () {
      // Times picked before the switch was flipped stay in state, so they must
      // not leak into the stored span.
      final span = appointmentSpan(
        date: DateTime(2026, 5, 10),
        isAllDay: true,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 11, minute: 0),
      );

      expect(span.start, DateTime(2026, 5, 10));
      expect(span.end, DateTime(2026, 5, 10, 23, 59));
    });

    test('appointmentSpan uses the picked times when not all-day', () {
      final span = appointmentSpan(
        date: DateTime(2026, 5, 10),
        isAllDay: false,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 11, minute: 30),
      );

      expect(span.start, DateTime(2026, 5, 10, 9));
      expect(span.end, DateTime(2026, 5, 10, 11, 30));
    });

    test('an end before the start rolls to the next day', () {
      final span = appointmentSpan(
        date: DateTime(2026, 5, 10),
        isAllDay: false,
        startTime: const TimeOfDay(hour: 22, minute: 0),
        endTime: const TimeOfDay(hour: 1, minute: 0),
      );

      expect(span.end.day, 11);
    });
  });
}
