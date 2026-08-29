"use strict";

/**
 * Ordering tests for the two employee-account callables.
 *
 * Every PURE piece here already has a suite (`performCreateAccount`,
 * `provisionAuthAccount`, `performChangeEmail`, `buildActivationPatch`). What
 * had none was the sequencing BETWEEN them — which is the entire security
 * story, and where both known bugs lived:
 *
 *   - the password reset must run only AFTER the doc transaction has claimed
 *     the person as still-`invited`;
 *   - the create rollback must delete the Auth account only when WE minted it;
 *   - the email change must write Auth FIRST and revert it if the doc fails,
 *     logging uid+docId and never the addresses (PII).
 *
 * A refactor that drops any of those passes the rest of the suite.
 */

jest.mock("firebase-admin/firestore");
jest.mock("firebase-admin/auth");
jest.mock("firebase-admin/messaging");
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  debug: jest.fn(),
  error: jest.fn(),
}));
jest.mock("../security", () => {
  const actual = jest.requireActual("../security");
  return {
    ...actual,
    assertAdmin: jest.fn().mockResolvedValue(undefined),
    enforceDurableRateLimit: jest.fn().mockResolvedValue({
      refund: jest.fn().mockResolvedValue(undefined),
    }),
  };
});
jest.mock("../notification_utils", () => ({
  sendToEmployee: jest.fn().mockResolvedValue(0),
  sendToActiveAdmins: jest.fn().mockResolvedValue(undefined),
  TIMED_RECIPIENT_ROLES: ["employee", "admin"],
}));

const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {getMessaging} = require("firebase-admin/messaging");
const logger = require("firebase-functions/logger");
const {
  sendToEmployee,
  sendToActiveAdmins,
} = require("../notification_utils");
const {
  createEmployeeAccount,
  completeEmployeeSetup,
  changeEmployeeEmail,
} = require("../employee_accounts");

const ADMIN = {uid: "admin-uid"};

const VALID_CREATE = {
  name: "Ada Lovelace",
  firstName: "Ada",
  lastName: "Lovelace",
  email: "Ada@Example.com",
  phone: "(514) 555-1234",
  colorValue: "4280391411",
  jobTitle: "technician",
};

/**
 * Firestore double. `docs` is the users collection keyed by doc id.
 * Records an ordered trace of the operations the callables perform.
 *
 * `usersByUid` is a SEPARATE map, because changeEmployeeEmail resolves its
 * caller through that bridge rather than through assertAdmin — it has to tell
 * an admin from the person editing their own row. It defaults to an active
 * admin so every pre-existing test keeps its old meaning.
 *
 * @param {!Object} docs Map of docId -> doc data (the `users` collection).
 * @param {!Array<string>} trace Shared ordered call log.
 * @param {!Object=} bridge Map of auth uid -> `usersByUid` doc data.
 * @return {!Object}
 */
function makeDb(docs, trace, bridge) {
  const bridgeDocs = bridge || {
    "admin-uid": {role: "admin", status: "active", docId: "admin-doc"},
  };
  const snapOf = (id) => ({
    id,
    exists: Object.prototype.hasOwnProperty.call(docs, id),
    data: () => docs[id],
    ref: {id},
  });
  const queryFor = (field, value) => {
    const matches = Object.keys(docs)
        .filter((id) => (docs[id] || {})[field] === value)
        .map(snapOf);
    return {empty: matches.length === 0, docs: matches};
  };

  const makeQuery = (field, value) => ({
    limit: () => makeQuery(field, value),
    get: async () => queryFor(field, value),
    __field: field,
    __value: value,
  });

  const bridgeSnapOf = (id) => ({
    id,
    exists: Object.prototype.hasOwnProperty.call(bridgeDocs, id),
    data: () => bridgeDocs[id],
    ref: {id},
  });

  const db = {
    collection: (name) => ({
      where: (field, _op, value) => makeQuery(field, value),
      doc: (id) => ({
        id: id || "generated-doc-id",
        get: async () => (name === "usersByUid" ?
          bridgeSnapOf(id) :
          snapOf(id)),
      }),
    }),
    runTransaction: async (fn) => {
      const tx = {
        get: async (target) => (target && target.__field ?
          queryFor(target.__field, target.__value) :
          snapOf(target.id)),
        update: (ref, patch) => {
          trace.push("db.update");
          docs[ref.id] = {...(docs[ref.id] || {}), ...patch};
        },
        set: (ref, value) => {
          trace.push("db.set");
          docs[ref.id] = value;
        },
      };
      const out = await fn(tx);
      trace.push("db.commit");
      return out;
    },
  };
  return db;
}

