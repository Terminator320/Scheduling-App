const {onObjectFinalized} = require("firebase-functions/v2/storage");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {getStorage} = require("firebase-admin/storage");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

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

  const isJpeg = buffer[0] === 0xFF && buffer[1] === 0xD8 && buffer[2] === 0xFF;
  const isPng =
    buffer[0] === 0x89 && buffer[1] === 0x50 &&
    buffer[2] === 0x4E && buffer[3] === 0x47;

  if (!isJpeg && !isPng) {
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
 * prefix (`appointments/{id}/images/`). Returns false (and logs) on failure —
 * the Firestore doc is already gone by the time this runs, so a Storage error
 * only orphans bytes and must not be treated as a purge failure.
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

      schedule: "every day 03:00",
      timeZone: "America/Toronto",
      maxInstances: 1,
    },
    async () => {
      const db = getFirestore();
      const cutoff = new Date();
      cutoff.setFullYear(cutoff.getFullYear() - HISTORY_RETENTION_YEARS);
      const col = db.collection("appointments");

      let purged = 0;
      let imageFailures = 0;
      // Every fetched doc is deleted, so the next page's oldest terminal visit
      // simply takes its place — a plain limit loop advances without a cursor.
      for (;;) {
        const snap = await col
            .where("status", "in", PURGE_STATUSES)
            .where("startTime", "<", cutoff)
            .orderBy("startTime")
            .limit(PURGE_BATCH_SIZE)
            .get();
        if (snap.empty) break;

        const batch = db.batch();
        for (const doc of snap.docs) batch.delete(doc.ref);
        await batch.commit();
        purged += snap.size;

        for (const doc of snap.docs) {
          const ok = await deleteAppointmentImages(doc.id);
          if (!ok) imageFailures += 1;
        }

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

// ----- One-time legacy client-name backfill ---------------------------------
//
// Pre-Wave-reshape "business-only" client docs stored their label under
// `businessName` with an empty `name`. The clients list now orders by `name`
// (alphabetical), so those docs sort to the very top with a blank key (and a
// doc missing `name` entirely would be excluded). This idempotent migration
// copies `businessName` -> `name` wherever `name` is empty, records a guard
// doc, and no-ops on every subsequent run. Admin SDK bypasses rules; it runs
// unattended and can be removed once it has completed in production.
const CLIENT_NAME_BACKFILL_GUARD = "maintenance/clientNameBackfill";
// Well under Firestore's 500-writes-per-batch ceiling, with headroom.
const CLIENT_NAME_BACKFILL_BATCH = 200;

const backfillLegacyClientNames = onSchedule(
    {schedule: "every 24 hours", maxInstances: 1},
    async () => {
      const db = getFirestore();
      const guardRef = db.doc(CLIENT_NAME_BACKFILL_GUARD);
      const guard = await guardRef.get();
      if (guard.exists && guard.data() && guard.data().done === true) {
        logger.debug("backfillLegacyClientNames: already done");
        return;
      }

      // Full scan is safe at the planned ~650-client scale (mirrors the import
      // index); the doc-id read order never excludes a doc missing `name`.
      const snap = await db.collection("clients").get();
      const docs = (snap && Array.isArray(snap.docs)) ? snap.docs : [];
      let batch = db.batch();
      let opsInBatch = 0;
      let fixed = 0;
      for (const doc of docs) {
        const d = doc.data() || {};
        const name = typeof d.name === "string" ? d.name.trim() : "";
        const businessName =
          typeof d.businessName === "string" ? d.businessName.trim() : "";
        if (name !== "" || businessName === "") continue;
        batch.update(doc.ref, {
          name: businessName,
          updatedAt: FieldValue.serverTimestamp(),
        });
        opsInBatch += 1;
        fixed += 1;
        if (opsInBatch >= CLIENT_NAME_BACKFILL_BATCH) {
          await batch.commit();
          batch = db.batch();
          opsInBatch = 0;
        }
      }
      if (opsInBatch > 0) await batch.commit();

      await guardRef.set({
        done: true,
        fixed,
        completedAt: FieldValue.serverTimestamp(),
      });
      logger.info("backfillLegacyClientNames: done",
          {fixed, scanned: docs.length});
    },
);

module.exports = {
  validateUploadedImage,
  purgeExpiredHistory,
  backfillLegacyClientNames,
};
