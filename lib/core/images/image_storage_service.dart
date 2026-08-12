import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import 'package:scheduling/core/images/image_upload_failure.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

class ImageStorageService {
  ImageStorageService({AppLogger? logger}) : _logger = logger ?? AppLogger();

  static const int maxUploadBytes = 8 * 1024 * 1024;

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final AppLogger _logger;

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
      throw const ImageUploadFailureInvalidFormat();
    }

    final size = await file.length();
    if (size > maxUploadBytes) {
      throw const ImageUploadFailureTooLarge();
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
    // NOTE: nothing in the current build renders from this URL any more —
    // AppointmentImageUrlResolver resolves storagePath at render time so every
    // read re-evaluates storage.rules. It is still persisted purely so builds
    // that predate the resolver keep showing photos uploaded from this one;
    // drop the write (and the field) once the fleet has moved, the same way
    // the 1.37.1 shim was retired.
    final url = await snapshot.ref.getDownloadURL();

    return AppointmentImage(
      url: url,
      storagePath: path,
      fileName: fileName,
      uploadedAt: DateTime.now(),
    );
  }

  Future<void> _deleteImage(AppointmentImage image) async {
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

  Future<void> deleteImages(List<AppointmentImage> images) async {
    await Future.wait(
      images.map((img) async {
        try {
          await _deleteImage(img);
        } catch (e, st) {
          _logger.warn(
            'IMG-DEL deleteImage failed (orphaned bytes): ${img.storagePath}',
            e,
            st,
          );
        }
      }),
    );
  }

  String _pathFromUrl(String url) {
    if (url.isEmpty) return '';
    try {
      final parts = url.split('/o/');
      if (parts.length < 2) return '';
      final encoded = parts[1].split('?').first;
      return Uri.decodeComponent(encoded);
    } catch (e, st) {
      _logger.warn('IMG-DEL pathFromUrl failed', e, st);
      return '';
    }
  }

  String _contentTypeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }
}
