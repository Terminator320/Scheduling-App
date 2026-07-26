"use strict";

/**
 * Tests the race-sensitive transaction core of createEmployeeInvite
 * (performCreateInvite) — duplicate-email lookup, prior-code sweep, and
 * writes all in one transaction — not the onCall wrapper's guards.
 */

const {performCreateInvite} = require("../invites");
const {hashSignupCode} = require("../signup_code_utils");

const TS = {__serverTimestamp: true};
const serverTimestamp = () => TS;

const CODE = "TESTCODE12345678";
const EXPIRES = new Date("2026-08-01T00:00:00Z");

const FIELDS = {
  name: "New Employee",
  email: "new@company.test",
  phone: "514-555-0100",
  colorValue: "4280391411",
};

/**
 * Fake Firestore exposing exactly the surface performCreateInvite uses:
 * collection().where().limit() queries read via tx.get(query), doc refs,
 * and a transaction that records every op in sequence.
 * @param {Object=} opts `existingUser` (a fake users query doc) and
 *   `priorCodes` (array of fake signupCodes docs for the re-issue sweep).
 * @return {{db: !Object, ops: !Array, newUserRefs: !Array}}
 */
function fakeDb(opts = {}) {
  const existingUser = opts.existingUser || null;
  const priorCodes = opts.priorCodes || [];
  const ops = [];
  const newUserRefs = [];
  let autoId = 0;

  const usersQuery = {_kind: "usersByEmail"};
  const priorQuery = {_kind: "priorCodesByInvite"};

  const db = {
    collection: (name) => {
      if (name === "users") {
        return {
          where: jest.fn(() => ({limit: jest.fn(() => usersQuery)})),
          doc: jest.fn(() => {
            const ref = {id: `new-user-${autoId++}`, _kind: "newUserRef"};
            newUserRefs.push(ref);
            return ref;
          }),
        };
      }
      if (name === "signupCodes") {
        return {
          doc: jest.fn((id) => ({id, _kind: "codeRef"})),
          where: jest.fn(() => priorQuery),
        };
      }
      throw new Error(`unexpected collection ${name}`);
    },
    runTransaction: async (fn) => {
      const tx = {
        get: jest.fn((q) => {
          ops.push({op: "get", target: q._kind});
          if (q === usersQuery) {
            return Promise.resolve({
              empty: existingUser === null,
              docs: existingUser ? [existingUser] : [],
            });
          }
          if (q === priorQuery) {
            return Promise.resolve({
              forEach: (cb) => priorCodes.forEach(cb),
            });
          }
          return Promise.reject(new Error("unexpected tx.get target"));
        }),
        set: jest.fn((ref, data) => ops.push({op: "set", ref, data})),
        update: jest.fn((ref, data) => ops.push({op: "update", ref, data})),
        delete: jest.fn((ref) => ops.push({op: "delete", ref})),
      };
      return fn(tx);
    },
  };

  return {db, ops, newUserRefs};
}

const optsBag = {code: CODE, expiresAt: EXPIRES, serverTimestamp};

describe("performCreateInvite — fresh email", () => {
  test("creates invite doc + code doc in the transaction", async () => {
    const {db, ops, newUserRefs} = fakeDb();
    const outcome = await performCreateInvite(db, FIELDS, optsBag);

    expect(outcome).toEqual({ok: true, code: CODE});
    expect(newUserRefs).toHaveLength(1);

    const sets = ops.filter((o) => o.op === "set");
    expect(sets).toHaveLength(2);

    const inviteSet = sets.find((o) => o.ref._kind === "newUserRef");
    expect(inviteSet.data).toEqual(expect.objectContaining({
      name: FIELDS.name,
      email: FIELDS.email,
      phone: FIELDS.phone,
      colorValue: FIELDS.colorValue,
      role: "employee",
      status: "invited",
      uid: "",
    }));

    const codeSet = sets.find((o) => o.ref._kind === "codeRef");
    expect(codeSet.ref.id).toBe(hashSignupCode(CODE));
    expect(codeSet.data).toEqual(expect.objectContaining({
      inviteDocId: newUserRefs[0].id,
      email: FIELDS.email,
      expiresAt: EXPIRES,
    }));
  });

  test("duplicate check runs INSIDE the transaction (via tx.get)",
      async () => {
        const {db, ops} = fakeDb();
        await performCreateInvite(db, FIELDS, optsBag);
        // The very first transactional op is the users-by-email read.
        expect(ops[0]).toEqual({op: "get", target: "usersByEmail"});
      });

  test("all reads precede all writes (Firestore txn requirement)",
      async () => {
        const existing = {
          id: "invite-1",
          ref: {id: "invite-1", _kind: "existingInviteRef"},
          data: () => ({status: "invited"}),
        };
        const priorCodes = [
          {ref: {id: "old-code-1", _kind: "oldCodeRef"}},
        ];
        const {db, ops} = fakeDb({existingUser: existing, priorCodes});
        await performCreateInvite(db, FIELDS, optsBag);

        const firstWrite = ops.findIndex((o) => o.op !== "get");
        const lastRead = ops.map((o) => o.op).lastIndexOf("get");
        expect(firstWrite).toBeGreaterThan(-1);
        expect(lastRead).toBeLessThan(firstWrite);
      });
});

