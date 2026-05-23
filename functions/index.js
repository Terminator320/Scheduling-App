const {setGlobalOptions} = require("firebase-functions");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onObjectFinalized} = require("firebase-functions/v2/storage");
const {getStorage} = require("firebase-admin/storage");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");

setGlobalOptions({maxInstances: 10});

initializeApp();

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
exports.syncUsersByUid = onDocumentWritten(
    "users/{userId}",
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

      // uid rotation: remove the stale bridge before writing the new one.
      if (beforeUid && beforeUid !== afterUid) {
        await bridge.doc(beforeUid).delete().catch((err) => {
          logger.warn("syncUsersByUid: stale bridge delete failed", {
            userId,
            beforeUid,
            err: err.message,
          });
        });
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

      if (!shouldHaveBridge(after)) {
        if (afterUid) {
          await bridge.doc(afterUid).delete().catch(() => {});
        }
        logger.debug("syncUsersByUid: no bridge needed", {
          userId,
          status: after.status,
          hasUid: !!afterUid,
        });
        return;
      }

      await bridge.doc(afterUid).set(bridgeBody(userId, after));
      logger.info("syncUsersByUid: bridge upserted", {
        userId,
        uid: afterUid,
        role: after.role,
        status: after.status,
      });
    },
);

// ----- Google Places callables ----------------------------------------------
//
// Both callables proxy the Places API v1 so the billing-sensitive key never
// ships in the Flutter binary. The key lives in Secret Manager; clients must
// be authenticated and pass App Check.

const GOOGLE_MAP_API_KEY = defineSecret("GOOGLE_MAP_API_KEY");

// Per-uid sliding-window rate limit. In-memory, per function instance.
// IMPORTANT: Set a GCP billing alert on the Maps Platform API in the Firebase
// Console — this in-memory limit is per-instance and is not a hard billing cap.
// With maxInstances: 10, the effective ceiling is RATE_LIMIT_MAX × instance
// count requests per window. RATE_LIMIT_MAX is kept low to bound that product.
const RATE_LIMIT_MAX = 20;
const RATE_LIMIT_WINDOW_MS = 60_000;
const rateBuckets = new Map();

/**
 * Throws HttpsError("resource-exhausted") when the caller's uid exceeds
 * RATE_LIMIT_MAX requests within RATE_LIMIT_WINDOW_MS. Mutates the bucket.
 * @param {string} uid Firebase Auth uid of the caller.
 */
function enforceRateLimit(uid) {
  const now = Date.now();
  // Evict expired entries when the map grows beyond the expected user count.
  if (rateBuckets.size > 200) {
    for (const [key, val] of rateBuckets) {
      if (now - val.windowStart >= RATE_LIMIT_WINDOW_MS) {
        rateBuckets.delete(key);
      }
    }
  }
  const bucket = rateBuckets.get(uid);
  if (!bucket || now - bucket.windowStart >= RATE_LIMIT_WINDOW_MS) {
    rateBuckets.set(uid, {count: 1, windowStart: now});
    return;
  }
  bucket.count += 1;
  if (bucket.count > RATE_LIMIT_MAX) {
    throw new HttpsError(
        "resource-exhausted",
        "too-many-places-requests",
    );
  }
}

const PLACE_ID_PATTERN = /^[A-Za-z0-9_.-]+$/;
const SESSION_TOKEN_MAX_LEN = 64;
const INPUT_MAX_LEN = 200;

// deleteAccount requires the caller to have re-authenticated within this
// window. Firebase ID tokens are valid ~1 hour, so without this check a
// stolen-but-not-yet-expired token could trigger irreversible deletion.
const REAUTH_MAX_AGE_SECONDS = 5 * 60;

/**
 * Validates and returns a trimmed string field from the callable payload.
 * Throws HttpsError("invalid-argument") when missing, wrong type, or out of
 * the [1, maxLen] range.
 * @param {object} data callable request data.
 * @param {string} key field name.
 * @param {number} maxLen max length (inclusive).
 * @return {string}
 */
function requireString(data, key, maxLen) {
  const value = typeof data?.[key] === "string" ? data[key].trim() : "";
  if (!value || value.length > maxLen) {
    throw new HttpsError("invalid-argument", `invalid-${key}`);
  }
  return value;
}

/**
 * Reads an optional sessionToken from the payload. Returns "" if absent;
 * throws HttpsError("invalid-argument") when present but malformed.
 * @param {object} data callable request data.
 * @return {string}
 */
function readSessionToken(data) {
  if (data?.sessionToken === undefined || data?.sessionToken === null) {
    return "";
  }
  if (typeof data.sessionToken !== "string" ||
      data.sessionToken.length > SESSION_TOKEN_MAX_LEN) {
    throw new HttpsError("invalid-argument", "invalid-sessionToken");
  }
  return data.sessionToken;
}

