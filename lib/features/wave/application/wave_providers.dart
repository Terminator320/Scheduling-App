import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/wave/data/wave_service.dart';
import 'package:scheduling/features/wave/domain/models/wave_connection.dart';

final waveServiceProvider = Provider<WaveService>(
  (ref) => WaveService(logger: ref.read(loggerProvider)),
);

/// Cached server-side Wave connection status. Fetched once via the admin-only
/// `waveGetConnection` callable and shared across Settings mounts, so opening
/// Settings repeatedly doesn't re-hit the function. Invalidate it after a
/// successful Connect to refresh the persisted status.
final waveConnectionProvider = FutureProvider<WaveConnection?>(
  (ref) => ref.read(waveServiceProvider).getConnection(),
);
