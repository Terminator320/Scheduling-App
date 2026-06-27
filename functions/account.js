const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");

const {assertPayloadShape, enforceDurableRateLimit} = require("./security");

// Auth-sensitive callables (resolveMyInvite, deleteAccount) are capped at
// AUTH_RATE_MAX attempts per AUTH_RATE_WINDOW_MS. Unlike the in-memory Places
// limiter, this is enforced in Firestore so the cap holds across function
// instances and cold starts — a brute-force caller cannot multiply it by
// maxInstances.
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
      await enforceDurableRateLimit(
          "deleteAccount",
          req.auth.uid,
          AUTH_RATE_MAX,
          AUTH_RATE_WINDOW_MS,
      );
      const uid = req.auth.uid;
      const db = getFirestore();

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

      const docId = bridgeSnap?.exists ? bridgeSnap.data().docId : null;

      if (docId) {
        try {
          await db.collection("users").doc(docId).delete();
        } catch (err) {
          logger.error("deleteAccount: users doc delete failed", {
            uid,
            docId,
            err: err.message,
          });
          throw new HttpsError("internal", "delete-user-doc-failed");
        }
      } else {
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
          if (!q.empty) {
            await q.docs[0].ref.delete();
            logger.info("deleteAccount: deleted users doc via uid fallback", {
              uid,
              docId: q.docs[0].id,
            });
          }
        } catch (err) {
          logger.error("deleteAccount: uid-fallback delete failed", {
            uid,
            err: err.message,
          });
          throw new HttpsError("internal", "delete-user-doc-failed");
        }
      }

      try {
        await getAuth().deleteUser(uid);
      } catch (err) {
        logger.error("deleteAccount: auth delete failed", {
          uid,
          err: err.message,
        });
        throw new HttpsError("internal", "delete-auth-user-failed");
      }

      logger.info("deleteAccount: user account deleted", {uid, docId});
      return {deleted: true};
    },
);

// Server-side resolver for the freshly-registered-user invite lookup.
// Replaces the client-side Firestore query that hits permission-denied because
// Firestore's rules engine cannot prove `resource.data.email ==
// request.auth.token.email` from a list query's email-literal where clause.
// Admin SDK bypasses rules; authority comes from `auth.token.email`, never
// from a client-supplied string.
const resolveMyInvite = onCall(
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
      const tokenEmail = req.auth.token?.email;
      if (typeof tokenEmail !== "string" || tokenEmail === "") {
        throw new HttpsError("failed-precondition", "no-email-claim");
      }
      // Only a verified email proves ownership. Anyone can register an
      // unverified account with a guessed email, so an unverified caller must
      // not learn whether an invite exists or read its name/color/role — return
      // the empty result, never the invite. The app only calls this after the
      // user verifies (tryActivateInvitedEmployee gates on emailVerified and
      // forces a fresh token), so the legitimate flow is unaffected.
      if (req.auth.token?.email_verified !== true) {
        return {found: false};
      }
      // Rate-limit AFTER the cheap precondition checks (mirrors deleteAccount):
      // a tokenless/precondition-failing retry must not record an attempt and
      // burn one of the caller's own limited slots.
      await enforceDurableRateLimit(
          "resolveMyInvite",
          req.auth.uid,
          AUTH_RATE_MAX,
          AUTH_RATE_WINDOW_MS,
      );
      const email = tokenEmail.trim().toLowerCase();
      const db = getFirestore();
      // Invites are employee-only — admin is granted post-activation, and
      // firestore.rules forbids invited-admin self-activation. Resolving only
      // employee invites keeps the callable consistent with that rule.
      const snap = await db
          .collection("users")
          .where("email", "==", email)
          .where("status", "==", "invited")
          .where("role", "==", "employee")
          .limit(1)
          .get();
      if (snap.empty) {
        return {found: false};
      }
      const doc = snap.docs[0];
      const d = doc.data();
      // Project only the fields the signup/activation flow consumes — never
      // return the whole users doc, so internal fields can't leak to the
      // pre-activation account.
      return {
        found: true,
        docId: doc.id,
        data: {
          name: d.name || "",
          colorValue: d.colorValue || null,
          role: d.role || "",
          status: d.status || "",
          email: d.email || "",
        },
      };
    },
);

module.exports = {deleteAccount, resolveMyInvite};
