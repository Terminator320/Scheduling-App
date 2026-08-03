"use strict";

/**
 * Tests the race-sensitive transaction cores of the employee-account
 * lifecycle (createEmployeeAccount / completeEmployeeSetup /
 * deleteEmployeeAccount) plus the pure activation patch. The onCall wrappers'
 * guards live elsewhere and aren't covered here.
 */

const {
  provisionAuthAccount,
  resetProvisionedPassword,
  performCreateAccount,
  performDeleteAccount,
  buildActivationPatch,
  DEFAULT_PASSWORD,
} = require("../employee_accounts");

const TS = {__serverTimestamp: true};
const serverTimestamp = () => TS;

const FIELDS = {
  name: "New Employee",
  firstName: "New",
  lastName: "Employee",
  email: "new@company.test",
  phone: "(514) 555-0100",
  colorValue: "4280391411",
  jobTitle: "technician",
  isAdmin: false,
};

/**
 * Fake Firestore exposing exactly the surface these cores use: a
 * collection().where().limit() query read via tx.get, doc refs, and a
 * transaction recording every op in sequence.
 * @param {Object=} opts `existingUser` (fake users query doc) and `doc` (fake
 *   snapshot returned for a direct users doc get).
 * @return {{db: !Object, ops: !Array, newRefs: !Array}}
 */
function fakeDb(opts = {}) {
  const existingUser = opts.existingUser || null;
  const docSnap = opts.doc || null;
  const ops = [];
  const newRefs = [];
  let autoId = 0;

  // Keyed by the queried field: performCreateAccount runs an email lookup AND
  // a uid-uniqueness lookup, and they must be answerable separately.
  const emailQuery = {_kind: "usersQuery", field: "email"};
  const uidQuery = {_kind: "usersQuery", field: "uid"};
  // Docs already carrying the uid under test (other than `existingUser`).
  const uidHolders = opts.uidHolders || [];

  const db = {
    collection: (name) => {
      if (name !== "users") throw new Error(`unexpected collection ${name}`);
      return {
        where: jest.fn((field) => ({
          limit: jest.fn(() => (field === "uid" ? uidQuery : emailQuery)),
        })),
        doc: jest.fn((id) => {
          const ref = {id: id || `new-user-${autoId++}`, _kind: "userRef"};
          newRefs.push(ref);
          return ref;
        }),
      };
    },
    runTransaction: async (fn) => {
      const tx = {
        get: jest.fn((target) => {
          if (target === emailQuery) {
            ops.push({op: "get", target: "usersQuery"});
            return Promise.resolve({
              empty: existingUser === null,
              docs: existingUser ? [existingUser] : [],
            });
          }
          if (target === uidQuery) {
            ops.push({op: "get", target: "uidQuery"});
            return Promise.resolve({
              empty: uidHolders.length === 0,
              docs: uidHolders,
            });
          }
          ops.push({op: "get", target: "userRef"});
          return Promise.resolve(
              docSnap || {exists: false, data: () => null},
          );
        }),
        set: jest.fn((ref, data) => ops.push({op: "set", ref, data})),
        update: jest.fn((ref, data) => ops.push({op: "update", ref, data})),
        delete: jest.fn((ref) => ops.push({op: "delete", ref})),
      };
      return fn(tx);
    },
  };
  return {db, ops, newRefs};
}

/**
 * @param {!Object} data stored users-doc data.
 * @param {string=} id doc id.
 * @return {!Object} a fake query doc.
 */
function userDoc(data, id = "existing-doc") {
  return {id, ref: {id, _kind: "existingRef"}, data: () => data};
}

