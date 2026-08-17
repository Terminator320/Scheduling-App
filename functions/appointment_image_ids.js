/**
 * @fileoverview Hand-mirror of
 * `lib/features/calendar/domain/policies/appointment_image_doc_id.dart`.
 *
 * The document id an appointment photo takes inside
 * `appointments/{appointmentId}/images/{imageId}`. Deterministic, so writing
 * the same photo twice is a no-op rather than a duplicate — which is what the
 * offline upload queue's append-only retry depends on now that the array's
 * `arrayUnion` deep-equality dedupe is gone.
 *
 * **This file and the Dart original must agree exactly.** The backfill writes
 * these ids; the client writes them again whenever it retries the same photo.
 * A divergence puts the same photo at two ids and it renders twice, with
 * nothing failing. The jest cases reuse the Dart suite's worked examples
 * verbatim for that reason — change one, change both.
 *
 * Dependency-free on purpose: the backfill script requires it directly, and it
 * must not drag a firebase-admin handle in (see the pure-policy-sibling rule
 * in functions/CLAUDE.md).
 */

// Keeps [A-Za-z0-9._-]; everything else becomes "_".
const UNSAFE_ID_CHARS = /[^A-Za-z0-9._-]/g;

// Far above any real value (a storage path runs ~50 chars, a download URL
// ~215). Guards Firestore's 1500-byte id limit against a pathological name.
const MAX_ID_LENGTH = 300;

/**
 * Sanitizes an identity key into a Firestore-legal id fragment.
 *
 * Truncation keeps the TAIL: both key shapes carry their unique part at the
 * end (a storage path ends in the millisecond-stamped file name, a download
 * URL in its token), so trimming from the front is what preserves uniqueness.
 * @param {string} key
 * @return {string}
 */
function sanitizeIdKey(key) {
  const sanitized = String(key).replace(UNSAFE_ID_CHARS, "_");
  return sanitized.length <= MAX_ID_LENGTH ?
    sanitized :
    sanitized.slice(sanitized.length - MAX_ID_LENGTH);
}

/**
 * The id for one stored photo map.
 *
 * Keyed on `storagePath` — the real identity, since that is what renders the
 * photo and what deletes it — falling back to `url` for the legacy docs that
 * carry a url and no storage path. Without that fallback every legacy photo on
 * an appointment collides on one id and they collapse into a single document.
 *
 * The `img_` prefix makes Firestore's reserved `__.*__` id shape unreachable:
 * a sanitized key can legitimately begin with `_`.
 * @param {?Object} image A stored picture map (`{storagePath, url, ...}`).
 * @return {string} The id, or "" when the map carries no usable identity.
 */
function appointmentImageDocId(image) {
  const data = image || {};
  const storagePath = String(data.storagePath || "").trim();
  const url = String(data.url || "").trim();
  const key = storagePath !== "" ? storagePath : url;
  if (key === "") return "";
  return `img_${sanitizeIdKey(key)}`;
}

module.exports = {appointmentImageDocId, MAX_ID_LENGTH};
