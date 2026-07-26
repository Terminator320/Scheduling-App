import 'dart:async';
import 'dart:convert';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One queued photo batch for an appointment (staged file paths on disk).
class PendingUpload {
  const PendingUpload({
    required this.appointmentId,
    required this.paths,
    required this.enqueuedAtMs,
  });

  final String appointmentId;
  final List<String> paths;
  final int enqueuedAtMs;

  String get id => '${appointmentId}_$enqueuedAtMs';

  Map<String, dynamic> toJson() => {
    'appointmentId': appointmentId,
    'paths': paths,
    'enqueuedAtMs': enqueuedAtMs,
  };

  static PendingUpload? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final appointmentId = (map['appointmentId'] ?? '').toString();
    final enqueuedAtMs = map['enqueuedAtMs'];
    final paths = map['paths'];
    if (appointmentId.isEmpty || enqueuedAtMs is! int || paths is! List) {
      return null;
    }
    return PendingUpload(
      appointmentId: appointmentId,
      paths: paths.map((p) => p.toString()).toList(),
      enqueuedAtMs: enqueuedAtMs,
    );
  }
}

/// Durable queue of photo batches that failed (or have yet) to upload — a
/// JSON list under one SharedPreferences key; corrupt data resets to empty.
class PendingUploadStore {
  PendingUploadStore({AppLogger? logger}) : _logger = logger ?? AppLogger();

  static const _key = 'pending_photo_uploads';
  static const _maxAge = Duration(days: 7);

  final AppLogger _logger;

  /// Serialization chain: all mutations via _serialized since the queue is ONE SharedPreferences key.
  Future<void> _mutations = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _mutations.then((_) => action());
    // Swallow errors on the chain only, so one failed mutation doesn't poison every later one — `result` still surfaces to the caller.
    _mutations = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<PendingUpload>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _logger.warn('IMG-UPLOAD pending queue was not a JSON list; reset');
        return const [];
      }
      return decoded
          .map(PendingUpload.fromJson)
          .whereType<PendingUpload>()
          .toList();
    } on FormatException catch (e, st) {
      // Silent data loss otherwise: resetting the queue drops photo batches a
      // technician believes are still waiting to upload.
      _logger.warn('IMG-UPLOAD pending queue decode failed; reset', e, st);
      return const [];
    }
  }

  Future<void> _save(List<PendingUpload> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> add(PendingUpload entry) => _serialized(() async {
    final entries = await load();
    await _save([...entries, entry]);
  });

  Future<void> remove(String id) => _serialized(() async {
    final entries = await load();
    await _save(entries.where((e) => e.id != id).toList());
  });

  /// Drops entries older than [_maxAge]; returns them for file cleanup.
  Future<List<PendingUpload>> prune({required DateTime now}) =>
      _serialized(() async {
        final entries = await load();
        final cutoff = now.subtract(_maxAge).millisecondsSinceEpoch;
        final pruned = entries.where((e) => e.enqueuedAtMs < cutoff).toList();
        if (pruned.isNotEmpty) {
          await _save(entries.where((e) => e.enqueuedAtMs >= cutoff).toList());
        }
        return pruned;
      });
}
