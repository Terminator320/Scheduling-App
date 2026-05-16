import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

class ImageStorageService {
  static const int maxUploadBytes = 8 * 1024 * 1024;

  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<bool> _isValidImageFile(File file) async {
    final raf = await file.open();
    try {
      final bytes = await raf.read(4);
      if (bytes.length < 3) return false;
      final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
      final isPng = bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E;
      return isJpeg || isPng;
    } finally {
      await raf.close();
    }
  }

  Future<AppointmentImage> uploadImage(String appointmentId, File file) async {
    if (!await _isValidImageFile(file)) {
      throw StateError('File is not a valid image.');
    }

    final size = await file.length();
    if (size > maxUploadBytes) {
      throw StateError('Image is too large to upload after compression.');
    }

    final originalName = file.uri.pathSegments.last;
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_$originalName';
    final path = 'appointments/$appointmentId/images/$fileName';

    final ref = _storage.ref(path);
    final metadata = SettableMetadata(
      contentType: _contentTypeFor(originalName),
      cacheControl: 'public, max-age=31536000',
    );

    final snapshot = await ref.putFile(file, metadata);
    final url = await snapshot.ref.getDownloadURL();

    return AppointmentImage(
      url: url,
      storagePath: path,
      fileName: fileName,
      uploadedAt: DateTime.now(),
    );
  }

  /// Uploads each file independently. Per-file failures are logged and
  /// counted instead of aborting the whole batch — one bad input shouldn't
  /// orphan the other successful uploads (the appointment would otherwise
  /// be patched with nothing and the user would see "all failed").
  Future<ImageUploadBatchResult> uploadImages(
    String appointmentId,
    List<File> files,
  ) async {
    final results = await Future.wait(
      files.map((f) async {
        try {
          return await uploadImage(appointmentId, f);
        } catch (e, st) {
          debugPrint('[ImageStorageService] upload failed for ${f.path}: $e');
          debugPrintStack(stackTrace: st);
          return null;
        }
      }),
    );
    final uploaded = results.whereType<AppointmentImage>().toList();
    return ImageUploadBatchResult(
      uploaded: uploaded,
      failedCount: results.length - uploaded.length,
    );
  }

  Future<void> deleteImage(AppointmentImage image) async {
    final path = image.storagePath.isNotEmpty
        ? image.storagePath
        : _pathFromUrl(image.url);
    if (path.isEmpty) return;
    try {
      await _storage.ref(path).delete();
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') return;
      rethrow;
    }
  }

  /// Best-effort batch delete. Per-file failures are logged but never
  /// rethrown — an orphan blob is preferable to blocking the user's save
  /// flow, and the dispatcher would otherwise mis-report a delete failure
  /// as a photo-upload failure.
  Future<void> deleteImages(List<AppointmentImage> images) async {
    await Future.wait(
      images.map((img) async {
        try {
          await deleteImage(img);
        } catch (e, st) {
          debugPrint(
            '[ImageStorageService] delete failed for ${img.storagePath}: $e',
          );
          debugPrintStack(stackTrace: st);
        }
      }),
    );
  }

  static String _pathFromUrl(String url) {
    if (url.isEmpty) return '';
    try {
      final parts = url.split('/o/');
      if (parts.length < 2) return '';
      final encoded = parts[1].split('?').first;
      return Uri.decodeComponent(encoded);
    } catch (e) {
      // A malformed URL means we can't delete the underlying Storage object
      // by-path; callers fall through to a no-op delete. Log so we know an
      // orphan happened instead of silently leaking blobs.
      debugPrint('[ImageStorageService] _pathFromUrl failed for "$url": $e');
      return '';
    }
  }

  // Storage rules and the magic-byte guard above both restrict uploads to
  // JPEG/PNG. Returning anything else here would race the rules and surface as
  // an opaque 403 to the user.
  String _contentTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }
}

class ImageUploadBatchResult {
  const ImageUploadBatchResult({
    required this.uploaded,
    required this.failedCount,
  });

  final List<AppointmentImage> uploaded;
  final int failedCount;
}
