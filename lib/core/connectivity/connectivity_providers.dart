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

/// True only on a confirmed "no connection at all" report — unknown states
/// (initial check still running, plugin error) count as online so the
/// offline banner never flashes without a real signal.
final isOfflineProvider = Provider<bool>((ref) {
  final results = ref.watch(connectivityResultsProvider).value;
  if (results == null) return false;
  return results.isEmpty ||
      results.every((result) => result == ConnectivityResult.none);
});