/**
 * Auth double recording every call into the shared trace.
 * @param {!Array<string>} trace Shared ordered call log.
 * @param {!Object} opts Behaviour overrides.
 * @return {!Object}
 */
function makeAuth(trace, opts = {}) {
  return {
    getUserByEmail: jest.fn(async (email) => {
      trace.push("auth.getUserByEmail");
      if (opts.existingUser) return opts.existingUser;
      const err = new Error("no user");
      err.code = "auth/user-not-found";
      throw err;
    }),
    createUser: jest.fn(async () => {
      trace.push("auth.createUser");
      if (opts.createUserError) throw opts.createUserError;
      return {uid: "new-uid"};
    }),
    updateUser: jest.fn(async () => {
      trace.push("auth.updateUser");
      if (opts.updateUserError) throw opts.updateUserError;
      return {};
    }),
    deleteUser: jest.fn(async () => {
      trace.push("auth.deleteUser");
      if (opts.deleteUserError) throw opts.deleteUserError;
    }),
  };
}

beforeEach(() => {
  jest.clearAllMocks();
  FieldValue.serverTimestamp = jest.fn(() => "TS");
  getMessaging.mockReturnValue({});
});

describe("createEmployeeAccount ordering", () => {
  test("mints a brand-new account and never resets its password", async () => {
    const trace = [];
    const auth = makeAuth(trace);
    getFirestore.mockReturnValue(makeDb({}, trace));
    getAuth.mockReturnValue(auth);

    const out = await createEmployeeAccount.run({
      data: VALID_CREATE,
      auth: ADMIN,
    });

    expect(out.email).toBe("ada@example.com");
    expect(trace).toEqual([
      "auth.getUserByEmail", // pre-flight: is this email taken?
      "auth.createUser",
      "db.set",
      "db.commit",
    ]);
    // reused === false, so the reset path must not run.
    expect(auth.updateUser).not.toHaveBeenCalled();
  });

  test("rejects isAdmin now that the #compat-1.47.0 carve-out is retired",
      async () => {
        const trace = [];
        const auth = makeAuth(trace);
        const docs = {};
        getFirestore.mockReturnValue(makeDb(docs, trace));
        getAuth.mockReturnValue(auth);

        // Builds at or below 1.47.0 sent `isAdmin` unconditionally, so the
        // allowlist accepted-and-ignored it until the fleet reached 1.53
        // (retired 2026-08-29). No supported build sends it now, so it is an
        // unexpected field like any other. This test is the tripwire: if a
        // client is ever changed to send it again, this fails rather than the
        // create silently breaking in production.
        await expect(createEmployeeAccount.run({
          data: {...VALID_CREATE, isAdmin: true},
          auth: ADMIN,
        })).rejects.toThrow(/unexpected-field/);

        // Refused before any write — no account, no Auth user.
        expect(docs["generated-doc-id"]).toBeUndefined();
        expect(auth.createUser).not.toHaveBeenCalled();
      });

  test("resets a pending account's password only AFTER the doc transaction",
      async () => {
        const trace = [];
        const auth = makeAuth(trace, {existingUser: {uid: "existing-uid"}});
        getFirestore.mockReturnValue(makeDb({
          d1: {
            email: "ada@example.com",
            uid: "existing-uid",
            status: "invited",
          },
        }, trace));
        getAuth.mockReturnValue(auth);

        await createEmployeeAccount.run({data: VALID_CREATE, auth: ADMIN});

        // The rotation must come after "db.commit". Resetting first meant a
        // setup committing in that window left the person ACTIVE on a password
        // nobody told them had been reverted.
        expect(trace.indexOf("auth.updateUser"))
            .toBeGreaterThan(trace.indexOf("db.commit"));
      });

  test("never deletes the Auth account of a REUSED (existing) user",
      async () => {
        const trace = [];
        const auth = makeAuth(trace, {existingUser: {uid: "existing-uid"}});
        // Status is no longer `invited`, so performCreateAccount returns
        // ok:false and the callable throws.
        getFirestore.mockReturnValue(makeDb({
          d1: {
            email: "ada@example.com",
            uid: "existing-uid",
            status: "invited",
          },
          d2: {email: "other@example.com", uid: "existing-uid"},
        }, trace));
        getAuth.mockReturnValue(auth);

        await expect(
            createEmployeeAccount.run({data: VALID_CREATE, auth: ADMIN}),
        ).rejects.toThrow(/email-exists/);

        // Rolling back a reused account would delete a real employee's Auth
        // record — the account was theirs before this call started.
        expect(auth.deleteUser).not.toHaveBeenCalled();
      });

  test("rolls back an account it just minted when the doc write fails",
      async () => {
        const trace = [];
        const auth = makeAuth(trace);
        const db = makeDb({}, trace);
        db.runTransaction = async () => {
          throw new Error("firestore unavailable");
        };
        getFirestore.mockReturnValue(db);
        getAuth.mockReturnValue(auth);

        await expect(
            createEmployeeAccount.run({data: VALID_CREATE, auth: ADMIN}),
        ).rejects.toThrow(/unavailable/);

        // An Auth account with no users doc is a sign-in SplashScreen cannot
        // resolve and no admin surface can see.
        expect(auth.deleteUser).toHaveBeenCalledWith("new-uid");
      });

  test("a failed rollback is logged loudly with the orphaned uid", async () => {
    const trace = [];
    const auth = makeAuth(trace, {
      deleteUserError: new Error("auth down"),
    });
    const db = makeDb({}, trace);
    db.runTransaction = async () => {
      throw new Error("firestore unavailable");
    };
    getFirestore.mockReturnValue(db);
    getAuth.mockReturnValue(auth);

    await expect(
        createEmployeeAccount.run({data: VALID_CREATE, auth: ADMIN}),
    ).rejects.toThrow();

    // Unrecoverable in-app and it bricks that email, so silence is the one
    // unacceptable outcome.
    expect(logger.error).toHaveBeenCalledWith(
        expect.stringContaining("orphaned auth account"),
        expect.objectContaining({uid: "new-uid"}),
    );
  });
});

