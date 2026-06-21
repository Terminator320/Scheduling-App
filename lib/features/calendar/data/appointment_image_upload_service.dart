import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/images/image_storage_service.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

class AppointmentImageUploadService {
  AppointmentImageUploadService({
    required AppointmentsRepository appointments,
    required PhotoUploadNotifier notifier,
    ImageStorageService? storage,
  }) : _appointments = appointments,
       _notifier = notifier,
       _storage = storage ?? ImageStorageService();

  final AppointmentsRepository _appointments;
  final PhotoUploadNotifier _notifier;
  final ImageStorageService _storage;

  void uploadInBackground({
    required String appointmentId,
    required List<File> newImages,
    List<AppointmentImage> existingImages = const [],
  }) {
    _run(
      appointmentId: appointmentId,
      newImages: List.of(newImages),
      existingImages: List.of(existingImages),
    );
  }

  Future<void> _run({
    required String appointmentId,
    required List<File> newImages,
    required List<AppointmentImage> existingImages,
  }) async {
    try {
      var failedCount = 0;
      final tooLargeNames = <String>[];
      if (newImages.isNotEmpty) {
        final result = await _uploadAndPatch(
          appointmentId,
          newImages,
          existingImages,
        );
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
      debugPrint('[AppointmentImageUpload] done for $appointmentId');
    } catch (e, st) {
      _notifier.reportFailure(appointmentId, failedCount: newImages.length);
      debugPrint('[AppointmentImageUpload] FAILED for $appointmentId: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<_UploadOutcome> _uploadAndPatch(
    String appointmentId,
    List<File> newImages,
    List<AppointmentImage> existingImages,
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
        await _appointments.updateAppointmentPictures(appointmentId, [
          ...existingImages,
          ...result.uploaded,
        ]);
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
        } catch (e) {
          debugPrint(
            '[AppointmentImageUpload] temp-cleanup failed for ${f.path}: $e',
          );
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
