const {setGlobalOptions} = require("firebase-functions");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onObjectFinalized} = require("firebase-functions/v2/storage");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {getStorage} = require("firebase-admin/storage");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const {WAVE_FULL_ACCESS_TOKEN} = require("./wave/auth");
const {graphql, whoami, listBusinesses} = require("./wave/client");
const {importCustomers} = require("./wave/customers");
const {
  enqueueCustomerUpsert,
  drainQueue,
  shouldEnqueueClientWrite,
} = require("./wave/worker");
const {mappedFieldsHash} = require("./wave/mappers");
const {classifyWaveError} = require("./wave/errors");

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
// This is a cheap, latency-free cost guard appropriate for the high-volume
// autocomplete path; auth-sensitive routes use the durable Firestore limiter
// below instead (see enforceDurableRateLimit).
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

// Hard cap on a callable payload once serialized. Every payload here is a
// couple of short strings; anything larger is malformed or abusive.
const MAX_PAYLOAD_BYTES = 4 * 1024;

// Auth-sensitive callables (resolveMyInvite, deleteAccount) are capped at
// AUTH_RATE_MAX attempts per AUTH_RATE_WINDOW_MS. Unlike the in-memory Places
// limiter above, this is enforced in Firestore so the cap holds across
// function instances and cold starts — a brute-force caller cannot multiply
// it by maxInstances.
const AUTH_RATE_MAX = 5;
const AUTH_RATE_WINDOW_MS = 15 * 60 * 1000;

// placesGetDetails is low-volume (one billable call per address the user
// actually selects), so it gets the durable Firestore cap rather than the
// in-memory limiter — that one resets on cold start and multiplies by
// maxInstances, giving no real ceiling on the per-detail Places cost. The
// limit is generous enough for an admin entering many appointments at once.
const PLACES_DETAILS_RATE_MAX = 40;
const PLACES_DETAILS_RATE_WINDOW_MS = 15 * 60 * 1000;

// deleteAccount requires the caller to have re-authenticated within this
// window. Firebase ID tokens are valid ~1 hour, so without this check a
// stolen-but-not-yet-expired token could trigger irreversible deletion.
const REAUTH_MAX_AGE_SECONDS = 5 * 60;

// waveImportCustomers is a heavy one-shot admin op (it paginates ~650 customers
// across ~7 Wave pages). A modest durable cap keeps a stuck/retried admin from
// hammering Wave: 5 imports per hour is ample for a setup/reconcile action.
const WAVE_IMPORT_RATE_MAX = 5;
const WAVE_IMPORT_RATE_WINDOW_MS = 60 * 60 * 1000;

/**
 * True when the string contains a C0 control character (code < 0x20) or DEL
 * (0x7F). Control characters have no place in a place query, place id, or
 * session token; rejecting them sanitizes the input against log injection
 * (these values get logged) and odd upstream behaviour.
 * @param {string} s value to inspect.
 * @return {boolean}
 */
function hasControlChar(s) {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x20 || c === 0x7F) return true;
  }
  return false;
}

/**
 * Rejects malformed, oversized, or unexpected callable payloads. Throws
 * HttpsError("invalid-argument") when `data` is not a plain object, exceeds
 * MAX_PAYLOAD_BYTES once serialized, or carries any key outside `allowedKeys`
 * (mass-assignment defence). A null/undefined payload is treated as empty.
 * @param {*} data raw callable request data.
 * @param {!Set<string>} allowedKeys the only keys this endpoint accepts.
 */
function assertPayloadShape(data, allowedKeys) {
  if (data === undefined || data === null) return;
  if (typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "malformed-payload");
  }
  let serialized;
  try {
    serialized = JSON.stringify(data);
  } catch {
    throw new HttpsError("invalid-argument", "malformed-payload");
  }
  if (serialized.length > MAX_PAYLOAD_BYTES) {
    throw new HttpsError("invalid-argument", "payload-too-large");
  }
  for (const key of Object.keys(data)) {
    if (!allowedKeys.has(key)) {
      throw new HttpsError("invalid-argument", "unexpected-field");
    }
  }
}

/**
 * Validates and returns a trimmed string field from the callable payload.
 * Throws HttpsError("invalid-argument") when missing, wrong type, out of the
 * [1, maxLen] range, or containing control characters.
 * @param {object} data callable request data.
 * @param {string} key field name.
 * @param {number} maxLen max length (inclusive).
 * @return {string}
 */
