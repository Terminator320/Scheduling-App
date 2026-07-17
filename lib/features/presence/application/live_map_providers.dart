import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';
import 'package:scheduling/features/presence/domain/live_map_aggregator.dart';
import 'package:scheduling/features/presence/domain/models/presence_fix.dart';

/// Live feed of every staff member's last-known fix (admin collection-group
/// read). autoDispose so leaving the map tab — where the screen stops watching
/// it — tears the Firestore listener down (see the pause-when-hidden gate in
/// `live_map_screen.dart`).
final allPresenceStreamProvider = StreamProvider.autoDispose<List<PresenceFix>>(
  (ref) => ref.watch(presenceRepositoryProvider).watchAllPresence(),
);

/// Injectable clock so tests pin "now" for staleness / freshness (twin of
/// `dashboardClockProvider`).
final liveMapClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// 30 s heartbeat that re-renders freshness labels and re-evaluates staleness
/// while the map tab is visible. autoDispose — the screen un-watches it when
/// the tab is hidden, so the ticker stops.
final liveMapTickProvider = StreamProvider.autoDispose<int>(
  (ref) => Stream<int>.periodic(const Duration(seconds: 30), (i) => i),
);

/// Presence fixes joined with the active-staff roster into plotted points.
/// Same reduction shape as `dashboardStatsProvider`: first error wins, any
/// loading source keeps it loading.
final liveMapPointsProvider =
    Provider.autoDispose<AsyncValue<List<StaffMapPoint>>>((ref) {
      final fixes = ref.watch(allPresenceStreamProvider);
      final users = ref.watch(allUsersStreamProvider);

      final sources = <AsyncValue<Object?>>[fixes, users];
      for (final source in sources) {
        if (source.hasError) {
          return AsyncValue.error(
            source.error!,
            source.stackTrace ?? StackTrace.current,
          );
        }
      }
      if (sources.any((source) => source.isLoading)) {
        return const AsyncValue.loading();
      }
      return AsyncValue.data(
        LiveMapAggregator.join(
          fixes: fixes.requireValue,
          users: users.requireValue,
        ),
      );
    });

/// Container-scoped holder for the set-equality memo below — a `Provider` so
/// each `ProviderContainer` (each test) gets its own cache.
final _staleIdsMemoProvider = Provider.autoDispose((ref) => _StaleIdsMemo());

class _StaleIdsMemo {
  Set<String>? value;
}

/// The user doc-ids whose latest fix is currently stale (> 25 min).
///
/// Set-equality notification mechanism (chosen to be BOTH correct in
/// riverpod 3.3.1 AND testable): a `Provider`'s `updateShouldNotify` is
/// `previous != next`, so returning the IDENTICAL previous `Set` instance when
/// membership is unchanged (`setEquals`) makes downstream watchers skip their
/// rebuild. This is the same content-equality idiom the employee lookup maps
/// use (`employees_providers.dart`) — no wrapper class needed. A 30 s tick that
/// flips nobody recomputes here but returns the same instance, so the marker
/// assembly is never notified; only the freshness labels (which watch the tick
/// directly) re-render.
final staleDocIdsProvider = Provider.autoDispose<Set<String>>((ref) {
  ref.watch(liveMapTickProvider); // drives the 30 s recompute
  final now = ref.watch(liveMapClockProvider)();
  final points =
      ref.watch(liveMapPointsProvider).value ?? const <StaffMapPoint>[];
  final memo = ref.watch(_staleIdsMemoProvider);
  final next = <String>{
    for (final point in points)
      if (LiveMapAggregator.isStale(point.updatedAt, now)) point.userDocId,
  };
  final previous = memo.value;
  if (previous != null && setEquals(previous, next)) return previous;
  memo.value = next;
  return next;
});