describe("completeEmployeeSetup activation", () => {
  const SETUP = {
    firstName: "Ada",
    lastName: "Lovelace",
    phone: "(514) 555-1234",
    termsAccepted: true,
    locationConsent: true,
  };
  const invitedDocs = () => ({
    d1: {email: "ada@example.com", uid: "emp-uid", status: "invited"},
  });

  test("activates a caller presenting no email claim at all", async () => {
    const trace = [];
    const docs = invitedDocs();
    getFirestore.mockReturnValue(makeDb(docs, trace));

    // The mailbox check went with the shared starting password (2026-08-21):
    // the password is now a random per-account secret, so signing in is itself
    // the proof that guard used to provide.
    //
    // ONE anchor, and deliberately the empty token rather than
    // `email_verified: false`: the callable can no longer distinguish true,
    // false and absent, so three tests could not fail independently. The
    // empty token is the strictest of the three — it also pins that the
    // removal left no claim-shaped read behind.
    const out = await completeEmployeeSetup.run({
      data: SETUP,
      auth: {uid: "emp-uid", token: {}},
    });

    expect(out).toEqual({ok: true});
    expect(docs.d1.status).toBe("active");
  });

  test("refuses an unauthenticated caller before the rate limiter",
      async () => {
        const {enforceDurableRateLimit} = require("../security");
        getFirestore.mockReturnValue(makeDb(invitedDocs(), []));

        await expect(completeEmployeeSetup.run({
          data: SETUP,
          auth: null,
        })).rejects.toThrow(/auth-required/);

        // The guard-order rule outlives the email_verified check that used to
        // demonstrate it: identity is settled before a caller can burn any of
        // the real employee's five attempts.
        expect(enforceDurableRateLimit).not.toHaveBeenCalled();
      });

  test("still refuses an account that is no longer invited", async () => {
    const docs = {
      d1: {email: "ada@example.com", uid: "emp-uid", status: "active"},
    };
    getFirestore.mockReturnValue(makeDb(docs, []));

    await expect(completeEmployeeSetup.run({
      data: SETUP,
      auth: {uid: "emp-uid", token: {}},
    })).rejects.toThrow(/setup-not-pending/);
  });
});

