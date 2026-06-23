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

const GOOGLE_MAP_API_KEY = defineSecret("GOOGLE_MAP_API_KEY");

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

const MAX_PAYLOAD_BYTES = 4 * 1024;

const AUTH_RATE_MAX = 5;
const AUTH_RATE_WINDOW_MS = 15 * 60 * 1000;

const PLACES_DETAILS_RATE_MAX = 40;
const PLACES_DETAILS_RATE_WINDOW_MS = 15 * 60 * 1000;

const REAUTH_MAX_AGE_SECONDS = 5 * 60;

const WAVE_IMPORT_RATE_MAX = 5;
const WAVE_IMPORT_RATE_WINDOW_MS = 60 * 60 * 1000;
// waveBootstrap's not-yet-connected path makes live Wave calls (whoami +
// listBusinesses). Cap it per-admin so a buggy/looping client can't burn the
// Wave request budget before a connection exists. The idempotent short-circuit
// (already-connected) runs before this and is not rate-limited.
const WAVE_BOOTSTRAP_RATE_MAX = 10;

// The Wave business to connect, kept in Secret Manager so the name never ships
// in the app and can change without an app release. Set it with
// `firebase functions:secrets:set WAVE_BUSINESS_NAME`. waveBootstrap (which
// declares it in its `secrets`) uses it as the target whenever the client
// supplies no businessId/businessName.
const WAVE_BUSINESS_NAME = defineSecret("WAVE_BUSINESS_NAME");

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
exports.deleteAccount = onCall(
    // TODO(pre-ship): set back to `enforceAppCheck: true` once the app ships
    {enforceAppCheck: false},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      assertPayloadShape(req.data, new Set());
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


exports.resolveMyInvite = onCall(
    // TODO(pre-ship): set back to `enforceAppCheck: true` once the app ships

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

      await enforceDurableRateLimit(
          "resolveMyInvite",
          req.auth.uid,
          AUTH_RATE_MAX,
          AUTH_RATE_WINDOW_MS,
      );
      const email = tokenEmail.trim().toLowerCase();
      const db = getFirestore();

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

const HISTORY_RETENTION_YEARS = 2;
const PURGE_STATUSES = ["done", "cancelled"];

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

exports.waveBootstrap = onCall(
    // TODO(pre-ship): set back to `enforceAppCheck: true` once the app ships
    // through Play Store and Play Integrity can mint verified App Check tokens.
    {
      secrets: [WAVE_FULL_ACCESS_TOKEN, WAVE_BUSINESS_NAME],
      enforceAppCheck: false,
    },
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
      // Fall back to the server-side configured business name (Secret Manager)
      // when the client sends none — the app connects without ever naming the
      // business. `|| ""` guards an unset/empty secret against a trim() throw.
      const configuredName = (WAVE_BUSINESS_NAME.value() || "").trim();
      const wantName = (typeof req.data?.businessName === "string" &&
        req.data.businessName.trim()) ?
        req.data.businessName.trim() : configuredName;

      // Only the not-yet-connected path (live Wave calls) is rate-limited.
      await enforceDurableRateLimit(
          "wave-bootstrap",
          req.auth.uid,
          WAVE_BOOTSTRAP_RATE_MAX,
          WAVE_IMPORT_RATE_WINDOW_MS,
      );

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
    const want = wantName.trim().toLowerCase();
    const match = list.find((b) => b && b.name.trim().toLowerCase() === want);
    if (!match) throw new HttpsError("not-found", "wave/business-not-found");
    return match;
  }
  if (list.length === 1) return list[0];
  throw new HttpsError("failed-precondition", "wave/business-ambiguous");
}

exports.waveListBusinesses = onCall(
    // TODO(pre-ship): set back to `enforceAppCheck: true` once the app ships
    // through Play Store and Play Integrity can mint verified App Check tokens.
    {secrets: [WAVE_FULL_ACCESS_TOKEN], enforceAppCheck: false},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      assertPayloadShape(req.data, new Set());
      await assertAdmin(req.auth.uid);


      await enforceDurableRateLimit(
          "wave-list",
          req.auth.uid,
          WAVE_BOOTSTRAP_RATE_MAX,
          WAVE_IMPORT_RATE_WINDOW_MS,
      );

      let businesses;
      try {
        await whoami();
        businesses = await listBusinesses();
      } catch (e) {
        const {code, message} = classifyWaveError(e);
        logger.warn("WAVE-LIST failed", {uid: req.auth.uid, code, message});
        throw new HttpsError(code, message);
      }

      logger.info("WAVE-LIST listed", {
        uid: req.auth.uid,
        count: businesses.length,
      });
      return {businesses};
    },
);

exports.waveGetConnection = onCall(
    // TODO(pre-ship): set back to `enforceAppCheck: true` once the app ships
    // through Play Store and Play Integrity can mint verified App Check tokens.
    {enforceAppCheck: false},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      assertPayloadShape(req.data, new Set());
      await assertAdmin(req.auth.uid);

      const snap = await getFirestore()
          .collection("wave").doc("connection").get();
      const data = snap.exists ? snap.data() : null;
      const businessId = data && typeof data.businessId === "string" ?
        data.businessId : "";
      const businessName = data && typeof data.businessName === "string" ?
        data.businessName : "";
      return {connected: Boolean(businessId), businessId, businessName};
    },
);


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
