import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/dashboard/application/dashboard_providers.dart';

/// The two halves of the dashboard window overlap by a fortnight — each query
/// reaches back to its own `fetchStart` to catch a run already under way — so
/// the provider must merge them by doc id, live winning. `mergeById` is
/// unit-tested on its own; this pins the WIRING, which is what a
/// `[...live, ...history]` regression would break while the aggregator's own
/// tests stayed green.
final _now = DateTime(2026, 7, 8, 12);

AppointmentRecord _appt({
  required String id,
  required DateTime start,
  String status = 'pending',
}) => AppointmentRecord(
  id: id,
  title: 'Job $id',
  startTime: start,
  endTime: start.add(const Duration(hours: 1)),
  status: status,
  employeeIds: const ['e1'],
);

ProviderContainer _container({
  List<AppointmentRecord> live = const [],
  List<AppointmentRecord> history = const [],
}) => ProviderContainer(
  overrides: [
    dashboardClockProvider.overrideWithValue(() => _now),
    appointmentsInRangeProvider.overrideWith((_, _) => Stream.value(live)),
    dashboardHistoryProvider.overrideWith((_) async => history),
  ],
)..listen(dashboardRecordsProvider, (_, _) {});

Future<List<AppointmentRecord>> _records(ProviderContainer container) async {
  await container.read(dashboardHistoryProvider.future);
  await container.read(
    appointmentsInRangeProvider(
      container.read(dashboardLiveRangeProvider),
    ).future,
  );
  return container.read(dashboardRecordsProvider).requireValue;
}

void main() {
  test('an appointment in both halves is counted once', () async {
    final overlapping = _appt(id: 'a1', start: DateTime(2026, 7, 7, 9));
    final container = _container(
      live: [overlapping],
      history: [overlapping],
    );
    addTearDown(container.dispose);

    expect(await _records(container), hasLength(1));
  });

  test('the live copy wins a collision, not the settled one', () async {
    final container = _container(
      live: [
        _appt(id: 'a1', start: DateTime(2026, 7, 7, 9), status: 'done'),
      ],
      // The settled copy still carries the pre-completion status.
      history: [_appt(id: 'a1', start: DateTime(2026, 7, 7, 9))],
    );
    addTearDown(container.dispose);

    expect((await _records(container)).single.status, 'done');
  });

  test('records unique to either half all survive the merge', () async {
    final container = _container(
      live: [_appt(id: 'a1', start: DateTime(2026, 7, 9, 9))],
      history: [_appt(id: 'a2', start: DateTime(2026, 6, 1, 9))],
    );
    addTearDown(container.dispose);

    expect(
      (await _records(container)).map((a) => a.id),
      containsAll(<String>['a1', 'a2']),
    );
  });
}