function requireString(data, key, maxLen) {
  const value = typeof data?.[key] === "string" ? data[key].trim() : "";
  if (!value || value.length > maxLen || hasControlChar(value)) {
    throw new HttpsError("invalid-argument", `invalid-${key}`);
  }
  return value;
}

/**
 * Reads an optional sessionToken from the payload. Returns "" if absent;
 * throws HttpsError("invalid-argument") when present but malformed (wrong
 * type, too long, or containing control characters).
 * @param {object} data callable request data.
 * @return {string}
 */
function readSessionToken(data) {
  if (data?.sessionToken === undefined || data?.sessionToken === null) {
    return "";
  }
  if (typeof data.sessionToken !== "string" ||
      data.sessionToken.length > SESSION_TOKEN_MAX_LEN ||
      hasControlChar(data.sessionToken)) {
    throw new HttpsError("invalid-argument", "invalid-sessionToken");
  }
  return data.sessionToken;
}

/**
 * Firestore-backed sliding-window rate limit. Unlike the in-memory limiter, it
 * holds across function instances and cold starts, so it is the right tool for
 * auth-sensitive routes — a brute-force caller cannot get maxInstances × max
 * tries. Counters live in `rateLimits/*`, which firestore.rules denies to all
 * clients (a client able to reset its own counter would defeat the cap).
 * Throws HttpsError("resource-exhausted") when the caller exceeds `max`
 * attempts within `windowMs`.
 * @param {string} route stable endpoint identifier (part of the doc key).
 * @param {string} uid Firebase Auth uid of the caller.
 * @param {number} max max attempts per window.
 * @param {number} windowMs window length in milliseconds.
 */
async function enforceDurableRateLimit(route, uid, max, windowMs) {
  const db = getFirestore();
  const ref = db.collection("rateLimits").doc(`${route}__${uid}`);
  const now = Date.now();
  let overLimit = false;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : null;
    const prior = data && Array.isArray(data.attempts) ? data.attempts : [];
    // True sliding window: keep only the attempt timestamps still inside the
    // window. A single windowStart counter would reset at the boundary and let
    // a caller burst 2×max across it; per-attempt timestamps cannot.
    const recent = prior.filter(
        (t) => typeof t === "number" && now - t < windowMs,
    );
    if (recent.length >= max) {
      // Rejected attempts are not recorded — otherwise a hammering caller would
      // hold the window full forever.
      overLimit = true;
      return;
    }
    recent.push(now);
    tx.set(ref, {
      route,
      attempts: recent,
      // Lets an optional Firestore TTL policy on `expiresAt` reap old rows.
      expiresAt: new Date(now + windowMs),
    });
  });
  if (overLimit) {
    logger.warn("enforceDurableRateLimit: limit exceeded", {route, uid});
    throw new HttpsError("resource-exhausted", "too-many-attempts");
  }
}

/**
 * Asserts the caller is an active admin by reading the `usersByUid/{uid}`
 * bridge (kept in sync by syncUsersByUid; fields `{role, docId, status}`).
 * Throws HttpsError("permission-denied", "wave/not-admin") for any caller who
 * is not an `admin` with an `active` status — including a missing bridge doc.
 * The role is read from Firestore, never from a client-supplied value.
 * @param {string} uid Firebase Auth uid of the caller.
 * @return {!Promise<void>}
 */
