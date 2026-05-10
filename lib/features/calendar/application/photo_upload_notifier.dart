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

  bool get hasErrors => failedCount > 0 || tooLargeFileNames.isNotEmpty;
}

/// Tracks background photo-upload failures across the app. Held as a single
/// instance via Riverpod so the upload pipeline can report from anywhere
/// while the calendar screen listens via `latestFailure` for the snackbar.
class PhotoUploadNotifier {
  PhotoUploadNotifier();

  /// Fires whenever a new failure arrives.
  final ValueNotifier<PhotoUploadFailure?> latestFailure = ValueNotifier(null);

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

  PhotoUploadFailure? failureFor(String appointmentId) =>
      _failures[appointmentId];

  void clearFailure(String appointmentId) {
    _failures.remove(appointmentId);
  }

  void dispose() {
    latestFailure.dispose();
  }
}

final photoUploadNotifierProvider = Provider<PhotoUploadNotifier>((ref) {
  final notifier = PhotoUploadNotifier();
  ref.onDispose(notifier.dispose);
  return notifier;
});
