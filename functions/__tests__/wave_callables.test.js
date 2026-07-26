"use strict";

/**
 * Tests that every Wave admin callable checks its guards in the right
 * order: auth, then assertAdmin, then assertPayloadShape/requireString,
 * then enforceDurableRateLimit, and only then the real work (the invariant
 * documented in .claude/rules/security.md). We mock the security module so
 * `mock.invocationCallOrder` can confirm that sequence.
 */

jest.mock("../security");
jest.mock("firebase-admin/firestore");
jest.mock("../wave/client");
jest.mock("../wave/customers");

const {HttpsError} = require("firebase-functions/v2/https");

const security = require("../security");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const waveClient = require("../wave/client");
const waveCustomers = require("../wave/customers");

const {
  selectBusiness,
  waveBootstrap,
  waveGetConnection,
  waveSetImportSchedule,
  waveImportCustomers,
} = require("../wave/callables");

const ADMIN_UID = "admin-uid";

/** Payload with a key no Wave callable accepts. */
const MALFORMED = {totallyUnexpectedField: "x"};

/**
 * Fake `wave/connection` doc store.
 * @param {?Object} connection Initial doc data, or null for "absent".
 * @return {!Object} `{db, updates, sets}`.
 */
function fakeFirestore(connection) {
  let data = connection ? {...connection} : null;
  const updates = [];
  const sets = [];
  const ref = {
    get: jest.fn(async () => ({
      exists: data !== null,
      data: () => data,
    })),
    update: jest.fn(async (patch) => {
      updates.push(patch);
      data = {...(data || {}), ...patch};
    }),
  };
  const db = {
    collection: jest.fn(() => ({doc: jest.fn(() => ref)})),
    runTransaction: jest.fn(async (fn) => fn({
      get: async () => ref.get(),
      set: (r, value) => {
        sets.push(value);
        data = {...value};
      },
    })),
  };
  return {db, ref, updates, sets};
}

/**
 * Builds a callable request.
 * @param {?string} uid Caller uid, or null for unauthenticated.
 * @param {*} data Payload.
 * @return {!Object}
 */
function req(uid, data) {
  return {auth: uid ? {uid} : null, data};
}

/**
 * Runs a callable and returns the HttpsError it threw.
 * @param {!Function} fn The onCall function.
 * @param {!Object} request
 * @return {!Promise<!HttpsError>}
 */
async function expectThrows(fn, request) {
  let caught = null;
  try {
    await fn.run(request);
  } catch (e) {
    caught = e;
  }
  expect(caught).toBeInstanceOf(HttpsError);
  return caught;
}

/**
 * Relative invocation order of two jest mocks' first calls.
 * @param {!Function} first
 * @param {!Function} second
 */
function expectCalledBefore(first, second) {
  expect(first).toHaveBeenCalled();
  expect(second).toHaveBeenCalled();
  expect(first.mock.invocationCallOrder[0])
      .toBeLessThan(second.mock.invocationCallOrder[0]);
}

beforeEach(() => {
  jest.clearAllMocks();

  // These mocks behave like the real guards, just without touching
  // Firestore.
  security.assertAdmin.mockImplementation(async (uid) => {
    if (uid !== ADMIN_UID) {
      throw new HttpsError("permission-denied", "wave/not-admin");
    }
  });
  security.assertPayloadShape.mockImplementation((data, allowed) => {
    if (data === undefined || data === null) return;
    for (const key of Object.keys(data)) {
      if (!allowed.has(key)) {
        throw new HttpsError("invalid-argument", "unexpected-field");
      }
    }
  });
  security.enforceDurableRateLimit.mockResolvedValue({refund: jest.fn()});

  FieldValue.serverTimestamp = jest.fn(() => "SERVER_TS");
  waveClient.whoami.mockResolvedValue({});
  waveClient.listBusinesses.mockResolvedValue([{id: "biz-1", name: "Acme"}]);
  waveCustomers.importCustomers.mockResolvedValue({
    totalCount: 0, imported: 0, updated: 0, skippedArchived: 0, pages: 1,
  });
  getFirestore.mockReturnValue(fakeFirestore(null).db);
});

