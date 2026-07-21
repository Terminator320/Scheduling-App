const crypto = require("crypto");
const {HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const {getFirestore} = require("firebase-admin/firestore");

const SESSION_TOKEN_MAX_LEN = 64;

// Hard cap on a callable payload once serialized. Every payload here is a
// couple of short strings; anything larger is malformed or abusive.
const MAX_PAYLOAD_BYTES = 4 * 1024;

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
 * Validates and returns a finite number field within [min, max] (inclusive).
 * Throws HttpsError("invalid-argument") when the value is missing, not a
 * number, NaN, non-finite (Infinity/-Infinity), or out of range.
 * @param {*} value raw payload value.
 * @param {string} name field name, used to build the error code.
 * @param {number} min minimum allowed value (inclusive).
 * @param {number} max maximum allowed value (inclusive).
 * @return {number}
 */
function requireNumberInRange(value, name, min, max) {
  if (typeof value !== "number" || !Number.isFinite(value) ||
      value < min || value > max) {
    throw new HttpsError("invalid-argument", `invalid-${name}`);
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
 * @param {string} key per-caller limiter key — usually the Auth uid, but the
 *   token email for redeemSignupCode (a failed signup re-mints the uid).
 * @param {number} max max attempts per window.
 * @param {number} windowMs window length in milliseconds.
 * @param {string} [keyKind] label for `key` ("uid" | "email"); email keys are
 *   PII, so only a hash is logged. Purely for log discrimination.
 * @return {!Promise<{refund: function(): !Promise<void>}>} A handle whose
 *   `refund()` removes the attempt just recorded (best-effort, never throws).
 *   Callers may use it so a server-side (`internal`) failure does not burn one
 *   of the caller's limited slots; caller-attributable failures must NOT be
 *   refunded. Existing callers that ignore the return value are unaffected.
 */
async function enforceDurableRateLimit(route, key, max, windowMs,
    keyKind = "uid") {
  const db = getFirestore();
  const ref = db.collection("rateLimits").doc(`${route}__${key}`);
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
    // Never log the raw key: for the email-keyed route it is PII. Log a short
    // sha256 prefix so operators can still correlate breaches without storing
    // the address.
    const keyHash = crypto.createHash("sha256").update(key)
        .digest("hex").slice(0, 12);
    logger.warn("enforceDurableRateLimit: limit exceeded",
        {route, keyKind, keyHash});
    throw new HttpsError("resource-exhausted", "too-many-attempts");
  }

  // Best-effort refund of the single attempt recorded above (one occurrence
  // of `now`). Swallows its own errors: refunding is an optimization, never
  // worth failing the caller's error path over.
  const refund = async () => {
    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const data = snap.exists ? snap.data() : null;
        const prior = data && Array.isArray(data.attempts) ?
          data.attempts : [];
        const idx = prior.indexOf(now);
        if (idx === -1) return;
        const next = prior.slice(0, idx).concat(prior.slice(idx + 1));
        tx.set(ref, {route, attempts: next}, {merge: true});
      });
    } catch (err) {
      logger.warn("enforceDurableRateLimit: refund failed", {
        route,
        err: err.message,
      });
    }
  };
  return {refund};
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

// NOTE: guards stay inline per callable — do NOT fold auth -> assertAdmin ->
// assertPayloadShape into a helper here. The callable suites mock `assertAdmin`
// to pin each callable's guard ORDER (__tests__/places_admin_gate.test.js); a
// helper defined in this module closes over the real one, so the mock stops
// applying. When adding a callable, copy the order from an existing one along
// with its guard tests.

module.exports = {
  hasControlChar,
  assertPayloadShape,
  requireString,
  requireNumberInRange,
  readSessionToken,
  enforceDurableRateLimit,
  assertAdmin,
};
