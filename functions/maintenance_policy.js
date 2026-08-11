"use strict";

/**
 * @fileoverview Pure maintenance POLICY — the retention/deletion decisions
 * behind `maintenance.js`, extracted so they can be tested without the
 * firebase-admin handles wrapped around them.
 *
 * `maintenance.js` resolves a Storage bucket and a Firestore handle at call
 * time, so it cannot be `require()`d outside the emulator. Everything here
 * takes its I/O as injected deps instead, which is the same split
 * `notification_policy` / `notification_utils` already use.
 *
 * This module is the one place the purge's three load-bearing rules live:
 * the status gate, the images-before-doc ordering, and the loop's
 * termination. All three delete data irreversibly if they regress.
 *
 * @module maintenance_policy
 */

/** Appointments older than this (by `startTime`) are eligible for purge. */
const HISTORY_RETENTION_YEARS = 2;

/**
 * ONLY terminal appointments are ever purged. A `pending`/`in_progress` job
 * is live work no matter how old its startTime is — widening this set deletes
 * jobs that were never finished.
 */
const PURGE_STATUSES = ["done", "cancelled"];

/** Well under Firestore's 500-writes-per-batch ceiling, with headroom. */
const PURGE_BATCH_SIZE = 200;

/** Only these object paths are appointment images. */
const APPOINTMENT_IMAGE_PREFIX = /^appointments\/[^/]+\/images\//;

/**
 * The instant before which terminal history is purgeable.
 * @param {!Date} now
 * @return {!Date}
 */
function historyCutoff(now) {
  const cutoff = new Date(now.getTime());
  cutoff.setFullYear(cutoff.getFullYear() - HISTORY_RETENTION_YEARS);
  return cutoff;
}

/**
 * True when a finalized Storage object is an appointment image and therefore
 * subject to magic-byte validation. Anything else is left alone.
 * @param {string} filePath
 * @return {boolean}
 */
function isAppointmentImagePath(filePath) {
  return APPOINTMENT_IMAGE_PREFIX.test(String(filePath || ""));
}

/**
 * Purges terminal appointments older than the cutoff: Storage images first,
 * then the docs whose images actually cleared.
 *
 * @param {{
 *   db: !Object,
 *   deleteImages: function(string): !Promise<boolean>,
 *   now: !Date,
 * }} deps `deleteImages` resolves false when a prefix could NOT be cleared.
 * @return {!Promise<{purged: number, imageFailures: number, cutoff: !Date}>}
 */
async function runHistoryPurge(deps) {
  const {db, deleteImages, now} = deps;
  const cutoff = historyCutoff(now);
  const col = db.collection("appointments");

  let purged = 0;
  let imageFailures = 0;
  // A plain limit loop advances without a cursor, since cleared docs are
  // deleted. The loop stops when a page makes no progress — meaning all image
  // cleanups failed, so retrying would just repeat them.
  for (;;) {
    const snap = await col
        .where("status", "in", PURGE_STATUSES)
        .where("startTime", "<", cutoff)
        .orderBy("startTime")
        .limit(PURGE_BATCH_SIZE)
        .get();
    if (snap.empty) break;

    // Images FIRST, then only the docs whose prefix actually cleared. The
    // reverse order orphans the bytes forever: nothing would point at them.
    const results = await Promise.all(
        snap.docs.map((doc) => deleteImages(doc.id)),
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

    // No page progress, so bail rather than refetching the same stuck docs
    // forever — the next quarterly run retries them.
    if (deletable === 0) break;
    if (snap.size < PURGE_BATCH_SIZE) break;
  }

  return {purged, imageFailures, cutoff};
}

module.exports = {
  // Exported for unit tests: the purge is the only unattended, irreversible
  // deletion in the repo, so its bounds are asserted against these rather than
  // against copied literals.
  HISTORY_RETENTION_YEARS,
  PURGE_STATUSES,
  PURGE_BATCH_SIZE,
  historyCutoff,
  isAppointmentImagePath,
  runHistoryPurge,
};
