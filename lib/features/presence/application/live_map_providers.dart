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