describe("changeEmployeeEmail ordering", () => {
  const PAYLOAD = {docId: "d1", email: "New@Example.com"};
  const seedDocs = () => ({
    d1: {email: "old@example.com", uid: "u1", status: "active"},
  });

  test("updates Auth BEFORE Firestore", async () => {
    const trace = [];
    const auth = makeAuth(trace);
    getFirestore.mockReturnValue(makeDb(seedDocs(), trace));
    getAuth.mockReturnValue(auth);

    await changeEmployeeEmail.run({data: PAYLOAD, auth: ADMIN});

    // Auth owns sign-in and is the only store that can truly refuse a
    // duplicate, so it must never be the one left behind.
    expect(trace.indexOf("auth.updateUser"))
        .toBeLessThan(trace.indexOf("db.update"));
    expect(auth.updateUser).toHaveBeenCalledWith("u1", {
      email: "new@example.com",
      emailVerified: false,
    });
  });

  test("reverts the Auth email when the doc write fails", async () => {
    const trace = [];
    const auth = makeAuth(trace);
    const db = makeDb(seedDocs(), trace);
    const realTx = db.runTransaction;
    let calls = 0;
    db.runTransaction = async (fn) => {
      calls += 1;
      if (calls === 1) throw new Error("firestore unavailable");
      return realTx(fn);
    };
    getFirestore.mockReturnValue(db);
    getAuth.mockReturnValue(auth);

    await expect(
        changeEmployeeEmail.run({data: PAYLOAD, auth: ADMIN}),
    ).rejects.toThrow(/unavailable/);

    expect(auth.updateUser).toHaveBeenLastCalledWith("u1", {
      email: "old@example.com",
    });
  });

  test("a failed revert logs uid + docId and never an email address",
      async () => {
        const trace = [];
        const auth = makeAuth(trace);
        // First call (the real change) succeeds, the revert then fails.
        auth.updateUser
            .mockImplementationOnce(async () => {
              trace.push("auth.updateUser");
              return {};
            })
            .mockImplementationOnce(async () => {
              throw new Error("auth down");
            });
        const db = makeDb(seedDocs(), trace);
        db.runTransaction = async () => {
          throw new Error("firestore unavailable");
        };
        getFirestore.mockReturnValue(db);
        getAuth.mockReturnValue(auth);

        await expect(
            changeEmployeeEmail.run({data: PAYLOAD, auth: ADMIN}),
        ).rejects.toThrow();

        expect(logger.error).toHaveBeenCalledWith(
            expect.stringContaining("desync"),
            expect.objectContaining({uid: "u1", docId: "d1"}),
        );
        // Emails are PII — the uid pair is what makes it findable instead.
        const [, payload] = logger.error.mock.calls[0];
        expect(JSON.stringify(payload)).not.toContain("@example.com");
      });

  test("refuses a doc with no Auth account rather than writing one store",
      async () => {
        const trace = [];
        const auth = makeAuth(trace);
        getFirestore.mockReturnValue(makeDb({
          d1: {email: "old@example.com", status: "invited"},
        }, trace));
        getAuth.mockReturnValue(auth);

        await expect(
            changeEmployeeEmail.run({data: PAYLOAD, auth: ADMIN}),
        ).rejects.toThrow(/account-has-no-auth/);

        expect(auth.updateUser).not.toHaveBeenCalled();
      });
});

