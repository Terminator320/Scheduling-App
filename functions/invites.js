const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {
  assertPayloadShape, requireString, assertAdmin, enforceDurableRateLimit,
} = require("./security");
const {
  INVITE_CODE_TTL_MS, generateSignupCode, hashSignupCode, validateRedemption,
} = require("./signup_code_utils");

// Mirrors account.js: auth-sensitive redemption is throttled per uid.
const REDEEM_RATE_MAX = 5;
const REDEEM_RATE_WINDOW_MS = 15 * 60 * 1000;

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
  if (v.length > maxLen) {
    throw new HttpsError("invalid-argument", `invalid-${key}`);
  }
  return v;
}

// TODO(pre-ship): set enforceAppCheck:true once the app ships through the
// stores and Play Integrity can mint verified App Check tokens.
const APP_CHECK = {enforceAppCheck: false};

const createEmployeeInvite = onCall(APP_CHECK, async (req) => {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  await assertAdmin(req.auth.uid);
  assertPayloadShape(req.data,
      new Set(["name", "email", "phone", "colorValue"]));
  const name = requireString(req.data, "name", 100);
  const email = requireString(req.data, "email", 254).toLowerCase();
  const phone = optionalString(req.data, "phone", 40);
  const colorValue = requireString(req.data, "colorValue", 40);

  const db = getFirestore();
  const dup = await db.collection("users")
      .where("email", "==", email).limit(1).get();
  if (!dup.empty) throw new HttpsError("already-exists", "email-exists");

  const code = generateSignupCode();
  const inviteRef = db.collection("users").doc();
  const codeRef = db.collection("signupCodes").doc(hashSignupCode(code));
  const expiresAt = new Date(Date.now() + INVITE_CODE_TTL_MS);
  await db.runTransaction(async (tx) => {
    tx.set(inviteRef, {
      name, email, phone, colorValue,
      role: "employee", status: "invited", uid: "",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(codeRef, {
      inviteDocId: inviteRef.id, email, expiresAt,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return {code};
});

const regenerateSignupCode = onCall(APP_CHECK, async (req) => {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  await assertAdmin(req.auth.uid);
  assertPayloadShape(req.data, new Set(["inviteDocId"]));
  const inviteDocId = requireString(req.data, "inviteDocId", 200);

  const db = getFirestore();
  const inviteSnap = await db.collection("users").doc(inviteDocId).get();
  const invite = inviteSnap.exists ? inviteSnap.data() : null;
  if (!invite || invite.status !== "invited") {
    throw new HttpsError("failed-precondition", "not-a-pending-invite");
  }
  const prior = await db.collection("signupCodes")
      .where("inviteDocId", "==", inviteDocId).get();
  const code = generateSignupCode();
  const batch = db.batch();
  prior.forEach((d) => batch.delete(d.ref));
  batch.set(db.collection("signupCodes").doc(hashSignupCode(code)), {
    inviteDocId, email: invite.email || "",
    expiresAt: new Date(Date.now() + INVITE_CODE_TTL_MS),
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
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
  await enforceDurableRateLimit(
      "redeemSignupCode", req.auth.uid, REDEEM_RATE_MAX, REDEEM_RATE_WINDOW_MS);

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
    throw new HttpsError("invalid-argument", "invalid-code");
  }
  return {role: outcome.role, name: outcome.name};
});

module.exports = {
  createEmployeeInvite, regenerateSignupCode, redeemSignupCode,
};
