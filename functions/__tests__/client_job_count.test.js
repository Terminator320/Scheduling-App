"use strict";

// The trigger resolves its Firestore handle and its claim ledger through these
// two modules, so both are replaced to run `recountClientJobs` itself. The
// `mock` prefix is what lets jest's hoisted factory close over the handle.
let mockDb = null;
jest.mock("../admin_firestore", () => ({
  adminFirestore: () => ({getFirestore: () => mockDb}),
}));
jest.mock("../recount_claim", () => ({
  debounceRecount: jest.fn(async (collection, key, recount) => ({
    skipped: false,
    result: await recount(),
  })),
}));
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

const {debounceRecount} = require("../recount_claim");
const logger = require("firebase-functions/logger");
const {
  clientsToRecount,
  mayShareABatch,
  recountClientJobs,
  recountOne,
  CLIENT_RECOUNT_CLAIMS,
  RECOUNT_SETTLE_MS,
  NOT_FOUND,
} = require("../client_job_count");

describe("clientsToRecount", () => {
  test("a create recounts the new client", () => {
    expect(clientsToRecount(null, {clientId: "c1"})).toEqual(["c1"]);
  });

  test("a delete recounts the old client", () => {
    expect(clientsToRecount({clientId: "c1"}, null)).toEqual(["c1"]);
  });

  test("a reassignment recounts both clients", () => {
    const ids = clientsToRecount({clientId: "c1"}, {clientId: "c2"});
    expect(ids.sort()).toEqual(["c1", "c2"]);
  });

  test("an unrelated edit recounts nothing", () => {
    const ids = clientsToRecount(
        {clientId: "c1", title: "Old"},
        {clientId: "c1", title: "New"},
    );
    expect(ids).toEqual([]);
  });

  test("a personal job has no clientId and recounts nothing", () => {
    const personal = {isPersonal: true, clientId: ""};
    expect(clientsToRecount(null, personal)).toEqual([]);
    expect(clientsToRecount({clientId: ""}, {clientId: ""})).toEqual([]);
  });

  test("non-string clientIds are ignored", () => {
    expect(clientsToRecount(null, {clientId: 42})).toEqual([]);
    expect(clientsToRecount(null, {})).toEqual([]);
  });

  test("blank-to-set is a reassignment from nothing", () => {
    expect(clientsToRecount({clientId: ""}, {clientId: "c2"})).toEqual(["c2"]);
  });

  test("surrounding whitespace does not fake a reassignment", () => {
    expect(clientsToRecount({clientId: " c1 "}, {clientId: "c1"})).toEqual([]);
  });

  test("ids that would make doc() throw synchronously are dropped", () => {
    // "/", "." and ".." are all rejected by `.doc()` BEFORE any promise
    // exists, and this trigger is retry:true — one poisoned document written
    // by the console or the Admin SDK would otherwise become a permanent
    // redelivery storm. Rules screen these on the app's own write paths, but
    // rules do not apply to either of those callers.
    for (const bad of ["a/b", ".", "..", " .. "]) {
      expect(clientsToRecount(null, {clientId: bad})).toEqual([]);
    }
    // Not over-broad: an id merely CONTAINING a dot is perfectly legal.
    expect(clientsToRecount(null, {clientId: "..a"})).toEqual(["..a"]);
  });
});

// ---------------------------------------------------------------------------
// recountOne
// ---------------------------------------------------------------------------

/**
 * Fake Firestore recording the aggregate queries it was asked for and the
 * write it received.
 *
 * `recountOne` issues TWO aggregates off one base query — every document for
 * the client, then the later days of its multi-day runs — so the chained
 * `where` has to be modelled or the second one reads as the first.
 * `laterRunDays` is what the `dayIndex > 1` leg answers.
 * @param {{count: number, laterRunDays: number, updateError: ?Object}} opts
 * @return {!Object} `{db, calls}`
 */
function fakeDb({count = 0, laterRunDays = 0, updateError = null} = {}) {
  const calls = {where: null, wheres: [], doc: null, update: [], set: []};
  const db = {
    collection(name) {
      if (name === "appointments") {
        return {
          where(field, op, value) {
            calls.where = {field, op, value};
            calls.wheres.push({field, op, value});
            const base = {
              count: () => ({get: async () => ({data: () => ({count})})}),
              where(f2, o2, v2) {
                calls.wheres.push({field: f2, op: o2, value: v2});
                return {
                  count: () => ({
                    get: async () => ({data: () => ({count: laterRunDays})}),
                  }),
                };
              },
            };
            return base;
          },
        };
      }
      return {
        doc(id) {
          calls.doc = id;
          return {
            async update(data) {
              calls.update.push(data);
              if (updateError) throw updateError;
            },
            async set(data, opts) {
              calls.set.push({data, opts});
            },
          };
        },
      };
    },
  };
  return {db, calls};
}

