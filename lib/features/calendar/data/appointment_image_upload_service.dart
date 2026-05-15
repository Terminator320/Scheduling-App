import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/images/image_compress_service.dart';
import 'package:scheduling/core/images/image_storage_service.dart';
import 'package:scheduling/features/calendar/application/appointments_providers.dart';
import 'package:scheduling/features/calendar/application/photo_upload_notifier.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

class AppointmentImageUploadService {
  AppointmentImageUploadService({
    required AppointmentsRepository appointments,
    required PhotoUploadNotifier notifier,
    ImageCompressService? compress,
    ImageStorageService? storage,
  }) : _appointments = appointments,
       _notifier = notifier,
       _compress = compress ?? ImageCompressService(),
       _storage = storage ?? ImageStorageService();

  final AppointmentsRepository _appointments;
  final PhotoUploadNotifier _notifier;
  final ImageCompressService _compress;
  final ImageStorageService _storage;

  void uploadInBackground({
    required String appointmentId,
    required List<File> newImages,
    List<AppointmentImage> existingImages = const [],
    List<AppointmentImage> toDelete = const [],
  }) {
    _run(
      appointmentId: appointmentId,
      newImages: List.of(newImages),
      existingImages: List.of(existingImages),
      toDelete: List.of(toDelete),
    );
  }

  Future<void> _run({
    required String appointmentId,
    required List<File> newImages,
    required List<AppointmentImage> existingImages,
    required List<AppointmentImage> toDelete,
  }) async {
    try {
      final tooLargeNames = <String>[];
      if (newImages.isNotEmpty) {
        tooLargeNames.addAll(
          await _compressUploadAndPatch(
            appointmentId,
            newImages,
            existingImages,
          ),
        );
      }
      if (toDelete.isNotEmpty) await _storage.deleteImages(toDelete);

      if (tooLargeNames.isNotEmpty) {
        _notifier.reportFailure(
          appointmentId,
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

  Future<List<String>> _compressUploadAndPatch(
    String appointmentId,
    List<File> newImages,
    List<AppointmentImage> existingImages,
  ) async {
    final compressed = await _compress.compressImages(newImages);

    try {
      final sizes = await Future.wait(compressed.map((f) => f.length()));

      final uploadable = <File>[];
      final tooLargeNames = <String>[];

      for (var i = 0; i < compressed.length; i++) {
        if (sizes[i] > ImageStorageService.maxUploadBytes) {
          tooLargeNames.add(_fileName(newImages[i]));
        } else {
          uploadable.add(compressed[i]);
        }
      }

      if (uploadable.isNotEmpty) {
        final uploaded = await _storage.uploadImages(appointmentId, uploadable);
        await _appointments.updateAppointmentPictures(appointmentId, [
          ...existingImages,
          ...uploaded,
        ]);
      }

      return tooLargeNames;
    } finally {
      // Compressed files live in the OS temp dir; clean them up regardless of
      // upload outcome so failures don't accumulate on-device.
      for (final f in compressed) {
        try {
          if (await f.exists()) await f.delete();
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

final appointmentImageUploadProvider = Provider<AppointmentImageUploadService>((
  ref,
) {
  return AppointmentImageUploadService(
    appointments: ref.watch(appointmentsRepositoryProvider),
    notifier: ref.watch(photoUploadNotifierProvider),
  );
});
