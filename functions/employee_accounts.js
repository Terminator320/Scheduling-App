const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {
  assertPayloadShape,
  requireString,
  assertAdmin,
  enforceDurableRateLimit,
  hasControlChar,
} = require("./security");

/**
 * The shared starting password every new employee account is created with.
 *
 * It is deliberately NOT a secret: the admin reads it off the roster and says
 * it out loud. What makes the account safe is that it stays `status:"invited"`
 * until `completeEmployeeSetup` runs, and the rules grant an invited user
 * nothing — so the window a known password opens is "can reach the setup
 * screen as this person", not "can read the business".
 *
 * That window is still real. Create the account when you are handing the
 * credentials over, not weeks ahead.
 *
 * **Hand-mirrored by `kDefaultStartingPassword` in
 * `lib/features/employees/domain/policies/starting_password_policy.dart`.**
 * This side is the authority; that one is only a display fallback for a row
 * whose account was created earlier. Change one and change the other — both
 * sides pin the literal in a test so a silent drift fails the suite.
 */
const DEFAULT_PASSWORD = "Welcome123!";

// Account creation is bounded per admin uid — defense-in-depth so a
// compromised admin session can't mass-create employees (each one is a real
// Firebase Auth account, not just a Firestore doc).
const CREATE_RATE_MAX = 20;
const CREATE_RATE_WINDOW_MS = 60 * 60 * 1000;

// Setup runs once per person; a handful of retries covers a fumbled password.
const SETUP_RATE_MAX = 5;
const SETUP_RATE_WINDOW_MS = 15 * 60 * 1000;

// Mirrors JobTitle.raw (lib/features/employees/domain/models/job_title.dart)
// and the rules' isValidJobTitle allowlist.
const JOB_TITLES = [
  "", "lead_tech", "technician", "apprentice", "dispatcher",
];

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
 * Creates (or re-provisions) the Firebase Auth account for an employee.
 *
 * Returns the uid plus whether the account already existed. A pre-existing
 * account has its password reset back to the default — that IS the "they never
 * signed in / they lost the password" path, and it is why this is safe to call
 * again for a still-`invited` person.
 *
 * @param {!Object} auth Admin Auth instance.
 * @param {string} email lowercased email.
 * @param {string} displayName composed name.
 * @param {string} password the default starting password.
 * @return {!Promise<{uid: string, reused: boolean}>}
 */
async function provisionAuthAccount(auth, email, displayName, password) {
  try {
    const user = await auth.createUser({
      email, password, displayName, emailVerified: false,
    });
    return {uid: user.uid, reused: false};
  } catch (e) {
    if (e && e.code === "auth/email-already-exists") {
      // Resolve the uid ONLY — the password of an existing account is not
      // touched here. Rotating it is `resetProvisionedPassword`, which the
      // caller runs AFTER the doc-level transaction has claimed the person as
      // still-`invited`. Doing it here reset the password first and asked
      // questions second, so a setup that committed in that window left the
      // employee active on a password nobody told them had been reverted.
      const existing = await auth.getUserByEmail(email);
      return {uid: existing.uid, reused: true};
    }
    throw e;
  }
}

/**
 * Rotates a re-provisioned account back to the shared starting password.
 *
 * Split out of provisionAuthAccount so it can run after the transaction: the
 * only safe moment to overwrite someone's password is once the doc read in the
 * same transaction has confirmed they never finished setup.
 *
 * @param {!Object} auth Admin Auth instance.
 * @param {string} uid the provisioned Auth uid.
 * @param {string} displayName composed name.
 * @param {string} password the default starting password.
 * @return {!Promise<void>}
 */
async function resetProvisionedPassword(auth, uid, displayName, password) {
  await auth.updateUser(uid, {password, displayName});
}

