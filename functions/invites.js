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
  INVITE_CODE_TTL_MS, generateSignupCode, hashSignupCode,
  validateInvitePending, validateRedemption,
} = require("./signup_code_utils");

// Mirrors account.js's throttle, but redeem is keyed by token email (below).
const REDEEM_RATE_MAX = 5;
const REDEEM_RATE_WINDOW_MS = 15 * 60 * 1000;

// Invite issuance is bounded per admin uid — defense-in-depth so a
// compromised admin session can't mass-create invited users + signup codes.
const INVITE_RATE_MAX = 20;
const INVITE_RATE_WINDOW_MS = 60 * 60 * 1000;

// previewInvite is unauthenticated, so the code hash is the only caller
// identity available to bound. This caps hammering of a single code.
const PREVIEW_RATE_MAX = 10;
const PREVIEW_RATE_WINDOW_MS = 15 * 60 * 1000;

// Mirrors JobTitle.raw (lib/features/employees/domain/models/job_title.dart)
// and the rules' isValidJobTitle allowlist.
const JOB_TITLES = [
  "", "lead_tech", "technician", "apprentice", "dispatcher",
];

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
 * @param {{name: string, firstName: string, lastName: string, email: string,
 *   phone: string, colorValue: string, jobTitle: string, isAdmin: boolean}}
 *   fields Validated invite fields (email already lowercased).
 * @param {{code: string, expiresAt: !Date, serverTimestamp: !Function}} opts
 *   The pre-generated one-time code, its expiry, and a serverTimestamp
 *   factory (injectable for tests).
 * @return {!Promise<{ok: boolean, code: (string|undefined)}>} `ok:false`
 *   means the email belongs to a claimed (non-invited) account.
 */
async function performCreateInvite(db, fields, opts) {
  const {
    name, firstName, lastName, email, phone, colorValue, jobTitle, isAdmin,
  } = fields;
  const {code, expiresAt, serverTimestamp} = opts;
  const role = isAdmin ? "admin" : "employee";
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
        name, firstName, lastName, phone, colorValue, jobTitle, role,
        // Mirrors the code's expiry onto the invited doc so the admin Team
        // row can caption it — clients can never read signupCodes.
        codeExpiresAt: expiresAt,
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
      name, firstName, lastName, email, phone, colorValue, jobTitle, role,
      status: "invited", uid: "",
      codeExpiresAt: expiresAt,
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
  assertPayloadShape(req.data, new Set([
    "name", "firstName", "lastName", "email", "phone", "colorValue",
    "jobTitle", "isAdmin",
  ]));
  const name = requireString(req.data, "name", 100);
  const firstName = optionalString(req.data, "firstName", 100);
  const lastName = optionalString(req.data, "lastName", 100);
  const email = requireString(req.data, "email", 254).toLowerCase();
  const phone = optionalString(req.data, "phone", 40);
  const colorValue = requireString(req.data, "colorValue", 40);
  const jobTitle = optionalString(req.data, "jobTitle", 40);
  const isAdmin = req.data.isAdmin === true;
  // Mirrors the rules' colorValue guard (firestore.rules isValidUserData) —
  // this Admin SDK write bypasses rules, so it's the one path that could
  // otherwise seed a value they'd reject.
  if (!/^-?[0-9]+$/.test(colorValue)) {
    throw new HttpsError("invalid-argument", "invalid-colorValue");
  }
  // Same reasoning for jobTitle: the allowlist here IS the enforcement.
  if (!JOB_TITLES.includes(jobTitle)) {
    throw new HttpsError("invalid-argument", "invalid-jobTitle");
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
      {name, firstName, lastName, email, phone, colorValue, jobTitle, isAdmin},
      {code, expiresAt, serverTimestamp: () => FieldValue.serverTimestamp()},
  );
  if (!outcome.ok) {
    throw new HttpsError("already-exists", "email-exists");
  }
  return {code};
});

