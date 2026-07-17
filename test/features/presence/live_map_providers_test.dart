import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/presence/application/live_map_providers.dart';
import 'package:scheduling/features/presence/domain/models/presence_fix.dart';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late DateTime now;
  late StreamController<int> tick;

  setUp(() {
    tick = StreamController<int>.broadcast();
  });

  tearDown(() async {
    await tick.close();
  });

  ProviderContainer buildContainer({required DateTime fixUpdatedAt}) {
    final container = ProviderContainer(
      overrides: [
        allPresenceStreamProvider.overrideWith(
          (ref) => Stream.value([
            PresenceFix(
              userDocId: 'u1',
              lat: 1,
              lng: 2,
              updatedAt: fixUpdatedAt,
            ),
          ]),
        ),
        allUsersStreamProvider.overrideWith(
          (ref) => Stream.value(const [
            EmployeeRecord(id: 'u1', name: 'Alice', status: 'active'),
          ]),
        ),
        liveMapClockProvider.overrideWith(
          (ref) =>
              () => now,
        ),
        liveMapTickProvider.overrideWith((ref) => tick.stream),
      ],
    );
    // autoDispose family state must survive across reads (project rule).
    container.listen(liveMapPointsProvider, (_, _) {});
    container.listen(staleDocIdsProvider, (_, _) {});
    return container;
  }

  test(
    'a 30 s tick that flips no one leaves staleDocIds un-notified '
    '(identical set instance)',
    () async {
      now = DateTime(2026, 7, 17, 12);
      // Reported 10 min ago — comfortably fresh, and stays fresh.
      final container = buildContainer(
        fixUpdatedAt: now.subtract(const Duration(minutes: 10)),
      );
      addTearDown(container.dispose);
      await _settle();

      final initial = container.read(staleDocIdsProvider);
      expect(initial, isEmpty);

      var notifications = 0;
      final sub = container.listen(
        staleDocIdsProvider,
        (_, _) => notifications++,
      );
      addTearDown(sub.close);

      tick.add(0);
      await _settle();
      tick.add(1);
      await _settle();

      expect(notifications, 0, reason: 'membership unchanged must not notify');
      expect(
        identical(initial, container.read(staleDocIdsProvider)),
        isTrue,
        reason: 'same Set instance is returned when membership is unchanged',
      );
    },
  );

  test(
    'a tick crossing the 25-min boundary for one person notifies with the '
    'new membership',
    () async {
      final base = DateTime(2026, 7, 17, 12);
      now = base.add(const Duration(minutes: 10)); // fix is 10 min old: fresh
      final container = buildContainer(fixUpdatedAt: base);
      addTearDown(container.dispose);
      await _settle();

      expect(container.read(staleDocIdsProvider), isEmpty);

      var notifications = 0;
      final sub = container.listen(
        staleDocIdsProvider,
        (_, _) => notifications++,
      );
      addTearDown(sub.close);

      // Still fresh: no change.
      tick.add(0);
      await _settle();
      expect(notifications, 0);

      // Advance past the 25-min window, then tick.
      now = base.add(const Duration(minutes: 30));
      tick.add(1);
      await _settle();

      expect(notifications, 1);
      expect(container.read(staleDocIdsProvider), {'u1'});
    },
  );
}
