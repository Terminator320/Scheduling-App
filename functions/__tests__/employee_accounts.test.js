"use strict";

/**
 * Tests the race-sensitive transaction cores of the employee-account
 * lifecycle (createEmployeeAccount / completeEmployeeSetup /
 * deleteEmployeeAccount) plus the pure activation patch. The onCall wrappers'
 * guards live elsewhere and aren't covered here.
 */

const {
  provisionAuthAccount,
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

  const usersQuery = {_kind: "usersQuery"};

  const db = {
    collection: (name) => {
      if (name !== "users") throw new Error(`unexpected collection ${name}`);
      return {
        where: jest.fn(() => ({
          limit: jest.fn(() => usersQuery),
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
          if (target === usersQuery) {
            ops.push({op: "get", target: "usersQuery"});
            return Promise.resolve({
              empty: existingUser === null,
              docs: existingUser ? [existingUser] : [],
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

  test("resets an existing account back to the default password", async () => {
    // This IS the "they never signed in / they lost it" path — re-running the
    // create for a still-invited person has to hand them a working password.
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