/**
 * Transactional core of createEmployeeAccount, extracted for unit testing.
 *
 * Writes the users doc for an already-provisioned Auth uid. The duplicate
 * lookup and the write share ONE transaction so two admins creating the same
 * person concurrently can't both win.
 *
 * @param {!Object} db Firestore instance.
 * @param {{name: string, firstName: string, lastName: string, email: string,
 *   phone: string, colorValue: string, jobTitle: string, isAdmin: boolean}}
 *   fields Validated fields (email already lowercased).
 * @param {{uid: string, serverTimestamp: !Function}} opts The provisioned Auth
 *   uid and a serverTimestamp factory (injectable for tests).
 * @return {!Promise<{ok: boolean, docId: (string|undefined)}>} `ok:false`
 *   means the email belongs to an account that has already been set up.
 */
async function performCreateAccount(db, fields, opts) {
  const {
    name, firstName, lastName, email, phone, colorValue, jobTitle, isAdmin,
  } = fields;
  const {uid, serverTimestamp} = opts;
  const role = isAdmin ? "admin" : "employee";

  return db.runTransaction(async (tx) => {
    const dup = await tx.get(
        db.collection("users").where("email", "==", email).limit(1),
    );
    const existing = dup.empty ? null : dup.docs[0];
    // A person who has finished setup owns their account now — re-creating
    // them would reset a password they chose. Only a still-pending one is
    // re-provisionable.
    if (existing && existing.data().status !== "invited") {
      return {ok: false};
    }

    // The uid must not already belong to somebody else's doc. `users.email` is
    // admin-editable and is never synced to the Auth account, so the email
    // check above can clear a doc that is NOT the account this uid came from —
    // and a second doc carrying a live employee's uid repoints the
    // `usersByUid` bridge that every rules gate resolves through, locking them
    // out. This is the rules' `allow create` uid denylist restated for the one
    // path that bypasses rules (Admin SDK).
    const byUid = await tx.get(
        db.collection("users").where("uid", "==", uid).limit(2),
    );
    const claimedElsewhere = byUid.docs.some(
        (d) => !existing || d.id !== existing.id,
    );
    if (claimedElsewhere) {
      return {ok: false};
    }

    if (existing) {
      // Refresh the editable fields; status and uid are already right.
      tx.update(existing.ref, {
        name, firstName, lastName, phone, colorValue, jobTitle, role, uid,
        updatedAt: serverTimestamp(),
      });
      return {ok: true, docId: existing.id};
    }

    const ref = db.collection("users").doc();
    tx.set(ref, {
      name, firstName, lastName, email, phone, colorValue, jobTitle, role,
      // The Auth account exists from this moment, so the doc carries its uid
      // immediately — unlike the retired code flow, where uid stayed "" until
      // redemption. `invited` is what still withholds every rules grant.
      status: "invited", uid,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    return {ok: true, docId: ref.id};
  });
}

const createEmployeeAccount = onCall(APP_CHECK, async (req) => {
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
  // 250, not 100: `name` is the JOIN of the two halves, each capped at 100
  // client- and server-side, so the composed value legitimately reaches 201.
  const name = requireString(req.data, "name", 250);
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
      "createEmployeeAccount", req.auth.uid, CREATE_RATE_MAX,
      CREATE_RATE_WINDOW_MS);

  const db = getFirestore();
  const auth = getAuth();

  // Refuse BEFORE touching Auth when the email belongs to a live account.
  // Two lookups, because the two stores can disagree: `users.email` is
  // admin-editable and is never written back to the Auth account, so an
  // email-keyed check alone can clear a doc that is not the account Auth would
  // actually hand us.
  const existingAuth = await auth.getUserByEmail(email).catch(() => null);
  if (existingAuth) {
    // Whose account IS this? Resolve by uid — that is the join the bridge and
    // every rules gate use.
    const byUid = await db.collection("users")
        .where("uid", "==", existingAuth.uid).limit(1).get();
    if (byUid.empty || byUid.docs[0].data().status !== "invited") {
      throw new HttpsError("already-exists", "email-exists");
    }
  }
  const claimed = await db.collection("users")
      .where("email", "==", email).limit(1).get();
  if (!claimed.empty && claimed.docs[0].data().status !== "invited") {
    throw new HttpsError("already-exists", "email-exists");
  }

  // Resolves the uid; for an EXISTING account this deliberately does not touch
  // the password yet (see resetProvisionedPassword).
  const provisioned = await provisionAuthAccount(
      auth, email, name, DEFAULT_PASSWORD);

  // The refusal is raised INSIDE the try so one catch owns the rollback —
  // "when do we un-mint the Auth account" must not have two answers to keep in
  // sync. Never leave an Auth account with no users doc: it would be a sign-in
  // that SplashScreen can't resolve and no admin surface can see or clean up.
  // Only roll back an account WE just minted.
  try {
    const outcome = await performCreateAccount(
        db,
        {
          name, firstName, lastName, email, phone, colorValue, jobTitle,
          isAdmin,
        },
        {
          uid: provisioned.uid,
          serverTimestamp: () => FieldValue.serverTimestamp(),
        },
    );
    if (!outcome.ok) throw new HttpsError("already-exists", "email-exists");
    // The doc is claimed and confirmed still-`invited`, so this is now safe:
    // nobody's chosen password can be behind this uid. A reused account is the
    // "never signed in / lost the password" path, and this IS that reset.
    if (provisioned.reused) {
      await resetProvisionedPassword(
          auth, provisioned.uid, name, DEFAULT_PASSWORD);
    }
  } catch (e) {
    if (!provisioned.reused) {
      await auth.deleteUser(provisioned.uid).catch(() => {});
    }
    throw e;
  }
  // The password is returned so the admin surface shows exactly what was set
  // rather than a constant it hopes still matches the server.
  return {email, password: DEFAULT_PASSWORD};
});

/**
 * Builds the activation patch completeEmployeeSetup applies to the invited
 * users doc. Pure, and exported so the never-empty-`name` contract is pinned
 * by tests rather than by the transaction that happens to use it.
 *
 * `name` is composed from the submitted halves, falling back PER HALF to the
 * stored halves, and is omitted entirely when both are blank — an empty `name`
 * drops the person out of watchAllUsers' orderBy('name') and therefore out of
 * the admin roster. This is the JS mirror of Dart's composeEmployeeName
 * never-empty contract.
 *
 * @param {{firstName: string, lastName: string, phone: string,
 *   termsAccepted: boolean, locationConsent: boolean}} fields The submitted
 *   setup profile (already trimmed and length-checked).
 * @param {{userData: !Object, serverTimestamp: !Function}} opts The stored doc
 *   data plus the timestamp factory (injectable for tests).
 * @return {!Object} the patch for tx.update.
 */
function buildActivationPatch(fields, opts) {
  const {firstName, lastName, phone, termsAccepted, locationConsent} = fields;
  const {userData, serverTimestamp} = opts;
  const patch = {status: "active", updatedAt: serverTimestamp()};
  if (firstName) patch.firstName = firstName;
  if (lastName) patch.lastName = lastName;
  if (phone) patch.phone = phone;
  const composed = [
    firstName || userData.firstName || "",
    lastName || userData.lastName || "",
  ].filter(Boolean).join(" ");
  if (composed) patch.name = composed;
  // Stamped only when the flags are actually true: a consent record for
  // someone who never saw the checkbox would be a false one.
  if (termsAccepted) patch.termsAcceptedAt = serverTimestamp();
  if (locationConsent) patch.locationConsentAt = serverTimestamp();
  return patch;
}

const completeEmployeeSetup = onCall(APP_CHECK, async (req) => {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  assertPayloadShape(req.data, new Set([
    "firstName", "lastName", "phone", "termsAccepted", "locationConsent",
  ]));
  const firstName = optionalString(req.data, "firstName", 100);
  const lastName = optionalString(req.data, "lastName", 100);
  // 40 mirrors createEmployeeAccount's server cap (the client caps at
  // TextLimits.phone via PhoneInputFormatter).
  const phone = optionalString(req.data, "phone", 40);
  const termsAccepted = req.data.termsAccepted === true;
  const locationConsent = req.data.locationConsent === true;
  await enforceDurableRateLimit(
      "completeEmployeeSetup", req.auth.uid, SETUP_RATE_MAX,
      SETUP_RATE_WINDOW_MS);

  const db = getFirestore();
  const uid = req.auth.uid;
  const outcome = await db.runTransaction(async (tx) => {
    const found = await tx.get(
        db.collection("users").where("uid", "==", uid).limit(1),
    );
    if (found.empty) return {ok: false, reason: "no-account"};
    const doc = found.docs[0];
    const userData = doc.data();
    // Idempotent-ish by refusal: an already-active account must not have its
    // consent stamps rewritten by a replayed call.
    if (userData.status !== "invited") {
      return {ok: false, reason: "not-pending"};
    }
    const patch = buildActivationPatch(
        {firstName, lastName, phone, termsAccepted, locationConsent},
        {userData, serverTimestamp: () => FieldValue.serverTimestamp()},
    );
    tx.update(doc.ref, patch);
    return {ok: true};
  });

  if (!outcome.ok) {
    if (outcome.reason === "not-pending") {
      throw new HttpsError("failed-precondition", "setup-not-pending");
    }
    throw new HttpsError("not-found", "account-not-found");
  }
  // No profile echoed back: the client discards it and re-resolves the account
  // through findUserByUid to route, so building one here served nothing.
  return {ok: true};
});

/**
 * Transactional core of deleteEmployeeAccount, extracted for unit testing.
 *
 * Refuses once the person has set up: from that point the account is theirs,
 * and the no-delete invariant applies (disable is the only removal).
 *
 * @param {!Object} db Firestore instance.
 * @param {string} docId users-doc id.
 * @return {!Promise<{ok: boolean, reason: (string|undefined),
 *   uid: (string|undefined)}>}
 */
async function performDeleteAccount(db, docId) {
  return db.runTransaction(async (tx) => {
    const ref = db.collection("users").doc(docId);
    const snap = await tx.get(ref);
    if (!snap.exists) return {ok: false, reason: "not-found"};
    const data = snap.data();
    // Transactional so a setup that commits first flips status and this
    // refuses instead of deleting a just-activated account.
    if (data.status !== "invited") {
      return {ok: false, reason: "not-pending"};
    }
    tx.delete(ref);
    return {ok: true, uid: data.uid || ""};
  });
}

const deleteEmployeeAccount = onCall(APP_CHECK, async (req) => {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  await assertAdmin(req.auth.uid);
  assertPayloadShape(req.data, new Set(["docId"]));
  const docId = requireString(req.data, "docId", 128);
  // `.doc()` throws synchronously on an id containing a slash, which would
  // surface as an opaque `internal` instead of a shaped rejection.
  if (docId.includes("/")) {
    throw new HttpsError("invalid-argument", "invalid-docId");
  }
  await enforceDurableRateLimit(
      "deleteEmployeeAccount", req.auth.uid, CREATE_RATE_MAX,
      CREATE_RATE_WINDOW_MS);

  const outcome = await performDeleteAccount(getFirestore(), docId);
  if (!outcome.ok) {
    if (outcome.reason === "not-pending") {
      throw new HttpsError("failed-precondition", "account-not-pending");
    }
    throw new HttpsError("not-found", "account-not-found");
  }
  // Doc first, Auth second: an Auth account with no doc is invisible to every
  // admin surface, while a doc with no Auth account is visible and fixable by
  // re-creating. Swallow user-not-found so a partial earlier run converges.
  if (outcome.uid) {
    await getAuth().deleteUser(outcome.uid).catch((e) => {
      if (!e || e.code !== "auth/user-not-found") throw e;
    });
  }
  return {ok: true};
});

module.exports = {
  DEFAULT_PASSWORD,
  createEmployeeAccount,
  completeEmployeeSetup,
  deleteEmployeeAccount,
  // Exported for unit tests of the transactional flows and the pure patch.
  provisionAuthAccount,
  resetProvisionedPassword,
  performCreateAccount,
  performDeleteAccount,
  buildActivationPatch,
};
