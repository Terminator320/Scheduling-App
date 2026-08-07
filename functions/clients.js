"use strict";

/**
 * @fileoverview Admin-only client deletion. A client is normally ARCHIVED, not
 * deleted; delete exists for junk data only and is refused for any client that
 * still has appointments, since deleting one orphans that history (the visits
 * keep a denormalized `clientName` but lose the `clientId` link). `allow
 * delete` on `/clients` is withdrawn in `firestore.rules`, so this callable is
 * the only delete path — rules cannot express "only when this client has no
 * appointments" (there is no cheap way to count a foreign collection there).
 * @module clients
 */

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const {getFirestore} = require("firebase-admin/firestore");

const {
  assertPayloadShape,
  requireString,
  assertAdmin,
  enforceDurableRateLimit,
} = require("./security");

const APP_CHECK = {enforceAppCheck: true};
const DELETE_RATE_MAX = 20;
const DELETE_RATE_WINDOW_MS = 60 * 60 * 1000;

/**
 * Deletes a client, refusing when it still has appointments.
 *
 * The count is a LIVE count() aggregate, deliberately not the denormalized
 * `jobCount` on the client doc: that field is lazily backfilled by
 * recountClientJobs, so it can be stale, missing, or wrong on a client whose
 * appointments were reassigned out-of-band. Deleting on a stale zero is
 * exactly the orphaned-history bug this gate exists to prevent.
 *
 * Exported separately from the callable so it unit-tests against an injected
 * db with no emulator.
 * @param {*} db Firestore instance.
 * @param {string} clientId Client doc id.
 * @return {!Promise<void>}
 */
async function performDeleteClient(db, clientId) {
  const ref = db.collection("clients").doc(clientId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "client-not-found");
  }

  const agg = await db
      .collection("appointments")
      .where("clientId", "==", clientId)
      .count()
      .get();
  const jobs = agg.data().count;
  if (jobs > 0) {
    throw new HttpsError("failed-precondition", "client-has-history");
  }

  await ref.delete();
}

// Guard order per .claude/rules/security.md: auth -> assertAdmin ->
// payload -> rate limit -> work. The payload is validated before a limiter
// slot is consumed so malformed bursts can't exhaust a real caller's window.
const deleteClient = onCall(APP_CHECK, async (req) => {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  await assertAdmin(req.auth.uid);
  assertPayloadShape(req.data, new Set(["clientId"]));
  const clientId = requireString(req.data, "clientId", 128);
  // `.doc()` throws synchronously on an id containing "/", which would surface
  // as an opaque internal error rather than a validation failure.
  if (clientId.includes("/")) {
    throw new HttpsError("invalid-argument", "invalid-clientId");
  }
  await enforceDurableRateLimit(
      "deleteClient", req.auth.uid, DELETE_RATE_MAX, DELETE_RATE_WINDOW_MS);

  await performDeleteClient(getFirestore(), clientId);
  logger.info("deleteClient: deleted", {uid: req.auth.uid, clientId});
});

module.exports = {deleteClient, performDeleteClient};
