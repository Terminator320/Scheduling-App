import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/dashboard/application/dashboard_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/policies/work_schedule_policy.dart';

/// Fixed clock: Wednesday 2026-07-08, noon. The live window is therefore
/// Mon 2026-07-06 → Mon 2026-07-13, which contains exactly one Saturday
/// (the 11th) and one Sunday (the 12th) — the two days the default roster
/// has switched off.
final _now = DateTime(2026, 7, 8, 12);

/// Saturday, inside the live window and outside the default working days.
final _saturday = DateTime(2026, 7, 11, 9);

/// Thursday, inside the window and squarely on a working day.
final _thursday = DateTime(2026, 7, 9, 9);

EmployeeRecord _employee(String id, {List<bool>? workingDays}) =>
    EmployeeRecord(
      id: id,
      name: 'Person $id',
      email: '$id@example.com',
      status: 'active',
      workingDays: workingDays ?? kDefaultWorkingDays,
    );

AppointmentRecord _appt({
  required String id,
  required DateTime start,
  DateTime? end,
  String status = 'pending',
  List<String> employeeIds = const ['e1'],
}) => AppointmentRecord(
  id: id,
  title: 'Job $id',
  startTime: start,
  endTime: end ?? start.add(const Duration(hours: 1)),
  status: status,
  employeeIds: employeeIds,
);

ProviderContainer _container({
  List<AppointmentRecord> appointments = const [],
  List<EmployeeRecord> employees = const [],
  Object? appointmentsError,
  bool appointmentsLoading = false,
}) {
  // The listens keep AutoDispose state alive across reads.
  return ProviderContainer(
      overrides: [
        dashboardClockProvider.overrideWithValue(() => _now),
        appointmentsInRangeProvider.overrideWith((_, _) {
          if (appointmentsError != null) {
            return Stream<List<AppointmentRecord>>.error(appointmentsError);
          }
          if (appointmentsLoading) {
            return const Stream<List<AppointmentRecord>>.empty();
          }
          return Stream.value(appointments);
        }),
        // The settled weeks are a one-shot read; these tests feed the live half.
        dashboardHistoryProvider.overrideWith((_) async => const []),
        employeesStreamProvider.overrideWith((_) => Stream.value(employees)),
      ],
    )
    ..listen(dashboardLiveRangeProvider, (_, _) {})
    ..listen(dashboardRecordsProvider, (_, _) {})
    ..listen(availabilityConflictsProvider, (_, _) {});
}

/// Both halves of the merge plus the roster arrive asynchronously, so a bare
/// read straight after construction only ever sees `loading`.
Future<void> _settle(ProviderContainer container) async {
  await container.read(dashboardHistoryProvider.future);
  await container.read(
    appointmentsInRangeProvider(
      container.read(dashboardLiveRangeProvider),
    ).future,
  );
  await container.read(employeesStreamProvider.future);
}

List<AvailabilityConflict> _conflicts(ProviderContainer container) =>
    container.read(availabilityConflictsProvider).requireValue;

void main() {
  test('the live window really does span the Saturday these tests book', () {
    // Anchors every case below: if the window ever stops covering the 11th,
    // the conflict assertions would pass vacuously as "All clear".
    final container = _container();
    addTearDown(container.dispose);

    final range = container.read(dashboardLiveRangeProvider);
    expect(range.start, DateTime(2026, 7, 6));
    expect(range.end, DateTime(2026, 7, 13));
    expect(_saturday.isAfter(range.start), isTrue);
    expect(_saturday.isBefore(range.end), isTrue);
  });

  test('names the assignee who holds the work, not a peer', () async {
    // The wiring bug this guards: grouping by the wrong key attributes one
    // person's weekend job to whoever happens to sort first.
    final container = _container(
      appointments: [
        _appt(id: 'a1', start: _saturday, employeeIds: const ['e2']),
      ],
      employees: [_employee('e1'), _employee('e2')],
    );
    addTearDown(container.dispose);
    await _settle(container);

    expect(_conflicts(container), hasLength(1));
    expect(_conflicts(container).single.employee.id, 'e2');
    expect(_conflicts(container).single.days, {6});
  });

  test('lists every assignee of a shared job', () async {
    final container = _container(
      appointments: [
        _appt(id: 'a1', start: _saturday, employeeIds: const ['e1', 'e2']),
      ],
      employees: [_employee('e1'), _employee('e2')],
    );
    addTearDown(container.dispose);
    await _settle(container);

    expect(
      _conflicts(container).map((c) => c.employee.id),
      containsAll(<String>['e1', 'e2']),
    );
  });

  test('an employee booked only on working days is omitted entirely', () async {
    // "All clear" must mean no conflicts, so a clear person is absent from the
    // list rather than present with an empty day set.
    final container = _container(
      appointments: [_appt(id: 'a1', start: _thursday)],
      employees: [_employee('e1')],
    );
    addTearDown(container.dispose);
    await _settle(container);

    expect(_conflicts(container), isEmpty);
  });

  test('a run counts the day it works, not just its first morning', () async {
    // Friday → Saturday. Scoping through the day-slice owner is what catches
    // the Saturday; a weekday derived from `startTime` would read Friday and
    // report all clear.
    final container = _container(
      appointments: [
        _appt(
          id: 'a1',
          start: DateTime(2026, 7, 10, 9),
          end: DateTime(2026, 7, 11, 17),
        ),
      ],
      employees: [_employee('e1')],
    );
    addTearDown(container.dispose);
    await _settle(container);

    expect(_conflicts(container).single.days, contains(6));
  });

  test('a cancelled weekend job is not a conflict', () async {
    final container = _container(
      appointments: [_appt(id: 'a1', start: _saturday, status: 'cancelled')],
      employees: [_employee('e1')],
    );
    addTearDown(container.dispose);
    await _settle(container);

    expect(_conflicts(container), isEmpty);
  });

  test(
    'a failed appointments read surfaces as an error, not as all clear',
    () async {
      // The dangerous shape: an empty list and a failed read both render as an
      // absent amber note, so the section would quietly claim the roster is fine.
      final container = _container(
        employees: [_employee('e1')],
        appointmentsError: StateError('denied'),
      );
      addTearDown(container.dispose);
      await pumpEventQueue();

      final conflicts = container.read(availabilityConflictsProvider);
      expect(conflicts.hasError, isTrue);
      expect(conflicts.hasValue, isFalse);
    },
  );

  test('an unsettled appointments read stays loading', () {
    final container = _container(
      employees: [_employee('e1')],
      appointmentsLoading: true,
    );
    addTearDown(container.dispose);

    expect(container.read(availabilityConflictsProvider).isLoading, isTrue);
  });
}
