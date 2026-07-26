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

// Mirrors account.js's throttle, but redeem is keyed by token email (below).
const REDEEM_RATE_MAX = 5;
const REDEEM_RATE_WINDOW_MS = 15 * 60 * 1000;

// Invite issuance is bounded per admin uid — defense-in-depth so a
// compromised admin session can't mass-create invited users + signup codes.
const INVITE_RATE_MAX = 20;
const INVITE_RATE_WINDOW_MS = 60 * 60 * 1000;

// Optional trimmed string with a length + control-char guard. Phone may be
// empty and requireString rejects empty, so we read it leniently here.
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
 * Runs the duplicate-email lookup, prior-code sweep, and writes inside ONE
 * Firestore transaction. This closes races the old check-then-write flow
 * had — duplicate invites for the same email, and a re-issue racing a
 * concurrent redeemSignupCode.
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
    // A real (claimed) account blocks re-use. A still-pending invite gets
    // re-issued instead — idempotent, useful for e.g. a lost or expired code.
    if (existing && existing.data().status !== "invited") {
      return {ok: false};
    }

    if (existing) {
      const prior = await tx.get(
          db.collection("signupCodes")
              .where("inviteDocId", "==", existing.id),
      );
      // Refresh the editable fields and replace the invite's code — this is
      // the re-issue path.
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
  // Validate the payload before consuming a rate-limit slot so malformed
  // submissions can't lock out a legitimate admin for an hour.
  assertPayloadShape(req.data,
      new Set(["name", "email", "phone", "colorValue"]));
  const name = requireString(req.data, "name", 100);
  const email = requireString(req.data, "email", 254).toLowerCase();
  const phone = optionalString(req.data, "phone", 40);
  const colorValue = requireString(req.data, "colorValue", 40);
  // Mirrors the rules' colorValue guard (firestore.rules isValidUserData) —
  // this Admin SDK write bypasses rules, so it's the one path that could
  // otherwise seed a value they'd reject.
  if (!/^-?[0-9]+$/.test(colorValue)) {
    throw new HttpsError("invalid-argument", "invalid-colorValue");
  }
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
  // Key the limit by target email, not caller uid — a failed signup deletes
  // and re-registers to mint a fresh uid, which would reset a uid-keyed cap.
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