async function assertAdmin(uid) {
  const db = getFirestore();
  const snap = await db.collection("usersByUid").doc(uid).get();
  const data = snap.exists ? snap.data() : null;
  if (!data || data.role !== "admin" || data.status !== "active") {
    logger.warn("assertAdmin: caller is not an active admin", {
      uid,
      role: data ? data.role : null,
      status: data ? data.status : null,
    });
    throw new HttpsError("permission-denied", "wave/not-admin");
  }
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
      assertPayloadShape(req.data, new Set(["input", "sessionToken"]));
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

      let data;
      try {
        data = await response.json();
      } catch (err) {
        logger.warn("placesAutocomplete: invalid JSON in 200 response", {
          status: response.status,
          err: err.message,
        });
        throw new HttpsError("internal", "places-upstream");
      }
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
      assertPayloadShape(req.data, new Set(["placeId", "sessionToken"]));
      const placeId = requireString(req.data, "placeId", 256);
      if (!PLACE_ID_PATTERN.test(placeId)) {
        throw new HttpsError("invalid-argument", "invalid-placeId");
      }
      const sessionToken = readSessionToken(req.data);

      await enforceDurableRateLimit(
          "placesGetDetails",
          req.auth.uid,
          PLACES_DETAILS_RATE_MAX,
          PLACES_DETAILS_RATE_WINDOW_MS,
      );

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

      let data;
      try {
        data = await response.json();
      } catch (err) {
        logger.warn("placesGetDetails: invalid JSON in 200 response", {
          status: response.status,
          err: err.message,
        });
        throw new HttpsError("internal", "places-upstream");
      }
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
exports.resolveMyInvite = onCall(
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

// ----- Scheduled history purge ----------------------------------------------
//
// History retention: done/cancelled appointments stay in history for
// HISTORY_RETENTION_YEARS, then are purged automatically — the Firestore doc
// AND its Storage images — once (and only once) that long has elapsed. The
// cutoff is anchored on `startTime` (the visit date, which is what the history
// view is keyed on) and is strict, so nothing is removed before the full
// window passes. Non-terminal appointments are never touched, however old —
// only history is purged. Image cleanup mirrors the manual delete path in
// EventDetailsController.deleteAppointment so a purged appointment leaves no
// orphaned bytes. Admin SDK bypasses security rules; this runs unattended.
const HISTORY_RETENTION_YEARS = 2;
const PURGE_STATUSES = ["done", "cancelled"];
// Well under Firestore's 500-writes-per-batch ceiling, with headroom.
const PURGE_BATCH_SIZE = 200;

/**
 * Best-effort deletion of every Storage object under an appointment's image
 * prefix (`appointments/{id}/images/`). Returns false (and logs) on failure —
 * the Firestore doc is already gone by the time this runs, so a Storage error
 * only orphans bytes and must not be treated as a purge failure.
 * @param {string} appointmentId Firestore doc id of the purged appointment.
 * @return {!Promise<boolean>} true when the prefix was cleared.
 */
async function deleteAppointmentImages(appointmentId) {
  const prefix = `appointments/${appointmentId}/images/`;
  try {
    await getStorage().bucket().deleteFiles({prefix});
    return true;
  } catch (err) {
    logger.warn("purgeExpiredHistory: image cleanup failed", {
      appointmentId,
      err: err.message,
    });
    return false;
  }
}

exports.purgeExpiredHistory = onSchedule(
    {

      schedule: "every day 03:00",
      timeZone: "America/Toronto",
      maxInstances: 1,
    },
    async () => {
      const db = getFirestore();
      const cutoff = new Date();
      cutoff.setFullYear(cutoff.getFullYear() - HISTORY_RETENTION_YEARS);
      const col = db.collection("appointments");

      let purged = 0;
      let imageFailures = 0;
      // Every fetched doc is deleted, so the next page's oldest terminal visit
      // simply takes its place — a plain limit loop advances without a cursor.
      for (;;) {
        const snap = await col
            .where("status", "in", PURGE_STATUSES)
            .where("startTime", "<", cutoff)
            .orderBy("startTime")
            .limit(PURGE_BATCH_SIZE)
            .get();
        if (snap.empty) break;

        const batch = db.batch();
        for (const doc of snap.docs) batch.delete(doc.ref);
        await batch.commit();
        purged += snap.size;

        for (const doc of snap.docs) {
          const ok = await deleteAppointmentImages(doc.id);
          if (!ok) imageFailures += 1;
        }

        if (snap.size < PURGE_BATCH_SIZE) break;
      }

      logger.info("purgeExpiredHistory: done", {
        purged,
        imageFailures,
        retentionYears: HISTORY_RETENTION_YEARS,
        cutoff: cutoff.toISOString(),
      });
    },
);

// ----- Wave Accounting integration ------------------------------------------
//
// Four functions wire the app's `clients` collection to Wave Accounting
// customers (plan Task 5). The single `wave/connection` doc holds the selected
// business id; `waveSyncQueue` is a durable outbox drained on a schedule. The
// heavy lifting (GraphQL transport, mapping, queue mechanics) lives in the
// `wave/*` modules — these functions are thin orchestrators that add auth,
// admin, and rate-limit guards and translate Wave errors into HttpsErrors.
//
// App Check posture mirrors deleteAccount/resolveMyInvite: the two admin
// callables run enforceAppCheck:false with a TODO(pre-ship) until Play
// Integrity can mint verified tokens for store builds.

/**
 * Reads the connected Wave `businessId` from the `wave/connection` doc, or
 * returns "" when the doc/field is absent. Used by the callables/scheduler to
 * gate on "bootstrapped yet?".
 * @return {!Promise<string>} The business id, or "" if not connected.
 */
async function readWaveBusinessId() {
  const snap = await getFirestore().collection("wave").doc("connection").get();
  const data = snap.exists ? snap.data() : null;
  return data && typeof data.businessId === "string" ? data.businessId : "";
}

// 1) waveBootstrap — admin-only, idempotent get-or-create of wave/connection.
exports.waveBootstrap = onCall(
    // TODO(pre-ship): set back to `enforceAppCheck: true` once the app ships
    // through Play Store and Play Integrity can mint verified App Check tokens.
    {secrets: [WAVE_FULL_ACCESS_TOKEN], enforceAppCheck: false},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      assertPayloadShape(req.data, new Set(["businessId", "businessName"]));
      await assertAdmin(req.auth.uid);

      const db = getFirestore();
      const ref = db.collection("wave").doc("connection");

      // Idempotent: an already-connected doc is returned unchanged.
      const existing = await ref.get();
      if (existing.exists && existing.data() &&
          typeof existing.data().businessId === "string" &&
          existing.data().businessId) {
        const d = existing.data();
        logger.info("WAVE-BOOT already connected", {
          uid: req.auth.uid,
          businessId: d.businessId,
        });
        return {businessId: d.businessId, businessName: d.businessName || ""};
      }

      const wantId = typeof req.data?.businessId === "string" ?
        req.data.businessId.trim() : "";
      const wantName = typeof req.data?.businessName === "string" ?
        req.data.businessName.trim() : "";

      // Network calls run OUTSIDE the transaction (transactions retry; a Wave
      // mutation must never run more than once). whoami() fast-fails a bad
      // token before we list businesses.
      let selected;
      try {
        await whoami();
        const businesses = await listBusinesses();
        selected = selectBusiness(businesses, wantId, wantName);
      } catch (e) {
        if (e instanceof HttpsError) throw e;
        const {code, message} = classifyWaveError(e);
        logger.warn("WAVE-BOOT failed", {uid: req.auth.uid, code, message});
        throw new HttpsError(code, message);
      }

      // Transaction set-if-absent so concurrent first calls converge on one
      // connection (the first writer wins; later writers return its value).
      const result = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(ref);
        const fd = fresh.exists ? fresh.data() : null;
        if (fd && typeof fd.businessId === "string" && fd.businessId) {
          return {businessId: fd.businessId, businessName: fd.businessName ||
            ""};
        }
        tx.set(ref, {
          businessId: selected.id,
          businessName: selected.name || "",
          bootstrappedAt: FieldValue.serverTimestamp(),
        });
        return {businessId: selected.id, businessName: selected.name || ""};
      });

      logger.info("WAVE-BOOT connected", {
        uid: req.auth.uid,
        businessId: result.businessId,
      });
      return result;
    },
);

