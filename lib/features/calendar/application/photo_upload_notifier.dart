import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PhotoUploadFailure {
  const PhotoUploadFailure({
    required this.appointmentId,
    this.failedCount = 0,
    this.tooLargeFileNames = const [],
  });

  final String appointmentId;
  final int failedCount;
  final List<String> tooLargeFileNames;
}

class PhotoUploadNotifier {
  PhotoUploadNotifier();

  final ValueNotifier<PhotoUploadFailure?> latestFailure = ValueNotifier(null);

  /// Photos still sitting in the offline queue, per appointment id.
  final ValueNotifier<Map<String, int>> pending = ValueNotifier(const {});

  final Map<String, PhotoUploadFailure> _failures = {};

  void reportFailure(
    String appointmentId, {
    int failedCount = 0,
    List<String> tooLargeFileNames = const [],
  }) {
    if (failedCount == 0 && tooLargeFileNames.isEmpty) return;
    final failure = PhotoUploadFailure(
      appointmentId: appointmentId,
      failedCount: failedCount,
      tooLargeFileNames: List.unmodifiable(tooLargeFileNames),
    );
    _failures[appointmentId] = failure;
    latestFailure.value = failure;
  }

  /// Replaces the whole queue snapshot.
  void reportPending(Map<String, int> counts) {
    if (mapEquals(pending.value, counts)) return;
    pending.value = Map.unmodifiable(counts);
  }

  PhotoUploadFailure? failureFor(String appointmentId) =>
      _failures[appointmentId];

  /// How many photos are still queued for [appointmentId].
  int pendingFor(String appointmentId) => pending.value[appointmentId] ?? 0;

  void clearFailure(String appointmentId) {
    _failures.remove(appointmentId);
  }

  void dispose() {
    latestFailure.dispose();
    pending.dispose();
  }
}

final photoUploadNotifierProvider = Provider<PhotoUploadNotifier>((ref) {
  final notifier = PhotoUploadNotifier();
  ref.onDispose(notifier.dispose);
  return notifier;
});
