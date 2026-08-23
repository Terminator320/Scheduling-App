import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';

/// The document id an [AppointmentImage] takes inside
/// `appointments/{appointmentId}/images/{imageId}`.
///
/// **Deterministic, because that is what makes the write idempotent.** The
/// offline upload queue re-runs an append whose doc-link write failed, and it
/// carries the already-uploaded images forward rather than re-uploading them
/// — so the same photo is written more than once by design. A generated id
/// (`.add()`) would produce a second document each time and the photo would
/// appear twice; a `set()` on this id is a no-op on the second pass.
///
/// This REPLACES the `arrayUnion` dedupe the array form depended on, which
/// worked only because every image serialized its exact `uploadedAt` and
/// `arrayUnion` compares maps by deep equality. That was fragile in a way this
/// is not: one field serialized a hair differently and the dedupe silently
/// stopped working.
///
/// **Keyed on `storagePath`, falling back to `url`.** `storagePath` is the
/// real identity of a photo — it is what renders it (see
/// `AppointmentImageLoader`) and what deletes it (`_deleteImage`). The
/// fallback is for the legacy entries that carry a `url` and no
/// `storagePath`; without it every one of them would collide on a single id
/// and a whole appointment's legacy photos would collapse into one document.
/// It is NOT a rendering fallback — the loader's was deleted once the prod
/// count of such documents came back zero. What still needs it is the
/// `pictures[]` side: the backfill and the clear script both key legacy array
/// entries through here, and the clear script REFUSES an appointment on an
/// entry with no identity at all.
///
/// **Hand-mirrored** by `appointmentImageDocId` in
/// `functions/appointment_image_ids.js`, which the backfill uses. The two must
/// agree exactly or a backfilled photo and the client's later retry of the
/// same photo land on different ids and it renders twice. Change both
/// together; `appointment_image_doc_id_test.dart` and its jest counterpart
/// share the same worked examples so a divergence fails a test.
String appointmentImageDocId(AppointmentImage image) =>
    appointmentImageDocIdFor(
      storagePath: image.storagePath,
      url: image.url,
    );

/// The raw-string form, for callers holding a map rather than a model — the
/// backfill's Dart-side tests, and anything reading an unparsed doc.
String appointmentImageDocIdFor({
  required String storagePath,
  required String url,
}) {
  final key = storagePath.trim().isNotEmpty ? storagePath.trim() : url.trim();
  if (key.isEmpty) return '';
  return 'img_${_sanitize(key)}';
}

/// Firestore document ids may not contain `/`, may not be `.` or `..`, and may
/// not match `__.*__`. Everything outside `[A-Za-z0-9._-]` becomes `_`.
///
/// The `img_` prefix the caller adds is what makes the `__.*__` case
/// unreachable — a sanitized key can begin with `_` (a leading `/` in a
/// storage path does exactly that), and `__foo__` is a reserved id that
/// Firestore rejects at write time. Prefixing is cheaper than detecting it.
///
/// Truncation keeps the **tail**, not the head: both key shapes carry their
/// unique part at the end (a storage path ends in the millisecond-stamped file
/// name, a download URL in its token), so trimming from the front is what
/// preserves uniqueness. The cap is far above any real value — a storage path
/// runs ~50 characters and a download URL ~215 — and exists only so a
/// pathological name cannot breach Firestore's 1500-byte id limit.
/// Written as the same one-line replace its JS mirror uses
/// (`String(key).replace(/[^A-Za-z0-9._-]/g, "_")`), deliberately: the two
/// implementations must agree exactly or one photo lands at two ids, and a
/// hand-rolled code-unit walk here could not be checked against the JS by eye.
/// Dart's `RegExp` matches code units without the unicode flag, like JS
/// without `/u`, so the two are equivalent character by character.
final _unsafeIdChars = RegExp('[^A-Za-z0-9._-]');

String _sanitize(String key) {
  final sanitized = key.replaceAll(_unsafeIdChars, '_');
  const maxLength = 300;
  return sanitized.length <= maxLength
      ? sanitized
      : sanitized.substring(sanitized.length - maxLength);
}
