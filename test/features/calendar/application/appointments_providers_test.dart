import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

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
}