/**
 * Builds the activation patch redeemSignupCode applies to the invited users
 * doc. Pure, and exported so the never-empty-`name` contract is pinned by
 * tests rather than by the transaction that happens to use it.
 *
 * `name` is composed from the submitted halves, falling back PER HALF to the
 * invite's stored halves, and is omitted entirely when both are blank — an
 * empty `name` drops the person out of watchAllUsers' orderBy('name') and
 * therefore out of the admin roster. This is the JS mirror of Dart's
 * composeEmployeeName never-empty contract.
 *
 * Consent stamps are conditional: the shipped client sends only `code`, and a
 * consent record for someone who never saw the checkbox would be a false one.
 *
 * @param {{uid: string, firstName: string, lastName: string, phone: string,
 *   termsAccepted: boolean, locationConsent: boolean}} fields The submitted
 *   acceptance profile (already trimmed and length-checked).
 * @param {{inviteData: !Object, serverTimestamp: !Function,
 *   deleteField: !Function}} opts The invite doc's stored data plus the two
 *   Firestore sentinel factories (injectable for tests).
 * @return {!Object} the patch for tx.update.
 */
function buildActivationPatch(fields, opts) {
  const {uid, firstName, lastName, phone, termsAccepted, locationConsent} =
    fields;
  const {inviteData, serverTimestamp, deleteField} = opts;
  const patch = {
    uid,
    status: "active",
    // The field describes a pending code; leaving it on an active doc is
    // junk a future reader would misinterpret.
    codeExpiresAt: deleteField(),
    updatedAt: serverTimestamp(),
  };
  if (firstName) patch.firstName = firstName;
  if (lastName) patch.lastName = lastName;
  if (phone) patch.phone = phone;
  const composed = [
    firstName || inviteData.firstName || "",
    lastName || inviteData.lastName || "",
  ].filter(Boolean).join(" ");
  if (composed) patch.name = composed;
  if (termsAccepted) patch.termsAcceptedAt = serverTimestamp();
  if (locationConsent) patch.locationConsentAt = serverTimestamp();
  return patch;
}