describe("changeEmployeeEmail caller branches", () => {
  const PAYLOAD = {docId: "d1", email: "New@Example.com"};
  const seedDocs = () => ({
    d1: {
      email: "old@example.com", uid: "u1", status: "active", name: "Theo Roy",
    },
  });
  // The self branch demands a fresh re-auth, so every self caller carries a
  // current `auth_time` the way a real re-authenticated client does.
  const freshAuthTime = () => Math.floor(Date.now() / 1000);
  const SELF = {uid: "self-uid", token: {auth_time: freshAuthTime()}};
  const selfBridge = {
    "self-uid": {role: "employee", status: "active", docId: "d1"},
  };

  test("an employee may move their OWN email", async () => {
    const trace = [];
    const auth = makeAuth(trace);
    getFirestore.mockReturnValue(makeDb(seedDocs(), trace, selfBridge));
    getAuth.mockReturnValue(auth);

    await changeEmployeeEmail.run({data: PAYLOAD, auth: SELF});

    expect(auth.updateUser).toHaveBeenCalledWith("u1", {
      email: "new@example.com",
      emailVerified: false,
    });
  });

  test("an employee may NOT move someone else's email", async () => {
    // Widening past admins must not widen WHICH doc a caller can reach.
    const trace = [];
    const auth = makeAuth(trace);
    getFirestore.mockReturnValue(makeDb(seedDocs(), trace, {
      "self-uid": {role: "employee", status: "active", docId: "other"},
    }));
    getAuth.mockReturnValue(auth);

    await expect(
        changeEmployeeEmail.run({data: PAYLOAD, auth: SELF}),
    ).rejects.toThrow(/not-admin/);
    expect(auth.updateUser).not.toHaveBeenCalled();
  });

  test("a disabled employee may not move their own email", async () => {
    const trace = [];
    const auth = makeAuth(trace);
    getFirestore.mockReturnValue(makeDb(seedDocs(), trace, {
      "self-uid": {role: "employee", status: "disabled", docId: "d1"},
    }));
    getAuth.mockReturnValue(auth);

    await expect(
        changeEmployeeEmail.run({data: PAYLOAD, auth: SELF}),
    ).rejects.toThrow(/not-admin/);
    expect(auth.updateUser).not.toHaveBeenCalled();
  });

  test("a SELF change notifies the admins, not the person", async () => {
    const trace = [];
    getFirestore.mockReturnValue(makeDb(seedDocs(), trace, selfBridge));
    getAuth.mockReturnValue(makeAuth(trace));

    await changeEmployeeEmail.run({data: PAYLOAD, auth: SELF});

    expect(sendToActiveAdmins).toHaveBeenCalled();
    expect(sendToEmployee).not.toHaveBeenCalled();
  });

  test("an ADMIN change notifies the person, not the admins", async () => {
    const trace = [];
    getFirestore.mockReturnValue(makeDb(seedDocs(), trace));
    getAuth.mockReturnValue(makeAuth(trace));

    await changeEmployeeEmail.run({data: PAYLOAD, auth: ADMIN});

    expect(sendToEmployee).toHaveBeenCalled();
    expect(sendToActiveAdmins).not.toHaveBeenCalled();
  });

  test("the admin notice never carries the address", async () => {
    // It lands on every admin's Lock Screen, and an email is PII.
    const trace = [];
    getFirestore.mockReturnValue(makeDb(seedDocs(), trace, selfBridge));
    getAuth.mockReturnValue(makeAuth(trace));

    await changeEmployeeEmail.run({data: PAYLOAD, auth: SELF});

    const [, data, buildMsg] = sendToActiveAdmins.mock.calls[0];
    expect(JSON.stringify(data)).not.toContain("@example.com");
    expect(JSON.stringify(buildMsg("en"))).not.toContain("@example.com");
    expect(buildMsg("en").body).toContain("Theo Roy");
  });

  test("a signed-out caller is refused before anything else", async () => {
    const trace = [];
    const auth = makeAuth(trace);
    getFirestore.mockReturnValue(makeDb(seedDocs(), trace));
    getAuth.mockReturnValue(auth);

    await expect(
        changeEmployeeEmail.run({data: PAYLOAD, auth: null}),
    ).rejects.toThrow(/auth-required/);
    expect(auth.updateUser).not.toHaveBeenCalled();
  });

  test("a SELF change with a stale re-auth is refused", async () => {
    // A still-valid ID token alone must not move a sign-in address — that is
    // the unattended-unlocked-phone primitive SelfEmailService guards against
    // client-side, restated here so a direct call can't skip it.
    const trace = [];
    const auth = makeAuth(trace);
    getFirestore.mockReturnValue(makeDb(seedDocs(), trace, selfBridge));
    getAuth.mockReturnValue(auth);

    await expect(changeEmployeeEmail.run({
      data: PAYLOAD,
      auth: {uid: "self-uid", token: {auth_time: freshAuthTime() - 600}},
    })).rejects.toThrow(/stale-auth/);
    expect(auth.updateUser).not.toHaveBeenCalled();
  });

  test("a SELF change presenting no token at all is refused", async () => {
    // Fails closed: a missing auth_time must not read as "recently
    // re-authenticated".
    const trace = [];
    const auth = makeAuth(trace);
    getFirestore.mockReturnValue(makeDb(seedDocs(), trace, selfBridge));
    getAuth.mockReturnValue(auth);

    await expect(
        changeEmployeeEmail.run({data: PAYLOAD, auth: {uid: "self-uid"}}),
    ).rejects.toThrow(/stale-auth/);
    expect(auth.updateUser).not.toHaveBeenCalled();
  });

  test("an ADMIN change is NOT gated on re-auth freshness", async () => {
    // Deliberate scope: updateEmployee has no re-auth step to satisfy, so
    // gating it would reject every admin edit made minutes after sign-in.
    const trace = [];
    const auth = makeAuth(trace);
    getFirestore.mockReturnValue(makeDb(seedDocs(), trace));
    getAuth.mockReturnValue(auth);

    await changeEmployeeEmail.run({data: PAYLOAD, auth: ADMIN});

    expect(auth.updateUser).toHaveBeenCalled();
  });
});