// This table lists the four admin callables and whether each one consumes
// a rate-limit slot on the happy path.
const CALLABLES = [
  {name: "waveBootstrap", fn: () => waveBootstrap, rateLimited: true},
  {name: "waveGetConnection", fn: () => waveGetConnection, rateLimited: false},
  {
    name: "waveSetImportSchedule",
    fn: () => waveSetImportSchedule,
    rateLimited: false,
  },
  {
    name: "waveImportCustomers",
    fn: () => waveImportCustomers,
    rateLimited: true,
  },
];

describe.each(CALLABLES)("$name guard order", ({fn, rateLimited}) => {
  test("an unauthenticated caller is rejected first", async () => {
    const err = await expectThrows(fn(), req(null, {}));

    expect(err.code).toBe("unauthenticated");
    expect(err.message).toBe("auth-required");
    expect(security.assertAdmin).not.toHaveBeenCalled();
    expect(security.assertPayloadShape).not.toHaveBeenCalled();
    expect(security.enforceDurableRateLimit).not.toHaveBeenCalled();
    expect(getFirestore).not.toHaveBeenCalled();
  });

  test("an auth object with no uid is treated as unauthenticated",
      async () => {
        const err = await expectThrows(fn(), {auth: {}, data: {}});
        expect(err.code).toBe("unauthenticated");
        expect(security.assertAdmin).not.toHaveBeenCalled();
      });

  test("a non-admin sending a malformed payload gets not-admin, " +
      "not unexpected-field", async () => {
    const err = await expectThrows(fn(), req("employee-uid", MALFORMED));

    expect(err.code).toBe("permission-denied");
    expect(err.message).toBe("wave/not-admin");
    // That's the point here: payload validation never runs for an
    // unprivileged caller, so the payload shape can't leak anything about
    // the endpoint.
    expect(security.assertPayloadShape).not.toHaveBeenCalled();
    expect(security.enforceDurableRateLimit).not.toHaveBeenCalled();
  });

  test("a non-admin never burns a rate-limit slot", async () => {
    await expectThrows(fn(), req("employee-uid", {}));
    expect(security.enforceDurableRateLimit).not.toHaveBeenCalled();
  });

  test("assertAdmin runs before assertPayloadShape for an admin", async () => {
    // We ignore the outcome here — some of these calls fail later on
    // business state. Only the guard sequence matters for this test.
    await fn().run(req(ADMIN_UID, {})).catch(() => {});

    expectCalledBefore(security.assertAdmin, security.assertPayloadShape);
    expect(security.assertAdmin).toHaveBeenCalledWith(ADMIN_UID);
  });

  test("an admin's malformed payload is rejected as unexpected-field",
      async () => {
        const err = await expectThrows(fn(), req(ADMIN_UID, MALFORMED));
        expect(err.code).toBe("invalid-argument");
        expect(err.message).toBe("unexpected-field");
        // Payload validation gates the limiter, so a burst of malformed
        // submissions cannot exhaust a legitimate admin's window.
        expect(security.enforceDurableRateLimit).not.toHaveBeenCalled();
      });

  if (!rateLimited) {
    test("is not rate limited on the happy path", async () => {
      await fn().run(req(ADMIN_UID, {})).catch(() => {});
      expect(security.enforceDurableRateLimit).not.toHaveBeenCalled();
    });
  }
});

