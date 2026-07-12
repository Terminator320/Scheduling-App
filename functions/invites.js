const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {
  assertPayloadShape,
  requireString,
  assertAdmin,
  enforceDurableRateLimit,
  hasControlChar,
} = require("./security");
const {
  INVITE_CODE_TTL_MS, generateSignupCode, hashSignupCode, validateRedemption,
} = require("./signup_code_utils");

// Mirrors account.js's throttle; redeem is keyed by token email (below).
const REDEEM_RATE_MAX = 5;
const REDEEM_RATE_WINDOW_MS = 15 * 60 * 1000;

// Invite issuance is bounded per admin uid — defense-in-depth so a
// compromised admin session can't mass-create invited users + signup codes
// (matches the other admin callables, e.g. waveBootstrap).
const INVITE_RATE_MAX = 20;
const INVITE_RATE_WINDOW_MS = 60 * 60 * 1000;

// Optional trimmed string with a length + control-char guard (phone may be
// empty; requireString rejects empty, so read it leniently here).
/**
 * Optional trimmed string field — like requireString but allows empty.
 * @param {object} data callable request data.
 * @param {string} key field name.
 * @param {number} maxLen max length (inclusive).
 * @return {string}
 */
function optionalString(data, key, maxLen) {
  const v = typeof data?.[key] === "string" ? data[key].trim() : "";
  if (v.length > maxLen || hasControlChar(v)) {
    throw new HttpsError("invalid-argument", `invalid-${key}`);
  }
  return v;
}

const APP_CHECK = {enforceAppCheck: true};

/**
 * Transactional core of createEmployeeInvite, extracted for unit testing.
 *
 * EVERYTHING — the duplicate-email lookup, the prior-code sweep, and the
 * writes — runs inside ONE Firestore transaction (equality queries are
 * allowed in transactions via `tx.get(query)`), closing two races the old
 * check-then-write flow had:
 *   1. Two concurrent invites for the same email both passed the
 *      out-of-transaction duplicate check and minted two invite docs.
 *   2. The re-issue branch's query+batch could interleave with a concurrent
 *      redeemSignupCode transaction (which flips the invite to 'active' and
 *      deletes the code doc), re-issuing a code for an already-claimed
 *      account. The transactional read of the invite doc now serializes the
 *      two: whichever commits second sees the other's write and
 *      retries/blocks correctly.
 *
 * @param {!Object} db Firestore instance.
 * @param {{name: string, email: string, phone: string, colorValue: string}}
 *   fields Validated invite fields (email already lowercased).
 * @param {{code: string, expiresAt: !Date, serverTimestamp: !Function}} opts
 *   The pre-generated one-time code, its expiry, and a serverTimestamp
 *   factory (injectable for tests).
 * @return {!Promise<{ok: boolean, code: (string|undefined)}>} `ok:false`
 *   means the email belongs to a claimed (non-invited) account.
 */
