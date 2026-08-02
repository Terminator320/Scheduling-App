"use strict";

/**
 * Covers the two P4b invite-lifecycle cores: performRevokeInvite's
 * transaction (the revoke-vs-redeem race) and buildActivationPatch (the
 * never-empty-`name` and conditional-consent contracts of the widened
 * redeemSignupCode). The onCall wrappers' guards follow the shared pattern
 * and aren't re-tested here.
 */

const {
  performRevokeInvite,
  buildActivationPatch,
} = require("../invites");

const TS = {__serverTimestamp: true};
const DELETE = {__delete: true};
const sentinels = {
  serverTimestamp: () => TS,
  deleteField: () => DELETE,
};

/**
 * Fake Firestore exposing exactly the surface performRevokeInvite uses.
 * @param {Object=} opts `userDoc` (null = missing) and `codeDocs`.
 * @return {{db: !Object, ops: !Array}}
 */
function fakeDb(opts = {}) {
  const userDoc = opts.userDoc === undefined ? {status: "invited", uid: ""} :
    opts.userDoc;
  const codeDocs = opts.codeDocs || [];
  const ops = [];
  const codesQuery = {_kind: "codesByInvite"};
  const userRef = {id: "invite-1", _kind: "userRef"};

  const db = {
    collection: (name) => {
      if (name === "users") return {doc: jest.fn(() => userRef)};
      if (name === "signupCodes") {
        return {where: jest.fn(() => codesQuery)};
      }
      throw new Error(`unexpected collection ${name}`);
    },
    runTransaction: async (fn) => fn({
      get: jest.fn((target) => {
        if (target === userRef) {
          ops.push({op: "get", target: "userRef"});
          return Promise.resolve({
            exists: userDoc !== null,
            data: () => userDoc,
          });
        }
        if (target === codesQuery) {
          ops.push({op: "get", target: "codesByInvite"});
          return Promise.resolve({forEach: (cb) => codeDocs.forEach(cb)});
        }
        return Promise.reject(new Error("unexpected tx.get target"));
      }),
      delete: jest.fn((ref) => ops.push({op: "delete", ref})),
    }),
  };
  return {db, ops};
}

describe("performRevokeInvite", () => {
  test("deletes every code doc and the invite doc", async () => {
    const codeDocs = [
      {ref: {id: "code-1", _kind: "codeRef"}},
      {ref: {id: "code-2", _kind: "codeRef"}},
    ];
    const {db, ops} = fakeDb({codeDocs});
    const outcome = await performRevokeInvite(db, "invite-1");

    expect(outcome).toEqual({ok: true});
    expect(ops.filter((o) => o.op === "delete").map((o) => o.ref.id))
        .toEqual(["code-1", "code-2", "invite-1"]);
  });

  test("all reads precede all writes (Firestore txn requirement)",
      async () => {
        const {db, ops} = fakeDb({
          codeDocs: [{ref: {id: "code-1", _kind: "codeRef"}}],
        });
        await performRevokeInvite(db, "invite-1");

        const firstWrite = ops.findIndex((o) => o.op !== "get");
        const lastRead = ops.map((o) => o.op).lastIndexOf("get");
        expect(firstWrite).toBeGreaterThan(-1);
        expect(lastRead).toBeLessThan(firstWrite);
      });

  test("not-found when the invite doc is gone", async () => {
    const {db, ops} = fakeDb({userDoc: null});
    const outcome = await performRevokeInvite(db, "invite-1");

    expect(outcome).toEqual({ok: false, reason: "not-found"});
    expect(ops.filter((o) => o.op === "delete")).toHaveLength(0);
  });

  test("not-pending once the account is active — the redeem race", async () => {
    const {db, ops} = fakeDb({userDoc: {status: "active", uid: "u1"}});
    const outcome = await performRevokeInvite(db, "invite-1");

    // Refusing is the spec'd behaviour: a redeem that committed first must
    // never have its just-activated account deleted out from under it.
    expect(outcome).toEqual({ok: false, reason: "not-pending"});
    expect(ops.filter((o) => o.op === "delete")).toHaveLength(0);
  });

  test("not-pending when a uid was claimed but the status lags", async () => {
    const {db} = fakeDb({userDoc: {status: "invited", uid: "u1"}});
    expect(await performRevokeInvite(db, "invite-1"))
        .toEqual({ok: false, reason: "not-pending"});
  });

  test("revokes an invite that has no code docs left", async () => {
    const {db, ops} = fakeDb({codeDocs: []});
    expect(await performRevokeInvite(db, "invite-1")).toEqual({ok: true});
    expect(ops.filter((o) => o.op === "delete")).toHaveLength(1);
  });
});

describe("buildActivationPatch", () => {
  const invite = {firstName: "Ada", lastName: "Byron", name: "Ada Byron"};
  const blank = {
    uid: "u1", firstName: "", lastName: "", phone: "",
    termsAccepted: false, locationConsent: false,
  };
  const build = (fields, inviteData = invite) =>
    buildActivationPatch({...blank, ...fields}, {...sentinels, inviteData});

  test("the shipped {code}-only payload still activates", () => {
    // Back-compat: the live client sends no profile fields at all.
    const patch = build({});
    expect(patch.uid).toBe("u1");
    expect(patch.status).toBe("active");
    expect(patch.updatedAt).toBe(TS);
  });

  test("always deletes codeExpiresAt — it describes a pending code", () => {
    expect(build({}).codeExpiresAt).toBe(DELETE);
  });

  test("submitted names and phone land on the doc", () => {
    const patch = build({
      firstName: "Grace", lastName: "Hopper", phone: "(514) 555-1234",
    });
    expect(patch.firstName).toBe("Grace");
    expect(patch.lastName).toBe("Hopper");
    expect(patch.phone).toBe("(514) 555-1234");
    expect(patch.name).toBe("Grace Hopper");
  });

  test("omits the fields the acceptance left blank", () => {
    const patch = build({firstName: "Grace"});
    expect(patch).not.toHaveProperty("lastName");
    expect(patch).not.toHaveProperty("phone");
  });

  test("composes name per half from the invite's stored halves", () => {
    // Only the first name was retyped — the invite's last name still counts.
    expect(build({firstName: "Grace"}).name).toBe("Grace Byron");
    expect(build({lastName: "Hopper"}).name).toBe("Ada Hopper");
  });

  test("never writes an empty name — it is omitted instead", () => {
    // watchAllUsers orders by `name` and Firestore excludes docs missing the
    // orderBy field, so a blank name would vanish the person from the roster.
    // Omitting leaves the invite's composed name in place.
    const patch = build({}, {firstName: "", lastName: "", name: "Ada Byron"});
    expect(patch).not.toHaveProperty("name");
  });

  test("a single known half still composes a non-empty name", () => {
    expect(build({}, {firstName: "", lastName: "Byron"}).name).toBe("Byron");
  });

  test("stamps consent only when the flag is true", () => {
    const patch = build({termsAccepted: true, locationConsent: true});
    expect(patch.termsAcceptedAt).toBe(TS);
    expect(patch.locationConsentAt).toBe(TS);
  });

  test("no consent record for a client that never showed the checkbox", () => {
    const patch = build({});
    expect(patch).not.toHaveProperty("termsAcceptedAt");
    expect(patch).not.toHaveProperty("locationConsentAt");
  });

  test("the two consent flags are independent", () => {
    const patch = build({termsAccepted: true});
    expect(patch.termsAcceptedAt).toBe(TS);
    expect(patch).not.toHaveProperty("locationConsentAt");
  });
});
