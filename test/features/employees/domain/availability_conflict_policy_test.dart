import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/domain/policies/availability_conflict_policy.dart';

AppointmentRecord _job({
  required DateTime start,
  DateTime? end,
  String status = 'pending',
}) => AppointmentRecord(
  id: 'a-${start.millisecondsSinceEpoch}',
  title: 'Job',
  startTime: start,
  endTime: end ?? start.add(const Duration(hours: 2)),
  status: status,
);

void main() {
  // 2026-08-10 is a Monday. `workingDays` is Sunday-indexed, so Monday is 1.
  final monday = DateTime(2026, 8, 10, 9);
  final wednesday = DateTime(2026, 8, 12, 9);
  final range = AppointmentDateRange(
    start: DateTime(2026, 8, 9),
    end: DateTime(2026, 8, 23),
  );

  const fiveDayWeek = [false, true, true, true, true, true, false];

  test('a day being turned OFF that holds work is reported', () {
    final conflicts = daysWithBookedWork(
      appointments: [_job(start: monday)],
      range: range,
      previousWorkingDays: fiveDayWeek,
      nextWorkingDays: const [false, false, true, true, true, true, false],
    );

    expect(conflicts, {1});
  });

  test('a day left ON is never reported, even when it holds work', () {
    final conflicts = daysWithBookedWork(
      appointments: [_job(start: monday)],
      range: range,
      previousWorkingDays: fiveDayWeek,
      nextWorkingDays: fiveDayWeek,
    );

    expect(conflicts, isEmpty);
  });

  test('a turned-off day with no work is not reported', () {
    final conflicts = daysWithBookedWork(
      appointments: [_job(start: wednesday)],
      range: range,
      previousWorkingDays: fiveDayWeek,
      nextWorkingDays: const [false, false, true, true, true, true, false],
    );

    expect(conflicts, isEmpty);
  });

  test('a cancelled job is not booked work', () {
    final conflicts = daysWithBookedWork(
      appointments: [_job(start: monday, status: 'cancelled')],
      range: range,
      previousWorkingDays: fiveDayWeek,
      nextWorkingDays: const [false, false, true, true, true, true, false],
    );

    expect(conflicts, isEmpty);
  });

  test('a completed job is not booked work either', () {
    // The warning is about work someone still has to move. A finished visit
    // needs nobody's attention.
    final conflicts = daysWithBookedWork(
      appointments: [_job(start: monday, status: 'done')],
      range: range,
      previousWorkingDays: fiveDayWeek,
      nextWorkingDays: const [false, false, true, true, true, true, false],
    );

    expect(conflicts, isEmpty);
  });

  test('a multi-day run reports every turned-off day it works', () {
    // Mon 9:00 → Wed 17:00 is a three-work-day run. Turning Monday AND
    // Wednesday off must flag both — which is exactly what reading `startTime`
    // alone would miss.
    final conflicts = daysWithBookedWork(
      appointments: [_job(start: monday, end: DateTime(2026, 8, 12, 17))],
      range: range,
      previousWorkingDays: fiveDayWeek,
      nextWorkingDays: const [false, false, true, false, true, true, false],
    );

    expect(conflicts, {1, 3});
  });

  test('turning nothing off short-circuits to empty', () {
    // Adding a day is never a conflict, so the common case costs no slicing.
    final conflicts = daysWithBookedWork(
      appointments: [_job(start: monday)],
      range: range,
      previousWorkingDays: fiveDayWeek,
      nextWorkingDays: const [true, true, true, true, true, true, true],
    );

    expect(conflicts, isEmpty);
  });

  group('daysBookedOutsideAvailability', () {
    // The dashboard's question: not "what would this change break" but "what
    // is already wrong". Same computation against a fully-available baseline.
    test('work on a day the person does not work is reported', () {
      final saturday = DateTime(2026, 8, 15, 9);

      final conflicts = daysBookedOutsideAvailability(
        appointments: [_job(start: saturday)],
        range: range,
        workingDays: fiveDayWeek,
      );

      expect(conflicts, {6});
    });

    test('work on a working day is never reported', () {
      final conflicts = daysBookedOutsideAvailability(
        appointments: [
          _job(start: monday),
          _job(start: wednesday),
        ],
        range: range,
        workingDays: fiveDayWeek,
      );

      expect(conflicts, isEmpty);
    });

    test('a multi-day run is judged on every day it works', () {
      // Friday through Sunday: the run STARTS on a working day, so a
      // startTime-derived weekday would see nothing wrong with it.
      final conflicts = daysBookedOutsideAvailability(
        appointments: [
          _job(
            start: DateTime(2026, 8, 14, 9),
            end: DateTime(2026, 8, 16, 17),
          ),
        ],
        range: range,
        workingDays: fiveDayWeek,
      );

      expect(conflicts, {6, 0});
    });

    test('a closed job is not a conflict', () {
      final conflicts = daysBookedOutsideAvailability(
        appointments: [_job(start: DateTime(2026, 8, 15, 9), status: 'done')],
        range: range,
        workingDays: fiveDayWeek,
      );

      expect(conflicts, isEmpty);
    });
  });
}
