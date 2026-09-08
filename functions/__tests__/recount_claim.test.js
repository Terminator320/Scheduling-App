"use strict";

const {
  claimRecount,
  releaseRecount,
  debounceRecount,
  isAlreadyExists,
  CLAIM_STALE_MS,
  CLAIM_TTL_MS,
  ALREADY_EXISTS,
} = require("../recount_claim");

const COLL = "clientRecountClaims";

/**
 * Minimal Firestore double: one in-memory map of claim docs.
 * @param {!Object=} opts Failure injection.
 * @return {!Object} `{db, store, calls}`
 */
function makeDb(opts = {}) {
  const store = new Map();
  const calls = {create: 0, set: 0, get: 0, del: 0};
  const db = {
    collection(name) {
      expect(name).toBe(COLL);
      return {
        doc(id) {
          // The real `.doc()` throws SYNCHRONOUSLY on a reserved id.
          if (opts.docThrows) throw opts.docThrows;
          return {
            async create(body) {
              calls.create += 1;
              if (opts.createThrows) throw opts.createThrows;
              if (store.has(id)) {
                const err = new Error("exists");
                err.code = ALREADY_EXISTS;
                throw err;
              }
              store.set(id, body);
            },
            async set(body) {
              calls.set += 1;
              if (opts.setThrows) throw opts.setThrows;
              store.set(id, body);
            },
            async get() {
              calls.get += 1;
              if (opts.getThrows) throw opts.getThrows;
              const body = store.get(id);
              return {get: (field) => (body ? body[field] : undefined)};
            },
            async delete() {
              calls.del += 1;
              if (opts.deleteThrows) throw opts.deleteThrows;
              store.delete(id);
            },
          };
        },
      };
    },
  };
  return {db, store, calls};
}

describe("isAlreadyExists", () => {
  test("matches both the numeric and the string code", () => {
    expect(isAlreadyExists({code: ALREADY_EXISTS})).toBe(true);
    expect(isAlreadyExists({code: "already-exists"})).toBe(true);
  });

  test("does not match anything else", () => {
    expect(isAlreadyExists(null)).toBe(false);
    expect(isAlreadyExists({code: 5})).toBe(false);
    expect(isAlreadyExists(new Error("boom"))).toBe(false);
  });
});

describe("claimRecount", () => {
  test("the first caller owns the recount", async () => {
    const {db, store} = makeDb();
    await expect(claimRecount(COLL, "c1", {db})).resolves.toBe(true);
    expect(store.has("c1")).toBe(true);
  });

  test("a sibling inside the window is suppressed", async () => {
    const {db} = makeDb();
    const now = new Date();
    await claimRecount(COLL, "c1", {db, now});
    const later = new Date(now.getTime() + CLAIM_STALE_MS - 1);
    await expect(claimRecount(COLL, "c1", {db, now: later}))
        .resolves.toBe(false);
  });

  test("a claim past the staleness window is taken over", async () => {
    const {db} = makeDb();
    const now = new Date();
    await claimRecount(COLL, "c1", {db, now});
    const later = new Date(now.getTime() + CLAIM_STALE_MS + 1);
    await expect(claimRecount(COLL, "c1", {db, now: later}))
        .resolves.toBe(true);
  });

  test("stamps expiresAt for the TTL policy", async () => {
    const {db, store} = makeDb();
    const now = new Date("2026-08-28T10:00:00Z");
    await claimRecount(COLL, "c1", {db, now});
    expect(store.get("c1").expiresAt.getTime())
        .toBe(now.getTime() + CLAIM_TTL_MS);
  });

  test("reads a Firestore Timestamp claimedAt, not just a Date", async () => {
    const {db, store} = makeDb();
    const now = new Date();
    store.set("c1", {
      claimedAt: {toMillis: () => now.getTime()},
      expiresAt: now,
    });
    const later = new Date(now.getTime() + CLAIM_STALE_MS - 1);
    await expect(claimRecount(COLL, "c1", {db, now: later}))
        .resolves.toBe(false);
  });

  test("FAILS OPEN when create throws a non-exists error", async () => {
    const warn = jest.fn();
    const {db} = makeDb({createThrows: new Error("ledger down")});
    await expect(claimRecount(COLL, "c1", {db, logger: {warn}}))
        .resolves.toBe(true);
    expect(warn).toHaveBeenCalled();
  });

  test("FAILS OPEN when `.doc()` itself throws on a reserved id", async () => {
    // `.doc()` rejects "." and ".." SYNCHRONOUSLY, and it used to sit one line
    // ABOVE the try — so the one error that preceded the guard was the one
    // error the documented fail-open did not cover. A console- or
    // Admin-SDK-written appointment carrying such an id made this reject, its
    // caller rethrow, and `retry: true` turn that into a redelivery storm.
    const warn = jest.fn();
    const {db} = makeDb({docThrows: new Error("invalid document reference")});
    await expect(claimRecount(COLL, "..", {db, logger: {warn}}))
        .resolves.toBe(true);
    expect(warn).toHaveBeenCalled();
  });

  test("FAILS OPEN when the takeover read throws", async () => {
    const warn = jest.fn();
    const {db} = makeDb();
    await claimRecount(COLL, "c1", {db});
    const broken = makeDb({getThrows: new Error("read down")});
    broken.store.set("c1", {claimedAt: new Date()});
    await expect(
        claimRecount(COLL, "c1", {db: broken.db, logger: {warn}}),
    ).resolves.toBe(true);
    expect(warn).toHaveBeenCalled();
  });

  test("FAILS OPEN when the takeover WRITE throws", async () => {
    // A distinct branch from the read failing, even though they share a catch:
    // the takeover has already decided the claim is abandoned and then cannot
    // rewrite it. Failing closed here would suppress a recount whose
    // predecessor was killed mid-flight — the exact case the takeover exists
    // for.
    const warn = jest.fn();
    const {db, store} = makeDb({setThrows: new Error("write down")});
    const claimedAt = new Date();
    store.set("c1", {claimedAt});
    const later = new Date(claimedAt.getTime() + CLAIM_STALE_MS + 1);

    await expect(claimRecount(COLL, "c1", {db, logger: {warn}, now: later}))
        .resolves.toBe(true);
    expect(warn).toHaveBeenCalled();
  });

  test("a claim with an unreadable claimedAt is taken over", async () => {
    const {db, store} = makeDb();
    store.set("c1", {claimedAt: "not a timestamp"});
    await expect(claimRecount(COLL, "c1", {db})).resolves.toBe(true);
  });
});

