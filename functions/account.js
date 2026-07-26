const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");

const {assertPayloadShape, enforceDurableRateLimit} = require("./security");

// deleteAccount is capped at AUTH_RATE_MAX attempts per AUTH_RATE_WINDOW_MS,
// enforced in Firestore (not in-memory) so the cap holds across instances
// and cold starts.
const AUTH_RATE_MAX = 5;
const AUTH_RATE_WINDOW_MS = 15 * 60 * 1000;

// deleteAccount requires the caller to have re-authenticated within this
// window, since a still-valid ID token alone shouldn't trigger deletion.
const REAUTH_MAX_AGE_SECONDS = 5 * 60;

/**
 * True when the caller's re-authentication is missing or too old to permit an
 * irreversible delete. Pure/testable.
 * @param {*} authTime ID-token `auth_time` (epoch seconds) or undefined.
 * @param {number} nowSec Current time in epoch seconds.
 * @param {number} maxAgeSeconds Allowed staleness window in seconds.
 * @return {boolean}
 */
function isReauthStale(authTime, nowSec, maxAgeSeconds) {
  return typeof authTime !== "number" ||
      nowSec - authTime > maxAgeSeconds;
}

// ----- deleteAccount callable ------------------------------------------------
//
// Satisfies the in-app deletion requirement from Apple App Store Guideline 5.1.1(v)
// and the Google Play Account Deletion policy; the client re-authenticates first and
// the server also re-checks auth_time against REAUTH_MAX_AGE_SECONDS.
//
// Scope of deletion (intentionally narrow — see plan §C6):
//   1. The caller's `users/{docId}` Firestore document (syncUsersByUid then
//      clears `usersByUid/{uid}` automatically).
//   2. The Firebase Auth user.
// Shared business data (appointments, clients, images) is untouched.
const deleteAccount = onCall(
    {enforceAppCheck: true},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      assertPayloadShape(req.data, new Set());
      // Checked before the rate limiter so a stale-auth rejection doesn't
      // burn one of the caller's deletion slots.
      const authTime = req.auth.token?.auth_time;
      const nowSec = Math.floor(Date.now() / 1000);
      if (isReauthStale(authTime, nowSec, REAUTH_MAX_AGE_SECONDS)) {
        logger.warn("deleteAccount: stale auth_time; reauth required", {
          uid: req.auth.uid,
          authTime,
          ageSec: typeof authTime === "number" ? nowSec - authTime : null,
        });
        throw new HttpsError("unauthenticated", "stale-auth");
      }
      const limiter = await enforceDurableRateLimit(
          "deleteAccount",
          req.auth.uid,
          AUTH_RATE_MAX,
          AUTH_RATE_WINDOW_MS,
      );
      const uid = req.auth.uid;
      const db = getFirestore();

      // Resolve the users doc before any destructive step — once the Auth
      // user is gone the caller can no longer retry.
      const bridgeSnap = await db
          .collection("usersByUid")
          .doc(uid)
          .get()
          .catch((err) => {
            logger.warn("deleteAccount: bridge read failed", {
              uid,
              err: err.message,
            });
            return null;
          });

      let docId = bridgeSnap?.exists ? bridgeSnap.data().docId : null;

      if (!docId) {
        // No bridge row — fall back to a direct uid lookup so we don't
        // strand the profile doc.
        logger.warn("deleteAccount: no bridge for uid; querying users by uid", {
          uid,
        });
        try {
          const q = await db
              .collection("users")
              .where("uid", "==", uid)
              .limit(1)
              .get();
          if (!q.empty) docId = q.docs[0].id;
        } catch (err) {
          logger.warn("deleteAccount: uid-fallback lookup failed", {
            uid,
            err: err.message,
          });
        }
      }

      // Delete the Auth user FIRST — the reverse order risks a live login
      // with no profile doc; a failed doc delete after Auth is gone just
      // leaves recoverable orphaned data.
      try {
        await getAuth().deleteUser(uid);
      } catch (err) {
        logger.error("deleteAccount: auth delete failed", {
          uid,
          err: err.message,
        });
        // Server-side failure — refund the rate-limit slot (best-effort) so
        // legitimate retries aren't locked out by our own errors.
        await limiter.refund();
        throw new HttpsError("internal", "delete-auth-user-failed");
      }

      if (docId) {
        try {
          // recursiveDelete removes the users doc and all its subcollections
          // (fcmTokens now, presence later); a plain doc delete would orphan
          // them, leaving a deleted account still receiving pushes.
          await db.recursiveDelete(db.collection("users").doc(docId));
        } catch (err) {
          // The Auth user is already gone, so log for cleanup but report
          // success — the caller's credentials no longer work anyway.
          logger.error("deleteAccount: users doc delete failed after auth " +
              "delete — orphaned users doc needs cleanup", {
            uid,
            docId,
            err: err.message,
          });
        }
      }

      logger.info("deleteAccount: user account deleted", {uid, docId});
      return {deleted: true};
    },
);

module.exports = {
  deleteAccount,
  // Exported for unit tests.
  isReauthStale,
};
