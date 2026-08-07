const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");

const VALID_ROLES = new Set(["admin", "employee"]);
const VALID_BRIDGE_STATUS = new Set(["active", "disabled"]);

/**
 * True when the user doc should have a bridge entry — suppressed for
 * invited users (no uid) or unknown statuses.
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
 * True when the user doc was deleted or an active account was deactivated —
 * coordinates are PII and must not outlive the account.
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
 * Decides whether to revoke or restore the user's Auth credential — the
 * Firestore `status` field alone never blocked sign-in on its own.
 * `"restore"` also safely no-ops on first activation (invited->active).
 * @param {?object} beforeData user doc fields before the write, or null.
 * @param {?object} afterData user doc fields after the write, or null.
 * @return {?string} "revoke" | "restore" | null.
 */
function authAccessChange(beforeData, afterData) {
  // Deleted doc, or active account leaving active — mirrors shouldPurgePresence
  // so access and PII are revoked by the same rule.
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
 * Applies [authAccessChange]'s decision to the Auth account. It's idempotent,
 * and if the user is already gone (removed by account deletion), we swallow
 * that instead of retrying forever.
 * @param {string} uid Firebase Auth uid.
 * @param {string} change "revoke" | "restore".
 * @param {!Object} auth Admin Auth instance.
 * @return {!Promise<void>}
 */
async function applyAuthAccess(uid, change, auth) {
  try {
    if (change === "revoke") {
      await auth.updateUser(uid, {disabled: true});
      // Stops new ID tokens. An already-issued one stays valid until it
      // expires (<=1 h), but the firestore.rules status gate blocks reads
      // during that window.
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
 * Deletes every push/Live-Activity delivery artifact for a user — FCM/Live
 * Activity token rows plus the card marker. It's idempotent since deleting a
 * doc that's already gone is a no-op.
 * @param {!Object} db Firestore instance.
 * @param {string} userId Firestore doc id of the user.
 * @return {!Promise<void>}
 */
async function purgeDeliveryState(db, userId) {
  // recursiveDelete paginates internally so a user with >500 stale token rows
  // can't fail partway — same primitive account.js uses.
  const subcollections = ["fcmTokens", "liveActivityTokens"];
  for (const name of subcollections) {
    await db.recursiveDelete(db.collection(`users/${userId}/${name}`));
  }
  await db.collection("liveActivityCards").doc(userId).delete();
}

// Mirrors `users` into `usersByUid/{uid}` so security rules can resolve a
// caller's role from their auth uid alone. `retry: true` is safe here since
// every path writes absolute values (set/delete on deterministic doc ids).
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

      // Mirrors the users doc into the usersByUid bridge — auth-critical, so
      // it runs first and its errors stay un-swallowed (retry:true re-runs).
      const mirrorBridge = async () => {
        // Skip writes with an unexpected role, as a defensive check. The
        // presence purge below still runs, so PII gets cleaned up regardless.
        if (after && after.role && !VALID_ROLES.has(after.role)) {
          logger.warn("syncUsersByUid: unexpected role; skipping", {
            userId,
            role: after.role,
          });
          return;
        }

        // On a uid rotation, the stale delete and the new set land in ONE
        // WriteBatch, so a crash between them can't leave both bridge docs
        // live. We don't swallow the batch error — retry:true re-runs the
        // handler.
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

        // No new bridge follows — the deletes below are terminal cleanup and
        // stay un-swallowed so retry:true can re-run a failed delete.
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

      // Purges PII presence data after the bridge mirror completes. Failures
      // rethrow so retry:true safely reconverges — mirrorBridge and delete()
      // are both idempotent.
      if (shouldPurgePresence(before, after)) {
        try {
          await db.doc(`users/${userId}/presence/location`).delete();
          // Stops push/Live Activity delivery along with the account, so a
          // deactivated tech doesn't keep showing up on a client's Lock
          // Screen card. Ending the on-device card itself needs APNs (left
          // to the two functions that bind APNS_SECRETS), so it just expires
          // on its own TTL.
          await purgeDeliveryState(db, userId);
        } catch (err) {
          logger.warn("syncUsersByUid: presence purge failed", {
            userId,
            error: err.message,
          });
          throw err;
        }
      }

      // Handle the Auth credential last — this is defence-in-depth beyond
      // the rules' status gate, and running it after the bridge mirror means
      // it never blocks that write.
      const change = authAccessChange(before, after);
      const authUid = afterUid || beforeUid;
      if (change && authUid) {
        try {
          await applyAuthAccess(authUid, change, getAuth());
          logger.info("syncUsersByUid: auth access updated", {userId, change});
        } catch (err) {
          // Rethrown so retry:true re-runs — every step above is idempotent.
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
  shouldPurgePresence,
  authAccessChange,
  applyAuthAccess,
};
