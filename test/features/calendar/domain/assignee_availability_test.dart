import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/assignee_availability.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

AppointmentRecord _job(
  String id, {
  required DateTime start,
  required DateTime end,
  List<String> employeeIds = const ['e1'],
  String status = 'pending',
  bool isPersonal = false,
  bool isDayOff = false,
}) => AppointmentRecord(
  id: id,
  startTime: start,
  endTime: end,
  employeeIds: employeeIds,
  status: status,
  isPersonal: isPersonal,
  isDayOff: isDayOff,
);

void main() {
  final windowStart = DateTime(2026, 8, 26, 9);
  final windowEnd = DateTime(2026, 8, 26, 12);

  group('clashingAppointments', () {
    test('an overlapping job clashes', () {
      final overlapping = _job(
        'a',
        start: DateTime(2026, 8, 26, 11),
        end: DateTime(2026, 8, 26, 13),
      );
      expect(
        clashingAppointments(
          appointments: [overlapping],
          start: windowStart,
          end: windowEnd,
        ),
        [overlapping],
      );
    });

    test('a job in the same day but a different window does not', () {
      expect(
        clashingAppointments(
          appointments: [
            _job(
              'a',
              start: DateTime(2026, 8, 26, 19),
              end: DateTime(2026, 8, 26, 21),
            ),
          ],
          start: windowStart,
          end: windowEnd,
        ),
        isEmpty,
      );
    });

    test('the two instants are a DAILY window, not one unbroken stretch', () {
      // A 9-5 run across the week does not put anybody on site at 7 pm on any
      // of those days, so an evening job inside it is not a clash.
      final run = _job(
        'run',
        start: DateTime(2026, 8, 24, 9),
        end: DateTime(2026, 8, 28, 17),
      );
      expect(
        clashingAppointments(
          appointments: [run],
          start: DateTime(2026, 8, 26, 19),
          end: DateTime(2026, 8, 26, 21),
        ),
        isEmpty,
      );
    });

    test('a terminal-status job is never a clash', () {
      for (final status in ['done', 'completed', 'cancelled']) {
        expect(
          clashingAppointments(
            appointments: [
              _job('a', start: windowStart, end: windowEnd, status: status),
            ],
            start: windowStart,
            end: windowEnd,
          ),
          isEmpty,
          reason: status,
        );
      }
    });

    test('excludeAppointmentId drops the record being edited', () {
      // Without it a job collides with itself and every one of its own
      // assignees reads as busy.
      expect(
        clashingAppointments(
          appointments: [_job('self', start: windowStart, end: windowEnd)],
          start: windowStart,
          end: windowEnd,
          excludeAppointmentId: 'self',
        ),
        isEmpty,
      );
    });

    test('a day off IS a clash by default — that is how it works', () {
      final off = _job(
        'off',
        start: DateTime(2026, 8, 26),
        end: DateTime(2026, 8, 26, 23, 59),
        isPersonal: true,
        isDayOff: true,
      );
      expect(
        clashingAppointments(
          appointments: [off],
          start: windowStart,
          end: windowEnd,
        ),
        [off],
      );
    });

    test('clientJobsOnly drops personal blocks', () {
      // The alert offers a SWAP on each row, and "swap Marc for Nadia" on
      // Marc's own dentist appointment is nonsense.
      final client = _job('client', start: windowStart, end: windowEnd);
      final personal = _job(
        'personal',
        start: windowStart,
        end: windowEnd,
        isPersonal: true,
      );
      expect(
        clashingAppointments(
          appointments: [client, personal],
          start: windowStart,
          end: windowEnd,
          clientJobsOnly: true,
        ),
        [client],
      );
    });
  });

  group('clashesByAssignee', () {
    test('keys each clash by the assignees it names', () {
      final job = _job(
        'a',
        start: windowStart,
        end: windowEnd,
        employeeIds: ['e1', 'e2'],
      );
      final byAssignee = clashesByAssignee(
        clashes: [job],
        employeeIds: ['e1', 'e2'],
      );
      expect(byAssignee.keys, unorderedEquals(['e1', 'e2']));
    });

    test('ignores assignees outside the candidate set', () {
      final job = _job(
        'a',
        start: windowStart,
        end: windowEnd,
        employeeIds: ['e1', 'stranger'],
      );
      expect(
        clashesByAssignee(clashes: [job], employeeIds: ['e1']).keys,
        ['e1'],
      );
    });

    test('time off wins over a booked job for the same person', () {
      // "Marc is off" is the truer sentence, and there is only room for one
      // line per person.
      final booked = _job('booked', start: windowStart, end: windowEnd);
      final off = _job(
        'off',
        start: DateTime(2026, 8, 26),
        end: DateTime(2026, 8, 26, 23, 59),
        isPersonal: true,
        isDayOff: true,
      );
      for (final order in [
        [booked, off],
        [off, booked],
      ]) {
        expect(
          clashesByAssignee(
            clashes: order,
            employeeIds: ['e1'],
          )['e1']!.isTimeOff,
          isTrue,
        );
      }
    });

    test('otherwise the earliest clash wins, so the figure names the first '
        'thing in the way', () {
      final later = _job(
        'later',
        start: DateTime(2026, 8, 26, 11),
        end: DateTime(2026, 8, 26, 12),
      );
      final earlier = _job(
        'earlier',
        start: DateTime(2026, 8, 26, 9),
        end: DateTime(2026, 8, 26, 10),
      );
      expect(
        clashesByAssignee(
          clashes: [later, earlier],
          employeeIds: ['e1'],
        )['e1']!.id,
        'earlier',
      );
    });
  });
}
