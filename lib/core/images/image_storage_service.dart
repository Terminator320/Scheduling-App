import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import 'package:scheduling/core/images/image_magic.dart';
import 'package:scheduling/core/images/image_upload_failure.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/validators/text_limits.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

class ImageStorageService {
  ImageStorageService({FirebaseStorage? storage, AppLogger? logger})
    : _storage = storage ?? FirebaseStorage.instance,
      _logger = logger ?? AppLogger();

  static const int maxUploadBytes = 8 * 1024 * 1024;

  final FirebaseStorage _storage;
  final AppLogger _logger;

  /// `<millis>_<originalName>`, bounded by [TextLimits.imageFileName].
  ///
  /// The bound is not cosmetic: the appointment-images subcollection rule caps
  /// `fileName` at the same 300, and `appendAppointmentPictures` writes a whole
  /// batch in ONE `WriteBatch` — so one over-long basename fails the batch with
  /// an opaque `permission-denied` and takes the valid photos with it. The
  /// millisecond prefix is kept and the basename is what gets trimmed, so the
  /// truncated name stays as unique as the untruncated one.
  static String composeFileName(String originalName, DateTime now) {
    final name = '${now.millisecondsSinceEpoch}_$originalName';
    return name.length <= TextLimits.imageFileName
        ? name
        : name.substring(0, TextLimits.imageFileName);
  }

  Future<bool> _isValidImageFile(File file) async {
    final raf = await file.open();
    try {
      // The signature test itself lives in `hasValidImageMagic` so it can be
      // tested without a File or a FirebaseStorage instance — and so it reads
      // as the deliberate mirror of `functions/image_magic.js` that it is.
      return hasValidImageMagic(await raf.read(4));
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
    final fileName = composeFileName(originalName, DateTime.now());
    final path = 'appointments/$appointmentId/images/$fileName';

    final ref = _storage.ref(path);
    final metadata = SettableMetadata(
      contentType: _contentTypeFor(originalName),
      cacheControl: 'public, max-age=31536000',
    );

    final snapshot = await ref.putFile(file, metadata);
    // NOTE: nothing in the current build renders from this URL any more —
    // AppointmentImageLoader fetches the bytes from storagePath, so no
    // renderable URL is produced at all. It is still persisted purely so
    // builds that predate that change keep showing photos uploaded from this
    // one; drop the write (and the field) once the fleet has moved, the same
    // way the 1.37.1 shim was retired.
    final url = await snapshot.ref.getDownloadURL();

    return AppointmentImage(
      url: url,
      storagePath: path,
      fileName: fileName,
      uploadedAt: DateTime.now(),
    );
  }

  /// Mints the download URL for an already-uploaded object, or `''` if it
  /// can't be minted.
  ///
  /// This is the ONE place left that produces a URL, and it is not a render
  /// path: the offline queue carries an already-uploaded image forward when
  /// its doc-link append didn't land, and the `pictures` array entry it
  /// re-writes still carries a `url` for builds that predate
  /// `AppointmentImageLoader`. It lives here beside the [uploadImage] write it
  /// reproduces, so nothing on the render side has a URL-minting method to
  /// reach for.
  Future<String> downloadUrlFor(String storagePath) async {
    if (storagePath.isEmpty) return '';
    try {
      return await _storage.ref(storagePath).getDownloadURL();
    } catch (e, st) {
      _logger.warn('IMG-URL downloadUrlFor failed: $storagePath', e, st);
      return '';
    }
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