describe("recountOne", () => {
  test("writes the aggregate count with update(), not set(merge)", async () => {
    // update() over set({merge:true}) is the load-bearing choice: a client
    // deleted out-of-band (Admin SDK or console — the app has no delete path)
    // must NOT be resurrected as a stub doc holding nothing but a count.
    const {db, calls} = fakeDb({count: 7});

    await recountOne(db, "c1");

    expect(calls.where).toEqual({field: "clientId", op: "==", value: "c1"});
    expect(calls.doc).toBe("c1");
    expect(calls.update).toEqual([{jobCount: 7}]);
    expect(calls.set).toEqual([]);
  });

  test("a multi-day run counts as ONE job, not one per day", async () => {
    // The badge says "jobs". A Monday-to-Friday booking is one job stored as
    // five day-documents, so a document count read 5 for it.
    const {db, calls} = fakeDb({count: 7, laterRunDays: 4});

    await recountOne(db, "c1");

    expect(calls.update).toEqual([{jobCount: 3}]);
  });

  test("the later-days leg filters dayIndex > 1, so day 1 still counts",
      async () => {
        // Only a run member carries `dayIndex`, and day 1 stores 1 — so the
        // inequality excludes both a single-day job (no field at all) and the
        // run's first day, which IS the job.
        const {db, calls} = fakeDb({count: 5, laterRunDays: 0});

        await recountOne(db, "c1");

        // One base query, reused for both aggregates.
        expect(calls.wheres).toEqual([
          {field: "clientId", op: "==", value: "c1"},
          {field: "dayIndex", op: ">", value: 1},
        ]);
        expect(calls.update).toEqual([{jobCount: 5}]);
      });

  test("writes an absolute count, not an increment", async () => {
    // The trigger runs with `retry: true` and a redelivered event would
    // double-count a FieldValue.increment. Absolute is idempotent by
    // construction.
    const {db, calls} = fakeDb({count: 0});

    await recountOne(db, "c1");

    expect(calls.update[0].jobCount).toBe(0);
    expect(typeof calls.update[0].jobCount).toBe("number");
  });

  test("swallows NOT_FOUND — the client is gone, there is nothing to fix",
      async () => {
        // Rethrowing here would make one deleted client a permanent
        // redelivery storm on `retry: true`.
        const {db} = fakeDb({count: 3, updateError: {code: NOT_FOUND}});

        await expect(recountOne(db, "gone")).resolves.toBeUndefined();
      });

  test("rethrows everything else, so retry: true still means something",
      async () => {
        // PERMISSION_DENIED (7) and UNAVAILABLE (14) are the cases a retry is
        // FOR. A blanket swallow would turn every one of them into a count
        // that silently stops updating.
        for (const code of [7, 14, "unavailable", undefined]) {
          const {db} = fakeDb({count: 3, updateError: {code}});
          await expect(recountOne(db, "c1")).rejects.toEqual({code});
        }
      });

  test("NOT_FOUND is Firestore's numeric 5, not the string", async () => {
    // The Admin SDK reports gRPC codes numerically. A `code === "not-found"`
    // spelling (the client SDK's) would fall through to the rethrow.
    expect(NOT_FOUND).toBe(5);

    const {db} = fakeDb({count: 3, updateError: {code: "not-found"}});
    await expect(recountOne(db, "c1")).rejects.toEqual({code: "not-found"});
  });
});

// ---------------------------------------------------------------------------
// mayShareABatch — the gate that decides whether the debounce is worth paying
// ---------------------------------------------------------------------------

