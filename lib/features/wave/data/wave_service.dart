import 'package:cloud_functions/cloud_functions.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/wave/domain/models/wave_connection.dart';
import 'package:scheduling/features/wave/domain/models/wave_import_schedule.dart';
import 'package:scheduling/features/wave/domain/wave_error_mapper.dart';

class WaveService {
  WaveService({FirebaseFunctions? functions, AppLogger? logger})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
      _logger = logger ?? AppLogger();

  final FirebaseFunctions _functions;
  final AppLogger _logger;

  /// Connect to Wave; business resolved server-side.
  Future<WaveConnection> bootstrap() async {
    final HttpsCallableResult<dynamic> result;
    try {
      result = await _functions
          .httpsCallable(
            'waveBootstrap',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call(<String, dynamic>{});
    } catch (e, st) {
      _logger.warn('WAVE-BOOT waveBootstrap callable failed', e, st);
      throw WaveErrorMapper.map(e);
    }

    try {
      // NOTE: `as Map?` — Android callables return Map<dynamic, dynamic>.
      final data = (result.data as Map?)?.cast<String, dynamic>() ?? const {};
      return WaveConnection.fromMap(data);
    } catch (e, st) {
      _logger.warn('WAVE-BOOT waveBootstrap response parse failed', e, st);
      throw WaveErrorMapper.map(e);
    }
  }

  /// Read persisted Wave connection; backs "Connected to X" status display.
  Future<WaveConnection?> getConnection() async {
    final HttpsCallableResult<dynamic> result;
    try {
      result = await _functions
          .httpsCallable(
            'waveGetConnection',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call(<String, dynamic>{});
    } catch (e, st) {
      _logger.warn('WAVE-CONN waveGetConnection callable failed', e, st);
      throw WaveErrorMapper.map(e);
    }

    try {
      // NOTE: `as Map?` — Android callables return Map<dynamic, dynamic>.
      final data = (result.data as Map?)?.cast<String, dynamic>() ?? const {};
      if (data['connected'] != true) return null;
      return WaveConnection.fromMap(data);
    } catch (e, st) {
      _logger.warn('WAVE-CONN waveGetConnection response parse failed', e, st);
      throw WaveErrorMapper.map(e);
    }
  }

  Future<WaveImportSummary> importCustomers() async {
    final HttpsCallableResult<dynamic> result;
    try {
      result = await _functions
          .httpsCallable(
            'waveImportCustomers',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call(<String, dynamic>{});
    } catch (e, st) {
      _logger.warn('WAVE-CUST waveImportCustomers callable failed', e, st);
      throw WaveErrorMapper.map(e);
    }

    try {
      // NOTE: `as Map?` — Android callables return Map<dynamic, dynamic>.
      final data = (result.data as Map?)?.cast<String, dynamic>() ?? const {};
      return WaveImportSummary.fromMap(data);
    } catch (e, st) {
      _logger.warn(
        'WAVE-CUST waveImportCustomers response parse failed',
        e,
        st,
      );
      throw WaveErrorMapper.map(e);
    }
  }

  /// Set automatic-import cadence.
  Future<void> setImportSchedule(WaveImportSchedule schedule) async {
    try {
      await _functions
          .httpsCallable(
            'waveSetImportSchedule',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call<void>(<String, dynamic>{'schedule': schedule.raw});
    } catch (e, st) {
      _logger.warn('WAVE-SCHED waveSetImportSchedule callable failed', e, st);
      throw WaveErrorMapper.map(e);
    }
  }
}
