import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

class _MockAppointmentsRepo extends Mock implements AppointmentsRepository {}

class _RecordingLogger extends AppLogger {
  final List<String> warnings = [];

  @override
  void warn(String message, [Object? error, StackTrace? stack]) =>
      warnings.add(message);
}

AppointmentRecord _appt(String id) => AppointmentRecord(
  id: id,
  title: 'Job $id',
  startTime: DateTime(2026, 7, 8, 9),
  endTime: DateTime(2026, 7, 8, 10),
  employeeIds: const ['e1'],
);

/// Runs [appointmentsOrEmpty] inside a real provider body, which is where it
/// lives in production, and returns the list plus the logger it wrote to.
({List<AppointmentRecord> records, _RecordingLogger logger}) _run(
  AsyncValue<List<AppointmentRecord>> input,
) {
  final logger = _RecordingLogger();
  final probe = Provider<List<AppointmentRecord>>(
    (ref) => appointmentsOrEmpty(ref, input, 'APPT-TEST'),
  );
  final container = ProviderContainer(
    overrides: [loggerProvider.overrideWithValue(logger)],
  );
  addTearDown(container.dispose);
  return (records: container.read(probe), logger: logger);
}

void main() {
  late _MockAppointmentsRepo repo;

  setUp(() {
    repo = _MockAppointmentsRepo();
    when(
      () => repo.watchInRange(any()),
    ).thenAnswer((_) => Stream.value(const <AppointmentRecord>[]));
    when(
      () => repo.watchForEmployeeInRange(any(), any()),
    ).thenAnswer((_) => Stream.value(const <AppointmentRecord>[]));
  });

  group('appointmentsOrEmpty', () {
    test('passes a settled list straight through', () {
      expect(
        _run(AsyncValue.data([_appt('a1')])).records.map((a) => a.id),
        ['a1'],
      );
    });

    test('degrades a failed query to an empty list', () {
      expect(
        _run(
          AsyncValue<List<AppointmentRecord>>.error(
            Exception('permission-denied'),
            StackTrace.empty,
          ),
        ).records,
        isEmpty,
      );
    });

    test('records the failure under the caller tag', () {
      // The whole point of the helper: a rejected listener must not be
      // indistinguishable from a day with genuinely no work AND unlogged.
      expect(
        _run(
          AsyncValue<List<AppointmentRecord>>.error(
            Exception('permission-denied'),
            StackTrace.empty,
          ),
        ).logger.warnings,
        ['APPT-TEST'],
      );
    });

    test('a still-loading query logs nothing', () {
      expect(
        _run(
          const AsyncValue<List<AppointmentRecord>>.loading(),
        ).logger.warnings,
        isEmpty,
      );
    });
  });

  group('keepWarmWithGrace', () {
    test('a provider is reused after its last watcher leaves', () async {
      var builds = 0;
      final warm = Provider.autoDispose<int>((ref) {
        keepWarmWithGrace(ref);
        return ++builds;
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.listen(warm, (_, _) {}).close();
      await Future<void>.delayed(Duration.zero);

      // A rebuild here is the dashboard re-issuing ~2000 document reads on a
      // drill-in-and-back.
      expect(container.read(warm), 1);
    });

    test('without the grace the same provider rebuilds', () async {
      var builds = 0;
      final cold = Provider.autoDispose<int>((ref) => ++builds);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.listen(cold, (_, _) {}).close();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(cold), 2);
    });
  });

  group('auth bootstrap', () {
    // Any stable month window works here; the behavior under test is the auth
    // bootstrap gate, not the exact calendar arithmetic.
    final range = AppointmentDateRange(
      start: DateTime(2026, 7),
      end: DateTime(2026, 7, 31, 23, 59),
    );

    test('appointmentsInRange waits for auth uid before opening the query', () async {
      final auth = StreamController<String?>();
      addTearDown(auth.close);
      final container = ProviderContainer(
        overrides: [
          authUidProvider.overrideWith((ref) => auth.stream),
          appointmentsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      container.listen(appointmentsInRangeProvider(range), (_, _) {});
      await pumpEventQueue();
      verifyNever(() => repo.watchInRange(any()));

      auth.add('uid-1');
      await pumpEventQueue();

      verify(() => repo.watchInRange(range)).called(1);
    });

    test('myAppointments waits for auth uid before opening the query', () async {
      final auth = StreamController<String?>();
      addTearDown(auth.close);
      final container = ProviderContainer(
        overrides: [
          authUidProvider.overrideWith((ref) => auth.stream),
          appointmentsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      final key = (employeeId: 'e1', range: range);

      container.listen(myAppointmentsProvider(key), (_, _) {});
      await pumpEventQueue();
      verifyNever(() => repo.watchForEmployeeInRange(any(), any()));

      auth.add('uid-1');
      await pumpEventQueue();

      verify(() => repo.watchForEmployeeInRange('e1', range)).called(1);
    });
  });
}
