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

  /// Connects to Wave. The target business is resolved server-side from the
  /// `WAVE_BUSINESS_NAME` secret, so the client sends no selector.
  Future<WaveConnection> bootstrap() async {
    final HttpsCallableResult<dynamic> result;
    try {
      result = await _functions
          .httpsCallable('waveBootstrap')
          .call(<String, dynamic>{});
    } catch (e, st) {
      _logger.warn('WAVE-BOOT waveBootstrap callable failed', e, st);
      throw WaveErrorMapper.map(e);
    }

    try {
      // NOTE: loose `as Map?` required — Android callables return
      // Map<dynamic, dynamic>, not Map<String, dynamic>.
      final data = (result.data as Map?)?.cast<String, dynamic>() ?? const {};
      return WaveConnection.fromMap(data);
    } catch (e, st) {
      _logger.warn('WAVE-BOOT waveBootstrap response parse failed', e, st);
      throw WaveErrorMapper.map(e);
    }
  }

  /// Reads the persisted Wave connection, or null when not yet connected.
  ///
  /// Backs the persistent "Connected to X" status: the app can't read the
  /// rules-locked `wave` collection directly, so it asks this admin-only
  /// callable instead.
  Future<WaveConnection?> getConnection() async {
    final HttpsCallableResult<dynamic> result;
    try {
      result = await _functions
          .httpsCallable('waveGetConnection')
          .call(<String, dynamic>{});
    } catch (e, st) {
      _logger.warn('WAVE-CONN waveGetConnection callable failed', e, st);
      throw WaveErrorMapper.map(e);
    }

    try {
      // NOTE: loose `as Map?` required — Android callables return
      // Map<dynamic, dynamic>, not Map<String, dynamic>.
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
          .httpsCallable('waveImportCustomers')
          .call(<String, dynamic>{});
    } catch (e, st) {
      _logger.warn('WAVE-CUST waveImportCustomers callable failed', e, st);
      throw WaveErrorMapper.map(e);
    }

    try {
      // NOTE: loose `as Map?` required — Android callables return
      // Map<dynamic, dynamic>, not Map<String, dynamic>.
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

  /// Sets the automatic-import cadence via the admin-only
  /// `waveSetImportSchedule` callable.
  Future<void> setImportSchedule(WaveImportSchedule schedule) async {
    try {
      await _functions.httpsCallable('waveSetImportSchedule').call<void>(
        <String, dynamic>{'schedule': schedule.raw},
      );
    } catch (e, st) {
      _logger.warn('WAVE-SCHED waveSetImportSchedule callable failed', e, st);
      throw WaveErrorMapper.map(e);
    }
  }
}
