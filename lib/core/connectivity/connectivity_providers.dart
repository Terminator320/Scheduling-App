import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live connectivity as reported by the platform, seeded with an initial
/// check so state is known at startup instead of waiting for the first change.
final connectivityResultsProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) async* {
  final connectivity = Connectivity();
  yield await connectivity.checkConnectivity();
  yield* connectivity.onConnectivityChanged;
});

/// True only when we get a confirmed "no connection at all" report. Unknown
/// states — like the initial check still running, or a plugin error — count
/// as online, so the offline banner never flashes without a real signal.
final isOfflineProvider = Provider<bool>((ref) {
  final results = ref.watch(connectivityResultsProvider).value;
  return results != null &&
      (results.isEmpty ||
          results.every((result) => result == ConnectivityResult.none));
});