describe("waveBootstrap", () => {
  test("payload validation precedes the rate limiter", async () => {
    getFirestore.mockReturnValue(fakeFirestore(null).db);
    await waveBootstrap.run(req(ADMIN_UID, {})).catch(() => {});

    expectCalledBefore(
        security.assertPayloadShape, security.enforceDurableRateLimit);
  });

  test("connects and rate-limits the not-yet-connected path", async () => {
    const {db, sets} = fakeFirestore(null);
    getFirestore.mockReturnValue(db);

    const out = await waveBootstrap.run(req(ADMIN_UID, {}));

    expect(out).toEqual({businessId: "biz-1", businessName: "Acme"});
    expect(sets[0]).toMatchObject({businessId: "biz-1"});
    expect(security.enforceDurableRateLimit)
        .toHaveBeenCalledWith("wave-bootstrap", ADMIN_UID, 10, 3600000);
  });

  test("the idempotent already-connected short-circuit is NOT rate limited",
      async () => {
        getFirestore.mockReturnValue(
            fakeFirestore({businessId: "biz-1", businessName: "Acme"}).db);

        const out = await waveBootstrap.run(req(ADMIN_UID, {}));

        expect(out).toEqual({businessId: "biz-1", businessName: "Acme"});
        expect(security.enforceDurableRateLimit).not.toHaveBeenCalled();
        expect(waveClient.whoami).not.toHaveBeenCalled();
      });

  test("the rate limiter fires before any live Wave call", async () => {
    getFirestore.mockReturnValue(fakeFirestore(null).db);
    security.enforceDurableRateLimit.mockRejectedValueOnce(
        new HttpsError("resource-exhausted", "too-many-attempts"));

    const err = await expectThrows(waveBootstrap, req(ADMIN_UID, {}));

    expect(err.code).toBe("resource-exhausted");
    expect(waveClient.whoami).not.toHaveBeenCalled();
    expect(waveClient.listBusinesses).not.toHaveBeenCalled();
  });

  test("accepts no payload keys at all", async () => {
    getFirestore.mockReturnValue(fakeFirestore(null).db);
    await waveBootstrap.run(req(ADMIN_UID, {})).catch(() => {});

    const allowed = security.assertPayloadShape.mock.calls[0][1];
    expect([...allowed]).toEqual([]);
  });
});

describe("waveImportCustomers", () => {
  test("payload validation precedes the rate limiter", async () => {
    getFirestore.mockReturnValue(fakeFirestore({businessId: "biz-1"}).db);
    await waveImportCustomers.run(req(ADMIN_UID, {})).catch(() => {});

    expectCalledBefore(
        security.assertPayloadShape, security.enforceDurableRateLimit);
  });

  test("the rate limiter fires before the Wave import runs", async () => {
    getFirestore.mockReturnValue(fakeFirestore({businessId: "biz-1"}).db);
    security.enforceDurableRateLimit.mockRejectedValueOnce(
        new HttpsError("resource-exhausted", "too-many-attempts"));

    const err = await expectThrows(waveImportCustomers, req(ADMIN_UID, {}));

    expect(err.code).toBe("resource-exhausted");
    expect(waveCustomers.importCustomers).not.toHaveBeenCalled();
  });

  test("caps admins at 5 imports per hour", async () => {
    getFirestore.mockReturnValue(fakeFirestore({businessId: "biz-1"}).db);
    await waveImportCustomers.run(req(ADMIN_UID, {}));

    expect(security.enforceDurableRateLimit)
        .toHaveBeenCalledWith("wave-import", ADMIN_UID, 5, 3600000);
  });

  test("a not-bootstrapped install fails after the guards, not before",
      async () => {
        getFirestore.mockReturnValue(fakeFirestore(null).db);

        const err = await expectThrows(waveImportCustomers, req(ADMIN_UID, {}));

        expect(err.code).toBe("failed-precondition");
        expect(err.message).toBe("wave/not-bootstrapped");
        expect(security.enforceDurableRateLimit).toHaveBeenCalled();
      });
});

