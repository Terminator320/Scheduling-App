import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/utils/current_day_provider.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/settings/application/my_details_providers.dart';

AppointmentRecord _job(DateTime start, {String status = 'pending'}) =>
    AppointmentRecord(
      id: 'a1',
      title: 'Job',
      startTime: start,
      endTime: start.add(const Duration(hours: 2)),
      status: status,
      employeeIds: const ['me'],
    );

const _fiveDayWeek = [false, true, true, true, true, true, false];
const _mondayOff = [false, false, true, true, true, true, false];

void main() {
  // The conflict provider reduces `myUpcomingAppointmentsProvider`, so
  // overriding that one keeps these tests free of Firestore and of the
  // identity chain — the reduction is what is under test here.
  // Pin the clock. myDetailsRangeProvider builds its window off
  // currentDayProvider, so without this the fixtures below rot: they passed on
  // the day they were written and then fell out of the window, which made the
  // "reports nothing" cases pass for the wrong reason.
  final today = DateTime(2026, 8, 10);

  ProviderContainer containerWith(List<AppointmentRecord> jobs) {
    final container = ProviderContainer(
      overrides: [
        currentDayProvider.overrideWithValue(today),
        myUpcomingAppointmentsProvider.overrideWith((ref) => jobs),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Set<int> conflictsFor(
    ProviderContainer container,
    List<bool> next,
  ) {
    final provider = myAvailabilityConflictProvider(
      AvailabilityChange(
        previousWorkingDays: _fiveDayWeek,
        nextWorkingDays: next,
      ),
    );
    // AutoDispose families need a listener or the state races teardown.
    container.listen(provider, (_, _) {});
    return container.read(provider);
  }

  test('reports Monday when Monday is switched off and holds a job', () {
    // 2026-08-10 is a Monday; workingDays is Sunday-indexed, so Monday is 1.
    final container = containerWith([_job(DateTime(2026, 8, 10, 9))]);

    expect(conflictsFor(container, _mondayOff), {1});
  });

  test('reports nothing when the day being switched off is free', () {
    final container = containerWith([_job(DateTime(2026, 8, 12, 9))]);

    expect(conflictsFor(container, _mondayOff), isEmpty);
  });

  test('reports nothing when no day is switched off', () {
    final container = containerWith([_job(DateTime(2026, 8, 10, 9))]);

    expect(conflictsFor(container, _fiveDayWeek), isEmpty);
  });

  test('a cancelled job is not a conflict', () {
    final container = containerWith([
      _job(DateTime(2026, 8, 10, 9), status: 'cancelled'),
    ]);

    expect(conflictsFor(container, _mondayOff), isEmpty);
  });

  test('the change value is keyed by content, not identity', () {
    // The family key must compare the LISTS, or a rebuild that produces an
    // equal-but-new list forks a fresh provider entry every frame.
    const a = AvailabilityChange(
      previousWorkingDays: _fiveDayWeek,
      nextWorkingDays: _mondayOff,
    );
    final b = AvailabilityChange(
      previousWorkingDays: List<bool>.from(_fiveDayWeek),
      nextWorkingDays: List<bool>.from(_mondayOff),
    );

    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });
}
