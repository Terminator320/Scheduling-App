const crypto = require("node:crypto");
const {HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const {getFirestore} = require("firebase-admin/firestore");

const SESSION_TOKEN_MAX_LEN = 64;

// Firestore's own document-id ceiling as the rules state it — hand-mirrored
// from `isValidDocIdField` in firestore.rules. Raise both together.
const DOC_ID_MAX_LEN = 128;

// Hard cap on a callable payload once serialized. Every payload here is just
// a couple of short strings, so anything larger is malformed or abusive.
const MAX_PAYLOAD_BYTES = 4 * 1024;

/**
 * True if the string contains a C0 control character or DEL. We guard
 * against these so logged values can't carry log-injection or odd upstream
 * behaviour.
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
 * Throws HttpsError("invalid-argument") when `data` isn't a plain object, is
 * oversized once serialized, or carries a key outside `allowedKeys` — this is
 * our mass-assignment defence. null/undefined is treated as empty.
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
  // BYTES, not `.length`: that counts UTF-16 code units, so 4096 emoji or CJK
  // characters serialize to ~12-16 KB and passed a cap whose constant and
  // error code both say bytes. `notification_utils.js` already measures this
  // way; this is the same measurement in the other direction.
  if (Buffer.byteLength(serialized, "utf8") > MAX_PAYLOAD_BYTES) {
    throw new HttpsError("invalid-argument", "payload-too-large");
  }
  for (const key of Object.keys(data)) {
    if (!allowedKeys.has(key)) {
      throw new HttpsError("invalid-argument", "unexpected-field");
    }
  }
}

/**
 * Validates and returns a trimmed string field, throwing
 * HttpsError("invalid-argument") when missing, wrong type, out of range, or
 * containing control characters.
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
 * Validates and returns a Firestore document id: a required string of at most
 * `DOC_ID_MAX_LEN` characters that carries no "/".
 *
 * The slash check is the load-bearing half, not tidiness. `db.collection(...)
 * .doc(id)` throws SYNCHRONOUSLY on an id containing one, which surfaces to
 * the caller as an opaque `internal` instead of a shaped validation failure.
 * This is the callable-side owner of the same rule `isValidDocIdField` states
 * in CEL (`firestore.rules`) — it was restated at three call sites, two of
 * them byte-identical down to the comment. Keep the 128 in step with the
 * rules copy.
 * @param {object} data callable request data.
 * @param {string} key field name.
 * @return {string}
 */
function requireDocId(data, key) {
  const value = requireString(data, key, DOC_ID_MAX_LEN);
  if (value.includes("/")) {
    throw new HttpsError("invalid-argument", `invalid-${key}`);
  }
  return value;
}

/**
 * Same as requireString but allows the field to be absent or empty — the
 * length cap and the control-char reject still apply to whatever is there.
 * @param {object} data callable request data.
 * @param {string} key field name.
 * @param {number} maxLen max length (inclusive).
 * @return {string} the trimmed value, or "" when absent.
 */
function optionalString(data, key, maxLen) {
  const value = typeof data?.[key] === "string" ? data[key].trim() : "";
  if (value.length > maxLen || hasControlChar(value)) {
    throw new HttpsError("invalid-argument", `invalid-${key}`);
  }
  return value;
}

/**
 * Validates and returns a finite number within [min, max], throwing
 * HttpsError("invalid-argument") when missing, non-numeric, non-finite, or
 * out of range.
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
 * Reads an optional sessionToken, returning "" if absent and throwing
 * HttpsError("invalid-argument") if present but malformed.
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
 * A sliding-window rate limit backed by Firestore, so it survives across
 * function instances and cold starts (unlike the in-memory limiter). Throws
 * HttpsError("resource-exhausted") once the caller exceeds `max` attempts
 * within `windowMs`. Counters live in `rateLimits/*`, which firestore.rules
 * denies to all clients.
 * @param {string} route stable endpoint identifier (part of the doc key).
 * @param {string} key per-caller limiter key — usually the Auth uid, but any
 *   stable per-caller identifier a route needs (see `keyKind`).
 * @param {number} max max attempts per window.
 * @param {number} windowMs window length in milliseconds.
 * @param {string} [keyKind] label for `key` ("uid" | "email"), purely for log
 *   discrimination; email keys are PII, so only a hash is logged.
 * @return {!Promise<{refund: function(): !Promise<void>}>} A handle whose
 *   `refund()` undoes the recorded attempt on a best-effort basis, so a
 *   server-side failure (not the caller's fault) doesn't burn one of their
 *   limited attempts. Existing callers that ignore the return value are
 *   unaffected.
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
    // We track per-attempt timestamps instead of a single windowStart
    // counter — a counter would let a caller burst 2×max across the boundary.
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
    // Never log the raw key — it's PII for the email-keyed route. Log a
    // short sha256 prefix instead so operators can still correlate breaches.
    const keyHash = crypto.createHash("sha256").update(key)
        .digest("hex").slice(0, 12);
    logger.warn("enforceDurableRateLimit: limit exceeded",
        {route, keyKind, keyHash});
    throw new HttpsError("resource-exhausted", "too-many-attempts");
  }

  // Best-effort refund of the recorded attempt. It swallows its own errors
  // since refunding is just an optimization — not worth failing the
  // caller's error path.
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
 * The whole opening of an ADMIN-ONLY callable: signed in, actually an admin,
 * and a payload of exactly [allowedKeys].
 *
 * One owner because the three steps were re-decided at eleven call sites, and
 * on 2026-09-01 three of those sites turned out to have a DELETABLE
 * `assertAdmin` — the whole suite stayed green with the gate removed, on the
 * callables that mint and delete real Firebase Auth accounts. Tests close
 * that for the three that were found; this closes it for the ones nobody has
 * looked at yet, because a callable that opens with this cannot be missing a
 * step.
 *
 * The ORDER is the security-relevant part and is fixed here:
 *
 *   auth -> assertAdmin -> assertPayloadShape
 *
 * Identity guards sit ABOVE the payload check so a non-privileged caller is
 * refused before anything reads their data, and the payload check sits above
 * whatever rate limiter the caller adds next, so a burst of malformed
 * submissions cannot exhaust a legitimate admin's window. `.claude/rules/
 * security.md` states that order; this is it made mechanical.
 *
 * NOT for a self-service callable. `changeEmployeeEmail` and
 * `completeEmployeeSetup` are deliberately not admin-only, and
 * `changeEmployeeEmail` resolves its caller through the pure
 * `resolveEmailChangeCaller` precisely so widening it past admins cannot
 * widen WHICH doc a caller reaches. Don't reach for this there.
 *
 * @param {!Object} req The callable request.
 * @param {!Set<string>} allowedKeys The only keys this endpoint accepts.
 * @return {!Promise<string>} The caller's uid, which every site needs next for
 *   its rate limiter.
 */
async function assertAdminCall(req, allowedKeys) {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  await assertAdmin(req.auth.uid);
  assertPayloadShape(req.data, allowedKeys);
  return req.auth.uid;
}

/**
 * Throws HttpsError("permission-denied", "wave/not-admin") unless the
 * `usersByUid/{uid}` bridge (kept in sync by syncUsersByUid) shows an active
 * admin. Role always comes from Firestore, never from the client.
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

/**
 * True when the caller's re-authentication is missing or too old to permit an
 * irreversible or identity-rewriting action. Pure/testable.
 *
 * Fails CLOSED on a missing or non-numeric `auth_time`: a caller that presents
 * no token claim must not read as "recently re-authenticated".
 * @param {*} authTime ID-token `auth_time` (epoch seconds) or undefined.
 * @param {number} nowSec Current time in epoch seconds.
 * @param {number} maxAgeSeconds Allowed staleness window in seconds.
 * @return {boolean}
 */
function isReauthStale(authTime, nowSec, maxAgeSeconds) {
  return typeof authTime !== "number" ||
      nowSec - authTime > maxAgeSeconds;
}

/**
 * Rejects a caller whose re-authentication is older than [maxAgeSeconds].
 *
 * Belongs ABOVE the rate limiter at every call site, so a stale-auth rejection
 * doesn't burn one of the caller's slots, and below the identity guards.
 * @param {!Object} auth The callable's `req.auth`.
 * @param {string} route Callable name, for the log line.
 * @param {number} maxAgeSeconds Allowed staleness window in seconds.
 * @return {void}
 */
function assertFreshReauth(auth, route, maxAgeSeconds) {
  const authTime = auth && auth.token ? auth.token.auth_time : undefined;
  const nowSec = Math.floor(Date.now() / 1000);
  if (isReauthStale(authTime, nowSec, maxAgeSeconds)) {
    logger.warn(`${route}: stale auth_time; reauth required`, {
      uid: auth ? auth.uid : null,
      authTime,
      ageSec: typeof authTime === "number" ? nowSec - authTime : null,
    });
    throw new HttpsError("unauthenticated", "stale-auth");
  }
}

// The App Check option block every callable spreads. It was declared as an
// identical private const in two modules; a callable that also sets a region,
// a timeout or a secret still writes `enforceAppCheck: true` inline beside
// them, because spreading a one-key constant into a larger options object
// reads as less explicit, not more, on a security-critical line.
const APP_CHECK = {enforceAppCheck: true};

// Keep guards inline per callable — a shared helper here would close over
// the real assertAdmin and break the guard-order mocks in
// __tests__/places_admin_gate.test.js.

module.exports = {
  APP_CHECK,
  hasControlChar,
  assertPayloadShape,
  requireString,
  requireDocId,
  optionalString,
  requireNumberInRange,
  readSessionToken,
  enforceDurableRateLimit,
  assertAdmin,
  assertAdminCall,
  isReauthStale,
  assertFreshReauth,
};