describe("releaseRecount", () => {
  test("deletes the claim", async () => {
    const {db, store} = makeDb();
    await claimRecount(COLL, "c1", {db});
    await releaseRecount(COLL, "c1", {db});
    expect(store.has("c1")).toBe(false);
  });

  test("swallows a failed delete; the staleness takeover covers it",
      async () => {
        const warn = jest.fn();
        const {db} = makeDb({deleteThrows: new Error("delete down")});
        await expect(releaseRecount(COLL, "c1", {db, logger: {warn}}))
            .resolves.toBeUndefined();
        expect(warn).toHaveBeenCalled();
      });
});

describe("debounceRecount", () => {
  test("collapses a batch to ONE aggregate", async () => {
    const {db} = makeDb();
    const recount = jest.fn().mockResolvedValue(7);
    const sleep = jest.fn().mockResolvedValue(undefined);
    const deps = {db, sleep, settleMs: 0};
    const results = await Promise.all([
      debounceRecount(COLL, "c1", recount, deps),
      debounceRecount(COLL, "c1", recount, deps),
      debounceRecount(COLL, "c1", recount, deps),
    ]);
    expect(recount).toHaveBeenCalledTimes(1);
    expect(results.filter((r) => r.skipped)).toHaveLength(2);
    expect(results.find((r) => !r.skipped).result).toBe(7);
  });

  test("RELEASES BEFORE the aggregate, so a retry can re-claim", async () => {
    const {db, store} = makeDb();
    let heldAtAggregate = null;
    const recount = jest.fn(async () => {
      heldAtAggregate = store.has("c1");
      return 1;
    });
    await debounceRecount(COLL, "c1", recount, {db, settleMs: 0});
    // The claim must already be gone when the aggregate runs — otherwise a
    // throwing recount would suppress its own retry.
    expect(heldAtAggregate).toBe(false);
  });

  test("a throwing aggregate leaves no claim behind", async () => {
    const {db, store} = makeDb();
    const boom = new Error("aggregate failed");
    await expect(
        debounceRecount(COLL, "c1", () => Promise.reject(boom), {
          db, settleMs: 0,
        }),
    ).rejects.toBe(boom);
    expect(store.has("c1")).toBe(false);
  });

  test("a sibling arriving after the window recounts again", async () => {
    const {db} = makeDb();
    const recount = jest.fn().mockResolvedValue(1);
    await debounceRecount(COLL, "c1", recount, {db, settleMs: 0});
    await debounceRecount(COLL, "c1", recount, {db, settleMs: 0});
    expect(recount).toHaveBeenCalledTimes(2);
  });

  test("waits the settle window before releasing", async () => {
    const {db} = makeDb();
    const order = [];
    const sleep = jest.fn(async (ms) => order.push(`sleep:${ms}`));
    await debounceRecount(COLL, "c1", async () => order.push("recount"), {
      db, sleep, settleMs: 2000,
    });
    expect(order).toEqual(["sleep:2000", "recount"]);
  });
});