/**
 * Selects the intended Wave business from the listed businesses. Selection
 * order: by id when `wantId` is given, else by name when `wantName` is given,
 * else the single business when exactly one exists. Never blindly takes the
 * first of several.
 * @param {!Array<{id: string, name: string}>} businesses Listed businesses.
 * @param {string} wantId Requested business id ("" when not provided).
 * @param {string} wantName Requested business name ("" when not provided).
 * @return {{id: string, name: string}} The selected business.
 * @throws {HttpsError} not-found when a given id/name has no match;
 *   failed-precondition when ambiguous (several businesses, no selector).
 */
function selectBusiness(businesses, wantId, wantName) {
  const list = Array.isArray(businesses) ? businesses : [];
  if (wantId) {
    const match = list.find((b) => b && b.id === wantId);
    if (!match) throw new HttpsError("not-found", "wave/business-not-found");
    return match;
  }
  if (wantName) {
    // NOTE: name match is case-insensitive and trims surrounding whitespace so
    // "acme co" / "  Acme Co  " both reach the same business. Id match above
    // stays exact (ids are opaque tokens).
    const want = wantName.trim().toLowerCase();
    const match = list.find((b) => b && b.name.trim().toLowerCase() === want);
    if (!match) throw new HttpsError("not-found", "wave/business-not-found");
    return match;
  }
  if (list.length === 1) return list[0];
  throw new HttpsError("failed-precondition", "wave/business-ambiguous");
}

