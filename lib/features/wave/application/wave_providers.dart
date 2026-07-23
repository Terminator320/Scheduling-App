import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/wave/data/wave_service.dart';
import 'package:scheduling/features/wave/domain/models/wave_connection.dart';

final waveServiceProvider = Provider<WaveService>(
  (ref) => WaveService(logger: ref.read(loggerProvider)),
);

/// Cached Wave connection; invalidate after Connect.
final waveConnectionProvider = FutureProvider<WaveConnection?>(
  (ref) => ref.read(waveServiceProvider).getConnection(),
);
