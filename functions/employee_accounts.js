const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {getMessaging} = require("firebase-admin/messaging");
const {
  assertPayloadShape,
  requireString,
  optionalString,
  assertAdmin,
  enforceDurableRateLimit,
  assertFreshReauth,
} = require("./security");
// index.js already loads notifications.js in every container, so this costs no
// extra cold start. sendToEmployee is the one owner of the token fetch, the
// role + active gate and stale-token pruning — never re-derive them here.
const {
  sendToEmployee,
  sendToActiveAdmins,
  TIMED_RECIPIENT_ROLES,
} = require("./notification_utils");
const {
  buildEmailChangedMessage,
  buildSelfEmailChangedMessage,
} = require("./notification_messages");

/**
 * The shared starting password every new employee account is created with.
 *
 * It is deliberately NOT a secret: the admin reads it off the roster and says
 * it out loud. What makes the account safe is that it stays `status:"invited"`
 * until `completeEmployeeSetup` runs, the rules grant an invited user nothing,
 * AND that callable refuses without a verified email — so a stranger who knows
 * the address can reach the setup screen but cannot get past it, because
 * finishing setup requires control of the mailbox. The setup screen sends the
 * standard Firebase verification email and waits for it.
 *
 * That window is still real: whoever holds the mailbox and the shared password
 * can activate the account. Create it when you are handing the credentials
 * over, not weeks ahead.
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

// changeEmployeeEmail rewrites a SIGN-IN IDENTITY, which is the
// account-takeover primitive an unattended unlocked phone offers — so it is
// budgeted far tighter than account creation, and it demands a fresh re-auth
// the same way deleteAccount does. The client re-authenticates before calling
// (SelfEmailService); this is the server-side half of that guarantee.
const EMAIL_CHANGE_RATE_MAX = 5;
const EMAIL_CHANGE_RATE_WINDOW_MS = 60 * 60 * 1000;
const EMAIL_CHANGE_REAUTH_MAX_AGE_SECONDS = 5 * 60;

// Mirrors JobTitle.raw (lib/features/employees/domain/models/job_title.dart)
// and the rules' isValidJobTitle allowlist.
const JOB_TITLES = [
  "", "lead_tech", "technician", "apprentice", "dispatcher",
];

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
  // the password yet (see resetProvisionedPassword). The pre-flight above
  // already resolved that account, so short-circuit rather than spending a
  // createUser that can only fail plus the getUserByEmail that recovers from
  // it — two Auth round trips of pure latency on the reset-password path.
  // Only when the email was NOT found do we go through provisionAuthAccount,
  // whose already-exists branch still covers a racing concurrent create.
  const provisioned = existingAuth ?
      {uid: existingAuth.uid, reused: true} :
      await provisionAuthAccount(auth, email, name, DEFAULT_PASSWORD);

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
      // A failed rollback leaves an Auth account with no users doc: invisible
      // to every admin surface, and it permanently bricks that email for
      // re-creation (the pre-flight above refuses an Auth account whose uid no
      // doc claims). Nothing can recover it in-app, so it MUST be loud —
      // swallowing it silently is how that state goes unnoticed for months.
      await auth.deleteUser(provisioned.uid).catch((rollbackError) => {
        logger.error(
            "createEmployeeAccount: orphaned auth account; delete it by hand",
            {uid: provisioned.uid, err: String(rollbackError)},
        );
      });
    }
    throw e;
  }
  // The password is returned so the admin surface shows exactly what was set
  // rather than a constant it hopes still matches the server.
  return {email, password: DEFAULT_PASSWORD};
});

/**
 * Transactional core of changeEmployeeEmail, extracted for unit testing.
 *
 * Re-checks BOTH things the pre-flight checked, because the pre-flight is only
 * an optimization: that this doc still holds [previousEmail] (nobody edited it
 * underneath us) and that no other doc holds the new one.
 *
 * @param {!Object} db Firestore instance.
 * @param {string} docId users-doc id.
 * @param {string} email the new, lowercased email.
 * @param {string} previousEmail what the doc held when we read it.
 * @param {{serverTimestamp: !Function}} opts Timestamp factory (injectable).
 * @return {!Promise<{ok: boolean}>}
 */