// 2) waveImportCustomers — admin-only one-shot Wave → App seed.
exports.waveImportCustomers = onCall(
    // TODO(pre-ship): set back to `enforceAppCheck: true` once the app ships
    // through Play Store and Play Integrity can mint verified App Check tokens.
    {
      secrets: [WAVE_FULL_ACCESS_TOKEN],
      enforceAppCheck: false,
      timeoutSeconds: 300,
    },
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      assertPayloadShape(req.data, new Set());
      await assertAdmin(req.auth.uid);
      await enforceDurableRateLimit(
          "wave-import",
          req.auth.uid,
          WAVE_IMPORT_RATE_MAX,
          WAVE_IMPORT_RATE_WINDOW_MS,
      );

      const businessId = await readWaveBusinessId();
      if (!businessId) {
        throw new HttpsError("failed-precondition", "wave/not-bootstrapped");
      }

      logger.info("WAVE-CUST import starting", {
        uid: req.auth.uid,
        businessId,
      });
      let summary;
      try {
        summary = await importCustomers({businessId, graphql});
      } catch (e) {
        const {code, message} = classifyWaveError(e);
        logger.warn("WAVE-CUST import failed", {
          uid: req.auth.uid,
          code,
          message,
        });
        throw new HttpsError(code, message);
      }

      logger.info("WAVE-CUST import done", {
        uid: req.auth.uid,
        totalCount: summary.totalCount,
        imported: summary.imported,
        updated: summary.updated,
        skippedArchived: summary.skippedArchived,
        pages: summary.pages,
      });
      return summary;
    },
);

// 3) waveUpsertCustomer — enqueues a Wave write-back when a client doc's mapped
// fields change. No secret needed (it only writes to the Firestore outbox).
exports.waveUpsertCustomer = onDocumentWritten(
    "clients/{clientId}",
    async (event) => {
      const beforeSnap = event.data?.before;
      const afterSnap = event.data?.after;
      const after = afterSnap?.exists ? afterSnap.data() : null;

      // Delete: the local doc is dropped and Wave is left intact (plan). No
      // enqueue.
      if (!after) return;

      const before = beforeSnap?.exists ? beforeSnap.data() : null;
      if (!shouldEnqueueClientWrite(before, after)) return;

      // NOTE: this write touches only wave.* fields, so
      // shouldEnqueueClientWrite returns false when the trigger re-fires
      // (mappedFieldsHash is unchanged) — no second pending-write or loop.
      const clientId = event.params.clientId;
      try {
        await getFirestore()
            .doc("clients/" + clientId)
            .update({"wave.syncState": "pending", "wave.syncError": null});
      } catch (e) {
        // Best-effort: the doc may have been deleted between the trigger
        // firing and this update. Log and continue — never fail the trigger.
        logger.warn("waveUpsertCustomer: could not mark pending",
            {clientId, err: e.message});
      }

      // Compute once here; shouldEnqueueClientWrite also hashes internally
      // but does not expose its result, so this call is the single explicit
      // hash at the enqueue site.
      const hash = mappedFieldsHash(after);
      await enqueueCustomerUpsert(clientId, {
        // payloadHash is diagnostic only: the worker re-reads the live doc
        // and recomputes before writing — the doc is the source of truth.
        payloadHash: hash,
      });
      logger.debug("waveUpsertCustomer: enqueued", {clientId});
    },
);

// 4) waveSyncWorker — drains the Wave outbox on a schedule. Single instance so
// Wave pacing stays simple; the worker's lease reaper + transactional claim
// handle robustness. 1/min × default batchLimit 30 = 30 Wave calls/min (< 60).
exports.waveSyncWorker = onSchedule(
    {
      schedule: "every 1 minutes",
      secrets: [WAVE_FULL_ACCESS_TOKEN],
      maxInstances: 1,
    },
    async () => {
      const businessId = await readWaveBusinessId();
      if (!businessId) {
        logger.debug("waveSyncWorker: not bootstrapped — nothing to do");
        return;
      }
      // `graphql`/`upsertCustomer` intentionally omitted: drainQueue defaults
      // to the real Wave client (WAVE_FULL_ACCESS_TOKEN is in scope via this
      // function's `secrets` binding).
      const summary = await drainQueue({businessId});
      logger.info("waveSyncWorker: drain done", {
        processed: summary.processed,
        done: summary.done,
        retried: summary.retried,
        dead: summary.dead,
        skipped: summary.skipped,
        reclaimed: summary.reclaimed,
      });
    },
);
