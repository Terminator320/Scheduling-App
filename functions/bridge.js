const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const {getFirestore} = require("firebase-admin/firestore");

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

      // Defensive: skip writes whose role is outside the expected set.
      if (after && after.role && !VALID_ROLES.has(after.role)) {
        logger.warn("syncUsersByUid: unexpected role; skipping", {
          userId,
          role: after.role,
        });
        return;
      }

      const staleUid = beforeUid && beforeUid !== afterUid ? beforeUid : "";

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
    },
);

module.exports = {syncUsersByUid, shouldHaveBridge, bridgeBody};
