import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/images/image_storage_service.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';

class AppointmentImageUploadService {
  AppointmentImageUploadService({
    required AppointmentsRepository appointments,
    required PhotoUploadNotifier notifier,
    ImageStorageService? storage,
    AppLogger? logger,
  }) : _appointments = appointments,
       _notifier = notifier,
       _storage = storage ?? ImageStorageService(),
       _logger = logger ?? AppLogger();

  final AppointmentsRepository _appointments;
  final PhotoUploadNotifier _notifier;
  final ImageStorageService _storage;
  final AppLogger _logger;

  void uploadInBackground({
    required String appointmentId,
    required List<File> newImages,
  }) {
    _run(appointmentId: appointmentId, newImages: List.of(newImages));
  }

  Future<void> _run({
    required String appointmentId,
    required List<File> newImages,
  }) async {
    try {
      var failedCount = 0;
      final tooLargeNames = <String>[];
      if (newImages.isNotEmpty) {
        final result = await _uploadAndPatch(appointmentId, newImages);
        tooLargeNames.addAll(result.tooLargeNames);
        failedCount += result.failedCount;
      }

      if (failedCount > 0 || tooLargeNames.isNotEmpty) {
        _notifier.reportFailure(
          appointmentId,
          failedCount: failedCount,
          tooLargeFileNames: tooLargeNames,
        );
      }
    } catch (e, st) {
      _notifier.reportFailure(appointmentId, failedCount: newImages.length);
      _logger.warn(
        'IMG-UPLOAD background run failed for $appointmentId',
        e,
        st,
      );
    }
  }

  Future<_UploadOutcome> _uploadAndPatch(
    String appointmentId,
    List<File> newImages,
  ) async {
    try {
      final sizes = await Future.wait(newImages.map((f) => f.length()));

      final uploadable = <File>[];
      final tooLargeNames = <String>[];

      for (var i = 0; i < newImages.length; i++) {
        if (sizes[i] > ImageStorageService.maxUploadBytes) {
          tooLargeNames.add(_fileName(newImages[i]));
        } else {
          uploadable.add(newImages[i]);
        }
      }

      var failedCount = 0;
      if (uploadable.isNotEmpty) {
        final result = await _storage.uploadImages(appointmentId, uploadable);
        // Append (arrayUnion) rather than rewriting the whole array from a
        // submit-time snapshot: an edit saved while this upload was in flight
        // would otherwise be overwritten with the stale base (C1).
        await _appointments.appendAppointmentPictures(
          appointmentId,
          result.uploaded,
        );
        failedCount = result.failedCount;
      }

      return _UploadOutcome(
        tooLargeNames: tooLargeNames,
        failedCount: failedCount,
      );
    } finally {
      for (final f in newImages) {
        try {
          await f.delete();
        } catch (e, st) {
          _logger.warn('IMG-UPLOAD temp cleanup failed for ${f.path}', e, st);
        }
      }
    }
  }

  static String _fileName(File file) {
    final segments = file.uri.pathSegments;
    return segments.isNotEmpty ? segments.last : file.path;
  }
}

class _UploadOutcome {
  const _UploadOutcome({
    required this.tooLargeNames,
    required this.failedCount,
  });

  final List<String> tooLargeNames;
  final int failedCount;
}

final appointmentImageUploadProvider = Provider<AppointmentImageUploadService>((
  ref,
) {
  return AppointmentImageUploadService(
    appointments: ref.watch(appointmentsRepositoryProvider),
    notifier: ref.watch(photoUploadNotifierProvider),
  );
});
