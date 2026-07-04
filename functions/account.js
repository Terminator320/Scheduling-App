const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");

const {assertPayloadShape, enforceDurableRateLimit} = require("./security");

// deleteAccount is an auth-sensitive callable capped at AUTH_RATE_MAX attempts
// per AUTH_RATE_WINDOW_MS. Unlike the in-memory Places limiter, this is
// enforced in Firestore so the cap holds across function instances and cold
// starts — a brute-force caller cannot multiply it by maxInstances.
const AUTH_RATE_MAX = 5;
const AUTH_RATE_WINDOW_MS = 15 * 60 * 1000;

// deleteAccount requires the caller to have re-authenticated within this
// window. Firebase ID tokens are valid ~1 hour, so without this check a
// stolen-but-not-yet-expired token could trigger irreversible deletion.
const REAUTH_MAX_AGE_SECONDS = 5 * 60;

// ----- deleteAccount callable ------------------------------------------------
//
// Implements C6 from the production-readiness plan and satisfies the in-app
// deletion requirement from Apple App Store Guideline 5.1.1(v) and the Google
// Play Account Deletion policy. The Flutter client re-authenticates the user
// immediately before invoking this; the server also re-checks the ID token's
// auth_time against REAUTH_MAX_AGE_SECONDS so a live-but-stale token cannot
// trigger deletion without going through the in-app re-auth flow.
// App Check + auth are required.
//
// Scope of deletion (intentionally narrow — see plan §C6):
//   1. The caller's `users/{docId}` Firestore document. The syncUsersByUid
//      Firestore trigger then clears `usersByUid/{uid}` automatically.
//   2. The Firebase Auth user.
// We do NOT touch shared business data (appointments, clients, appointment
// images): those are owned by the business, not the individual account.
const deleteAccount = onCall(
    // TODO(pre-ship): set back to `enforceAppCheck: true` once the app ships
    // through Play Store and Play Integrity can mint verified App Check
    // tokens. Temporarily false so testers on Firebase App Distribution
    // sideloads (UNRECOGNIZED_VERSION verdict) aren't blocked.
    {enforceAppCheck: false},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      assertPayloadShape(req.data, new Set());
      // Stale-auth is checked BEFORE the rate limiter so a stale-but-cheap
      // rejection doesn't burn one of the caller's 5 deletion slots (which
      // would let a few reauth retries lock them out of deletion entirely).
      const authTime = req.auth.token?.auth_time;
      const nowSec = Math.floor(Date.now() / 1000);
      if (typeof authTime !== "number" ||
          nowSec - authTime > REAUTH_MAX_AGE_SECONDS) {
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

      // Resolve the users doc BEFORE any destructive step: once the Auth user
      // is gone the caller can no longer retry, so everything that can fail
      // recoverably happens first.
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
        // No bridge row — it may simply be stale/missing while a users doc
        // still exists. Fall back to a direct uid lookup so we don't strand
        // the profile doc (account-deletion completeness for store policy).
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

      // Delete the Auth user FIRST. Ordering rationale: if the Firestore doc
      // were deleted first and the Auth delete then failed, the caller would
      // be left with a live login and no profile — and because their ID token
      // still works, a retry storm burns their rate-limit slots against a
      // half-deleted account. The reverse partial failure (Auth gone, doc
      // delete fails) is recoverable server-side: the doc is orphaned data an
      // admin/cleanup can remove, and the caller's account is genuinely gone.
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
          await db.collection("users").doc(docId).delete();
        } catch (err) {
          // The Auth user is already gone (the irreversible, policy-relevant
          // part). A doc-delete failure only leaves recoverable orphaned data
          // — log loudly for cleanup but report success to the caller, who
          // could not retry anyway (their credentials no longer work).
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

module.exports = {deleteAccount};
