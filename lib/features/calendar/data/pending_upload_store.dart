import 'dart:async';
import 'dart:convert';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One queued photo batch for an appointment (staged file paths on disk).
class PendingUpload {
  const PendingUpload({
    required this.appointmentId,
    required this.paths,
    required this.enqueuedAtMs,
    this.uploaded = const [],
  });

  final String appointmentId;
  final List<String> paths;
  final int enqueuedAtMs;

  /// Images already uploaded to Storage on a previous pass whose
  /// appointment-doc link (the `arrayUnion` append) hasn't landed yet. They're
  /// re-attempted append-only on the next drain — never re-uploaded, since
  /// their local files are already gone. Preserving each image's exact
  /// `uploadedAt` keeps the `arrayUnion` re-link idempotent if the earlier
  /// append actually committed server-side.
  final List<AppointmentImage> uploaded;

  String get id => '${appointmentId}_$enqueuedAtMs';

  Map<String, dynamic> toJson() => {
    'appointmentId': appointmentId,
    'paths': paths,
    'enqueuedAtMs': enqueuedAtMs,
    if (uploaded.isNotEmpty) 'uploaded': uploaded.map(_imageToJson).toList(),
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
    final rawUploaded = map['uploaded'];
    return PendingUpload(
      appointmentId: appointmentId,
      paths: paths.map((p) => p.toString()).toList(),
      enqueuedAtMs: enqueuedAtMs,
      uploaded: rawUploaded is List
          ? rawUploaded
                .whereType<Map<Object?, Object?>>()
                .map((m) => AppointmentImage.fromMap(m.cast<String, dynamic>()))
                .toList()
          : const [],
    );
  }

  // Serialize the timestamp as ISO-8601 (fromMap parses it back), so an
  // uploaded image round-trips through SharedPreferences byte-identically.
  static Map<String, dynamic> _imageToJson(AppointmentImage image) => {
    'url': image.url,
    'storagePath': image.storagePath,
    'fileName': image.fileName,
    'uploadedAt': image.uploadedAt?.toIso8601String(),
  };
}

/// A durable queue of photo batches that failed to upload, or just haven't
/// uploaded yet. It's stored as a JSON list under one SharedPreferences key,
/// and if that data ever comes back corrupt, we just reset it to empty.
class PendingUploadStore {
  PendingUploadStore({AppLogger? logger}) : _logger = logger ?? AppLogger();

  static const _key = 'pending_photo_uploads';
  static const _maxAge = Duration(days: 7);

  final AppLogger _logger;

  /// Every mutation goes through [_serialized], because the whole queue
  /// lives under one SharedPreferences key and reads/writes need to run
  /// one at a time to stay consistent.
  Future<void> _mutations = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _mutations.then((_) => action());
    // We swallow the error only on the internal chain, so one failed
    // mutation doesn't block every mutation after it. The caller still sees
    // the real error through `result`.
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
      // Worth logging loudly here: resetting the queue silently drops photo
      // batches that a technician thinks are still waiting to upload.
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

  /// Drops entries older than [_maxAge] and returns them so the caller can
  /// clean up their files.
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
