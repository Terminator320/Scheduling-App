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
 *    range-query surface and cannot afford a subcollection read each. It is
 *    DEBOUNCED per parent through a short-lived claim ledger; see
 *    `debouncedRecountPictures` for why the release/aggregate ORDER is the
 *    whole design.
 *
 * The orchestration lives here rather than in the trigger wiring so it is
 * testable: every body takes an injected `db`, in the same shape as
 * `maintenance_policy.js`.
 */
const {onDocumentDeleted, onDocumentWritten} =
  require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const {getFirestore} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");

/**
 * Hand-mirror of `_imagesSubcollection` in
 * `lib/features/calendar/data/firebase_appointments_repository.dart`.
 * `firestore.rules` matches this path literally too — all three must agree.
 */
const IMAGES_SUBCOLLECTION = "images";

/**
 * Admin-SDK-only claim ledger that collapses one photo batch's N recounts
 * into one parent write. Same posture as `appointmentSeriesNotices`: nothing
 * client-side may read or write it.
 */
const RECOUNT_CLAIM_COLLECTION = "appointmentRecountClaims";

/**
 * How long the claiming invocation waits before recounting, to absorb the
 * rest of its batch's triggers. Correctness never depends on this number —
 * see `debouncedRecountPictures` — so it is tuned purely for how much of a
 * batch one recount swallows. A sibling arriving after the window simply
 * recounts again, which is the old behaviour.
 */
const RECOUNT_SETTLE_MS = 2000;

/**
 * A claim older than this is presumed abandoned (an invocation killed between
 * claiming and releasing) and is taken over. Deliberately a handful of
 * seconds: a claim that outlives its usefulness would suppress the offline
 * queue's replay, which is this counter's ONLY self-heal.
 */
const RECOUNT_CLAIM_STALE_MS = 15 * 1000;

/**
 * Absolute lifetime stamped on `expiresAt` for the Firestore TTL policy
 * (declared in `firestore.indexes.json`, expiration offset 0). TTL is
 * housekeeping only — the claim is inert after `RECOUNT_CLAIM_STALE_MS`
 * whether or not the policy has swept it, and the normal path deletes it
 * explicitly. Nothing here relies on the policy for correctness.
 */
const RECOUNT_CLAIM_TTL_MS = 5 * 60 * 1000;

/**
 * The photo count past which one appointment's photos stop being fully
 * readable, and the log line is the only sign of it.
 *
 * It is what STANDS IN for the `pictures` array's 100-entry rules cap on the
 * new shape. **That clause is still in `firestore.rules` and still enforced**
 * — deliberately, for the documents `clear-appointment-picture-arrays.js` has
 * not reached, whose arrays ride along in `request.resource.data` on every
 * ordinary edit. What it guarded was a hard failure: the parent document's
 * 1 MB ceiling, which made an over-full job permanently un-updatable. Moving
 * photos into a subcollection is precisely what makes that unreachable for a
 * job written by a current build, so no equivalent CEILING was needed on the
 * new store.
 *
 * What survives is softer and quieter: `AppointmentImagesStore.fetch` reads at
 * most `scanLimit` (the same 100) photos, so anything past that is invisible
 * in the app with only a client-side warn to say so. Rules cannot count
 * documents in a subcollection, and the picker already caps a job at
 * `maxImagesPerAppointment` (10), so a job that gets here has a modified
 * client behind it. Recording it server-side is what makes that visible at
 * all — keep this number equal to the Dart read cap.
 */
const PICTURE_COUNT_WARN_CAP = 100;

/**
 * True for the Firestore ALREADY_EXISTS a losing `create()` raises.
 * @param {*} err
 * @return {boolean}
 */
function isAlreadyExists(err) {
  return !!err && (err.code === 6 || err.code === "already-exists");
}

/**
 * Milliseconds from a Firestore Timestamp, a Date or a raw number.
 * @param {*} value
 * @return {?number} null when there is no usable timestamp.
 */
function toMillis(value) {
  if (!value) return null;
  if (typeof value === "number") return value;
  if (value instanceof Date) return value.getTime();
  if (typeof value.toMillis === "function") return value.toMillis();
  return null;
}

/**
 * The body every recount claim is written with.
 * @param {!Date} nowDate
 * @return {{claimedAt: !Date, expiresAt: !Date}}
 */
function claimBody(nowDate) {
  return {
    claimedAt: nowDate,
    expiresAt: new Date(nowDate.getTime() + RECOUNT_CLAIM_TTL_MS),
  };
}

/**
 * Sleeps `ms` — the default injectable so tests never wait.
 * @param {number} ms
 * @return {!Promise<void>}
 */
function defaultSleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Deletes every Storage object under one appointment's image prefix.
 *
 * The bucket is resolved INSIDE the call, never at module load — that is what
 * keeps this file requirable (and therefore testable) outside the emulator,
 * the distinction `maintenance.js` had to split a policy module out to get.
 * @param {string} appointmentId
 * @return {!Promise<void>} rejects when the prefix could not be cleared.
 */
async function deleteAppointmentImageBytes(appointmentId) {
  const prefix = `appointments/${appointmentId}/${IMAGES_SUBCOLLECTION}/`;
  await getStorage().bucket().deleteFiles({prefix});
}

/**
 * Deletes a deleted appointment's photos — the Storage bytes AND the photo
 * documents.
 *
 * **The bytes half is not housekeeping either.** Until the CONTRACT step the
 * client deleted them, enumerating `appointment.pictures` to know which
 * objects to remove; that array is gone, and nothing client-side can
 * enumerate a subcollection it is no longer reading. So this is now the only
 * thing standing between an appointment delete and photos orphaned in
 * Storage — paid for monthly, attached to nothing, with no query that can
 * find them. The prefix is derived from the appointment id rather than from
 * any stored path, so it also sweeps up bytes whose document link never
 * landed.
 *
 * `recursiveDelete` for the documents rather than a hand-rolled paged loop: it
 * is the Admin SDK's own bulk writer, it handles the paging, and
 * `syncUsersByUid` already uses it for `liveActivityTokens` — one way of doing
 * this in the codebase.
 *
 * ORDER: bytes first, documents second — the same rule `purgeExpiredHistory`
 * follows. The photo documents are the last thing pointing at those objects,
 * so dropping them before the bytes are gone loses the trail on a failure.
 *
 * Errors are RETHROWN, unlike most best-effort cleanup here. The trigger runs
 * with `retry: true` and the failure mode it guards against is permanent and
 * invisible; a swallowed error would leave the orphans it exists to prevent
 * with nothing to notice them. Both halves are idempotent, so a retry that
 * repeats the successful half is free.
 * @param {string} appointmentId
 * @param {{db: !Object, deleteImages: !Function}} deps Both injected: the
 *   production caller passes `deleteAppointmentImageBytes` and jest passes a
 *   fake. No default here, so a caller cannot half-wire it.
 * @return {!Promise<void>}
 */
async function purgeAppointmentImages(appointmentId, deps) {
  const {db, deleteImages} = deps;
  await deleteImages(appointmentId);
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
  const {db, logger: log} = deps;
  const parent = db.collection("appointments").doc(appointmentId);
  const snap = await parent.collection(IMAGES_SUBCOLLECTION).count().get();
  const count = snap.data().count;
  if (count > PICTURE_COUNT_WARN_CAP && log) {
    log.warn("appointment holds more photos than the app can read", {
      appointmentId,
      count,
      cap: PICTURE_COUNT_WARN_CAP,
    });
  }
  try {
    await parent.update({pictureCount: count});
  } catch (err) {
    if (err && err.code === 5) return -1; // NOT_FOUND — parent already deleted.
    throw err;
  }
  return count;
}

/**
 * Claims the right to recount one parent (first writer wins).
 *
 * FAILS OPEN everywhere: any error other than a live claim returns true and
 * recounts. Failing open costs one extra parent write — exactly the old
 * behaviour — while failing closed would leave `pictureCount` wrong with
 * nothing left to notice it.
 * @param {string} appointmentId
 * @param {!Object} deps `{db, logger, now}`.
 * @return {!Promise<boolean>} True when this invocation owns the recount.
 */
async function claimRecount(appointmentId, deps) {
  const {db, logger: log, now} = deps;
  const nowDate = now || new Date();
  const ref = db.collection(RECOUNT_CLAIM_COLLECTION).doc(appointmentId);
  try {
    await ref.create(claimBody(nowDate));
    return true;
  } catch (err) {
    if (!isAlreadyExists(err)) {
      if (log) log.warn("recount claim failed; recounting anyway", {err});
      return true;
    }
  }
  // A claim exists. Take over one older than the window so an invocation
  // killed between claiming and releasing can't suppress recounts until the
  // TTL policy gets round to it — and so a genuinely later write (the offline
  // queue's replay, a backfill re-run) always recounts.
  try {
    const snap = await ref.get();
    const claimedMs = toMillis(snap.get("claimedAt"));
    if (claimedMs != null &&
        nowDate.getTime() - claimedMs < RECOUNT_CLAIM_STALE_MS) {
      return false;
    }
    await ref.set(claimBody(nowDate));
    return true;
  } catch (err) {
    if (log) {
      log.warn("recount claim takeover failed; recounting anyway", {err});
    }
    return true;
  }
}

/**
 * Releases this invocation's claim. Best-effort: a failed delete leaves a
 * claim the staleness takeover above already treats as inert.
 * @param {string} appointmentId
 * @param {!Object} deps `{db, logger}`.
 * @return {!Promise<void>}
 */