describe("performCreateInvite — claimed email", () => {
  test("active account → ok:false and ZERO writes", async () => {
    const existing = {
      id: "user-1",
      ref: {id: "user-1", _kind: "existingUserRef"},
      data: () => ({status: "active"}),
    };
    const {db, ops} = fakeDb({existingUser: existing});
    const outcome = await performCreateInvite(db, FIELDS, optsBag);

    expect(outcome).toEqual({ok: false});
    expect(ops.filter((o) => o.op !== "get")).toHaveLength(0);
  });

  test("disabled account also blocks re-use", async () => {
    const existing = {
      id: "user-1",
      ref: {id: "user-1", _kind: "existingUserRef"},
      data: () => ({status: "disabled"}),
    };
    const {db} = fakeDb({existingUser: existing});
    const outcome = await performCreateInvite(db, FIELDS, optsBag);
    expect(outcome).toEqual({ok: false});
  });
});

describe("performCreateInvite — re-issue for a pending invite", () => {
  const existing = () => ({
    id: "invite-1",
    ref: {id: "invite-1", _kind: "existingInviteRef"},
    data: () => ({status: "invited"}),
  });

  test("sweeps prior codes, refreshes the invite, writes the new code — " +
    "all in one transaction", async () => {
    const priorCodes = [
      {ref: {id: "old-code-1", _kind: "oldCodeRef"}},
      {ref: {id: "old-code-2", _kind: "oldCodeRef"}},
    ];
    const {db, ops, newUserRefs} = fakeDb({
      existingUser: existing(), priorCodes,
    });
    const outcome = await performCreateInvite(db, FIELDS, optsBag);

    expect(outcome).toEqual({ok: true, code: CODE});
    // No new users doc minted.
    expect(newUserRefs).toHaveLength(0);

    // Both stale codes deleted transactionally.
    const deletes = ops.filter((o) => o.op === "delete");
    expect(deletes).toHaveLength(2);
    expect(deletes.map((o) => o.ref.id).sort())
        .toEqual(["old-code-1", "old-code-2"]);

    // The invite doc is refreshed (editable fields only — email/role/status
    // untouched by the update).
    const update = ops.find((o) => o.op === "update");
    expect(update.ref.id).toBe("invite-1");
    expect(update.data).toEqual({
      name: FIELDS.name,
      phone: FIELDS.phone,
      colorValue: FIELDS.colorValue,
      updatedAt: TS,
    });

    // The new code points at the existing invite.
    const codeSet = ops.find(
        (o) => o.op === "set" && o.ref._kind === "codeRef");
    expect(codeSet.data.inviteDocId).toBe("invite-1");
  });

  test("prior-code sweep is read via tx.get (not an out-of-txn query)",
      async () => {
        const {db, ops} = fakeDb({existingUser: existing(), priorCodes: []});
        await performCreateInvite(db, FIELDS, optsBag);
        expect(ops.filter((o) => o.op === "get").map((o) => o.target))
            .toEqual(["usersByEmail", "priorCodesByInvite"]);
      });
});