async function performChangeEmail(db, docId, email, previousEmail, opts) {
  const {serverTimestamp} = opts;
  return db.runTransaction(async (tx) => {
    const ref = db.collection("users").doc(docId);
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new HttpsError("not-found", "account-not-found");
    }
    if ((snap.data().email || "") !== previousEmail) {
      throw new HttpsError("aborted", "email-changed");
    }
    const dup = await tx.get(
        db.collection("users").where("email", "==", email).limit(2),
    );
    if (dup.docs.some((d) => d.id !== docId)) {
      throw new HttpsError("already-exists", "email-exists");
    }
    tx.update(ref, {email, updatedAt: serverTimestamp()});
    return {ok: true};
  });
}

/**
 * Decides whether this caller may move [docId]'s email, and how.
 *
 * Pure over the caller's `usersByUid` bridge data so the guard is testable
 * without Firestore. Two ways through and no third: an ACTIVE ADMIN may move
 * any doc, and an ACTIVE EMPLOYEE may move their OWN. Everything else is
 * refused — a disabled account (whose Auth credential outlives the status flip
 * until syncUsersByUid revokes it), an invited account mid-setup, a missing
 * bridge doc, an unknown role, or an employee naming somebody else's doc.
 *
 * Widening this callable past admins must never widen WHICH doc a caller can
 * reach. That is the failure this function exists to make hard to write.
 *
 * `isSelf` reports whether the caller IS the target, independent of role,
 * because it drives who gets notified — an admin editing their own row is a
 * self change and must not push "someone changed their email" to themselves.
 *
 * @param {?Object} bridge The caller's `usersByUid/{uid}` data, or null.
 * @param {string} docId The users-doc id being changed.
 * @return {!Promise<{isSelf: boolean, callerDocId: string}>}
 */
async function resolveEmailChangeCaller(bridge, docId) {
  const data = bridge || null;
  if (!data || data.status !== "active") {
    throw new HttpsError("permission-denied", "not-admin");
  }
  const callerDocId = data.docId || "";
  // An empty callerDocId must never match an empty target.
  const isSelf = callerDocId !== "" && callerDocId === docId;
  if (data.role === "admin") return {isSelf, callerDocId};
  if (data.role === "employee" && isSelf) return {isSelf: true, callerDocId};
  throw new HttpsError("permission-denied", "not-admin");
}

/**
 * Moves an employee's sign-in email in Firebase Auth AND on their users doc.
 *
 * This exists because nothing else joins those two stores: `updateEmployee`
 * writes only Firestore, so an admin edit left the person signing in with the
 * old address while every admin surface showed the new one — and it desynced
 * the two stores that createEmployeeAccount joins on.
 *
 * Only for a doc that already carries a `uid`. A pending doc with no Auth
 * account behind it has nothing to join, and the client writes its email
 * directly under the rules.
 */