const redeemSignupCode = onCall(APP_CHECK, async (req) => {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  assertPayloadShape(req.data, new Set([
    "code", "firstName", "lastName", "phone",
    "termsAccepted", "locationConsent",
  ]));
  const code = requireString(req.data, "code", 32);
  const firstName = optionalString(req.data, "firstName", 100);
  const lastName = optionalString(req.data, "lastName", 100);
  // 40 mirrors createEmployeeInvite's server cap (the client caps at
  // TextLimits.phone = 15 via PhoneInputFormatter).
  const phone = optionalString(req.data, "phone", 40);
  const termsAccepted = req.data.termsAccepted === true;
  const locationConsent = req.data.locationConsent === true;
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
    const patch = buildActivationPatch(
        {
          uid: req.auth.uid, firstName, lastName, phone,
          termsAccepted, locationConsent,
        },
        {
          inviteData,
          serverTimestamp: () => FieldValue.serverTimestamp(),
          deleteField: () => FieldValue.delete(),
        },
    );
    tx.update(inviteRef, patch);
    tx.delete(codeRef);
    return {
      ok: true,
      role: inviteData.role || "employee",
      // The just-written name when the acceptance supplied one, so the
      // response can't report a name the doc no longer has.
      name: patch.name || inviteData.name || "",
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

/**
 * Transactional core of revokeInvite, extracted for unit testing.
 *
 * The transaction is what closes the revoke-vs-redeem race: both flows
 * transact over the same two docs, so a redeem that commits first flips
 * `status` to `active` and this refuses with `not-pending` instead of
 * deleting a just-activated account.
 *
 * @param {!Object} db Firestore instance.
 * @param {string} inviteDocId users-doc id of the pending invite.
 * @return {!Promise<{ok: boolean, reason: (string|undefined)}>} `ok:false`
 *   with `not-found` or `not-pending`.
 */
async function performRevokeInvite(db, inviteDocId) {
  return db.runTransaction(async (tx) => {
    const ref = db.collection("users").doc(inviteDocId);
    const snap = await tx.get(ref);
    if (!snap.exists) return {ok: false, reason: "not-found"};
    const data = snap.data();
    if (data.status !== "invited" || (data.uid || "") !== "") {
      return {ok: false, reason: "not-pending"};
    }
    const codes = await tx.get(
        db.collection("signupCodes").where("inviteDocId", "==", inviteDocId),
    );
    codes.forEach((d) => tx.delete(d.ref));
    tx.delete(ref);
    return {ok: true};
  });
}

const revokeInvite = onCall(APP_CHECK, async (req) => {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  await assertAdmin(req.auth.uid);
  // Payload before the limiter so a burst of malformed submissions can't
  // exhaust a legitimate admin's window.
  assertPayloadShape(req.data, new Set(["inviteDocId"]));
  const inviteDocId = requireString(req.data, "inviteDocId", 128);
  // `.doc()` throws synchronously on an id containing a slash, which would
  // surface as an opaque `internal` instead of a shaped rejection.
  if (inviteDocId.includes("/")) {
    throw new HttpsError("invalid-argument", "invalid-inviteDocId");
  }
  // Its own route key, same shape and budget as invite issuance.
  await enforceDurableRateLimit(
      "revokeInvite", req.auth.uid, INVITE_RATE_MAX, INVITE_RATE_WINDOW_MS);

  const outcome = await performRevokeInvite(getFirestore(), inviteDocId);
  if (!outcome.ok) {
    if (outcome.reason === "not-pending") {
      throw new HttpsError("failed-precondition", "invite-not-pending");
    }
    throw new HttpsError("not-found", "invite-not-found");
  }
  return {ok: true};
});

// The ONLY unauthenticated callable in this codebase — the caller is accepting
// an invite and has no account yet, so there is no uid to guard or to key a
// rate limit by. App Check enforcement, the payload shape guard and the
// per-code-hash limiter below are what stand in for the identity check.
// Disclosing the invited email to someone already holding a valid code adds
// nothing: the code is the bearer credential for exactly that account.
const previewInvite = onCall(APP_CHECK, async (req) => {
  assertPayloadShape(req.data, new Set(["code"]));
  const code = requireString(req.data, "code", 32);
  const codeHash = hashSignupCode(code);
  // Keyed by the code hash: caps hammering of ONE code. A caller varying
  // codes gets a fresh key each time, which is acceptable — at ~60 bits of
  // entropy online enumeration is not a real attack, and App Check gates the
  // endpoint to genuine app builds. The code itself is never logged.
  await enforceDurableRateLimit(
      "previewInvite", codeHash, PREVIEW_RATE_MAX, PREVIEW_RATE_WINDOW_MS,
      "code");

  const db = getFirestore();
  const codeSnap = await db.collection("signupCodes").doc(codeHash).get();
  const codeData = codeSnap.exists ? codeSnap.data() : null;
  let inviteData = null;
  if (codeData) {
    const inviteSnap = await db.collection("users")
        .doc(codeData.inviteDocId).get();
    inviteData = inviteSnap.exists ? inviteSnap.data() : null;
  }
  const v = validateInvitePending({codeData, inviteData, nowMs: Date.now()});
  if (!v.ok) {
    if (v.reason === "expired") {
      throw new HttpsError("failed-precondition", "code-expired");
    }
    throw new HttpsError("invalid-argument", "invalid-code");
  }
  // Only the fields the acceptance screen renders — never the doc id, the
  // phone, the colour, or anything else on the invite.
  return {
    email: inviteData.email || "",
    firstName: inviteData.firstName || "",
    lastName: inviteData.lastName || "",
    role: inviteData.role || "employee",
    expiresAtMs: codeData.expiresAt.toMillis(),
  };
});

module.exports = {
  createEmployeeInvite,
  redeemSignupCode,
  revokeInvite,
  previewInvite,
  // Exported for unit tests of the transactional invite flows and the pure
  // activation patch.
  performCreateInvite,
  performRevokeInvite,
  buildActivationPatch,
};
