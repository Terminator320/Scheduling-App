import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:scheduling/core/services/image_compress_service.dart';
import 'package:scheduling/core/services/image_storage_service.dart';
import 'package:scheduling/features/calendar/models/appointment_image.dart';
import 'package:scheduling/features/calendar/services/appointment_service.dart';
import 'package:scheduling/features/calendar/services/photo_upload_notifier.dart';

class AppointmentImageUploadService {

  final ImageCompressService _compress;
  final ImageStorageService _storage;
  final AppointmentService _appointments;

  AppointmentImageUploadService({
    ImageCompressService? compress,
    ImageStorageService? storage,
    AppointmentService? appointments,
  })  : _compress = compress ?? ImageCompressService(),
        _storage = storage ?? ImageStorageService(),
        _appointments = appointments ?? AppointmentService();

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
      final List<String> tooLargeNames = [];
      if (newImages.isNotEmpty) {
        tooLargeNames.addAll(
          await _compressUploadAndPatch(appointmentId, newImages, existingImages),
        );
      }
      if (toDelete.isNotEmpty) await _storage.deleteImages(toDelete);

      if (tooLargeNames.isNotEmpty) {
        PhotoUploadNotifier.instance.reportFailure(
          appointmentId,
          tooLargeFileNames: tooLargeNames,
        );
      }
      debugPrint('[AppointmentImageUpload] done for $appointmentId');
    } catch (e, st) {
      PhotoUploadNotifier.instance.reportFailure(
        appointmentId,
        failedCount: newImages.length,
      );
      debugPrint('[AppointmentImageUpload] FAILED for $appointmentId: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<List<String>> _compressUploadAndPatch(
    String appointmentId,
    List<File> newImages,
    List<AppointmentImage> existingImages,
  ) async {
    debugPrint(
      '[AppointmentImageUpload] compressing ${newImages.length} image(s)...',
    );
    final compressed = await _compress.compressImages(newImages);

    final sizes = await Future.wait(compressed.map((f) => f.length()));

    final List<File> uploadable = [];
    final List<String> tooLargeNames = [];

    for (int i = 0; i < compressed.length; i++) {
      if (sizes[i] > ImageStorageService.maxUploadBytes) {
        tooLargeNames.add(_fileName(newImages[i]));
      } else {
        uploadable.add(compressed[i]);
      }
    }

    if (uploadable.isNotEmpty) {
      debugPrint(
        '[AppointmentImageUpload] uploading ${uploadable.length} image(s)...',
      );
      final uploaded = await _storage.uploadImages(appointmentId, uploadable);

      debugPrint(
        '[AppointmentImageUpload] patching Firestore with ${uploaded.length} new + ${existingImages.length} existing...',
      );
      await _appointments.updateAppointmentPictures(
        appointmentId,
        [...existingImages, ...uploaded],
      );
    }

    return tooLargeNames;
  }

  static String _fileName(File file) {
    final segments = file.uri.pathSegments;
    return segments.isNotEmpty ? segments.last : file.path;
  }
}