describe("provisionAuthAccount", () => {
  test("the shared starting password is the exact mirrored literal", () => {
    // Pins the Dart-side mirror kDefaultStartingPassword
    // (lib/features/employees/domain/policies/starting_password_policy.dart),
    // which the roster row shows as its fallback. Every other assertion here
    // uses the imported symbol, so without this one the constant could be
    // rotated on this side alone and the suite would still pass green.
    expect(DEFAULT_PASSWORD).toBe("Welcome123!");
  });

  test("mints a new account with the shared starting password", async () => {
    const auth = {
      createUser: jest.fn(async () => ({uid: "uid-1"})),
      getUserByEmail: jest.fn(),
      updateUser: jest.fn(),
    };

    const out = await provisionAuthAccount(
        auth, "new@company.test", "New Employee", DEFAULT_PASSWORD);

    expect(out).toEqual({uid: "uid-1", reused: false});
    expect(auth.createUser).toHaveBeenCalledWith({
      email: "new@company.test",
      password: DEFAULT_PASSWORD,
      displayName: "New Employee",
      emailVerified: false,
    });
    expect(auth.updateUser).not.toHaveBeenCalled();
  });

  test("resolves an existing account's uid WITHOUT touching its password",
      async () => {
        // The reset is deferred to resetProvisionedPassword, which the caller
        // runs only after the transaction confirms the person is still
        // `invited`. Resetting here reset first and asked questions second: a
        // setup committing in that window left the employee active on a
        // password nobody told them had been reverted.
        const err = new Error("exists");
        err.code = "auth/email-already-exists";
        const auth = {
          createUser: jest.fn(async () => {
            throw err;
          }),
          getUserByEmail: jest.fn(async () => ({uid: "uid-existing"})),
          updateUser: jest.fn(async () => ({})),
        };

        const out = await provisionAuthAccount(
            auth, "new@company.test", "New Employee", DEFAULT_PASSWORD);

        expect(out).toEqual({uid: "uid-existing", reused: true});
        expect(auth.updateUser).not.toHaveBeenCalled();
      });

  test("resetProvisionedPassword is what hands back a working password",
      async () => {
        // This IS the "they never signed in / they lost it" path — re-running
        // create for a still-invited person has to give them a usable password.
        const auth = {updateUser: jest.fn(async () => ({}))};

        await resetProvisionedPassword(
            auth, "uid-existing", "New Employee", DEFAULT_PASSWORD);

        expect(auth.updateUser).toHaveBeenCalledWith("uid-existing", {
          password: DEFAULT_PASSWORD,
          displayName: "New Employee",
        });
      });

  test("rethrows any error that is not email-already-exists", async () => {
    const err = new Error("boom");
    err.code = "auth/internal-error";
    const auth = {
      createUser: jest.fn(async () => {
        throw err;
      }),
      getUserByEmail: jest.fn(),
      updateUser: jest.fn(),
    };

    await expect(provisionAuthAccount(
        auth, "e@t.test", "N", DEFAULT_PASSWORD)).rejects.toThrow("boom");
    expect(auth.getUserByEmail).not.toHaveBeenCalled();
  });
});

describe("performCreateAccount", () => {
  test("writes an invited doc carrying the Auth uid", async () => {
    const {db, ops, newRefs} = fakeDb();

    const out = await performCreateAccount(
        db, FIELDS, {uid: "uid-1", serverTimestamp});

    expect(out.ok).toBe(true);
    const set = ops.find((o) => o.op === "set");
    expect(set.ref).toBe(newRefs[0]);
    expect(set.data).toMatchObject({
      email: "new@company.test",
      status: "invited",
      // The uid lands immediately — unlike the retired code flow, where it
      // stayed "" until redemption. `invited` is what withholds the grants.
      uid: "uid-1",
      role: "employee",
      createdAt: TS,
      updatedAt: TS,
    });
  });

  test("refuses an email that belongs to a set-up account", async () => {
    // Re-creating them would reset a password they chose.
    const {db, ops} = fakeDb({
      existingUser: userDoc({status: "active", email: FIELDS.email}),
    });

    const out = await performCreateAccount(
        db, FIELDS, {uid: "uid-1", serverTimestamp});

    expect(out.ok).toBe(false);
    expect(ops.some((o) => o.op === "set" || o.op === "update")).toBe(false);
  });

  test("refuses when the uid already belongs to another doc", async () => {
    // `users.email` is admin-editable and never synced to Auth, so the email
    // check can clear a doc that is NOT the account this uid came from. A
    // second doc carrying a live employee's uid repoints the usersByUid bridge
    // every rules gate resolves through, locking that employee out entirely.
    const {db, ops} = fakeDb({
      uidHolders: [userDoc({status: "active", uid: "uid-1"}, "someone-else")],
    });

    const out = await performCreateAccount(
        db, FIELDS, {uid: "uid-1", serverTimestamp});

    expect(out.ok).toBe(false);
    expect(ops.some((o) => o.op === "set" || o.op === "update")).toBe(false);
  });

  test("the person's OWN doc does not count as a uid collision", async () => {
    // Re-provisioning an invited person re-reads the doc that already carries
    // their uid — that must not be mistaken for somebody else claiming it.
    const own = userDoc({status: "invited", email: FIELDS.email, uid: "uid-2"});
    const {db, ops} = fakeDb({existingUser: own, uidHolders: [own]});

    const out = await performCreateAccount(
        db, FIELDS, {uid: "uid-2", serverTimestamp});

    expect(out).toEqual({ok: true, docId: "existing-doc"});
    expect(ops.some((o) => o.op === "update")).toBe(true);
  });

  test("re-provisions a still-invited person in place", async () => {
    const {db, ops} = fakeDb({
      existingUser: userDoc({status: "invited", email: FIELDS.email}),
    });

    const out = await performCreateAccount(
        db, FIELDS, {uid: "uid-2", serverTimestamp});

    expect(out).toEqual({ok: true, docId: "existing-doc"});
    const update = ops.find((o) => o.op === "update");
    // Every editable field is refreshed, so a call site passing blanks would
    // wipe them — the client must send the whole stored record.
    expect(update.data).toMatchObject({
      name: FIELDS.name,
      firstName: FIELDS.firstName,
      lastName: FIELDS.lastName,
      phone: FIELDS.phone,
      colorValue: FIELDS.colorValue,
      jobTitle: FIELDS.jobTitle,
      role: "employee",
      uid: "uid-2",
    });
    expect(ops.some((o) => o.op === "set")).toBe(false);
  });

  test("maps isAdmin onto the role field", async () => {
    const {db, ops} = fakeDb();

    await performCreateAccount(
        db, {...FIELDS, isAdmin: true}, {uid: "u", serverTimestamp});

    expect(ops.find((o) => o.op === "set").data.role).toBe("admin");
  });

  test("reads before it writes", async () => {
    // Firestore transactions forbid a read after a write.
    const {db, ops} = fakeDb();

    await performCreateAccount(db, FIELDS, {uid: "u", serverTimestamp});

    const firstWrite = ops.findIndex((o) => o.op !== "get");
    const lastRead = ops.map((o) => o.op).lastIndexOf("get");
    expect(lastRead).toBeLessThan(firstWrite);
  });
});

