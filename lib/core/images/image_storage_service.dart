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
  ///
  /// It is also what makes a storage path write-once: every name carries the
  /// millisecond it was composed at, so nothing ever overwrites an object, and
  /// `AppointmentImageDiskCache` can key on the path without revalidating.
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
      // `private`, not `public`: these bytes are fetched with an Authorization
      // header (render-from-bytes via `ref.getData()`), and RFC 9111 §3.5 lets
      // a SHARED cache store an authenticated response only when it is marked
      // `public` — which would re-authorize an intermediary to keep and reuse
      // one entitled user's photo for a year. Nothing is lost: the disk cache
      // owns offline/session reuse and keys on the write-once `storagePath`.
      cacheControl: 'private, max-age=31536000',
    );

    await ref.putFile(file, metadata);

    // NO `url`. This used to call `getDownloadURL()` and persist the result,
    // and **that is the last thing in the app that minted one** — a
    // `?alt=media&token=…` link whose token is stable per object, never
    // expires, and serves the bytes over plain HTTPS with no auth and no
    // `storage.rules` evaluation. Rendering stopped using it when
    // `AppointmentImageLoader` moved to authenticated SDK fetches off
    // `storagePath`; the write outlived that only so builds predating the
    // loader kept showing photos, and it went with them at the CONTRACT step.
    // Nothing renders from a stored url now — the loader's fallback went with
    // the field. `_deleteImage` below is the last reader, and only for a
    // legacy entry that never had a `storagePath`. Do not reintroduce this.
    return AppointmentImage(
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
