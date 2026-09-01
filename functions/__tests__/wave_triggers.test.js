"use strict";

/**
 * `wave/triggers.js` had no test file of its own. Its two exports were only
 * ever reached through `notifications_riders.test.js`, which MOCKS the whole
 * module, so two seams were mutation-provable:
 *
 *   - the `runWaveDaily` connection-read guard deployed 2026-09-01: hoist that
 *     `await ref.get()` back above the try and the "never throws" contract in
 *     its own JSDoc breaks again, green.
 *   - the `waveUpsertCustomer` batch payload: it executes on every enqueue but
 *     nothing asserted its contents, so deleting `...problemsPatch(after)`
 *     passes the whole suite and Wave Phase 1 silently stops writing the only
 *     data source its report reads.
 */

jest.mock("firebase-admin/firestore");
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  debug: jest.fn(),
  error: jest.fn(),
}));
jest.mock("../wave/worker", () => ({
  enqueueCustomerUpsert: jest.fn(),
  drainQueue: jest.fn(),
  listOutstandingClientIds: jest.fn(),
  shouldEnqueueClientWrite: jest.fn(),
}));
jest.mock("../wave/sync_run", () => ({
  importWithWatermark: jest.fn(),
  readWaveBusinessIdCached: jest.fn(),
}));

const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const worker = require("../wave/worker");
const syncRun = require("../wave/sync_run");
const {problemsPatch} = require("../wave/customer_contract");
const {waveUpsertCustomer, runWaveDaily} = require("../wave/triggers");

const snapOf = (data) => ({exists: data !== null, data: () => data});

const makeEvent = (clientId, before, after) => ({
  params: {clientId},
  data: {before: snapOf(before), after: snapOf(after)},
});

/**
 * Firestore double recording the batch this trigger builds.
 * @param {!Object=} opts `connection` doc data, `connectionError` to throw on
 *   the read, or `commitError` to throw on commit.
 * @return {!Object} `{db, batchUpdates, commits}`
 */
function makeDb(opts = {}) {
  const batchUpdates = [];
  const commits = [];
  const db = {
    batch: () => ({
      update: (ref, patch) => batchUpdates.push({ref, patch}),
      commit: async () => {
        commits.push(batchUpdates.length);
        if (opts.commitError) throw opts.commitError;
      },
    }),
    doc: (p) => ({__path: p}),
    collection: () => ({
      doc: () => ({
        get: async () => {
          if (opts.connectionError) throw opts.connectionError;
          return snapOf(
              opts.connection === undefined ? null : opts.connection);
        },
      }),
    }),
  };
  return {db, batchUpdates, commits};
}

const IDLE_DRAIN = {
  processed: 0, done: 0, retried: 0, dead: 0, skipped: 0, reclaimed: 0,
};

beforeEach(() => {
  jest.clearAllMocks();
  FieldValue.serverTimestamp = jest.fn(() => "TS");
  worker.shouldEnqueueClientWrite.mockReturnValue(true);
  worker.enqueueCustomerUpsert.mockResolvedValue(undefined);
  worker.drainQueue.mockResolvedValue(IDLE_DRAIN);
  worker.listOutstandingClientIds.mockResolvedValue([]);
  syncRun.readWaveBusinessIdCached.mockResolvedValue("");
});

