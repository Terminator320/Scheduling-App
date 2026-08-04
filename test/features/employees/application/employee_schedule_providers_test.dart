import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/utils/current_day_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/application/employee_schedule_providers.dart';

/// The range streams query from `AppointmentDateRange.fetchStart` — 14 days
/// BEFORE the range's start — so a job already under way is still fetched.
/// That makes the emitted list a deliberate superset of the day, and every
/// reducer over it has to re-scope. These pin that: before the fix the roster
/// count, the detail panel and the drawer badge each reported a fortnight of
/// jobs as "today".
final _today = DateTime(2026, 8, 4);

AppointmentRecord _job({
  required String id,
  required DateTime start,
  required DateTime end,
  List<String> employeeIds = const ['e1'],
  String status = 'pending',
}) => AppointmentRecord(
  id: id,
  title: 'Job $id',
  startTime: start,
  endTime: end,
  employeeIds: employeeIds,
  status: status,
);

Future<ProviderContainer> _containerWith(List<AppointmentRecord> jobs) async {
  final container = ProviderContainer(
    overrides: [
      currentDayProvider.overrideWithValue(_today),
      appointmentsInRangeProvider.overrideWith(
        (ref, range) => Stream.value(jobs),
      ),
    ],
  );
  addTearDown(container.dispose);
  // AutoDispose family state races teardown without an explicit listener.
  container
    ..listen(employeeJobsTodayProvider, (_, _) {})
    ..listen(employeeTodayJobsProvider('e1'), (_, _) {});
  // The override is still a Stream, so the reducers read `.value == null`
  // until it emits — await the first frame before asserting.
  await container.read(
    appointmentsInRangeProvider(AppointmentDateRange.forDay(_today)).future,
  );
  return container;
}

void main() {
  group('employeeJobsTodayProvider', () {
    test('counts a job that runs today', () async {
      final container = await _containerWith([
        _job(
          id: 'a',
          start: DateTime(2026, 8, 4, 9),
          end: DateTime(2026, 8, 4, 17),
        ),
      ]);
      expect(container.read(employeeJobsTodayProvider), {'e1': 1});
    });

    test('ignores a job that ran a fortnight ago', () async {
      // The whole regression: this doc IS in the emitted list because the
      // query reaches back 14 days, but it is not today's work.
      final container = await _containerWith([
        _job(
          id: 'old',
          start: DateTime(2026, 7, 23, 9),
          end: DateTime(2026, 7, 23, 17),
        ),
      ]);
      expect(container.read(employeeJobsTodayProvider), isEmpty);
    });

    test('counts a multi-day run that is on site today', () async {
      final container = await _containerWith([
        _job(
          id: 'run',
          start: DateTime(2026, 8, 1, 9),
          end: DateTime(2026, 8, 6, 17),
        ),
      ]);
      expect(container.read(employeeJobsTodayProvider), {'e1': 1});
    });

    test('ignores a multi-day run that finished before today', () async {
      final container = await _containerWith([
        _job(
          id: 'done',
          start: DateTime(2026, 7, 28, 9),
          end: DateTime(2026, 8, 2, 17),
        ),
      ]);
      expect(container.read(employeeJobsTodayProvider), isEmpty);
    });

    test('does not count a cancelled visit', () async {
      final container = await _containerWith([
        _job(
          id: 'x',
          start: DateTime(2026, 8, 4, 9),
          end: DateTime(2026, 8, 4, 17),
          status: 'cancelled',
        ),
      ]);
      expect(container.read(employeeJobsTodayProvider), isEmpty);
    });

    test('counts per assignee', () async {
      final container = await _containerWith([
        _job(
          id: 'a',
          start: DateTime(2026, 8, 4, 9),
          end: DateTime(2026, 8, 4, 17),
          employeeIds: const ['e1', 'e2'],
        ),
        _job(
          id: 'stale',
          start: DateTime(2026, 7, 25, 9),
          end: DateTime(2026, 7, 25, 17),
          employeeIds: const ['e2'],
        ),
      ]);
      expect(container.read(employeeJobsTodayProvider), {'e1': 1, 'e2': 1});
    });
  });

  group('employeeTodayJobsProvider', () {
    test('agrees with the count on the row that opened it', () async {
      final container = await _containerWith([
        _job(
          id: 'today',
          start: DateTime(2026, 8, 4, 9),
          end: DateTime(2026, 8, 4, 17),
        ),
        _job(
          id: 'old',
          start: DateTime(2026, 7, 23, 9),
          end: DateTime(2026, 7, 23, 17),
        ),
      ]);
      final jobs = container.read(employeeTodayJobsProvider('e1'));
      expect(jobs.map((j) => j.id), ['today']);
      expect(jobs.length, container.read(employeeJobsTodayProvider)['e1']);
    });

    test('excludes another employee’s job', () async {
      final container = await _containerWith([
        _job(
          id: 'theirs',
          start: DateTime(2026, 8, 4, 9),
          end: DateTime(2026, 8, 4, 17),
          employeeIds: const ['e2'],
        ),
      ]);
      expect(container.read(employeeTodayJobsProvider('e1')), isEmpty);
    });

    test('orders by today’s clock time, not the stored instant', () async {
      final container = await _containerWith([
        // A 5-day run booked Aug 1, daily window 17:00-19:00. Its stored
        // startTime is Aug 1, so `orderBy('startTime')` floats it to the front
        // even though it is the LAST thing this person does today.
        _job(
          id: 'run',
          start: DateTime(2026, 8, 1, 17),
          end: DateTime(2026, 8, 5, 19),
        ),
        _job(
          id: 'morning',
          start: DateTime(2026, 8, 4, 8),
          end: DateTime(2026, 8, 4, 10),
        ),
      ]);
      expect(
        container.read(employeeTodayJobsProvider('e1')).map((j) => j.id),
        ['morning', 'run'],
      );
    });
  });
}
