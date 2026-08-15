/**
 * @fileoverview The server half of moving appointment photos into the
 * `appointments/{id}/images` subcollection.
 *
 * Two triggers, and the first one is not optional:
 *
 * 1. `cascadeDeleteAppointmentImages` — **Firestore does NOT delete a
 *    subcollection when its parent document is deleted.** The photo documents
 *    survive as orphans: invisible in the console under a parent that no
 *    longer exists, unreachable by every query the app makes, and impossible
 *    to find later without knowing the id. This trigger is the only thing
 *    standing between an ordinary appointment delete and permanent silent
 *    litter, and it must cover all three delete paths — the client's single
 *    delete, its series delete, and `purgeExpiredHistory` (Admin SDK deletes
 *    fire triggers too).
 *
 * 2. `recountAppointmentPictures` — maintains the denormalized `pictureCount`
 *    the card's photo indicator reads, since the card renders on every
 *    range-query surface and cannot afford a subcollection read each.
 *
 * The orchestration lives here rather than in the trigger wiring so it is
 * testable: both bodies take an injected `db`, in the same shape as
 * `maintenance_policy.js`.
 */
const {onDocumentDeleted, onDocumentWritten} =
  require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const {getFirestore} = require("firebase-admin/firestore");

/**
 * Hand-mirror of `_imagesSubcollection` in
 * `lib/features/calendar/data/firebase_appointments_repository.dart`.
 * `firestore.rules` matches this path literally too — all three must agree.
 */
const IMAGES_SUBCOLLECTION = "images";

/**
 * Deletes every photo document under a deleted appointment.
 *
 * `recursiveDelete` rather than a hand-rolled paged loop: it is the Admin
 * SDK's own bulk writer, it handles the paging, and `syncUsersByUid` already
 * uses it for `liveActivityTokens` — one way of doing this in the codebase.
 *
 * Errors are RETHROWN, unlike most best-effort cleanup here. The trigger runs
 * with `retry: true` and the failure mode it guards against is permanent and
 * invisible; a swallowed error would leave the orphans it exists to prevent
 * with nothing to notice them.
 * @param {string} appointmentId
 * @param {!Object} deps `{db}`.
 * @return {!Promise<void>}
 */
async function purgeAppointmentImages(appointmentId, deps) {
  const {db} = deps;
  const ref = db
      .collection("appointments")
      .doc(appointmentId)
      .collection(IMAGES_SUBCOLLECTION);
  await db.recursiveDelete(ref);
}

/**
 * Recomputes `pictureCount` on the parent from a `count()` aggregate.
 *
 * ABSOLUTE, never an increment — the same rule and the same reason as
 * `recountClientJobs`: this runs with `retry: true`, and a retried
 * `FieldValue.increment` double-counts. The aggregate costs a fraction of a
 * read and photo writes are rare.
 *
 * `update()`, not `set({merge: true})`, so an appointment deleted in the
 * window between the photo write and this recount is never resurrected as a
 * count-only stub. A `not-found` is therefore an expected outcome, not an
 * error: the cascade above has already removed the photos.
 * @param {string} appointmentId
 * @param {!Object} deps `{db, logger}`.
 * @return {!Promise<number>} the count written, or -1 when the parent was gone.
 */
async function recountPictures(appointmentId, deps) {
  const {db} = deps;
  const parent = db.collection("appointments").doc(appointmentId);
  const snap = await parent.collection(IMAGES_SUBCOLLECTION).count().get();
  const count = snap.data().count;
  try {
    await parent.update({pictureCount: count});
  } catch (err) {
    if (err && err.code === 5) return -1; // NOT_FOUND — parent already deleted.
    throw err;
  }
  return count;
}

// `retry: true` is safe and wanted: recursiveDelete is idempotent (a second
// pass finds nothing), and the orphans this prevents are permanent.
const cascadeDeleteAppointmentImages = onDocumentDeleted(
    {document: "appointments/{appointmentId}", retry: true},
    async (event) => {
      const appointmentId = event.params.appointmentId;
      await purgeAppointmentImages(appointmentId, {db: getFirestore()});
      logger.info("appointment images purged", {appointmentId});
    },
);

// `retry: true` is safe because the write is an absolute count, not a delta.
//
// IT DELIBERATELY RECOUNTS ON EVERY WRITE, INCLUDING AN UPDATE THAT CANNOT HAVE
// MOVED THE COUNT. Strictly, only a create or a delete changes it, and an
// `if (before.exists && after.exists) return` would skip the two paths that
// rewrite an existing image doc — the offline queue replaying
// `set(..., {merge: true})` on the DERIVED doc id, and a backfill re-run.
// That guard was written and then removed on purpose, because those two paths
// are the ONLY self-heal this counter has: a recount whose parent `update()`
// keeps failing exhausts its retry window and leaves `pictureCount` wrong
// forever, and an idempotent replay is what silently repairs it. The saving is
// small and lands on rare paths; the durability is not.
//
// It buys nothing against the real write amplification either.
// `appendAppointmentPictures` writes N image docs in ONE batch, so N recounts
// land on the SAME parent within milliseconds — against Firestore's
// ~1 write/sec/document guidance — but those are genuine CREATES, which any
// such guard must let through. Fix that by batching the recount if it ever
// bites, never by suppressing the replay.
const recountAppointmentPictures = onDocumentWritten(
    {
      document:
        `appointments/{appointmentId}/${IMAGES_SUBCOLLECTION}/{imageId}`,
      retry: true,
    },
    async (event) => {
      await recountPictures(event.params.appointmentId, {db: getFirestore()});
    },
);

module.exports = {
  cascadeDeleteAppointmentImages,
  recountAppointmentPictures,
  purgeAppointmentImages,
  recountPictures,
  IMAGES_SUBCOLLECTION,
};