const changeEmployeeEmail = onCall(APP_CHECK, async (req) => {
  if (!req.auth || !req.auth.uid) {
    throw new HttpsError("unauthenticated", "auth-required");
  }
  const db = getFirestore();
  assertPayloadShape(req.data, new Set(["docId", "email"]));
  const docId = requireString(req.data, "docId", 128);
  // `.doc()` throws synchronously on an id containing a slash, which would
  // surface as an opaque `internal` instead of a shaped rejection.
  if (docId.includes("/")) {
    throw new HttpsError("invalid-argument", "invalid-docId");
  }
  const email = requireString(req.data, "email", 254).toLowerCase();
  // Guard order: auth → payload → IDENTITY → re-auth freshness → rate limit →
  // work. The payload is validated before a slot is consumed so a burst of
  // malformed submissions can't exhaust a legitimate caller's window; the
  // identity guards sit above the limiter so a non-entitled caller still can't
  // burn one.
  const bridgeSnap = await db.collection("usersByUid").doc(req.auth.uid).get();
  const {isSelf, callerDocId} = await resolveEmailChangeCaller(
      bridgeSnap.exists ? bridgeSnap.data() : null, docId);
  // A valid ID token alone must not be enough to move your OWN sign-in
  // address: SelfEmailService re-authenticates first, but that is a
  // client-side ordering, and anything reaching this callable directly
  // bypasses it. Same check deleteAccount makes, for the same reason.
  //
  // SELF ONLY, deliberately. The admin branch is reached from
  // `updateEmployee`, which has no re-auth step to satisfy this — gating it
  // here would reject every admin email edit made more than five minutes
  // after sign-in. Closing the admin half needs a re-auth prompt on that save
  // path first; until then an unattended admin session can still rewrite a
  // colleague's address, bounded only by assertAdmin and the budget below.
  if (isSelf) {
    assertFreshReauth(
        req.auth, "changeEmployeeEmail", EMAIL_CHANGE_REAUTH_MAX_AGE_SECONDS);
  }
  // Same per-caller budget either way: this rewrites a sign-in identity, so a
  // compromised session must not be able to walk the roster.
  await enforceDurableRateLimit(
      "changeEmployeeEmail", req.auth.uid, EMAIL_CHANGE_RATE_MAX,
      EMAIL_CHANGE_RATE_WINDOW_MS);

  const auth = getAuth();

  const snap = await db.collection("users").doc(docId).get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "account-not-found");
  }
  const previousEmail = snap.data().email || "";
  const uid = snap.data().uid || "";
  if (!uid) {
    throw new HttpsError("failed-precondition", "account-has-no-auth");
  }
  if (email === previousEmail) return {ok: true};

  // Cheap pre-flight so the common conflict costs no Auth write plus rollback.
  // performChangeEmail's transaction is the authoritative check.
  const claimed = await db.collection("users")
      .where("email", "==", email).limit(2).get();
  if (claimed.docs.some((d) => d.id !== docId)) {
    throw new HttpsError("already-exists", "email-exists");
  }

  // Auth FIRST, Firestore second, deliberately. The failure being fixed is a
  // doc that moved while Auth did not, so the store that owns sign-in must be
  // the one never left behind — and it is the one that can actually refuse a
  // duplicate. `emailVerified` resets because the new address is unproven.
  try {
    await auth.updateUser(uid, {email, emailVerified: false});
  } catch (e) {
    if (e && e.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "email-exists");
    }
    if (e && e.code === "auth/user-not-found") {
      throw new HttpsError("not-found", "account-not-found");
    }
    throw e;
  }

  try {
    await performChangeEmail(db, docId, email, previousEmail, {
      serverTimestamp: () => FieldValue.serverTimestamp(),
    });
  } catch (e) {
    // Put Auth back where the doc still says it is. A failed revert leaves the
    // person signing in with an address no admin surface shows — the exact
    // desync this callable exists to prevent — and nothing in-app can find it,
    // so it MUST be loud. Emails are PII: the uid pair is what makes it
    // findable in the console.
    await auth.updateUser(uid, {email: previousEmail}).catch((revertError) => {
      logger.error(
          "changeEmployeeEmail: auth/users email desync; fix it by hand",
          {uid, docId, err: String(revertError)},
      );
    });
    throw e;
  }

  // Who needs telling depends on who did it. An ADMIN edit surprises the
  // employee, so the employee is told. A SELF edit surprises nobody who made
  // it — the admins are the ones who need to know a sign-in identity moved.
  const deps = {db, messaging: getMessaging(), logger};
  if (isSelf) {
    await notifyAdminsOfSelfEmailChange(deps, callerDocId, docId);
  } else {
    await notifyEmailChanged(deps, docId, email);
  }
  return {ok: true};
});