describe("buildActivationPatch", () => {
  const base = {
    firstName: "Zoé",
    lastName: "Roy",
    phone: "(514) 555-1234",
    termsAccepted: true,
    locationConsent: true,
  };

  test("activates and composes the name from the submitted halves", () => {
    const patch = buildActivationPatch(
        base, {userData: {}, serverTimestamp});

    expect(patch.status).toBe("active");
    expect(patch.name).toBe("Zoé Roy");
    expect(patch.firstName).toBe("Zoé");
    expect(patch.lastName).toBe("Roy");
    expect(patch.phone).toBe("(514) 555-1234");
    expect(patch.updatedAt).toBe(TS);
  });

  test("falls back per half to what the admin already stored", () => {
    const patch = buildActivationPatch(
        {...base, lastName: ""},
        {userData: {firstName: "Stored", lastName: "Lavoie"}, serverTimestamp},
    );

    expect(patch.name).toBe("Zoé Lavoie");
    expect(patch.lastName).toBeUndefined();
  });

  test("omits name entirely when every half is blank", () => {
    // An empty `name` drops the person out of watchAllUsers' orderBy('name')
    // and therefore out of the admin roster — never write one.
    const patch = buildActivationPatch(
        {...base, firstName: "", lastName: ""},
        {userData: {}, serverTimestamp},
    );

    expect(patch.name).toBeUndefined();
    expect("name" in patch).toBe(false);
  });

  test("stamps consent only when the flags are actually true", () => {
    const patch = buildActivationPatch(
        {...base, termsAccepted: false, locationConsent: false},
        {userData: {}, serverTimestamp},
    );

    expect(patch.termsAcceptedAt).toBeUndefined();
    expect(patch.locationConsentAt).toBeUndefined();
  });

  test("stamps each consent independently", () => {
    const patch = buildActivationPatch(
        {...base, locationConsent: false},
        {userData: {}, serverTimestamp},
    );

    expect(patch.termsAcceptedAt).toBe(TS);
    expect(patch.locationConsentAt).toBeUndefined();
  });

  test("never rewrites uid — the doc has carried it since creation", () => {
    const patch = buildActivationPatch(base, {userData: {}, serverTimestamp});

    expect("uid" in patch).toBe(false);
  });
});

describe("performDeleteAccount", () => {
  test("deletes a still-pending account and reports its uid", async () => {
    const {db, ops} = fakeDb({
      doc: {exists: true, data: () => ({status: "invited", uid: "uid-9"})},
    });

    const out = await performDeleteAccount(db, "doc-1");

    expect(out).toEqual({ok: true, uid: "uid-9"});
    expect(ops.some((o) => o.op === "delete")).toBe(true);
  });

  test("refuses once the person has finished setup", async () => {
    // From that point the account is theirs and the no-delete invariant
    // applies — disable is the only removal.
    const {db, ops} = fakeDb({
      doc: {exists: true, data: () => ({status: "active", uid: "uid-9"})},
    });

    const out = await performDeleteAccount(db, "doc-1");

    expect(out).toEqual({ok: false, reason: "not-pending"});
    expect(ops.some((o) => o.op === "delete")).toBe(false);
  });

  test("reports not-found for a missing doc", async () => {
    const {db} = fakeDb({doc: {exists: false, data: () => null}});

    expect(await performDeleteAccount(db, "nope"))
        .toEqual({ok: false, reason: "not-found"});
  });
});
