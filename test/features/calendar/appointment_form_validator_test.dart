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
}) {
  return AppointmentFormInput(
    title: title,
    date: date ?? DateTime(2026, 5, 10),
    startTime: startTime ?? const TimeOfDay(hour: 10, minute: 0),
    endTime: endTime ?? const TimeOfDay(hour: 11, minute: 0),
    client: client,
    selectedEmployees: employees,
  );
}

void main() {
  group('AppointmentFormValidator.validate', () {
    test('valid form returns empty map', () {
      expect(AppointmentFormValidator.validate(_input()), isEmpty);
    });

    test('reports titleRequired on empty / whitespace title', () {
      for (final t in ['', '   ', '\t']) {
        final errors = AppointmentFormValidator.validate(_input(title: t));
        expect(errors['title'], AppointmentFormError.titleRequired,
            reason: 'title=${t.codeUnits}');
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
      final errors =
          AppointmentFormValidator.validate(_input(client: null));
      expect(errors['client'], AppointmentFormError.clientRequired);
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

    test('end equal to start triggers endTimeMustBeAfterStart only if neither '
        'overnight bump nor missing field', () {
      // When start and end are equal AND not on a missing date, the bump
      // makes end+1day, which is after start, so the validator does not
      // fire endTimeMustBeAfterStart. This pins existing behaviour: end ==
      // start is treated as a 24h overnight appointment.
      final errors = AppointmentFormValidator.validate(
        _input(
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 9, minute: 0),
        ),
      );
      expect(errors, isEmpty);
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

    test('bumps to next day when end <= start', () {
      final r = combineEndDateAndTime(
        DateTime(2026, 5, 10),
        const TimeOfDay(hour: 1, minute: 0),
        const TimeOfDay(hour: 23, minute: 0),
      );
      expect(r, DateTime(2026, 5, 11, 1));
    });

    test('returns same-day end when no startTime supplied', () {
      final r = combineEndDateAndTime(
        DateTime(2026, 5, 10),
        const TimeOfDay(hour: 9, minute: 0),
      );
      expect(r, DateTime(2026, 5, 10, 9));
    });
  });
}