/**
 * Tells the employee their sign-in address moved.
 *
 * **Best-effort, and deliberately AFTER the commit**: the change is already
 * durable in both stores, so a push failure must not fail the callable and
 * hand the admin an error for something that worked. It is a courtesy, not a
 * guarantee — an employee with no live FCM token (app never installed, signed
 * out, notifications denied) still learns the hard way, which is why the admin
 * should tell them directly too.
 *
 * Roles are the TIMED set, not the change set: the change set is
 * employees-only because an admin normally makes those edits themselves, and
 * here the admin editing the row is a DIFFERENT person from the one whose
 * sign-in is moving.
 *
 * @param {!Object} deps `{db, messaging, logger}`.
 * @param {string} docId users doc id of the employee.
 * @param {string} email The new sign-in email.
 * @return {!Promise<void>}
 */
async function notifyEmailChanged(deps, docId, email) {
  try {
    await sendToEmployee(
        deps,
        docId,
        {kind: "emailChanged"},
        (locale) => buildEmailChangedMessage(email, locale),
        TIMED_RECIPIENT_ROLES,
    );
  } catch (e) {
    // Never the address itself — emails are PII and this is a log line.
    logger.warn("changeEmployeeEmail: notify failed", {docId, err: String(e)});
  }
}

/**
 * Tells the active admins that someone changed their OWN sign-in address.
 *
 * `notifyEmailChanged` pushes the person whose address moved, which is right
 * when an admin made the change and pointless when they made it themselves —
 * so a self change notifies the managers instead, through the shared
 * `sendToActiveAdmins` fan-out.
 *
 * Deliberately does NOT name the new address: this reaches every admin's Lock
 * Screen, and an email is PII. Best-effort and after the commit, exactly like
 * its sibling — the change is already durable in both stores, so a push
 * failure must not hand the caller an error for something that worked.
 *
 * @param {!Object} deps `{db, messaging, logger}`.
 * @param {string} callerDocId The person who made the change (excluded).
 * @param {string} docId users doc id whose email moved.
 * @return {!Promise<void>}
 */
async function notifyAdminsOfSelfEmailChange(deps, callerDocId, docId) {
  try {
    const snap = await deps.db.collection("users").doc(docId).get();
    const name = (snap.exists && (snap.data() || {}).name) || "";
    await sendToActiveAdmins(
        deps,
        {kind: "selfEmailChanged", docId},
        (locale) => buildSelfEmailChangedMessage(name, locale),
        {excludeDocId: callerDocId},
    );
  } catch (e) {
    // Never the address itself — emails are PII and this is a log line.
    logger.warn("changeEmployeeEmail: admin notify failed",
        {docId, err: String(e)});
  }
}

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
  // The account is created on a SHARED starting password, so signing in proves
  // nothing about who you are. This is the guard that makes the invite window
  // survivable: activation requires control of the mailbox, so a stranger who
  // knows the address can reach the setup screen but cannot leave the `invited`
  // state — where the rules grant nothing. An identity guard, so it sits above
  // the rate limiter (a caller who can't pass it must not burn slots).
  //
  // Fails CLOSED on a missing token: `req.auth.token && ...` would have let a
  // caller through by NOT presenting one, which is the wrong direction for the
  // guard the paragraph above describes. v2 always populates it for an
  // authenticated call, so this is posture, not a live hole.
  if (!req.auth.token || req.auth.token.email_verified !== true) {
    throw new HttpsError("failed-precondition", "email-not-verified");
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
      if (!e || e.code !== "auth/user-not-found") {
        // The doc is already gone, so this leaves an Auth account no admin
        // surface can see and whose email createEmployeeAccount will then
        // refuse. The throw tells the admin it failed; the log is what makes
        // the leftover findable.
        logger.error(
            "deleteEmployeeAccount: orphaned auth account; delete it by hand",
            {uid: outcome.uid, err: String(e)},
        );
        throw e;
      }
    });
  }
  return {ok: true};
});

module.exports = {
  DEFAULT_PASSWORD,
  createEmployeeAccount,
  completeEmployeeSetup,
  deleteEmployeeAccount,
  changeEmployeeEmail,
  // Exported for unit tests of the transactional flows and the pure patch.
  provisionAuthAccount,
  resetProvisionedPassword,
  performCreateAccount,
  performDeleteAccount,
  performChangeEmail,
  resolveEmailChangeCaller,
  notifyEmailChanged,
  buildActivationPatch,
};
