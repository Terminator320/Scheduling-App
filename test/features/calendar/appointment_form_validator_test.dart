import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
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
      // Regression: times picked BEFORE all-day was switched on stay in
      // state; the validator must not raise a time error against rows that
      // are no longer on screen.
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

    test('overnight appointment (end < start) is valid', () {
      final errors = AppointmentFormValidator.validate(
        _input(
          startTime: const TimeOfDay(hour: 23, minute: 0),
          endTime: const TimeOfDay(hour: 1, minute: 0),
        ),
      );
      // The validator no longer checks end-vs-start ordering — appointmentSpan
      // owns the overnight roll-over at save time.
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

  group('allDaySpan / appointmentSpan', () {
    test('an all-day block spans midnight to 23:59 of the same date', () {
      // Real instants, not sentinels — every range query and the overdue
      // sweep keep treating it as an ordinary appointment.
      final span = allDaySpan(
        DateTime(2026, 5, 10, 14, 37),
        DateTime(2026, 5, 10, 14, 37),
      );

      expect(span.start, DateTime(2026, 5, 10));
      expect(span.end, DateTime(2026, 5, 10, 23, 59));
    });

    test('appointmentSpan picks the all-day pair and ignores the times', () {
      // Times picked before the switch was flipped stay in state, so they must
      // not leak into the stored span.
      final span = appointmentSpan(
        date: DateTime(2026, 5, 10),
        endDate: DateTime(2026, 5, 10),
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
        endDate: DateTime(2026, 5, 10),
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
        endDate: DateTime(2026, 5, 10),
        isAllDay: false,
        startTime: const TimeOfDay(hour: 22, minute: 0),
        endTime: const TimeOfDay(hour: 1, minute: 0),
      );

      expect(span.end.day, 11);
    });
  });

  group('appointmentSpan', () {
    test('a same-day job spans the picked times', () {
      final span = appointmentSpan(
        date: DateTime(2026, 8),
        endDate: DateTime(2026, 8),
        isAllDay: false,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
      );
      expect(span.start, DateTime(2026, 8, 1, 9));
      expect(span.end, DateTime(2026, 8, 1, 17));
    });

    test('a multi-day job ends on the end date at the end time', () {
      final span = appointmentSpan(
        date: DateTime(2026, 8),
        endDate: DateTime(2026, 8, 5),
        isAllDay: false,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
      );
      expect(span.start, DateTime(2026, 8, 1, 9));
      expect(span.end, DateTime(2026, 8, 5, 17));
    });

    test('a night shift ends the morning after the last night', () {
      final span = appointmentSpan(
        date: DateTime(2026, 8),
        endDate: DateTime(2026, 8, 3),
        isAllDay: false,
        startTime: const TimeOfDay(hour: 22, minute: 0),
        endTime: const TimeOfDay(hour: 6, minute: 0),
      );
      expect(span.start, DateTime(2026, 8, 1, 22));
      expect(span.end, DateTime(2026, 8, 4, 6));
    });

    test('an all-day run spans midnight to 23:59 of the end date', () {
      final span = appointmentSpan(
        date: DateTime(2026, 8, 10),
        endDate: DateTime(2026, 8, 14),
        isAllDay: true,
      );
      expect(span.start, DateTime(2026, 8, 10));
      expect(span.end, DateTime(2026, 8, 14, 23, 59));
    });

    test('equal start and end times read as a continuous 24-hour window', () {
      final span = appointmentSpan(
        date: DateTime(2026, 8),
        endDate: DateTime(2026, 8, 3),
        isAllDay: false,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 9, minute: 0),
      );
      expect(span.end, DateTime(2026, 8, 4, 9));
    });
  });

  group('span validation', () {
    Map<String, AppointmentFormError> run({
      required DateTime date,
      required DateTime endDate,
    }) => AppointmentFormValidator.validate(
      AppointmentFormInput(
        title: 'Repipe',
        date: date,
        endDate: endDate,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
        client: null,
        selectedEmployees: const [],
        isPersonal: true,
      ),
    );

    test('rejects an end date before the start date', () {
      final errors = run(
        date: DateTime(2026, 8, 5),
        endDate: DateTime(2026, 8),
      );
      expect(errors['endDate'], AppointmentFormError.endDateBeforeStart);
    });

    test('accepts a span of exactly 14 days', () {
      final errors = run(
        date: DateTime(2026, 8),
        endDate: DateTime(2026, 8, 14),
      );
      expect(errors['endDate'], isNull);
    });

    test('rejects a span of 15 days', () {
      final errors = run(
        date: DateTime(2026, 8),
        endDate: DateTime(2026, 8, 15),
      );
      expect(errors['endDate'], AppointmentFormError.spanTooLong);
    });

    test(
      'accepts an end time before the start time — that is a night shift',
      () {
        final errors = AppointmentFormValidator.validate(
          AppointmentFormInput(
            title: 'Nuit',
            date: DateTime(2026, 8),
            endDate: DateTime(2026, 8, 3),
            startTime: const TimeOfDay(hour: 22, minute: 0),
            endTime: const TimeOfDay(hour: 6, minute: 0),
            client: null,
            selectedEmployees: const [],
            isPersonal: true,
          ),
        );
        expect(errors['endTime'], isNull);
        expect(errors['endDate'], isNull);
      },
    );

    test('a null end date is read as same-day and raises nothing', () {
      final errors = AppointmentFormValidator.validate(
        AppointmentFormInput(
          title: 'Repipe',
          date: DateTime(2026, 8),
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 17, minute: 0),
          client: null,
          selectedEmployees: const [],
          isPersonal: true,
        ),
      );
      expect(errors['endDate'], isNull);
    });
  });

  // I12: extracted precisely because both form bodies had copied it — and it
  // shipped with no tests, while its neighbours `allDaySpan`/`appointmentSpan`
  // are well covered.
  group('runLengthDays', () {
    test('a single-day job is 1, not 0', () {
      expect(runLengthDays(DateTime(2026, 8, 2), DateTime(2026, 8, 2)), 1);
    });

    test('counts the end date INCLUSIVELY', () {
      // "The end date names the last day the crew STARTS work" — Aug 2 to
      // Aug 6 is five work days, which is what the card's "Day 3 of 5" and
      // the 14-day cap both count.
      expect(runLengthDays(DateTime(2026, 8, 2), DateTime(2026, 8, 6)), 5);
    });

    test('a half-filled form reads as a single day', () {
      expect(runLengthDays(null, DateTime(2026, 8, 6)), 1);
      expect(runLengthDays(DateTime(2026, 8, 2), null), 1);
      expect(runLengthDays(null, null), 1);
    });

    test('a reversed pair floors at 1 rather than going negative', () {
      // The validator refuses this separately; the floor keeps every caller
      // that renders a counter from showing "Day 1 of -3".
      expect(runLengthDays(DateTime(2026, 8, 6), DateTime(2026, 8, 2)), 1);
    });

    test('counts CALENDAR days across a DST shift', () {
      // Composed from wall-clock dates, so the hour the clocks move must not
      // round a day off the count.
      expect(runLengthDays(DateTime(2026, 11, 7), DateTime(2026, 11, 8)), 2);
      expect(runLengthDays(DateTime(2026, 3, 8), DateTime(2026, 3, 9)), 2);
    });

    test('the widest run the form can save is the 14-day cap', () {
      expect(
        runLengthDays(DateTime(2026, 8, 2), DateTime(2026, 8, 15)),
        maxAppointmentSpanDays,
      );
    });
  });

  group('withoutKeys', () {
    const errors = {
      'date': AppointmentFormError.dateRequired,
      'startTime': AppointmentFormError.startTimeRequired,
      'endTime': AppointmentFormError.endTimeRequired,
    };

    test('drops every named key and keeps the rest', () {
      final result = withoutKeys(errors, const ['startTime', 'endTime']);
      expect(result, {'date': AppointmentFormError.dateRequired});
    });

    test('returns the same map when none of the keys is present', () {
      expect(identical(withoutKeys(errors, const ['client']), errors), isTrue);
    });
  });
}