describe("waveUpsertCustomer mark-pending batch", () => {
  // A business named only by its own phone number is the shape that produced
  // the 2026-08-30 dead letter, so it is the one worth carrying here.
  const CLIENT = {
    type: "business",
    name: "5145554321",
    phone: "5145554321",
    email: "shop@example.com",
  };

  test("carries the report-only wave.problems patch, not just syncState",
      async () => {
        const {db, batchUpdates} = makeDb();
        getFirestore.mockReturnValue(db);

        await waveUpsertCustomer.run(makeEvent("c1", null, CLIENT));

        expect(batchUpdates).toHaveLength(1);
        const {patch} = batchUpdates[0];
        expect(patch["wave.syncState"]).toBe("pending");
        expect(patch["wave.syncError"]).toBeNull();

        // Phase 1 reads nothing else. Delete `...problemsPatch(after)` from
        // the trigger and this is the assertion that notices.
        const expected = problemsPatch(CLIENT);
        expect(Object.keys(expected).length).toBeGreaterThan(0);
        for (const [k, v] of Object.entries(expected)) {
          expect(patch[k]).toEqual(v);
        }
      });

  test("rides the SAME batch as the enqueue, so neither can land alone",
      async () => {
        const {db, commits} = makeDb();
        getFirestore.mockReturnValue(db);

        await waveUpsertCustomer.run(makeEvent("c1", null, CLIENT));

        expect(worker.enqueueCustomerUpsert).toHaveBeenCalledWith(
            "c1",
            expect.objectContaining({batch: expect.anything()}),
        );
        expect(commits).toEqual([1]);
      });

  test("a deleted client enqueues nothing", async () => {
    const {db, batchUpdates} = makeDb();
    getFirestore.mockReturnValue(db);

    await waveUpsertCustomer.run(makeEvent("c1", CLIENT, null));

    expect(batchUpdates).toEqual([]);
    expect(worker.enqueueCustomerUpsert).not.toHaveBeenCalled();
  });

  test("a failed batch commit still enqueues, without the patch", async () => {
    const {db} = makeDb({commitError: new Error("doc gone")});
    getFirestore.mockReturnValue(db);

    await waveUpsertCustomer.run(makeEvent("c1", null, CLIENT));

    // Second call is the fallback: enqueue-only, no batch.
    expect(worker.enqueueCustomerUpsert).toHaveBeenCalledTimes(2);
    const last = worker.enqueueCustomerUpsert.mock.calls[1][1];
    expect(last.batch).toBeUndefined();
  });
});

describe("runWaveDaily connection read", () => {
  test("a THROWING connection read returns quietly, never rejects",
      async () => {
        // The JSDoc says "never throws", and the caller is a rider on a
        // user-facing push whose real work has already completed. Hoist the
        // `await ref.get()` above the try and this rejects instead.
        const {db} = makeDb({connectionError: new Error("unavailable")});
        getFirestore.mockReturnValue(db);

        await expect(runWaveDaily()).resolves.toBeUndefined();

        expect(logger.warn).toHaveBeenCalledWith(
            expect.stringContaining("connection read failed"),
            expect.anything(),
        );
        expect(worker.drainQueue).not.toHaveBeenCalled();
      });

  test("no connection doc means nothing to do", async () => {
    const {db} = makeDb();
    getFirestore.mockReturnValue(db);

    await expect(runWaveDaily()).resolves.toBeUndefined();
    expect(worker.drainQueue).not.toHaveBeenCalled();
  });

  test("drains even when the import cadence is off", async () => {
    // The `off` setting governs the PULL only. Gating the push on it would
    // mean the default configuration never pushes automatically at all.
    const {db} = makeDb({
      connection: {businessId: "biz-1", importSchedule: "off"},
    });
    getFirestore.mockReturnValue(db);

    await runWaveDaily();

    expect(worker.drainQueue).toHaveBeenCalledTimes(1);
    expect(syncRun.importWithWatermark).not.toHaveBeenCalled();
  });

  test("a failing drain does not skip the import below it", async () => {
    worker.drainQueue.mockRejectedValueOnce(new Error("drain boom"));
    syncRun.importWithWatermark.mockResolvedValue({
      summary: {
        imported: 0, updated: 0, skippedArchived: 0,
        skippedPending: 0, skippedUnchanged: 0, pages: 1,
      },
      window: {reason: "full"},
    });
    const {db} = makeDb({
      connection: {businessId: "biz-1", importSchedule: "weekly"},
    });
    getFirestore.mockReturnValue(db);

    await runWaveDaily();

    expect(syncRun.importWithWatermark).toHaveBeenCalledTimes(1);
  });
});
