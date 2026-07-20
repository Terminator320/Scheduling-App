const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");

const VALID_ROLES = new Set(["admin", "employee"]);
const VALID_BRIDGE_STATUS = new Set(["active", "disabled"]);

/**
 * Returns true when the user doc should have a corresponding bridge entry.
 * Bridge is suppressed for invited users (no uid yet) or unknown statuses.
 * @param {object} data user document fields.
 * @return {boolean}
 */
function shouldHaveBridge(data) {
  if (!data) return false;
  const uid = data.uid;
  const status = data.status;
  if (typeof uid !== "string" || uid === "") return false;
  if (!VALID_BRIDGE_STATUS.has(status)) return false;
  return true;
}

/**
 * Body to upsert into usersByUid for the given userId + after-snapshot data.
 * @param {string} userId Firestore doc id of the user.
 * @param {object} data user document fields.
 * @return {{role: string, docId: string, status: string}}
 */
function bridgeBody(userId, data) {
  return {
    role: data.role,
    docId: userId,
    status: data.status,
  };
}

/**
 * Pure decision: should the user's live-location presence doc be purged?
 * True when the user doc was deleted (after == null) or when an active
 * account was deactivated (before active, after not active). Never on
 * create (before == null), active->active, or invited->active. Coordinates
 * are PII, so a departed/disabled account must not leave its last location.
 * @param {?object} beforeData user doc fields before the write, or null.
 * @param {?object} afterData user doc fields after the write, or null.
 * @return {boolean}
 */
function shouldPurgePresence(beforeData, afterData) {
  if (!beforeData) return false;
  if (!afterData) return true;
  return beforeData.status === "active" && afterData.status !== "active";
}

/**
 * Pure decision: what should happen to the user's Firebase Auth credential?
 *
 * The Firestore `status` field alone never stopped a terminated employee from
 * authenticating — it only stopped them being authorized. Deactivation now
 * disables the Auth account and revokes refresh tokens; reactivation re-enables
 * it, or a re-hired employee would be locked out with no visible cause.
 *
 * `"restore"` also covers invited->active (first activation), where the account
 * was never disabled — updateUser is idempotent, so that's a harmless no-op.
 * @param {?object} beforeData user doc fields before the write, or null.
 * @param {?object} afterData user doc fields after the write, or null.
 * @return {?string} "revoke" | "restore" | null.
 */
function authAccessChange(beforeData, afterData) {
  // Deleted doc, or an active account leaving active. Mirrors
  // shouldPurgePresence so access and PII are revoked by the same rule.
  if (beforeData && (!afterData ||
      (beforeData.status === "active" && afterData.status !== "active"))) {
    return "revoke";
  }
  if (afterData && afterData.status === "active" &&
      (!beforeData || beforeData.status !== "active")) {
    return "restore";
  }
  return null;
}

/**
 * Applies [authAccessChange]'s decision to the Auth account. Idempotent:
 * disabling an already-disabled user is a no-op, and a missing user (the
 * account-deletion flow removes it) is swallowed rather than retried forever.
 * @param {string} uid Firebase Auth uid.
 * @param {string} change "revoke" | "restore".
 * @param {!Object} auth Admin Auth instance.
 * @return {!Promise<void>}
 */
async function applyAuthAccess(uid, change, auth) {
  try {
    if (change === "revoke") {
      await auth.updateUser(uid, {disabled: true});
      // Stops NEW ID tokens being minted. An already-issued ID token stays
      // valid until it expires (<=1 h) — the firestore.rules status gate is
      // what blocks reads in that window.
      await auth.revokeRefreshTokens(uid);
    } else {
      await auth.updateUser(uid, {disabled: false});
    }
  } catch (err) {
    if (err && err.code === "auth/user-not-found") {
      logger.debug("syncUsersByUid: no auth user to update", {change});
      return;
    }
    throw err;
  }
}

/**
 * Deletes every push/Live-Activity delivery artifact for a user: the FCM and
 * Live Activity token rows plus the server-owned card marker. Idempotent —
 * deletes of missing docs are no-ops, so a retried event converges.
 * @param {!Object} db Firestore instance.
 * @param {string} userId Firestore doc id of the user.
 * @return {!Promise<void>}
 */
async function purgeDeliveryState(db, userId) {
  // recursiveDelete (not a single batch) — it paginates internally, so a user
  // with >500 stale token rows can't fail partway. Same primitive account.js
  // uses to avoid orphaning these subcollections.
  const subcollections = ["fcmTokens", "liveActivityTokens"];
  for (const name of subcollections) {
    await db.recursiveDelete(db.collection(`users/${userId}/${name}`));
  }
  await db.collection("liveActivityCards").doc(userId).delete();
}

