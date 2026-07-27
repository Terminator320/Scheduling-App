import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/presence/application/presence_sync_controller.dart';
import 'package:scheduling/features/presence/domain/live_map_aggregator.dart';
import 'package:scheduling/features/presence/domain/models/presence_fix.dart';


final allPresenceStreamProvider = StreamProvider.autoDispose<List<PresenceFix>>(
  (ref) => ref.watch(presenceRepositoryProvider).watchAllPresence(),
);

final liveMapClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);


final liveMapTickProvider = StreamProvider.autoDispose<int>(
  (ref) => Stream<int>.periodic(const Duration(seconds: 30), (i) => i),
);


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
