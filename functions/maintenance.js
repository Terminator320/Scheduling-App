const {onObjectFinalized} = require("firebase-functions/v2/storage");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {getStorage} = require("firebase-admin/storage");
const {getFirestore} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const {hasValidImageMagic} = require("./image_magic");

// Validates magic bytes of newly uploaded appointment images and deletes any
// file that is not JPEG (FF D8 FF) or PNG (89 50 4E 47). The Storage rule
// trusts client-provided contentType, so a direct REST/SDK caller could
// upload arbitrary content; this trigger closes that gap server-side.
const validateUploadedImage = onObjectFinalized(async (event) => {
  const obj = event.data;
  const filePath = obj.name ?? "";

  if (!filePath.match(/^appointments\/[^/]+\/images\//)) return;

  const file = getStorage().bucket(obj.bucket).file(filePath);
  let buffer;
  try {
    const stream = file.createReadStream({start: 0, end: 7});
    const chunks = [];
    await new Promise((resolve, reject) => {
      stream.on("data", (c) => chunks.push(c));
      stream.on("end", resolve);
      stream.on("error", reject);
    });
    buffer = Buffer.concat(chunks);
  } catch (err) {
    logger.warn("validateUploadedImage: read failed — deleting", {
      filePath,
      err: err.message,
    });
    await file.delete().catch((delErr) =>
      logger.error("validateUploadedImage: delete after read-fail failed", {
        filePath,
        err: delErr.message,
      }),
    );
    return;
  }

  if (!hasValidImageMagic(buffer)) {
    logger.warn("validateUploadedImage: invalid magic bytes — deleting", {
      filePath,
    });
    await file.delete().catch((err) =>
      logger.error("validateUploadedImage: delete failed", {
        filePath,
        err: err.message,
      }),
    );
  }
});

// ----- Scheduled history purge ----------------------------------------------
//
// History retention: done/cancelled appointments stay in history for
// HISTORY_RETENTION_YEARS, then are purged automatically — the Firestore doc
// AND its Storage images — once (and only once) that long has elapsed. The
// cutoff is anchored on `startTime` (the visit date, which is what the history
// view is keyed on) and is strict, so nothing is removed before the full
// window passes. Non-terminal appointments are never touched, however old —
// only history is purged. Image cleanup mirrors the manual delete path in
// EventDetailsController.deleteAppointment so a purged appointment leaves no
// orphaned bytes. Admin SDK bypasses security rules; this runs unattended.
const HISTORY_RETENTION_YEARS = 2;
const PURGE_STATUSES = ["done", "cancelled"];
// Well under Firestore's 500-writes-per-batch ceiling, with headroom.
const PURGE_BATCH_SIZE = 200;

/**
 * Best-effort deletion of every Storage object under an appointment's image
 * prefix (`appointments/{id}/images/`). Returns false (and logs) on failure.
 * Images are deleted BEFORE the Firestore doc: a doc whose image prefix
 * failed to clear is kept so the next quarterly run retries it — deleting the
 * doc first would orphan the PII bytes forever (nothing would ever point at
 * them again).
 * @param {string} appointmentId Firestore doc id of the purged appointment.
 * @return {!Promise<boolean>} true when the prefix was cleared.
 */
async function deleteAppointmentImages(appointmentId) {
  const prefix = `appointments/${appointmentId}/images/`;
  try {
    await getStorage().bucket().deleteFiles({prefix});
    return true;
  } catch (err) {
    logger.warn("purgeExpiredHistory: image cleanup failed", {
      appointmentId,
      err: err.message,
    });
    return false;
  }
}

const purgeExpiredHistory = onSchedule(
    {
      // Quarterly — 03:00 Toronto on the 1st of Jan/Apr/Jul/Oct (unix-cron:
      // min hour dom mon dow). History only grows past the 2-year cutoff
      // slowly, so a quarterly sweep is plenty, and it keeps the "leftovers
      // carry to the next run" window down to ~3 months (vs a full year) if a
      // run ever leaves work behind.
      schedule: "0 3 1 1,4,7,10 *",
      timeZone: "America/Toronto",
      maxInstances: 1,
      // Image deletion is a Storage round-trip per appointment, and a quarterly
      // run clears a quarter of newly-expired history at once. 3600s (the gen2
      // max) gives that backlog room to finish in a single run rather than
      // stranding leftovers until next quarter.
      timeoutSeconds: 3600,
    },
    async () => {
      const db = getFirestore();
      const cutoff = new Date();
      cutoff.setFullYear(cutoff.getFullYear() - HISTORY_RETENTION_YEARS);
      const col = db.collection("appointments");

      let purged = 0;
      let imageFailures = 0;
      // Docs whose images cleared are deleted, so the next page's oldest
      // terminal visit takes its place — a plain limit loop advances without
      // a cursor. Docs whose image cleanup FAILED are kept (see below) and
      // would repeat in the next page, so the loop also stops when a page
      // makes no progress.
      for (;;) {
        const snap = await col
            .where("status", "in", PURGE_STATUSES)
            .where("startTime", "<", cutoff)
            .orderBy("startTime")
            .limit(PURGE_BATCH_SIZE)
            .get();
        if (snap.empty) break;

        // Delete each doc's image prefix FIRST (concurrently rather than one
        // network round-trip at a time), then delete only the docs whose
        // prefix actually cleared. Reversed order would orphan the images'
        // PII forever on a Storage failure: with the doc gone, no later run
        // would ever retry that prefix.
        const results = await Promise.all(
            snap.docs.map((doc) => deleteAppointmentImages(doc.id)),
        );

        const batch = db.batch();
        let deletable = 0;
        snap.docs.forEach((doc, i) => {
          if (results[i]) {
            batch.delete(doc.ref);
            deletable += 1;
          } else {
            imageFailures += 1;
          }
        });
        if (deletable > 0) await batch.commit();
        purged += deletable;

        // No page progress (every image delete failed) — bail out rather
        // than refetching the same stuck docs forever; the next quarterly run
        // retries them.
        if (deletable === 0) break;
        if (snap.size < PURGE_BATCH_SIZE) break;
      }

      logger.info("purgeExpiredHistory: done", {
        purged,
        imageFailures,
        retentionYears: HISTORY_RETENTION_YEARS,
        cutoff: cutoff.toISOString(),
      });
    },
);

module.exports = {
  validateUploadedImage,
  purgeExpiredHistory,
};