describe("mayShareABatch", () => {
  test("an ordinary single-day job is never part of a batch", () => {
    // The overwhelmingly common write. Debouncing it buys nothing and costs
    // 2 s of billed wall-clock plus a claim create() AND delete() — taking the
    // path from 2 Firestore writes to 4.
    expect(mayShareABatch({clientId: "c1"})).toBe(false);
    expect(mayShareABatch({clientId: "c1", seriesId: "", dayCount: 0}))
        .toBe(false);
  });

  test("a multi-day run day-document is", () => {
    expect(mayShareABatch({dayCount: 14, dayIndex: 3})).toBe(true);
  });

  test("a repeat-series occurrence is", () => {
    expect(mayShareABatch({seriesId: "root1"})).toBe(true);
  });

  test("the series ROOT is too, even though seriesId is its own id", () => {
    // add_event_controller.dart writes the root in the SAME WriteBatch as its
    // siblings and stamps it with its own id. Excluding it would leave the root
    // recounting alone while the siblings collapse to a second recount — two
    // aggregates where the whole point is one.
    expect(mayShareABatch({seriesId: "a1"})).toBe(true);
  });

  test("a missing document is not a batch", () => {
    expect(mayShareABatch(null)).toBe(false);
  });

  test("junk in either marker degrades to the un-debounced path", () => {
    expect(mayShareABatch({dayCount: "many", seriesId: 42})).toBe(false);
    expect(mayShareABatch({dayCount: NaN})).toBe(false);
    expect(mayShareABatch({seriesId: "   "})).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// recountClientJobs — the debounce adapter
// ---------------------------------------------------------------------------

/**
 * A Firestore-written event carrying the given before/after document fields.
 * @param {?Object} before
 * @param {?Object} after
 * @param {string=} appointmentId
 * @return {!Object}
 */
function writeEvent(before, after, appointmentId = "a1") {
  return {
    params: {appointmentId},
    data: {
      before: {exists: before != null, data: () => before},
      after: {exists: after != null, data: () => after},
    },
  };
}

describe("recountClientJobs", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockDb = null;
  });

  test("a plain create recounts DIRECTLY, with no claim and no settle",
      async () => {
        const {db, calls} = fakeDb({count: 4});
        mockDb = db;

        await recountClientJobs.run(writeEvent(null, {clientId: "c1"}));

        expect(debounceRecount).not.toHaveBeenCalled();
        expect(calls.update).toEqual([{jobCount: 4}]);
      });

  test("a run day-document debounces in the right ledger, at the right window",
      async () => {
        // All three arguments are silent when wrong. A collection name that
        // does not match the deny-all block in firestore.rules AND the TTL
        // policy in firestore.indexes.json yields a ledger the claim can never
        // write: claimRecount then fails open on every call and the debounce
        // simply never engages — no error, no log, just the old cost profile.
        const {db, calls} = fakeDb({count: 9});
        mockDb = db;

        await recountClientJobs.run(
            writeEvent(null, {clientId: "c1", dayCount: 14, dayIndex: 2}));

        expect(debounceRecount).toHaveBeenCalledTimes(1);
        const [collection, key, , deps] = debounceRecount.mock.calls[0];
        expect(collection).toBe(CLIENT_RECOUNT_CLAIMS);
        expect(CLIENT_RECOUNT_CLAIMS).toBe("clientRecountClaims");
        expect(key).toBe("c1");
        expect(deps.settleMs).toBe(RECOUNT_SETTLE_MS);
        expect(calls.update).toEqual([{jobCount: 9}]);
      });

  test("a DELETE reads the batch markers off `before`", async () => {
    // There is no `after` to read them from, and a run delete is exactly the
    // batch worth collapsing.
    const {db} = fakeDb({count: 0});
    mockDb = db;

    await recountClientJobs.run(
        writeEvent({clientId: "c1", dayCount: 5}, null));

    expect(debounceRecount).toHaveBeenCalledTimes(1);
  });

  test("a reassignment recounts both clients on the same path", async () => {
    const {db} = fakeDb({count: 1});
    mockDb = db;

    await recountClientJobs.run(
        writeEvent({clientId: "c1"}, {clientId: "c2", seriesId: "root"}));

    expect(debounceRecount.mock.calls.map((c) => c[1]).sort())
        .toEqual(["c1", "c2"]);
  });

  test("an unrelated edit does no work at all", async () => {
    mockDb = null; // any Firestore access would throw
    await recountClientJobs.run(
        writeEvent({clientId: "c1", title: "Old"}, {clientId: "c1"}));
    expect(debounceRecount).not.toHaveBeenCalled();
  });

  test("RETHROWS a failing recount, so retry: true still means something",
      async () => {
        // Swallowing here would turn every transient UNAVAILABLE into a
        // jobCount that silently stops updating.
        const denied = {code: 7};
        const {db} = fakeDb({count: 2, updateError: denied});
        mockDb = db;

        await expect(
            recountClientJobs.run(writeEvent(null, {clientId: "c1"})),
        ).rejects.toEqual(denied);
        expect(logger.error).toHaveBeenCalledWith(
            "recountClientJobs failed",
            expect.objectContaining({clientId: "c1"}),
        );
      });
});
