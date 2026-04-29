import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:scheduling/core/services/image_compress_service.dart';
import 'package:scheduling/core/services/image_storage_service.dart';
import 'package:scheduling/features/calendar/models/appointment_image.dart';
import 'package:scheduling/features/calendar/services/appointment_service.dart';

/// Handles background image compression, upload, and Firestore patching
/// for appointment images. Call [uploadInBackground] and forget it — it
/// never throws; the appointment record is already saved before this runs.


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

  /// Compresses and uploads [newImages], then patches the appointment's
  /// pictures field to [existingImages] + the newly uploaded ones.
  /// Also deletes any [toDelete] images from Firebase Storage.
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
      await Future.wait([
        if (newImages.isNotEmpty)
          _compressUploadAndPatch(appointmentId, newImages, existingImages),
        if (toDelete.isNotEmpty) _storage.deleteImages(toDelete),
      ]);
      debugPrint('[AppointmentImageUpload] done for $appointmentId');
    } catch (e, st) {
      debugPrint('[AppointmentImageUpload] FAILED for $appointmentId: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> _compressUploadAndPatch(
    String appointmentId,
    List<File> newImages,
    List<AppointmentImage> existingImages,
  ) async {
    debugPrint(
      '[AppointmentImageUpload] compressing ${newImages.length} image(s)...',
    );
    final compressed = await _compress.compressImages(newImages);

    debugPrint(
      '[AppointmentImageUpload] uploading ${compressed.length} image(s)...',
    );
    final uploaded = await _storage.uploadImages(appointmentId, compressed);

    debugPrint(
      '[AppointmentImageUpload] patching Firestore with ${uploaded.length} new + ${existingImages.length} existing...',
    );
    await _appointments.updateAppointmentPictures(
      appointmentId,
      [...existingImages, ...uploaded],
    );
  }
}
