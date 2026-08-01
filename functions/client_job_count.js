"use strict";

/**
 * @fileoverview Maintains the denormalized `jobCount` on client docs.
 *
 * The count is recomputed with a Firestore `count()` aggregate and written
 * ABSOLUTELY — never `FieldValue.increment`. This trigger runs with
 * `retry: true`, and a retried event would double-count an increment; an
 * absolute write is idempotent by construction. Same principle as
 * `propagateClientEdits`.
 *
 * Cost is ~1 aggregate read per appointment write that creates, deletes or
 * reassigns a job. Backfill is lazy: a client's count self-heals on its next
 * appointment write, and a row renders no count until the field exists.
 *
 * @module client_job_count
 */

const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");

/** Firestore `NOT_FOUND` — the client was deleted out from under the job. */
const NOT_FOUND = 5;

/**
 * Reads a doc's `clientId` as a non-empty trimmed string, or "".
 * @param {?Object} data Appointment document fields, or null.
 * @return {string}
 */
function clientIdOf(data) {
  if (!data) return "";
  const raw = data.clientId;
  return typeof raw === "string" ? raw.trim() : "";
}

/**
 * Which client docs need their `jobCount` recomputed after this write.
 *
 * Creates and deletes touch one client; a reassignment touches both. An edit
 * that leaves `clientId` alone touches none, so an ordinary title or time
 * change costs zero reads. Personal jobs carry no `clientId` and are skipped.
 *
 * @param {?Object} beforeData Appointment fields before the write, or null.
 * @param {?Object} afterData Appointment fields after the write, or null.
 * @return {!Array<string>} Deduped client doc ids, possibly empty.
 */
function clientsToRecount(beforeData, afterData) {
  const before = clientIdOf(beforeData);
  const after = clientIdOf(afterData);
  if (before === after) return [];
  const ids = [];
  if (before) ids.push(before);
  if (after) ids.push(after);
  return ids;
}

/**
 * Recomputes and writes `jobCount` for one client.
 * @param {!Object} db Firestore instance.
 * @param {string} clientId Client doc id.
 * @return {!Promise<void>}
 */
async function recountOne(db, clientId) {
  const snapshot = await db
      .collection("appointments")
      .where("clientId", "==", clientId)
      .count()
      .get();
  const jobCount = snapshot.data().count;
  try {
    // update(), not set({merge:true}) — a client removed out-of-band (the app
    // has no delete path, but the Admin SDK and console bypass that) must not
    // be resurrected as a stub doc holding nothing but a count.
    await db.collection("clients").doc(clientId).update({jobCount});
  } catch (err) {
    if (err && err.code === NOT_FOUND) return;
    throw err;
  }
}

const recountClientJobs = onDocumentWritten(
    {
      document: "appointments/{appointmentId}",
      region: "us-central1",
      // Safe to retry: every write is an absolute recount.
      retry: true,
    },
    async (event) => {
      const before = event.data && event.data.before;
      const after = event.data && event.data.after;
      const ids = clientsToRecount(
          before && before.exists ? before.data() : null,
          after && after.exists ? after.data() : null,
      );
      if (ids.length === 0) return;

      // eslint-disable-next-line global-require
      const {getFirestore} = require("firebase-admin/firestore");
      const db = getFirestore();
      for (const clientId of ids) {
        try {
          await recountOne(db, clientId);
        } catch (err) {
          logger.error("recountClientJobs failed", {clientId, err});
          throw err;
        }
      }
    },
);

module.exports = {clientsToRecount, recountClientJobs};