describe("waveGetConnection", () => {
  test("reads the connection for an admin", async () => {
    getFirestore.mockReturnValue(fakeFirestore({
      businessId: "biz-1",
      businessName: "Acme",
      importSchedule: "weekly",
    }).db);

    expect(await waveGetConnection.run(req(ADMIN_UID, {}))).toEqual({
      connected: true,
      businessId: "biz-1",
      businessName: "Acme",
      importSchedule: "weekly",
    });
  });

  test("an absent doc reports disconnected with schedule off", async () => {
    getFirestore.mockReturnValue(fakeFirestore(null).db);

    expect(await waveGetConnection.run(req(ADMIN_UID, {}))).toEqual({
      connected: false,
      businessId: "",
      businessName: "",
      importSchedule: "off",
    });
  });

  test("an unknown stored schedule normalizes to off", async () => {
    getFirestore.mockReturnValue(
        fakeFirestore({businessId: "b", importSchedule: "hourly"}).db);

    const out = await waveGetConnection.run(req(ADMIN_UID, {}));
    expect(out.importSchedule).toBe("off");
  });
});

describe("waveSetImportSchedule", () => {
  test("allows only the `schedule` key", async () => {
    getFirestore.mockReturnValue(fakeFirestore({businessId: "b"}).db);
    await waveSetImportSchedule
        .run(req(ADMIN_UID, {schedule: "weekly"})).catch(() => {});

    const allowed = security.assertPayloadShape.mock.calls[0][1];
    expect([...allowed]).toEqual(["schedule"]);
  });

  test("writes an accepted cadence", async () => {
    const {db, updates} = fakeFirestore({businessId: "b"});
    getFirestore.mockReturnValue(db);

    expect(await waveSetImportSchedule.run(req(ADMIN_UID, {
      schedule: "monthly",
    }))).toEqual({schedule: "monthly"});
    expect(updates).toEqual([{importSchedule: "monthly"}]);
  });

  test("rejects a cadence outside the allowlist", async () => {
    getFirestore.mockReturnValue(fakeFirestore({businessId: "b"}).db);

    const err = await expectThrows(
        waveSetImportSchedule, req(ADMIN_UID, {schedule: "hourly"}));

    expect(err.code).toBe("invalid-argument");
    expect(err.message).toBe("wave/invalid-schedule");
  });

  test("value validation runs before the Firestore read", async () => {
    const fake = fakeFirestore({businessId: "b"});
    getFirestore.mockReturnValue(fake.db);

    await expectThrows(
        waveSetImportSchedule, req(ADMIN_UID, {schedule: 42}));

    expect(fake.ref.get).not.toHaveBeenCalled();
  });

  test("a not-bootstrapped install is rejected without a write", async () => {
    const fake = fakeFirestore(null);
    getFirestore.mockReturnValue(fake.db);

    const err = await expectThrows(
        waveSetImportSchedule, req(ADMIN_UID, {schedule: "weekly"}));

    expect(err.message).toBe("wave/not-bootstrapped");
    expect(fake.updates).toEqual([]);
  });
});

describe("selectBusiness", () => {
  const list = [
    {id: "b1", name: "Acme Co"},
    {id: "b2", name: "Other Inc"},
  ];

  test("matches the configured name case- and whitespace-insensitively", () => {
    expect(selectBusiness(list, "  acme co ")).toEqual(list[0]);
  });

  test("a configured name with no match is not-found", () => {
    expect(() => selectBusiness(list, "Nope"))
        .toThrow(expect.objectContaining({message: "wave/business-not-found"}));
  });

  test("with no selector, a single business is taken", () => {
    expect(selectBusiness([list[0]], "")).toEqual(list[0]);
  });

  test("with no selector and several businesses it refuses to guess", () => {
    expect(() => selectBusiness(list, ""))
        .toThrow(expect.objectContaining({message: "wave/business-ambiguous"}));
  });

  test("a non-array / empty list is ambiguous, never a silent pick", () => {
    expect(() => selectBusiness(null, "")).toThrow(HttpsError);
    expect(() => selectBusiness([], "")).toThrow(HttpsError);
  });
});