// Rules can only `get` documents by full path, and `users` docs use Firestore-
// generated IDs — this trigger mirrors `users` into `usersByUid/{uid}` so
// security rules can resolve a caller's role from their auth uid alone.
// `retry: true` is safe: every path writes absolute values (set/delete on
// deterministic doc ids), so a crash-retry converges on the same bridge state.
const syncUsersByUid = onDocumentWritten(
    {document: "users/{userId}", retry: true},
    async (event) => {
      const userId = event.params.userId;
      const beforeSnap = event.data?.before;
      const afterSnap = event.data?.after;
      const before = beforeSnap?.exists ? beforeSnap.data() : null;
      const after = afterSnap?.exists ? afterSnap.data() : null;

      const db = getFirestore();
      const bridge = db.collection("usersByUid");

      const beforeUid =
        before && typeof before.uid === "string" ? before.uid : "";
      const afterUid =
        after && typeof after.uid === "string" ? after.uid : "";

      const staleUid = beforeUid && beforeUid !== afterUid ? beforeUid : "";

      // Mirror the users doc into the usersByUid bridge. This is the
      // auth-critical work: role resolution depends on it, so it runs first
      // and its errors stay un-swallowed (retry:true re-runs the handler).
      const mirrorBridge = async () => {
        // Defensive: skip writes whose role is outside the expected set.
        // Note: the presence purge below still runs even when this guard
        // skips the mirror — an untrusted doc still gets its PII cleaned up,
        // and presence self-heals on the client's next location write.
        if (after && after.role && !VALID_ROLES.has(after.role)) {
          logger.warn("syncUsersByUid: unexpected role; skipping", {
            userId,
            role: after.role,
          });
          return;
        }

        // uid rotation into a valid bridge: the stale delete and the new set
        // land in ONE WriteBatch so a crash between them can't leave BOTH
        // bridge docs live (two uids resolving to the same users doc). The
        // batch error is NOT swallowed — retry:true re-runs the handler.
        if (after && shouldHaveBridge(after)) {
          const batch = db.batch();
          if (staleUid) batch.delete(bridge.doc(staleUid));
          batch.set(bridge.doc(afterUid), bridgeBody(userId, after));
          await batch.commit();
          logger.info("syncUsersByUid: bridge upserted", {
            userId,
            uid: afterUid,
            staleUidRemoved: staleUid || undefined,
            role: after.role,
            status: after.status,
          });
          return;
        }

        // No new bridge follows — the deletes below are terminal cleanup. They
        // also stay un-swallowed so retry:true can re-run a failed delete.
        if (staleUid) {
          await bridge.doc(staleUid).delete();
        }

        if (!after) {
          if (beforeUid) {
            logger.info("syncUsersByUid: user deleted -> bridge removed", {
              userId,
              uid: beforeUid,
            });
          }
          return;
        }

        if (afterUid) {
          await bridge.doc(afterUid).delete();
        }
        logger.debug("syncUsersByUid: no bridge needed", {
          userId,
          status: after.status,
          hasUid: !!afterUid,
        });
      };

      await mirrorBridge();

      // Live-location presence is PII. Once the account is deleted or
      // deactivated, purge its last coordinates. This runs strictly AFTER the
      // bridge mirror above (which stays un-swallowed and completes first) —
      // a purge failure must never precede, block, or corrupt that mirror.
      // But a purge failure MUST still be retried: on error, log (no
      // coordinates) then RETHROW so retry:true re-runs the handler. That's
      // safe because mirrorBridge is idempotent (absolute set/delete writes,
      // per the comments above), so a retried event just re-mirrors — a
      // harmless no-op if it already succeeded — then re-attempts the purge.
      // delete() of an already-missing doc is itself a no-op, so repeated
      // retries converge without ever leaving stale coordinates unpurged.
      if (shouldPurgePresence(before, after)) {
        try {
          await db.doc(`users/${userId}/presence/location`).delete();
          // Push + Live Activity delivery must stop with the account. Without
          // this a deactivated tech keeps a Lock Screen card showing a client
          // name and address, and a later reschedule pushes a refreshed one.
          // Deleting the token rows is what actually stops delivery; the card
          // marker goes too so the dispatcher stops resolving a card that can
          // no longer be reached. (Ending the on-device card needs an APNs
          // send, and only the two functions binding APNS_SECRETS may do that
          // — the orphaned card expires on its own TTL.)
          await purgeDeliveryState(db, userId);
        } catch (err) {
          logger.warn("syncUsersByUid: presence purge failed", {
            userId,
            error: err.message,
          });
          throw err;
        }
      }

      // Auth credential last: the rules gate (isAssignedEmployee /
      // isAssignedToAppointment require status 'active') is the immediate
      // protection, this is defence-in-depth that stops the account
      // authenticating at all. Runs AFTER the bridge mirror for the same
      // reason the purge does — it must never block or corrupt that write.
      const change = authAccessChange(before, after);
      const authUid = afterUid || beforeUid;
      if (change && authUid) {
        try {
          await applyAuthAccess(authUid, change, getAuth());
          logger.info("syncUsersByUid: auth access updated", {userId, change});
        } catch (err) {
          // Rethrown so retry:true re-runs; every step above is idempotent.
          logger.warn("syncUsersByUid: auth access update failed", {
            userId,
            change,
            error: err.message,
          });
          throw err;
        }
      }
    },
);

module.exports = {
  syncUsersByUid,
  shouldHaveBridge,
  bridgeBody,
  shouldPurgePresence,
  authAccessChange,
  applyAuthAccess,
};