async function releaseRecount(appointmentId, deps) {
  const {db, logger: log} = deps;
  try {
    await db.collection(RECOUNT_CLAIM_COLLECTION).doc(appointmentId).delete();
  } catch (err) {
    if (log) log.warn("recount claim release failed", {err});
  }
}

/**
 * Debounces the recount per parent: the first trigger of a photo batch claims
 * the parent, settles, and performs ONE recount; the rest return having done
 * nothing.
 *
 * WHY: `appendAppointmentPictures` writes N image docs in ONE batch, so N
 * triggers land on the SAME parent within milliseconds — against Firestore's
 * ~1 write/sec/document guidance — and, worse, every parent write re-fires
 * `notifyAppointmentChanges`. Ten photos on one job cost 10 recounts and 11
 * notification invocations for a single user action, multiplied again by
 * `retry: true` contention retries.
 *
 * **THE ORDER IS THE DESIGN: release the claim BEFORE running the aggregate.**
 * A suppressed sibling's document was committed before its trigger fired, and
 * its trigger fired before the release; the aggregate runs after the release,
 * so a strongly-consistent `count()` necessarily sees it. Nothing a debounce
 * suppressed can be missed. Count first and release after, and a photo written
 * in that gap would be both suppressed and uncounted — the one way this
 * optimisation could corrupt the number it maintains.
 *
 * **IT STILL RECOUNTS ON EVERY WRITE, INCLUDING AN UPDATE THAT CANNOT HAVE
 * MOVED THE COUNT.** `event.data` is deliberately never consulted. An
 * `if (before.exists && after.exists) return` guard was written and then
 * removed on purpose: the only paths it skips are the offline queue replaying
 * `set(..., {merge: true})` on the DERIVED doc id, and a backfill re-run — and
 * those two are the ONLY self-heal this counter has. A recount whose parent
 * `update()` keeps failing exhausts its retry window and leaves `pictureCount`
 * wrong forever, where an idempotent replay repairs it silently. The debounce
 * preserves that: a claim lives seconds and is deleted on the normal path, so
 * a later, separate write always claims afresh and always recounts. Suppress a
 * sibling of the batch in flight, never a replay.
 * @param {string} appointmentId
 * @param {!Object} deps `{db, logger, now, sleep, settleMs}`.
 * @return {!Promise<{skipped: boolean, count: ?number}>}
 */
async function debouncedRecountPictures(appointmentId, deps) {
  const mine = await claimRecount(appointmentId, deps);
  if (!mine) return {skipped: true, count: null};
  const sleep = deps.sleep || defaultSleep;
  const settleMs = deps.settleMs == null ? RECOUNT_SETTLE_MS : deps.settleMs;
  await sleep(settleMs);
  await releaseRecount(appointmentId, deps);
  // Released first (see above), so a recount that throws is also free to
  // re-claim on the trigger's retry rather than suppressing itself.
  const count = await recountPictures(appointmentId, deps);
  return {skipped: false, count};
}

// `retry: true` is safe and wanted: recursiveDelete is idempotent (a second
// pass finds nothing), and the orphans this prevents are permanent.
const cascadeDeleteAppointmentImages = onDocumentDeleted(
    {document: "appointments/{appointmentId}", retry: true},
    async (event) => {
      const appointmentId = event.params.appointmentId;
      await purgeAppointmentImages(appointmentId, {
        db: getFirestore(),
        deleteImages: deleteAppointmentImageBytes,
      });
      logger.info("appointment images purged", {appointmentId});
    },
);

// `retry: true` is safe because the write is an absolute count, not a delta —
// and because the claim is released before the aggregate, so a retry re-claims
// instead of suppressing itself. See `debouncedRecountPictures` for the
// ordering rule and for why no before/after guard belongs here.
const recountAppointmentPictures = onDocumentWritten(
    {
      document:
        `appointments/{appointmentId}/${IMAGES_SUBCOLLECTION}/{imageId}`,
      retry: true,
    },
    async (event) => {
      await debouncedRecountPictures(
          event.params.appointmentId, {db: getFirestore(), logger});
    },
);

module.exports = {
  cascadeDeleteAppointmentImages,
  // Exported for `maintenance.js`, so the image prefix has ONE owner.
  deleteAppointmentImageBytes,
  recountAppointmentPictures,
  purgeAppointmentImages,
  recountPictures,
  debouncedRecountPictures,
  IMAGES_SUBCOLLECTION,
  PICTURE_COUNT_WARN_CAP,
  RECOUNT_CLAIM_COLLECTION,
  RECOUNT_CLAIM_STALE_MS,
  RECOUNT_CLAIM_TTL_MS,
};