async function performCreateInvite(db, fields, opts) {
  const {name, email, phone, colorValue} = fields;
  const {code, expiresAt, serverTimestamp} = opts;
  const codeRef = db.collection("signupCodes").doc(hashSignupCode(code));

  return db.runTransaction(async (tx) => {
    // All reads first (Firestore transactions forbid reads after writes).
    const dup = await tx.get(
        db.collection("users").where("email", "==", email).limit(1),
    );
    const existing = dup.empty ? null : dup.docs[0];
    // A real (claimed) account blocks re-use; a still-pending invite is
    // re-issued instead (idempotent — covers a lost/expired code and seeds a
    // code for invites created before signup codes existed).
    if (existing && existing.data().status !== "invited") {
      return {ok: false};
    }

    if (existing) {
      const prior = await tx.get(
          db.collection("signupCodes")
              .where("inviteDocId", "==", existing.id),
      );
      // Re-issue: refresh the editable fields and replace the invite's code.
      prior.forEach((d) => tx.delete(d.ref));
      tx.update(existing.ref, {
        name, phone, colorValue,
        updatedAt: serverTimestamp(),
      });
      tx.set(codeRef, {
        inviteDocId: existing.id, email, expiresAt,
        createdAt: serverTimestamp(),
      });
      return {ok: true, code};
    }

    const inviteRef = db.collection("users").doc();
    tx.set(inviteRef, {
      name, email, phone, colorValue,
      role: "employee", status: "invited", uid: "",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    tx.set(codeRef, {
      inviteDocId: inviteRef.id, email, expiresAt,
      createdAt: serverTimestamp(),
    });
    return {ok: true, code};
  });
}

const createEmployeeInvite = onCall(APP_CHECK, async (req) => {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  await assertAdmin(req.auth.uid);
  // Validate the payload BEFORE consuming a rate-limit slot, so ~20 malformed
  // submissions can't lock a legitimate admin out of inviting for an hour.
  // assertAdmin stays above the limiter so non-admins still can't burn slots.
  assertPayloadShape(req.data,
      new Set(["name", "email", "phone", "colorValue"]));
  const name = requireString(req.data, "name", 100);
  const email = requireString(req.data, "email", 254).toLowerCase();
  const phone = optionalString(req.data, "phone", 40);
  const colorValue = requireString(req.data, "colorValue", 40);
  await enforceDurableRateLimit(
      "createEmployeeInvite", req.auth.uid, INVITE_RATE_MAX,
      INVITE_RATE_WINDOW_MS);

  const db = getFirestore();
  // The code is generated OUTSIDE the transaction so a transaction retry
  // reuses the same code/hash (deterministic doc id across retries).
  const code = generateSignupCode();
  const expiresAt = new Date(Date.now() + INVITE_CODE_TTL_MS);

  const outcome = await performCreateInvite(
      db,
      {name, email, phone, colorValue},
      {code, expiresAt, serverTimestamp: () => FieldValue.serverTimestamp()},
  );
  if (!outcome.ok) {
    throw new HttpsError("already-exists", "email-exists");
  }
  return {code};
});

const redeemSignupCode = onCall(APP_CHECK, async (req) => {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  assertPayloadShape(req.data, new Set(["code"]));
  const code = requireString(req.data, "code", 32);
  const tokenEmail = req.auth.token && req.auth.token.email;
  if (typeof tokenEmail !== "string" || tokenEmail === "") {
    throw new HttpsError("failed-precondition", "no-email-claim");
  }
  // Key the limit by the target email, not the caller uid: an attacker can
  // delete + re-register the same email to mint a fresh uid (the signup flow
  // does exactly that on a failed attempt), which would reset a uid-keyed
  // counter. The email pins the cap to the invite being guessed.
  const rateKey = tokenEmail.trim().toLowerCase();
  await enforceDurableRateLimit(
      "redeemSignupCode", rateKey, REDEEM_RATE_MAX, REDEEM_RATE_WINDOW_MS,
      "email");

  const db = getFirestore();
  const codeRef = db.collection("signupCodes").doc(hashSignupCode(code));
  const outcome = await db.runTransaction(async (tx) => {
    const codeSnap = await tx.get(codeRef);
    const codeData = codeSnap.exists ? codeSnap.data() : null;
    let inviteData = null;
    let inviteRef = null;
    if (codeData) {
      inviteRef = db.collection("users").doc(codeData.inviteDocId);
      const inviteSnap = await tx.get(inviteRef);
      inviteData = inviteSnap.exists ? inviteSnap.data() : null;
    }
    const v = validateRedemption({
      codeData, inviteData, tokenEmail, nowMs: Date.now(),
    });
    if (!v.ok) return v;
    tx.update(inviteRef, {
      uid: req.auth.uid, status: "active",
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.delete(codeRef);
    return {
      ok: true,
      role: inviteData.role || "employee",
      name: inviteData.name || "",
    };
  });
  if (!outcome.ok) {
    if (outcome.reason === "expired") {
      throw new HttpsError("failed-precondition", "code-expired");
    }
    if (outcome.reason === "email-mismatch") {
      throw new HttpsError("failed-precondition", "code-email-mismatch");
    }
    throw new HttpsError("invalid-argument", "invalid-code");
  }
  return {role: outcome.role, name: outcome.name};
});

module.exports = {
  createEmployeeInvite,
  redeemSignupCode,
  // Exported for unit tests of the transactional invite flow.
  performCreateInvite,
};
