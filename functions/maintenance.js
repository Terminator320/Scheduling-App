const {onObjectFinalized} = require("firebase-functions/v2/storage");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {getStorage} = require("firebase-admin/storage");
const {getFirestore} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const {hasValidImageMagic} = require("./image_magic");

// Validates magic bytes of newly uploaded appointment images and deletes any
// file that isn't JPEG or PNG — the Storage rule trusts client-provided
// contentType, so this closes that gap server-side.
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
// Purges done/cancelled appointments (Firestore doc + Storage images) once
// HISTORY_RETENTION_YEARS has elapsed since `startTime`. Non-terminal
// appointments are never touched.
const HISTORY_RETENTION_YEARS = 2;
const PURGE_STATUSES = ["done", "cancelled"];
// Well under Firestore's 500-writes-per-batch ceiling, with headroom.
const PURGE_BATCH_SIZE = 200;

/**
 * Deletes every Storage object under an appointment's image prefix
 * (`appointments/{id}/images/`) — best effort, so a failure just logs and
 * returns false, and the caller keeps the doc around for the next run to
 * retry.
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
      // Runs quarterly at 03:00 Toronto on the 1st of Jan/Apr/Jul/Oct
      // (unix-cron: min hour dom mon dow). That's plenty, since history
      // only grows past the 2-year cutoff slowly.
      schedule: "0 3 1 1,4,7,10 *",
      timeZone: "America/Toronto",
      maxInstances: 1,
      // 1800s (the max for a scheduled trigger) gives a quarter's worth of
      // newly-expired history room to finish in a single run.
      timeoutSeconds: 1800,
    },
    async () => {
      const db = getFirestore();
      const cutoff = new Date();
      cutoff.setFullYear(cutoff.getFullYear() - HISTORY_RETENTION_YEARS);
      const col = db.collection("appointments");

      let purged = 0;
      let imageFailures = 0;
      // A plain limit loop advances without a cursor, since cleared docs
      // are deleted. The loop stops when a page makes no progress —
      // meaning all image cleanups failed, so retrying would just repeat
      // them.
      for (;;) {
        const snap = await col
            .where("status", "in", PURGE_STATUSES)
            .where("startTime", "<", cutoff)
            .orderBy("startTime")
            .limit(PURGE_BATCH_SIZE)
            .get();
        if (snap.empty) break;

        // Delete each doc's image prefix FIRST (concurrently), then delete
        // only the docs whose prefix actually cleared — reversed order would
        // orphan the images forever on a Storage failure.
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

        // No page progress, so bail rather than refetching the same stuck
        // docs forever — the next quarterly run will retry them.
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
