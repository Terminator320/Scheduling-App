import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/assignee_availability_provider.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';

class _MockRepo extends Mock implements AppointmentsRepository {}

/// Stands in for `MainCalendarScreen`, the real owner of the open range.
final _testOwner = Object();

EmployeeRecord _person(String id, String name) => EmployeeRecord(
  id: id,
  name: name,
  status: 'active',
  jobTitle: JobTitle.technician,
);

final _marc = _person('e1', 'Marc Tremblay');
final _nadia = _person('e2', 'Nadia Berger');

AppointmentRecord _job({
  required DateTime start, required DateTime end, String id = 'job-1',
  List<String> employeeIds = const ['e1'],
}) => AppointmentRecord(
  id: id,
  title: 'Job',
  startTime: start,
  endTime: end,
  employeeIds: employeeIds,
  employeeNames: const ['Marc Tremblay'],
);

void main() {
  setUpAll(() {
    registerFallbackValue(<String>[]);
    registerFallbackValue(DateTime(2026));
  });

  late _MockRepo repository;

  setUp(() {
    repository = _MockRepo();
    when(
      () => repository.findClashingAppointments(
        employeeIds: any(named: 'employeeIds'),
        start: any(named: 'start'),
        end: any(named: 'end'),
        excludeAppointmentId: any(named: 'excludeAppointmentId'),
      ),
    ).thenAnswer((_) async => const []);
  });

  /// A container with the roster and, optionally, an open calendar range whose
  /// stream holds [jobs].
  Future<ProviderContainer> makeContainer({
    List<EmployeeRecord> roster = const [],
    AppointmentDateRange? openRange,
    List<AppointmentRecord> jobs = const [],
  }) async {
    final container = ProviderContainer(
      // main.dart disables Riverpod 3's exponential retry; without the same
      // override an errored provider's `.future` never completes and the test
      // times out at 30s instead of failing.
      retry: (retryCount, error) => null,
      overrides: [
        appointmentsRepositoryProvider.overrideWithValue(repository),
        employeesStreamProvider.overrideWith((_) => Stream.value(roster)),
        if (openRange != null)
          appointmentsInRangeProvider(
            openRange,
          ).overrideWith((_) => Stream.value(jobs)),
      ],
    );
    addTearDown(container.dispose);
    if (openRange != null) {
      // `publish` takes an owner token so a second screen can't clobber the
      // range the calendar is holding open; the test stands in as that owner.
      container
          .read(openCalendarRangeProvider.notifier)
          .publish(_testOwner, openRange);
    }
    // `assignableEmployeesProvider` reads the roster stream's `.value`, which
    // is null until the first emission lands - without settling it here every
    // case would see an empty roster and short-circuit before any query.
    container.listen(employeesStreamProvider, (_, _) {});
    await container.read(employeesStreamProvider.future);
    if (openRange != null) {
      // Same reason: the live path reduces whatever the range stream has
      // ALREADY emitted, so an unsettled one reads as "no jobs" and the live
      // case would pass for the wrong reason.
      container.listen(appointmentsInRangeProvider(openRange), (_, _) {});
      await container.read(appointmentsInRangeProvider(openRange).future);
    }
    return container;
  }

  group('assigneeAvailabilityProvider', () {
    test('an empty roster answers nothing and never queries', () async {
      final container = await makeContainer();
      final result = await container.read(
        assigneeAvailabilityProvider((
          start: DateTime(2026, 8, 26, 9),
          end: DateTime(2026, 8, 26, 12),
          excludeAppointmentId: null,
        )).future,
      );

      expect(result, isEmpty);
      verifyNever(
        () => repository.findClashingAppointments(
          employeeIds: any(named: 'employeeIds'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          excludeAppointmentId: any(named: 'excludeAppointmentId'),
        ),
      );
    });

    test('a span INSIDE the open range reduces the live stream, costing no '
        'extra read', () async {
      final open = AppointmentDateRange(
        start: DateTime(2026, 8),
        end: DateTime(2026, 9),
      );
      final container = await makeContainer(
        roster: [_marc, _nadia],
        openRange: open,
        jobs: [
          _job(
            start: DateTime(2026, 8, 26, 8),
            end: DateTime(2026, 8, 26, 12),
          ),
        ],
      );

      final result = await container.read(
        assigneeAvailabilityProvider((
          start: DateTime(2026, 8, 26, 9),
          end: DateTime(2026, 8, 26, 11),
          excludeAppointmentId: null,
        )).future,
      );

      expect(result.keys, ['e1']);
      verifyNever(
        () => repository.findClashingAppointments(
          employeeIds: any(named: 'employeeIds'),
          start: any(named: 'start'),
          end: any(named: 'end'),
          excludeAppointmentId: any(named: 'excludeAppointmentId'),
        ),
      );
    });

    test(
      'a span OUTSIDE the open range falls back to a one-shot query',
      () async {
        // The branch CLAUDE.md calls out by name: without it a date past the
        // open range makes every clash invisible and the picker silently
        // reports everyone as free — no error, no log, and visually identical
        // to "nobody is busy".
        final open = AppointmentDateRange(
          start: DateTime(2026, 8),
          end: DateTime(2026, 9),
        );
        when(
          () => repository.findClashingAppointments(
            employeeIds: any(named: 'employeeIds'),
            start: any(named: 'start'),
            end: any(named: 'end'),
            excludeAppointmentId: any(named: 'excludeAppointmentId'),
          ),
        ).thenAnswer(
          (_) async => [
            _job(
              start: DateTime(2026, 11, 4, 8),
              end: DateTime(2026, 11, 4, 12),
            ),
          ],
        );

        final container = await makeContainer(
          roster: [_marc, _nadia],
          openRange: open,
        );

        final result = await container.read(
          assigneeAvailabilityProvider((
            // Well past the open range's end.
            start: DateTime(2026, 11, 4, 9),
            end: DateTime(2026, 11, 4, 11),
            excludeAppointmentId: null,
          )).future,
        );

        expect(result.keys, ['e1'], reason: 'the clash must still be visible');
        verify(
          () => repository.findClashingAppointments(
            employeeIds: any(named: 'employeeIds'),
            start: any(named: 'start'),
            end: any(named: 'end'),
            excludeAppointmentId: any(named: 'excludeAppointmentId'),
          ),
        ).called(1);
      },
    );

    test(
      'with NO open range at all it falls back rather than answering free',
      () async {
        // The admin-only publisher means a technician never opens that stream.
        when(
          () => repository.findClashingAppointments(
            employeeIds: any(named: 'employeeIds'),
            start: any(named: 'start'),
            end: any(named: 'end'),
            excludeAppointmentId: any(named: 'excludeAppointmentId'),
          ),
        ).thenAnswer(
          (_) async => [
            _job(
              start: DateTime(2026, 8, 26, 8),
              end: DateTime(2026, 8, 26, 12),
            ),
          ],
        );

        final container = await makeContainer(roster: [_marc, _nadia]);

        final result = await container.read(
          assigneeAvailabilityProvider((
            start: DateTime(2026, 8, 26, 9),
            end: DateTime(2026, 8, 26, 11),
            excludeAppointmentId: null,
          )).future,
        );

        expect(result.keys, ['e1']);
        verify(
          () => repository.findClashingAppointments(
            employeeIds: any(named: 'employeeIds'),
            start: any(named: 'start'),
            end: any(named: 'end'),
            excludeAppointmentId: any(named: 'excludeAppointmentId'),
          ),
        ).called(1);
      },
    );

    test(
      'a span ending exactly ON the range end still uses the live stream',
      () async {
        // `_covers` is inclusive at both ends; an off-by-one here would send an
        // in-window span down the paid path on every keystroke.
        final open = AppointmentDateRange(
          start: DateTime(2026, 8),
          end: DateTime(2026, 9),
        );
        final container = await makeContainer(
          roster: [_marc],
          openRange: open,
        );

        await container.read(
          assigneeAvailabilityProvider((
            start: DateTime(2026, 8),
            end: DateTime(2026, 9),
            excludeAppointmentId: null,
          )).future,
        );

        verifyNever(
          () => repository.findClashingAppointments(
            employeeIds: any(named: 'employeeIds'),
            start: any(named: 'start'),
            end: any(named: 'end'),
            excludeAppointmentId: any(named: 'excludeAppointmentId'),
          ),
        );
      },
    );

    test(
      'a span starting one microsecond before the range falls back',
      () async {
        final open = AppointmentDateRange(
          start: DateTime(2026, 8),
          end: DateTime(2026, 9),
        );
        final container = await makeContainer(roster: [_marc], openRange: open);

        await container.read(
          assigneeAvailabilityProvider((
            start: DateTime(
              2026,
              8,
            ).subtract(const Duration(microseconds: 1)),
            end: DateTime(2026, 8, 2),
            excludeAppointmentId: null,
          )).future,
        );

        verify(
          () => repository.findClashingAppointments(
            employeeIds: any(named: 'employeeIds'),
            start: any(named: 'start'),
            end: any(named: 'end'),
            excludeAppointmentId: any(named: 'excludeAppointmentId'),
          ),
        ).called(1);
      },
    );

    test('only ASSIGNABLE crew are asked about', () async {
      const dispatcher = EmployeeRecord(
        id: 'e9',
        name: 'Ines Colas',
        status: 'active',
        jobTitle: JobTitle.dispatcher,
      );
      final container = await makeContainer(roster: [_marc, dispatcher]);

      await container.read(
        assigneeAvailabilityProvider((
          start: DateTime(2026, 8, 26, 9),
          end: DateTime(2026, 8, 26, 11),
          excludeAppointmentId: null,
        )).future,
      );

      final captured =
          verify(
                () => repository.findClashingAppointments(
                  employeeIds: captureAny(named: 'employeeIds'),
                  start: any(named: 'start'),
                  end: any(named: 'end'),
                  excludeAppointmentId: any(named: 'excludeAppointmentId'),
                ),
              ).captured.single
              as List<String>;
      expect(captured, contains('e1'));
      expect(captured, isNot(contains('e9')));
    });
  });
}
