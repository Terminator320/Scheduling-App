const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");

const {
  assertPayloadShape,
  enforceDurableRateLimit,
  isReauthStale,
} = require("./security");
const {runAccountDeletion} = require("./account_policy");

// deleteAccount is capped at AUTH_RATE_MAX attempts per AUTH_RATE_WINDOW_MS,
// enforced in Firestore (not in-memory) so the cap holds across instances
// and cold starts.
const AUTH_RATE_MAX = 5;
const AUTH_RATE_WINDOW_MS = 15 * 60 * 1000;

// deleteAccount requires the caller to have re-authenticated within this
// window, since a still-valid ID token alone shouldn't trigger deletion.
const REAUTH_MAX_AGE_SECONDS = 5 * 60;

// ----- deleteAccount callable ------------------------------------------------
//
// Satisfies the in-app deletion requirement from Apple App Store Guideline
// 5.1.1(v) and the Google Play Account Deletion policy. The client
// re-authenticates first, and the server also re-checks auth_time against
// REAUTH_MAX_AGE_SECONDS.
//
// Deletion is intentionally narrow — it only removes the caller's
// `users/{docId}` doc (which cascades to `usersByUid/{uid}` via
// syncUsersByUid) and the Firebase Auth user. Shared business data
// (appointments, clients, images) is left untouched.
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
      // The ordering rules live in account_policy.js so they can be tested
      // with injected doubles — this callable owns only the guards above.
      const {deleted} = await runAccountDeletion(
          {
            db: getFirestore(),
            auth: getAuth(),
            logger,
            limiter,
            onAuthFailure: () =>
              new HttpsError("internal", "delete-auth-user-failed"),
          },
          req.auth.uid,
      );
      return {deleted};
    },
);

module.exports = {
  deleteAccount,
  // Re-exported from security.js (its one owner, shared with
  // changeEmployeeEmail) so the existing unit tests keep their import path.
  isReauthStale,
};
