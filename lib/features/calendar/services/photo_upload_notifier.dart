import 'package:flutter/foundation.dart';

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

/// In-memory singleton that tracks background photo upload failures.
/// The upload service writes here; the calendar screen and detail sheet read here.
class PhotoUploadNotifier {
  static final PhotoUploadNotifier instance = PhotoUploadNotifier._();
  PhotoUploadNotifier._();

  /// Fires whenever a new failure arrives — used to trigger the calendar snackbar.
  final latestFailure = ValueNotifier<PhotoUploadFailure?>(null);

  final _failures = <String, PhotoUploadFailure>{};

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
}
