import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_image_doc_id.dart';

/// Reads and writes appointment photos in `appointments/{id}/images`.
class AppointmentImagesStore {
  AppointmentImagesStore({
    required CollectionReference<Map<String, dynamic>> appointments,
    required AppLogger logger,
  }) : _appointments = appointments,
       _logger = logger;

  final CollectionReference<Map<String, dynamic>> _appointments;
  final AppLogger _logger;

  /// The literal subcollection path shared with rules and functions.
  static const String imagesSubcollection = 'images';

  /// Maximum number of photo documents fetched for one appointment.
  static const int scanLimit = 100;

  /// Returns the images subcollection for one appointment.
  CollectionReference<Map<String, dynamic>> _imagesOf(String id) =>
      _appointments.doc(id).collection(imagesSubcollection);

  Future<void> append(String id, List<AppointmentImage> pictures) async {
    if (pictures.isEmpty) return;
    // Keep an appended photo batch atomic for offline retries.
    final batch = _appointments.firestore.batch();
    for (final picture in pictures) {
      final docId = appointmentImageDocId(picture);
      // Invalid ids or missing storage paths cannot produce renderable docs.
      if (docId.isEmpty || picture.storagePath.trim().isEmpty) continue;
      // Derived ids make offline retries idempotent.
      batch.set(
        _imagesOf(id).doc(docId),
        _toSubcollectionMap(picture),
        SetOptions(merge: true),
      );
    }
    // Only the server-side recount owns `pictureCount`.
    batch.update(_appointments.doc(id), {
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> remove(String id, List<AppointmentImage> pictures) async {
    if (pictures.isEmpty) return;
    final batch = _appointments.firestore.batch();
    for (final picture in pictures) {
      final docId = appointmentImageDocId(picture);
      if (docId.isEmpty) continue;
      // Missing photo documents are harmless delete no-ops.
      batch.delete(_imagesOf(id).doc(docId));
    }
    batch.update(_appointments.doc(id), {
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<List<AppointmentImage>> fetch(String id) async {
    // Ordered so viewer indexes mean the same thing on every device.
    final snapshot = await _imagesOf(
      id,
    ).orderBy('uploadedAt').limit(scanLimit).get();
    if (snapshot.docs.length >= scanLimit) {
      _logger.warn(
        'APPT-IMG subcollection read for $id hit the $scanLimit-doc cap — '
        'photos beyond it were not loaded',
      );
    }
    return [
      for (final doc in snapshot.docs) AppointmentImage.fromMap(doc.data()),
    ];
  }

  /// Builds the subcollection shape without writing token URLs.
  static Map<String, dynamic> _toSubcollectionMap(AppointmentImage image) {
    return {
      'storagePath': image.storagePath,
      if (image.fileName != null) 'fileName': image.fileName,
      'uploadedAt': image.uploadedAt == null
          ? null
          : Timestamp.fromDate(image.uploadedAt!),
    };
  }
}
