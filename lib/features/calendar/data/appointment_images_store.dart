import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/policies/appointment_image_doc_id.dart';

/// The photo half of the appointments repository: the
/// `appointments/{id}/images` subcollection.
///
/// **The CODE side of the move off the parent document is complete (the
/// CONTRACT step); the DATA side is not.** The `pictures` array these methods
/// used to dual-write is gone from the app — nothing here reads it and nothing
/// writes it — but it is still ON every document that predates the change, and
/// `clear-appointment-picture-arrays.js` has NOT run yet. It is step 4 of the
/// runbook in `docs/DEPLOYMENT.md`, gated on the fleet ageing off builds that
/// still write the array. Two things depend on that distinction and must stay:
/// the `pictures` size cap in `firestore.rules`, and the clear script itself.
/// Those surviving arrays also carry a Storage download url, which is what
/// keeps 🔴 S1 open. That array made every appointment read carry its whole
/// photo list (a stored download url alone was ~215 of a ~290-byte entry)
/// while the calendar reads up to 1000 appointments at a time and only the
/// detail sheet ever shows a photo. What stays on the parent is
/// `pictureCount`, ~15 bytes, for the card indicator.
///
/// A collaborator rather than more of `FirebaseAppointmentsRepository` because
/// that step had to be a file to open rather than a diff scattered through a
/// 900-line class. (The repository as a whole is not a god file and is not
/// being split — this one block was the exception.)
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

  /// Ceiling on [fetch], and the only bound left on a job's photos.
  ///
  /// A subcollection has no document-size ceiling to run into — that is what
  /// the move bought, and it is why the array's 100-entry rules cap was not
  /// reinstated as a ceiling when the array went. It keeps the array's number
  /// rather than inventing a second one, and `PICTURE_COUNT_WARN_CAP`
  /// (`functions/appointment_images.js`) is its server-side twin: the recount
  /// warns past the same figure, because anything beyond it is simply absent
  /// from the app. The picker's own cap
  /// (`AppointmentFormConcerns.maxImagesPerAppointment`, 10) means only a
  /// modified client can get anywhere near this.
  static const int scanLimit = 100;

  /// `appointments/{id}/images` — where a job's photos live.
  CollectionReference<Map<String, dynamic>> _imagesOf(String id) =>
      _appointments.doc(id).collection(imagesSubcollection);

  Future<void> append(String id, List<AppointmentImage> pictures) async {
    if (pictures.isEmpty) return;
    // One batch: this path is retried by the offline queue, and a partial
    // write would put some of a batch on the job and not the rest, with
    // nothing able to tell which.
    final batch = _appointments.firestore.batch();
    for (final picture in pictures) {
      final docId = appointmentImageDocId(picture);
      // Two skips, and the SECOND is the load-bearing one. No identity means
      // no legal document id, and writing it would throw and fail the whole
      // batch, taking the photos that ARE valid down with it.
      //
      // No `storagePath` means no handle: `url` is rejected by the rules and
      // renders nothing, so the document would be unrenderable — and worse,
      // it would read as COVERAGE. `clear-appointment-picture-arrays.js`
      // decides whether an array entry is safe to destroy by looking for its
      // derived id in the subcollection, so a placeholder written here would
      // let the clear run delete the array entry whose `url` is the only
      // thing still pointing at those bytes. Mirrors the same skip in
      // `backfill-appointment-images.js`, which is where this was caught.
      if (docId.isEmpty || picture.storagePath.trim().isEmpty) continue;
      // `set`, not `add`: the id is derived from the photo, so the offline
      // queue's append-only retry of an already-uploaded image is a no-op
      // instead of a duplicate. This replaced the array's `arrayUnion` dedupe,
      // which only ever worked because every image serialized its exact
      // `uploadedAt`. `merge: true` so a retry cannot blank a field the first
      // pass wrote.
      batch.set(
        _imagesOf(id).doc(docId),
        _toSubcollectionMap(picture),
        SetOptions(merge: true),
      );
    }
    // The parent is touched for `updatedAt` alone now. Keep it: adding a photo
    // is an edit, and the job's list surfaces sort and reconcile on that
    // field. `pictureCount` is NOT written here — `recountAppointmentPictures`
    // owns it, and the rules reject a client write that moves it.
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
      // Deleting a document that isn't there is a no-op, so this needs no
      // existence check — and it cannot silently miss the way the retired
      // `FieldValue.arrayRemove` half could, which matched by DEEP EQUALITY of
      // the whole entry map and so only removed a photo the caller had parsed
      // out of this very document.
      batch.delete(_imagesOf(id).doc(docId));
    }
    batch.update(_appointments.doc(id), {
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

  /// The subcollection's document shape.
  ///
  /// Two things about it are load-bearing:
  ///
  /// **`url` is never written.** Photos render from bytes fetched off
  /// `storagePath` by `AppointmentImageLoader`, so every read re-evaluates
  /// `storage.rules`; a persisted url is a permanent rules-free token with no
  /// reader left in the app, and `ImageStorageService` stopped minting one at
  /// the CONTRACT step. A carve-out survived here for the LEGACY entry that
  /// had only a url, on the reasoning that dropping it destroyed the single
  /// thing that could render the photo — but a prod count on 2026-08-22 found
  /// **zero** such documents, `firestore.rules` no longer accepts the field,
  /// and the loader's fallback is gone, so this write would now be refused
  /// rather than merely unread. Omitting it was also most of the size win: the
  /// url was ~215 of a ~290-byte entry.
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
      if (image.fileName != null) 'fileName': image.fileName,
      'uploadedAt': image.uploadedAt == null
          ? null
          : Timestamp.fromDate(image.uploadedAt!),
    };
  }
}
