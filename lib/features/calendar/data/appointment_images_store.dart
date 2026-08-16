import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_image_doc_id.dart';

/// The photo half of the appointments repository: the `pictures` array and the
/// `appointments/{id}/images` subcollection it is moving to.
///
/// **This is phase 1 of that move, and it writes BOTH stores deliberately.**
/// The subcollection is the new home; the array is kept in step because the
/// build in the field (1.45.0+72) reads photos off the parent document and
/// knows nothing about the subcollection, so dropping it now blanks every
/// photo on every phone until it updates. It goes at the CONTRACT step, once
/// no device still runs a build that reads it — the same gate the
/// `#compat-1.37.1` shim waited on. Do not "finish the migration" early.
///
/// A collaborator rather than more of `FirebaseAppointmentsRepository`
/// precisely BECAUSE of that pending step: this is the surface the CONTRACT
/// change rewrites wholesale, and it should be a file to open rather than a
/// diff scattered through a 900-line class. (The repository as a whole is not
/// a god file and is not being split — this one block is the exception.)
class AppointmentImagesStore {
  AppointmentImagesStore({
    required CollectionReference<Map<String, dynamic>> appointments,
    required AppLogger logger,
  }) : _appointments = appointments,
       _logger = logger;

  final CollectionReference<Map<String, dynamic>> _appointments;
  final AppLogger _logger;

  /// The subcollection photos live in, under each appointment.
  ///
  /// Hand-mirrored as `IMAGES_SUBCOLLECTION` in
  /// `functions/appointment_images.js` — the cascade-delete trigger, the
  /// `pictureCount` trigger and the backfill all name the same path, and
  /// `firestore.rules` matches on it literally.
  static const String imagesSubcollection = 'images';

  /// Ceiling on [fetch]. `isValidAppointmentData` caps the `pictures` array at
  /// 100 and a SUBCOLLECTION has no such ceiling, so this is what keeps the
  /// read bounded once the array is retired at the CONTRACT step — matching
  /// the array's cap rather than inventing a second number.
  static const int scanLimit = 100;

  /// `appointments/{id}/images` — the subcollection photos are moving to.
  CollectionReference<Map<String, dynamic>> _imagesOf(String id) =>
      _appointments.doc(id).collection(imagesSubcollection);

  Future<void> append(String id, List<AppointmentImage> pictures) async {
    if (pictures.isEmpty) return;
    // One batch, so the two stores cannot disagree: a partial write here would
    // leave a photo visible on one surface and absent on the other, and this
    // path is retried by the offline queue, which would then see an
    // inconsistent state it has no way to reconcile.
    final batch = _appointments.firestore.batch();
    for (final picture in pictures) {
      final docId = appointmentImageDocId(picture);
      // No identity means nothing to render and no legal document id. Skipping
      // is right: writing it would throw and fail the whole batch, taking the
      // photos that ARE valid down with it.
      if (docId.isEmpty) continue;
      // `set`, not `add`: the id is derived from the photo, so the offline
      // queue's append-only retry of an already-uploaded image is a no-op
      // instead of a duplicate. This is what replaces the array's arrayUnion
      // deep-equality dedupe. `merge: true` so a retry cannot blank a field
      // the first pass wrote.
      batch.set(
        _imagesOf(id).doc(docId),
        _toSubcollectionMap(picture),
        SetOptions(merge: true),
      );
    }
    // Still arrayUnion, for the same reason it always was: a concurrent edit
    // or the batch's other half must never clobber photos it never saw.
    batch.update(_appointments.doc(id), {
      'pictures': FieldValue.arrayUnion(pictures.map(toArrayMap).toList()),
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
      // Deleting a doc that isn't there is a no-op, so this needs no
      // existence check — and unlike the arrayRemove below it cannot silently
      // miss. That asymmetry is worth knowing: `arrayRemove` matches by DEEP
      // EQUALITY of the whole map, so it only works because the caller hands
      // back images parsed from this very doc. Change what [toArrayMap] emits
      // and the array half stops removing anything, with no error — one more
      // reason the array's days are numbered.
      batch.delete(_imagesOf(id).doc(docId));
    }
    batch.update(_appointments.doc(id), {
      'pictures': FieldValue.arrayRemove(pictures.map(toArrayMap).toList()),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<List<AppointmentImage>> fetch(String id) async {
    // Ordered so the viewer's index means the same thing on every device —
    // the subcollection has no inherent order, where the array carried its
    // own. `uploadedAt` is the field the array was effectively sorted by
    // (append order), so this preserves what people already see.
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

  /// The ARRAY's entry shape, on the parent document.
  ///
  /// Public because the whole-record serializer needs it too, and having two
  /// spellings of what an array entry looks like would break `arrayRemove`'s
  /// deep-equality match in silence.
  ///
  /// Built by OVERRIDING `AppointmentImage.toMap()` rather than restating its
  /// keys, which is what makes that single-owner claim true — the model was
  /// already a second spelling, reached through `AppointmentRecord.toMap()`
  /// and `PendingUploadStore` (which composes the same way). Restated here, a
  /// field added to the model would land in one path and not the other, and
  /// `arrayRemove` — which matches the whole map by DEEP EQUALITY — would
  /// quietly stop removing anything. The only difference is the wire type of
  /// `uploadedAt`: Firestore wants a `Timestamp` where the model holds a
  /// `DateTime`.
  static Map<String, dynamic> toArrayMap(AppointmentImage image) => {
    ...image.toMap(),
    'uploadedAt': image.uploadedAt == null
        ? null
        : Timestamp.fromDate(image.uploadedAt!),
  };

  /// The subcollection's document shape.
  ///
  /// Deliberately NOT [toArrayMap]. Two differences, both load-bearing:
  ///
  /// `url` is written **only when there is no `storagePath`**. Photos are
  /// rendered from bytes fetched off `storagePath` by `AppointmentImageLoader`,
  /// so every read re-evaluates `storage.rules`; the persisted `url` is a
  /// permanent rules-free token URL kept only for builds predating the loader,
  /// and those builds read the ARRAY, never this. So a new photo's `url` would be
  /// a credential stored for no reader — while a LEGACY entry that has only a
  /// url still needs it, or backfilling it here destroys the one thing that
  /// can render it. Dropping it is also most of the size win: the url is
  /// ~215 of a ~290-byte entry.
  ///
  /// `fileName` is omitted when absent rather than written as null, so the
  /// document carries no key it has no value for.
  ///
  /// **`uploadedAt` is the exception and is always written, as an explicit
  /// `null` when unknown.** [fetch] orders by it, and Firestore EXCLUDES a
  /// document missing the field it orders by — omitting the key the way
  /// `fileName` omits its own would drop that photo out of the read entirely,
  /// with nothing erroring. Same trap as `archived` on clients and `expiresAt`
  /// on the TTL ledgers. A null sorts first, which is the right place for a
  /// photo whose upload time was never recorded.
  static Map<String, dynamic> _toSubcollectionMap(AppointmentImage image) {
    return {
      'storagePath': image.storagePath,
      if (image.storagePath.isEmpty && image.url.isNotEmpty) 'url': image.url,
      if (image.fileName != null) 'fileName': image.fileName,
      'uploadedAt': image.uploadedAt == null
          ? null
          : Timestamp.fromDate(image.uploadedAt!),
    };
  }
}
