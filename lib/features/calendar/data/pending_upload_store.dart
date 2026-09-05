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
    required this.ownerUid,
    required this.ownerEmployeeId,
    this.uploaded = const [],
  });

  final String appointmentId;
  final List<String> paths;
  final int enqueuedAtMs;
  /// Who staged this batch. Empty on a LEGACY entry — one written by a build
  /// from before the queue carried an owner. Such an entry is never uploaded
  /// (an empty id matches nobody, which is the point: on a shared or
  /// handed-over phone the next account must not finish somebody else's
  /// upload) but it is still PARSED, so `prune` reaches it and deletes its
  /// staged files. Dropping it at parse time stranded those files forever.
  final String ownerUid;
  final String ownerEmployeeId;

  bool get hasOwner => ownerUid.isNotEmpty && ownerEmployeeId.isNotEmpty;

  /// Already-uploaded images waiting for an append-only retry.
  final List<AppointmentImage> uploaded;

  String get id => '${appointmentId}_$enqueuedAtMs';

  Map<String, dynamic> toJson() => {
    'appointmentId': appointmentId,
    'paths': paths,
    'enqueuedAtMs': enqueuedAtMs,
    'ownerUid': ownerUid,
    'ownerEmployeeId': ownerEmployeeId,
    if (uploaded.isNotEmpty) 'uploaded': uploaded.map(_imageToJson).toList(),
  };

  static PendingUpload? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final appointmentId = (map['appointmentId'] ?? '').toString();
    final enqueuedAtMs = map['enqueuedAtMs'];
    final paths = map['paths'];
    final ownerUid = (map['ownerUid'] ?? '').toString();
    final ownerEmployeeId = (map['ownerEmployeeId'] ?? '').toString();
    if (appointmentId.isEmpty || enqueuedAtMs is! int || paths is! List) {
      return null;
    }
    final rawUploaded = map['uploaded'];
    return PendingUpload(
      appointmentId: appointmentId,
      paths: paths.map((p) => p.toString()).toList(),
      enqueuedAtMs: enqueuedAtMs,
      ownerUid: ownerUid,
      ownerEmployeeId: ownerEmployeeId,
      uploaded: rawUploaded is List
          ? rawUploaded
                .whereType<Map<Object?, Object?>>()
                .map((m) => AppointmentImage.fromMap(m.cast<String, dynamic>()))
                .toList()
          : const [],
    );
  }

  // JSON-safe image shape for SharedPreferences.
  static Map<String, dynamic> _imageToJson(AppointmentImage image) => {
    ...image.toMap(),
    if (image.storagePath.isNotEmpty) 'url': '',
    'uploadedAt': image.uploadedAt?.toIso8601String(),
  };
}

/// Durable SharedPreferences queue for pending photo uploads.
class PendingUploadStore {
  PendingUploadStore({AppLogger? logger}) : _logger = logger ?? AppLogger();

  static const _key = 'pending_photo_uploads';
  static const _maxAge = Duration(days: 7);

  final AppLogger _logger;

  /// Serializes read-modify-write queue mutations.
  Future<void> _mutations = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _mutations.then((_) => action());
    // Keep the internal chain alive while returning the real result.
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
      // Resetting the queue drops batches the user expects to upload.
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

  /// Replaces [id] atomically so failed requeues keep the old entry reachable.
  Future<void> replace(String id, PendingUpload entry) => _serialized(() async {
    final entries = await load();
    await _save([
      ...entries.where((e) => e.id != id && e.id != entry.id),
      entry,
    ]);
  });

  /// Drops entries older than [_maxAge] and returns them so the caller can
  /// clean up their files.
  Future<List<PendingUpload>> prune({required DateTime now}) =>
      _serialized(() async {
        final entries = await load();
        final cutoff = now.subtract(_maxAge).millisecondsSinceEpoch;
        final kept = <PendingUpload>[];
        final pruned = <PendingUpload>[];
        for (final entry in entries) {
          (entry.enqueuedAtMs < cutoff ? pruned : kept).add(entry);
        }
        if (pruned.isNotEmpty) {
          await _save(kept);
        }
        return pruned;
      });

  Future<List<PendingUpload>> clearAll() => _serialized(() async {
    final entries = await load();
    if (entries.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    return entries;
  });
}
