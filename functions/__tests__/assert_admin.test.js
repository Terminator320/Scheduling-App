"use strict";

/**
 * Tests for `assertAdmin` — the admin gate on 8 of the 14 callables
 * (`deleteClient`, `createEmployeeAccount`, `deleteEmployeeAccount`, the two
 * durably-limited Places routes and all five Wave callables).
 */

jest.mock("firebase-admin/firestore");
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  debug: jest.fn(),
  error: jest.fn(),
}));

const {getFirestore} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const {assertAdmin, assertAdminCall, shortHash} = require("../security");

/**
 * In-memory Firestore double exposing one `usersByUid` document.
 * @param {?Object} seed The stored bridge doc, or null for "does not exist".
 * @return {!Object} `{db, collections}` — `collections` records what was read.
 */
function makeDb(seed) {
  const collections = [];
  const db = {
    collection: (name) => {
      collections.push(name);
      return {
        doc: () => ({
          get: async () => ({
            exists: seed !== null,
            data: () => seed,
          }),
        }),
      };
    },
  };
  return {db, collections};
}

/**
 * Runs `assertAdmin` and returns the thrown error, or null when it resolved.
 * @param {?Object} seed The stored bridge doc.
 * @return {!Promise<?Object>}
 */
async function attempt(seed) {
  const {db} = makeDb(seed);
  getFirestore.mockReturnValue(db);
  try {
    await assertAdmin("caller-uid");
    return null;
  } catch (e) {
    return e;
  }
}

beforeEach(() => {
  jest.clearAllMocks();
});

describe("assertAdmin", () => {
  test("an active admin passes", async () => {
    expect(await attempt({role: "admin", status: "active"})).toBeNull();
  });

  test("resolves the caller through the usersByUid bridge", async () => {
    const {db, collections} = makeDb({role: "admin", status: "active"});
    getFirestore.mockReturnValue(db);
    await assertAdmin("caller-uid");
    expect(collections).toEqual(["usersByUid"]);
  });

  test("a DISABLED admin is refused", async () => {
    // The half most likely to be dropped as redundant.
    const err = await attempt({role: "admin", status: "disabled"});
    expect(err).not.toBeNull();
    expect(err.code).toBe("permission-denied");
    expect(err.message).toContain("wave/not-admin");
  });

  test("an admin whose status is empty is refused", async () => {
    // Exact-match on "active", so an unset or unknown status fails closed the
    // way `!employee.isActive` does on the client.
    expect(await attempt({role: "admin", status: ""})).not.toBeNull();
  });

  test("an active EMPLOYEE is refused", async () => {
    expect(await attempt({role: "employee", status: "active"})).not.toBeNull();
  });

  test("a missing bridge row is refused, not thrown through", async () => {
    // `snap.exists` is false, so `data` is null — the guard must read that as
    // "not an admin" rather than dereferencing it.
    const err = await attempt(null);
    expect(err).not.toBeNull();
    expect(err.code).toBe("permission-denied");
  });

  test("a bridge row with neither field is refused", async () => {
    expect(await attempt({})).not.toBeNull();
  });

  test("the refusal warns without logging PII", async () => {
    await attempt({role: "employee", status: "active"});
    expect(logger.warn).toHaveBeenCalledTimes(1);
    const [, payload] = logger.warn.mock.calls[0];
    expect(payload).toEqual({
      uidHash: shortHash("caller-uid"),
      role: "employee",
      status: "active",
    });
    // No raw uid, email, name or token material may ride along in the warn.
    expect(payload).not.toHaveProperty("uid");
    expect(JSON.stringify(payload)).not.toMatch(/caller-uid|@/);
  });

  test("a passing check logs nothing", async () => {
    await attempt({role: "admin", status: "active"});
    expect(logger.warn).not.toHaveBeenCalled();
  });
});

/**
 * `assertAdminCall` composes the three-step opening every admin-only callable
 * needs, and it is what makes a MISSING gate unrepresentable rather than merely
 * tested for.
 */
describe("assertAdminCall", () => {
  const req = (over) => ({
    auth: {uid: "caller-uid"},
    data: {clientId: "c1"},
    ...over,
  });
  const KEYS = new Set(["clientId"]);

  beforeEach(() => {
    jest.clearAllMocks();
  });

  test("an active admin with a clean payload passes, and gets their uid back",
      async () => {
        getFirestore.mockReturnValue(
            makeDb({role: "admin", status: "active"}).db);

        await expect(assertAdminCall(req(), KEYS)).resolves.toBe("caller-uid");
      });

  test("a signed-out caller is refused BEFORE the roster is read", async () => {
    const {db, collections} = makeDb({role: "admin", status: "active"});
    getFirestore.mockReturnValue(db);

    await expect(assertAdminCall(req({auth: null}), KEYS))
        .rejects.toThrow(/auth-required/);
    expect(collections).toEqual([]);
  });

  test("a caller with an auth object but no uid is refused too", async () => {
    // Fail closed on missing input, the shape `assertFreshReauth` sets.
    const {db, collections} = makeDb({role: "admin", status: "active"});
    getFirestore.mockReturnValue(db);

    await expect(assertAdminCall(req({auth: {}}), KEYS))
        .rejects.toThrow(/auth-required/);
    expect(collections).toEqual([]);
  });

  test("a non-admin is refused", async () => {
    getFirestore.mockReturnValue(
        makeDb({role: "employee", status: "active"}).db);

    await expect(assertAdminCall(req(), KEYS)).rejects.toThrow();
  });

  test("a DISABLED admin is refused", async () => {
    // The half that makes deactivation effective.
    getFirestore.mockReturnValue(
        makeDb({role: "admin", status: "disabled"}).db);

    await expect(assertAdminCall(req(), KEYS)).rejects.toThrow();
  });

  test("the ADMIN check runs BEFORE the payload check", async () => {
    // Order is the security-relevant part: a non-privileged caller must be
    // refused before anything reads their data, and both must sit above
    // whatever rate limiter the caller adds next so a burst of malformed
    // submissions cannot exhaust a legitimate admin's window.
    getFirestore.mockReturnValue(
        makeDb({role: "employee", status: "active"}).db);

    await expect(
        assertAdminCall(req({data: {clientId: "c1", evil: 1}}), KEYS),
    ).rejects.toThrow(/not-admin/);
  });

  test("an unexpected key is refused for an admin", async () => {
    getFirestore.mockReturnValue(
        makeDb({role: "admin", status: "active"}).db);

    await expect(
        assertAdminCall(req({data: {clientId: "c1", evil: 1}}), KEYS),
    ).rejects.toThrow(/unexpected-field/);
  });

  test("an absent payload is accepted, as assertPayloadShape allows",
      async () => {
        // Callables whose every field is optional pass no data at all; the
        // per-field readers are what refuse a missing required one.
        getFirestore.mockReturnValue(
            makeDb({role: "admin", status: "active"}).db);

        await expect(assertAdminCall(req({data: undefined}), KEYS))
            .resolves.toBe("caller-uid");
      });
});