exports.placesAutocomplete = onCall(
    {
      enforceAppCheck: true,
      secrets: [GOOGLE_MAP_API_KEY],
    },
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      const input = requireString(req.data, "input", INPUT_MAX_LEN);
      const sessionToken = readSessionToken(req.data);

      enforceRateLimit(req.auth.uid);

      const body = {
        input,
        includedRegionCodes: ["ca"],
        locationBias: {
          circle: {
            // Montréal
            center: {latitude: 45.5017, longitude: -73.5673},
            radius: 50000.0,
          },
        },
      };
      if (sessionToken) body.sessionToken = sessionToken;

      let response;
      try {
        response = await fetch(
            "https://places.googleapis.com/v1/places:autocomplete",
            {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                "X-Goog-Api-Key": GOOGLE_MAP_API_KEY.value().trim(),
                "X-Goog-FieldMask": "suggestions.placePrediction.placeId," +
                  "suggestions.placePrediction.text",
              },
              body: JSON.stringify(body),
            },
        );
      } catch (err) {
        logger.error("placesAutocomplete: transport error", {
          uid: req.auth.uid,
          err: err.message,
        });
        throw new HttpsError("internal", "places-transport");
      }

      if (!response.ok) {
        const preview = (await response.text()).slice(0, 200);
        logger.warn("placesAutocomplete: upstream non-200", {
          status: response.status,
          body: preview,
        });
        throw new HttpsError("internal", "places-upstream");
      }

      const data = await response.json();
      return {suggestions: Array.isArray(data.suggestions) ?
        data.suggestions : []};
    },
);

exports.placesGetDetails = onCall(
    {
      enforceAppCheck: true,
      secrets: [GOOGLE_MAP_API_KEY],
    },
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      const placeId = requireString(req.data, "placeId", 256);
      if (!PLACE_ID_PATTERN.test(placeId)) {
        throw new HttpsError("invalid-argument", "invalid-placeId");
      }
      const sessionToken = readSessionToken(req.data);

      enforceRateLimit(req.auth.uid);

      const url = new URL(
          `https://places.googleapis.com/v1/places/${encodeURIComponent(
              placeId,
          )}`,
      );
      if (sessionToken) url.searchParams.set("sessionToken", sessionToken);

      let response;
      try {
        response = await fetch(url.toString(), {
          method: "GET",
          headers: {
            "X-Goog-Api-Key": GOOGLE_MAP_API_KEY.value().trim(),
            "X-Goog-FieldMask": "formattedAddress,addressComponents",
          },
        });
      } catch (err) {
        logger.error("placesGetDetails: transport error", {
          uid: req.auth.uid,
          err: err.message,
        });
        throw new HttpsError("internal", "places-transport");
      }

      if (!response.ok) {
        const preview = (await response.text()).slice(0, 200);
        logger.warn("placesGetDetails: upstream non-200", {
          status: response.status,
          body: preview,
        });
        throw new HttpsError("internal", "places-upstream");
      }

      const data = await response.json();
      return {
        formattedAddress: typeof data.formattedAddress === "string" ?
          data.formattedAddress : "",
        addressComponents: Array.isArray(data.addressComponents) ?
          data.addressComponents : [],
      };
    },
);

// Validates magic bytes of newly uploaded appointment images and deletes any
// file that is not JPEG (FF D8 FF) or PNG (89 50 4E 47). The Storage rule
// trusts client-provided contentType, so a direct REST/SDK caller could
// upload arbitrary content; this trigger closes that gap server-side.
exports.validateUploadedImage = onObjectFinalized(async (event) => {
  const obj = event.data;
  const filePath = obj.name ?? "";

  if (!filePath.match(/^appointments\/[^/]+\/images\//)) return;

  const file = getStorage().bucket(obj.bucket).file(filePath);
  let buffer;
  try {
    const stream = file.createReadStream({start: 0, end: 7});
    const chunks = [];
    await new Promise((resolve, reject) => {
      stream.on("data", (c) => chunks.push(c));
      stream.on("end", resolve);
      stream.on("error", reject);
    });
    buffer = Buffer.concat(chunks);
  } catch (err) {
    logger.warn("validateUploadedImage: read failed — deleting", {
      filePath,
      err: err.message,
    });
    await file.delete().catch((delErr) =>
      logger.error("validateUploadedImage: delete after read-fail failed", {
        filePath,
        err: delErr.message,
      }),
    );
    return;
  }

  const isJpeg = buffer[0] === 0xFF && buffer[1] === 0xD8 && buffer[2] === 0xFF;
  const isPng =
    buffer[0] === 0x89 && buffer[1] === 0x50 &&
    buffer[2] === 0x4E && buffer[3] === 0x47;

  if (!isJpeg && !isPng) {
    logger.warn("validateUploadedImage: invalid magic bytes — deleting", {
      filePath,
    });
    await file.delete().catch((err) =>
      logger.error("validateUploadedImage: delete failed", {
        filePath,
        err: err.message,
      }),
    );
  }
});

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
exports.deleteAccount = onCall(
    {enforceAppCheck: true},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
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
        // No bridge row found — best-effort cleanup of an orphan auth account.
        // We still try to delete the Auth user below so the caller can recover.
        logger.warn("deleteAccount: no bridge for uid; auth-only delete", {
          uid,
        });
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
exports.resolveMyInvite = onCall(
    {enforceAppCheck: true},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      const tokenEmail = req.auth.token?.email;
      if (typeof tokenEmail !== "string" || tokenEmail === "") {
        throw new HttpsError("failed-precondition", "no-email-claim");
      }
      const email = tokenEmail.trim().toLowerCase();
      const db = getFirestore();
      const snap = await db
          .collection("users")
          .where("email", "==", email)
          .where("status", "==", "invited")
          .where("role", "in", ["employee", "admin"])
          .limit(1)
          .get();
      if (snap.empty) {
        return {found: false};
      }
      const doc = snap.docs[0];
      return {
        found: true,
        docId: doc.id,
        data: doc.data(),
      };
    },
);
