import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/wave/data/wave_service.dart';

final waveServiceProvider = Provider<WaveService>(
  (ref) => WaveService(logger: ref.read(loggerProvider)),
);
