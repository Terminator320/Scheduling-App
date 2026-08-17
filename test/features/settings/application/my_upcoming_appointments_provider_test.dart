import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/utils/current_day_provider.dart';
import 'package:scheduling/features/auth/application/active_user_identity_provider.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/settings/application/my_details_providers.dart';

/// Pinned so `myDetailsRangeProvider`'s window is stable. Nothing here filters
/// on the range — the family overrides below ignore their key — but a moving
/// clock would still fork a new family entry per run.
final _today = DateTime(2026, 8, 10);

AppointmentRecord _job({
  String id = 'a1',
  List<String> employeeIds = const ['me'],
}) => AppointmentRecord(
  id: id,
  title: 'Job $id',
  startTime: DateTime(2026, 8, 10, 9),
  endTime: DateTime(2026, 8, 10, 11),
  employeeIds: employeeIds,
);

/// Counts which of the two streams the provider actually opened.
///
/// The whole point of the role branch is that a technician NEVER reaches
/// `appointmentsInRangeProvider`, so "did this stream get built" is the
/// behaviour under test — an output assertion alone cannot see it.
class _Reads {
  int range = 0;
  int mine = 0;
}

class _RecordingLogger extends AppLogger {
  final warnings = <String>[];

  @override
  void warn(String message, [Object? error, StackTrace? stack]) {
    warnings.add(message);
  }
}

typedef _Harness = ({
  ProviderContainer container,
  _Reads reads,
  _RecordingLogger logger,
});

_Harness _harness({
  required ActiveUserIdentity? identity,
  List<AppointmentRecord> rangeJobs = const [],
  List<AppointmentRecord> myJobs = const [],
  Object? myJobsError,
}) {
  final reads = _Reads();
  final logger = _RecordingLogger();
  final container = ProviderContainer(
    overrides: [
      currentDayProvider.overrideWithValue(_today),
      loggerProvider.overrideWithValue(logger),
      activeUserIdentityProvider.overrideWith((ref) => identity),
      appointmentsInRangeProvider.overrideWith((ref, range) {
        reads.range++;
        return Stream.value(rangeJobs);
      }),
      myAppointmentsProvider.overrideWith((ref, key) {
        reads.mine++;
        if (myJobsError != null) {
          return Stream<List<AppointmentRecord>>.error(myJobsError);
        }
        return Stream.value(myJobs);
      }),
    ],
  );
  addTearDown(container.dispose);
  // AutoDispose state needs a listener to survive between reads.
  container.listen(myUpcomingAppointmentsProvider, (_, _) {});
  return (container: container, reads: reads, logger: logger);
}

void main() {
  test('an admin reads the business-wide range stream', () async {
    final h = _harness(
      identity: (role: 'admin', docId: 'me'),
      rangeJobs: [_job()],
    );
    await pumpEventQueue();

    expect(
      h.container.read(myUpcomingAppointmentsProvider).map((j) => j.id),
      ['a1'],
    );
    expect(h.reads.range, 1);
    expect(h.reads.mine, 0);
  });

  test('an employee never opens the business-wide range query', () async {
    // The shipped bug: the range query constrains `startTime` alone, and rules
    // evaluate a LIST query against its constraints — so `isAssignedEmployee`
    // rejected a technician's whole query and `?? const []` swallowed it. This
    // must fail if the role branch is ever collapsed back to one provider.
    final h = _harness(
      identity: (role: 'employee', docId: 'me'),
      rangeJobs: [_job()],
      myJobs: [_job(id: 'a2')],
    );
    await pumpEventQueue();

    expect(h.reads.range, 0);
    expect(h.reads.mine, 1);
    expect(
      h.container.read(myUpcomingAppointmentsProvider).map((j) => j.id),
      ['a2'],
    );
  });

  test('a null identity yields an empty list and opens no stream', () async {
    final h = _harness(identity: null, rangeJobs: [_job()], myJobs: [_job()]);
    await pumpEventQueue();

    expect(h.container.read(myUpcomingAppointmentsProvider), isEmpty);
    expect(h.reads.range, 0);
    expect(h.reads.mine, 0);
  });

  test('a job this person is not assigned to is filtered out', () async {
    final h = _harness(
      identity: (role: 'employee', docId: 'me'),
      myJobs: [
        _job(id: 'mine'),
        _job(id: 'theirs', employeeIds: const ['someone-else']),
      ],
    );
    await pumpEventQueue();

    expect(
      h.container.read(myUpcomingAppointmentsProvider).map((j) => j.id),
      ['mine'],
    );
  });

  test(
    'a failed stream yields an empty list and logs once under MYDET',
    () async {
      final h = _harness(
        identity: (role: 'employee', docId: 'me'),
        myJobsError: StateError('permission-denied'),
      );
      await pumpEventQueue();

      expect(h.container.read(myUpcomingAppointmentsProvider), isEmpty);
      expect(h.logger.warnings, hasLength(1));
      expect(h.logger.warnings.single, startsWith('MYDET'));
    },
  );
}
