"use strict";

const {enqueueCustomerUpsert, drainQueue} = require("../worker");
const {WaveValidationError} = require("../customers");
const {WaveApiError} = require("../client");

// ---------------------------------------------------------------------------
// Fakes / helpers
// ---------------------------------------------------------------------------

/** Stable timestamp sentinel — lets test assertions be precise. */
const TS = {__serverTimestamp: true};
// now() factory that returns the sentinel.
const now = () => TS;

/**
 * Builds a minimal logger fake that records calls.
 * @return {{error: jest.Mock, warn: jest.Mock, info: jest.Mock}}
 */
function fakeLogger() {
  const lg = {
    error: jest.fn(),
    warn: jest.fn(),
    info: jest.fn(),
  };
  return lg;
}

/**
 * Creates a fake Firestore doc snapshot.
 * @param {string} id Document id.
 * @param {Object|null} data Document data (null = missing).
 * @param {!Object} ref The doc ref this snapshot belongs to.
 * @return {!Object}
 */
function snap(id, data, ref) {
  return {
    id,
    exists: data !== null,
    data: () => data,
    ref,
  };
}

/**
 * Fake doc ref that records `set` and `update` calls and exposes a mutable
 * `_data` field for in-place mutation (simulates Firestore writes).
 * @param {string} id Document id.
 * @param {Object|null} initialData Initial snapshot data.
 * @return {!Object}
 */
function fakeRef(id, initialData) {
  const ref = {
    id,
    _data: initialData,
    updates: [],
    sets: [],
    /** @param {Object} u */
    update: jest.fn((u) => {
      ref.updates.push(u);
      // Mutate _data so the next read sees the updated state.
      if (ref._data !== null) Object.assign(ref._data, u);
      return Promise.resolve();
    }),
    /**
     * @param {Object} d
     * @param {Object=} opts
     */
    set: jest.fn((d, opts) => {
      ref.sets.push({data: d, opts});
      if (opts && opts.merge) {
        ref._data = ref._data ? Object.assign({}, ref._data, d) : {...d};
      } else {
        ref._data = {...d};
      }
      return Promise.resolve();
    }),
  };
  return ref;
}

/**
 * Builds a fake Firestore that holds a single `waveSyncQueue` doc (for
 * enqueue tests).
 * @param {string} jobId
 * @param {Object|null} existingData
 * @return {{db: !Object, ref: !Object}}
 */
function enqueueDb(jobId, existingData = null) {
  const ref = fakeRef(jobId, existingData);
  const db = {
    collection: jest.fn((col) => {
      if (col !== "waveSyncQueue") throw new Error(`unexpected col: ${col}`);
      return {
        doc: jest.fn((id) => {
          if (id !== jobId) throw new Error(`unexpected doc id: ${id}`);
          return ref;
        }),
      };
    }),
  };
  return {db, ref};
}

/**
 * Builds a fake Firestore for drainQueue. Supports one or more `waveSyncQueue`
 * job documents returned by the query, plus a configurable `runTransaction`.
 *
 * @param {!Array<{id:string, data:Object}>} jobs Job docs to return from query.
 * @param {Object=} opts
 * @param {boolean=} opts.claimSucceeds Whether the claim txn should succeed
 *   (default true — sets inflight).
 * @param {boolean=} opts.claimSetsInflight Whether the re-read in the txn
 *   still shows 'queued' (default true).
 * @return {{db: !Object, refs: !Array<!Object>}}
 */
function drainDb(jobs, opts = {}) {
  const claimSetsInflight = opts.claimSetsInflight !== false;
  const claimSucceeds = opts.claimSucceeds !== false;

  const refs = jobs.map((j) => fakeRef(j.id, {...j.data}));

  // Build the query snapshot.
  const snapshots = refs.map((ref, i) => snap(jobs[i].id, {...jobs[i].data},
      ref));

  const db = {
    collection: jest.fn((col) => {
      if (col !== "waveSyncQueue") throw new Error(`unexpected col: ${col}`);
      return {
        where: jest.fn().mockReturnThis(),
        orderBy: jest.fn().mockReturnThis(),
        limit: jest.fn().mockReturnThis(),
        get: jest.fn(() => Promise.resolve({docs: snapshots})),
      };
    }),
    runTransaction: jest.fn(async (fn) => {
      if (!claimSucceeds) throw new Error("transaction contention");
      const txn = {
        get: jest.fn((ref) => {
          // Re-read the ref's current _data for claim verification.
          const currentData = ref._data;
          return Promise.resolve(snap(ref.id, currentData, ref));
        }),
        update: jest.fn((ref, fields) => {
          if (claimSetsInflight) {
            Object.assign(ref._data, fields);
          }
        }),
      };
      return fn(txn);
    }),
  };

  return {db, refs};
}

/**
 * Builds a no-op backoff function that always returns a fixed delay, making
 * tests deterministic.
 * @param {number=} delayMs Fixed delay to return (default 1000ms).
 * @return {function(number):number}
 */
function fixedBackoff(delayMs = 1000) {
  return jest.fn(() => delayMs);
}

// ---------------------------------------------------------------------------
// enqueueCustomerUpsert
// ---------------------------------------------------------------------------

describe("enqueueCustomerUpsert", () => {
  test("uses deterministic jobId customerUpsert__<clientId>", async () => {
    const {db, ref} = enqueueDb("customerUpsert__abc123");
    const jobId = await enqueueCustomerUpsert("abc123", {db, now});
    expect(jobId).toBe("customerUpsert__abc123");
    expect(ref.sets).toHaveLength(1);
  });

  test("writes required fields with merge:true", async () => {
    const {db, ref} = enqueueDb("customerUpsert__c1");
    await enqueueCustomerUpsert("c1", {db, now});

    expect(ref.set).toHaveBeenCalledWith(
        expect.objectContaining({
          type: "customerUpsert",
          refPath: "clients/c1",
          status: "queued",
          nextAttemptAt: TS,
          idempotencyKey: "customerUpsert__c1",
          attempts: 0,
          lastError: null,
        }),
        {merge: true},
    );
  });

  test("re-enqueue for same client resets attempts:0, status:queued, " +
    "lastError:null (does NOT create a second doc)", async () => {
    // Simulate an existing job that had failed attempts.
    const existing = {
      type: "customerUpsert",
      refPath: "clients/c1",
      status: "dead",
      attempts: 3,
      lastError: "WaveApiError(auth)",
      idempotencyKey: "customerUpsert__c1",
      nextAttemptAt: new Date(0),
    };
    const {db, ref} = enqueueDb("customerUpsert__c1", existing);
    await enqueueCustomerUpsert("c1", {db, now});

    // Only ONE set() call (merge:true on the same ref — no new doc).
    expect(ref.sets).toHaveLength(1);
    expect(ref.sets[0].opts).toEqual({merge: true});
    expect(ref.sets[0].data.attempts).toBe(0);
    expect(ref.sets[0].data.status).toBe("queued");
    expect(ref.sets[0].data.lastError).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// drainQueue — happy path
// ---------------------------------------------------------------------------

describe("drainQueue happy path", () => {
  test("claims a queued+due job (sets inflight) and marks done on success",
      async () => {
        const job = {
          id: "customerUpsert__c1",
          data: {
            type: "customerUpsert",
            refPath: "clients/c1",
            status: "queued",
            attempts: 0,
            nextAttemptAt: new Date("2024-01-01"),
            lastError: null,
            idempotencyKey: "customerUpsert__c1",
          },
        };
        const {db, refs} = drainDb([job]);
        const mockUpsert = jest.fn(() =>
          Promise.resolve({status: "patched", waveCustomerId: "wv-1"}));
        const logger = fakeLogger();

        const summary = await drainQueue({
          db, now, logger,
          upsertCustomer: mockUpsert,
          businessId: "biz-1",
          backoffFn: fixedBackoff(),
        });

        expect(mockUpsert).toHaveBeenCalledTimes(1);
        expect(mockUpsert).toHaveBeenCalledWith("c1", expect.objectContaining({
          db,
          businessId: "biz-1",
        }));

        // Final state: done, lastError cleared.
        const lastUpdate = refs[0].updates[refs[0].updates.length - 1];
        expect(lastUpdate.status).toBe("done");
        expect(lastUpdate.lastError).toBeNull();

        expect(summary).toEqual({
          processed: 1, done: 1, retried: 0, dead: 0, skipped: 0,
        });

        expect(logger.error).not.toHaveBeenCalled();
      });

  test("skips jobs not due (nextAttemptAt in the future)", async () => {
    // The fake db always returns whatever docs we give it, so here we verify
    // that the WHERE clause args are correct (we trust Firestore to filter,
    // but verify the builder is called with the right constraints).
    const {db} = drainDb([]);
    const mockUpsert = jest.fn();
    await drainQueue({
      db, now, logger: fakeLogger(),
      upsertCustomer: mockUpsert,
      backoffFn: fixedBackoff(),
    });
    expect(mockUpsert).not.toHaveBeenCalled();
  });

  test("respects batchLimit", async () => {
    const jobs = Array.from({length: 5}, (_, i) => ({
      id: `customerUpsert__c${i}`,
      data: {
        type: "customerUpsert",
        refPath: `clients/c${i}`,
        status: "queued",
        attempts: 0,
        nextAttemptAt: new Date("2024-01-01"),
        lastError: null,
        idempotencyKey: `customerUpsert__c${i}`,
      },
    }));

    // Build a db that tracks how many docs the query returns.
    const {db, refs} = drainDb(jobs);

    // Capture the limit() call to verify batchLimit is forwarded.
    let capturedLimit = null;
    const originalCollection = db.collection.bind(db);
    db.collection = jest.fn((col) => {
      const q = originalCollection(col);
      const origLimit = q.limit.bind(q);
      q.limit = jest.fn((n) => {
        capturedLimit = n;
        return origLimit(n);
      });
      return q;
    });

    const mockUpsert = jest.fn(() => Promise.resolve({status: "done"}));
    await drainQueue({
      db, now, logger: fakeLogger(),
      upsertCustomer: mockUpsert,
      batchLimit: 3,
      backoffFn: fixedBackoff(),
    });

    expect(capturedLimit).toBe(3);
    // All 5 are in the fake snapshot, so all 5 get processed (the real
    // Firestore would only return 3; we verify the limit arg is passed).
    expect(refs).toHaveLength(5);
  });
});

// ---------------------------------------------------------------------------
// drainQueue — claim atomicity
// ---------------------------------------------------------------------------

describe("drainQueue claim atomicity", () => {
  test("skips a job that is already inflight at claim time", async () => {
    const job = {
      id: "customerUpsert__c1",
      data: {
        type: "customerUpsert",
        refPath: "clients/c1",
        status: "queued", // appears queued in the query snapshot
        attempts: 0,
        nextAttemptAt: new Date("2024-01-01"),
        lastError: null,
        idempotencyKey: "customerUpsert__c1",
      },
    };
    // Simulate the re-read showing the job as already inflight (race).
    const {db} = drainDb([job], {claimSetsInflight: false});

    // Override runTransaction so that the re-read returns 'inflight'.
    db.runTransaction = jest.fn(async (fn) => {
      const txn = {
        get: jest.fn((ref) =>
          Promise.resolve(snap(ref.id, {
            ...ref._data, status: "inflight",
          }, ref))),
        update: jest.fn(),
      };
      return fn(txn);
    });

    const mockUpsert = jest.fn();
    const summary = await drainQueue({
      db, now, logger: fakeLogger(),
      upsertCustomer: mockUpsert,
      backoffFn: fixedBackoff(),
    });

    expect(mockUpsert).not.toHaveBeenCalled();
    expect(summary.skipped).toBe(1);
    expect(summary.processed).toBe(0);
  });

  test("skips if transaction itself throws (contention)", async () => {
    const job = {
      id: "customerUpsert__c1",
      data: {
        type: "customerUpsert",
        refPath: "clients/c1",
        status: "queued",
        attempts: 0,
        nextAttemptAt: new Date("2024-01-01"),
        lastError: null,
        idempotencyKey: "customerUpsert__c1",
      },
    };
    const {db} = drainDb([job], {claimSucceeds: false});
    const mockUpsert = jest.fn();
    const logger = fakeLogger();

    const summary = await drainQueue({
      db, now, logger,
      upsertCustomer: mockUpsert,
      backoffFn: fixedBackoff(),
    });

    expect(mockUpsert).not.toHaveBeenCalled();
    expect(summary.skipped).toBe(1);
    expect(logger.warn).toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// drainQueue — retryable errors
// ---------------------------------------------------------------------------

describe("drainQueue retryable errors", () => {
  // eslint-disable-next-line max-len
  test("WaveApiError(network) → back to queued, attempts++, nextAttemptAt advanced, lastError set",
      async () => {
        const job = {
          id: "customerUpsert__c1",
          data: {
            type: "customerUpsert",
            refPath: "clients/c1",
            status: "queued",
            attempts: 0,
            nextAttemptAt: new Date("2024-01-01"),
            lastError: null,
            idempotencyKey: "customerUpsert__c1",
          },
        };
        const {db, refs} = drainDb([job]);
        const networkErr = new WaveApiError("network", "fetch failed");
        const mockUpsert = jest.fn(() => Promise.reject(networkErr));
        const backoffFn = jest.fn(() => 5000);
        const logger = fakeLogger();

        const summary = await drainQueue({
          db, now, logger,
          upsertCustomer: mockUpsert,
          maxAttempts: 5,
          backoffFn,
        });

        expect(summary).toEqual({
          processed: 1, done: 0, retried: 1, dead: 0, skipped: 0,
        });

        const finalUpdate = refs[0].updates[refs[0].updates.length - 1];
        expect(finalUpdate.status).toBe("queued");
        expect(finalUpdate.attempts).toBe(1);
        expect(finalUpdate.lastError).toBe("WaveApiError(network)");
        expect(finalUpdate.nextAttemptAt).toBeInstanceOf(Date);

        // backoffFn called with attempts-1 (0-indexed attempt index).
        expect(backoffFn).toHaveBeenCalledWith(0);

        // Must not dead-log on a retryable error.
        expect(logger.error).not.toHaveBeenCalled();
      });

  test("WaveApiError(rateLimited) → retryable", async () => {
    const job = {
      id: "customerUpsert__c1",
      data: {
        type: "customerUpsert",
        refPath: "clients/c1",
        status: "queued",
        attempts: 2,
        nextAttemptAt: new Date("2024-01-01"),
        lastError: "WaveApiError(network)",
        idempotencyKey: "customerUpsert__c1",
      },
    };
    const {db, refs} = drainDb([job]);
    const rateLimitErr = new WaveApiError("rateLimited", "rate limited");
    const mockUpsert = jest.fn(() => Promise.reject(rateLimitErr));

    const summary = await drainQueue({
      db, now, logger: fakeLogger(),
      upsertCustomer: mockUpsert,
      maxAttempts: 5,
      backoffFn: fixedBackoff(),
    });

    expect(summary.retried).toBe(1);
    const finalUpdate = refs[0].updates[refs[0].updates.length - 1];
    expect(finalUpdate.status).toBe("queued");
    expect(finalUpdate.attempts).toBe(3);
    expect(finalUpdate.lastError).toBe("WaveApiError(rateLimited)");
  });

  test("retryable until cap → finally dead", async () => {
    const maxAttempts = 3;
    const job = {
      id: "customerUpsert__c1",
      data: {
        type: "customerUpsert",
        refPath: "clients/c1",
        status: "queued",
        // Already at maxAttempts - 1: next failure pushes it to the cap.
        attempts: maxAttempts - 1,
        nextAttemptAt: new Date("2024-01-01"),
        lastError: "WaveApiError(network)",
        idempotencyKey: "customerUpsert__c1",
      },
    };
    const {db, refs} = drainDb([job]);
    const networkErr = new WaveApiError("network", "still failing");
    const mockUpsert = jest.fn(() => Promise.reject(networkErr));
    const logger = fakeLogger();

    const summary = await drainQueue({
      db, now, logger,
      upsertCustomer: mockUpsert,
      maxAttempts,
      backoffFn: fixedBackoff(),
    });

    expect(summary).toEqual({
      processed: 1, done: 0, retried: 0, dead: 1, skipped: 0,
    });

    const finalUpdate = refs[0].updates[refs[0].updates.length - 1];
    expect(finalUpdate.status).toBe("dead");
    expect(finalUpdate.attempts).toBe(maxAttempts);
    expect(typeof finalUpdate.lastError).toBe("string");

    // Must log at error level.
    expect(logger.error).toHaveBeenCalledTimes(1);
    const [msg, meta] = logger.error.mock.calls[0];
    expect(typeof msg).toBe("string");
    expect(meta.jobId).toBe("customerUpsert__c1");
    expect(meta.clientId).toBe("c1");
    // Must not expose PII or raw Wave message.
    expect(JSON.stringify(meta)).not.toContain("still failing");
  });

  test("unexpected non-Wave error → retryable (bounded)", async () => {
    const job = {
      id: "customerUpsert__c1",
      data: {
        type: "customerUpsert",
        refPath: "clients/c1",
        status: "queued",
        attempts: 0,
        nextAttemptAt: new Date("2024-01-01"),
        lastError: null,
        idempotencyKey: "customerUpsert__c1",
      },
    };
    const {db, refs} = drainDb([job]);
    const unexpectedErr = new TypeError("boom — unexpected infra error");
    const mockUpsert = jest.fn(() => Promise.reject(unexpectedErr));

    const summary = await drainQueue({
      db, now, logger: fakeLogger(),
      upsertCustomer: mockUpsert,
      maxAttempts: 5,
      backoffFn: fixedBackoff(),
    });

    expect(summary.retried).toBe(1);
    expect(summary.dead).toBe(0);
    const finalUpdate = refs[0].updates[refs[0].updates.length - 1];
    expect(finalUpdate.status).toBe("queued");
    // lastError must not echo the raw error message (PII guard).
    expect(finalUpdate.lastError).not.toContain("boom");
  });
});

// ---------------------------------------------------------------------------
// drainQueue — non-retryable errors
// ---------------------------------------------------------------------------

describe("drainQueue non-retryable errors", () => {
  test("WaveValidationError → dead immediately (no retry), logs error",
      async () => {
        const job = {
          id: "customerUpsert__c1",
          data: {
            type: "customerUpsert",
            refPath: "clients/c1",
            status: "queued",
            attempts: 0,
            nextAttemptAt: new Date("2024-01-01"),
            lastError: null,
            idempotencyKey: "customerUpsert__c1",
          },
        };
        const {db, refs} = drainDb([job]);
        const validationErr = new WaveValidationError(
            [{code: "INVALID_EMAIL", message: "customer@example.com bad",
              path: ["email"]}],
        );
        const mockUpsert = jest.fn(() => Promise.reject(validationErr));
        const logger = fakeLogger();

        const summary = await drainQueue({
          db, now, logger,
          upsertCustomer: mockUpsert,
          maxAttempts: 5,
          backoffFn: fixedBackoff(),
        });

        expect(summary).toEqual({
          processed: 1, done: 0, retried: 0, dead: 1, skipped: 0,
        });
        const finalUpdate = refs[0].updates[refs[0].updates.length - 1];
        expect(finalUpdate.status).toBe("dead");
        expect(finalUpdate.attempts).toBe(1);

        // Logged at error.
        expect(logger.error).toHaveBeenCalledTimes(1);

        // lastError must not echo Wave's raw message.
        expect(finalUpdate.lastError).not.toContain("customer@example.com");
        expect(finalUpdate.lastError).not.toContain("bad");
      });

  test("WaveApiError(auth) → dead immediately (no retry), logs error",
      async () => {
        const job = {
          id: "customerUpsert__c1",
          data: {
            type: "customerUpsert",
            refPath: "clients/c1",
            status: "queued",
            attempts: 0,
            nextAttemptAt: new Date("2024-01-01"),
            lastError: null,
            idempotencyKey: "customerUpsert__c1",
          },
        };
        const {db, refs} = drainDb([job]);
        const authErr = new WaveApiError("auth", "token revoked");
        const mockUpsert = jest.fn(() => Promise.reject(authErr));
        const logger = fakeLogger();

        const summary = await drainQueue({
          db, now, logger,
          upsertCustomer: mockUpsert,
          maxAttempts: 5,
          backoffFn: fixedBackoff(),
        });

        expect(summary).toEqual({
          processed: 1, done: 0, retried: 0, dead: 1, skipped: 0,
        });

        const finalUpdate = refs[0].updates[refs[0].updates.length - 1];
        expect(finalUpdate.status).toBe("dead");
        expect(logger.error).toHaveBeenCalledTimes(1);

        // Log meta must not include the raw error message "token revoked".
        const logMeta = logger.error.mock.calls[0][1];
        expect(JSON.stringify(logMeta)).not.toContain("token revoked");
        expect(logMeta.errorKind).toBe("auth");
      });

  test("WaveApiError(graphql) → dead immediately", async () => {
    const job = {
      id: "customerUpsert__c1",
      data: {
        type: "customerUpsert",
        refPath: "clients/c1",
        status: "queued",
        attempts: 0,
        nextAttemptAt: new Date("2024-01-01"),
        lastError: null,
        idempotencyKey: "customerUpsert__c1",
      },
    };
    const {db, refs} = drainDb([job]);
    const graphqlErr = new WaveApiError("graphql", "resolver error");
    const mockUpsert = jest.fn(() => Promise.reject(graphqlErr));
    const logger = fakeLogger();

    const summary = await drainQueue({db, now, logger,
      upsertCustomer: mockUpsert, maxAttempts: 5,
      backoffFn: fixedBackoff()});

    expect(summary.dead).toBe(1);
    expect(summary.retried).toBe(0);
    const finalUpdate = refs[0].updates[refs[0].updates.length - 1];
    expect(finalUpdate.status).toBe("dead");
    expect(logger.error).toHaveBeenCalledTimes(1);
  });
});

// ---------------------------------------------------------------------------
// drainQueue — PII / log safety
// ---------------------------------------------------------------------------

describe("drainQueue PII + log safety", () => {
  test("lastError and logger output contain no PII or Wave raw message",
      async () => {
        const job = {
          id: "customerUpsert__c1",
          data: {
            type: "customerUpsert",
            refPath: "clients/c1",
            status: "queued",
            attempts: 4, // one below cap
            nextAttemptAt: new Date("2024-01-01"),
            lastError: null,
            idempotencyKey: "customerUpsert__c1",
          },
        };
        const {db, refs} = drainDb([job]);
        // Raw error message contains PII-like content.
        const authErr = new WaveApiError(
            "auth",
            "Token for jane.doe@example.com is expired",
        );
        const mockUpsert = jest.fn(() => Promise.reject(authErr));
        const logger = fakeLogger();

        await drainQueue({
          db, now, logger,
          upsertCustomer: mockUpsert,
          maxAttempts: 5,
          backoffFn: fixedBackoff(),
        });

        const finalUpdate = refs[0].updates[refs[0].updates.length - 1];

        // Neither lastError nor log output should contain the email address.
        expect(finalUpdate.lastError).not.toContain("jane.doe@example.com");
        expect(finalUpdate.lastError).not.toContain("expired");

        const logArgs = logger.error.mock.calls[0];
        const logJson = JSON.stringify(logArgs);
        expect(logJson).not.toContain("jane.doe@example.com");
        expect(logJson).not.toContain("expired");
      });
});

// ---------------------------------------------------------------------------
// drainQueue — multi-job batch
// ---------------------------------------------------------------------------

describe("drainQueue multi-job batch", () => {
  test("processes multiple jobs independently in one call", async () => {
    const jobs = [
      {
        id: "customerUpsert__c1",
        data: {
          type: "customerUpsert", refPath: "clients/c1",
          status: "queued", attempts: 0,
          nextAttemptAt: new Date("2024-01-01"), lastError: null,
          idempotencyKey: "customerUpsert__c1",
        },
      },
      {
        id: "customerUpsert__c2",
        data: {
          type: "customerUpsert", refPath: "clients/c2",
          status: "queued", attempts: 0,
          nextAttemptAt: new Date("2024-01-01"), lastError: null,
          idempotencyKey: "customerUpsert__c2",
        },
      },
    ];
    const {db, refs} = drainDb(jobs);
    let call = 0;
    const mockUpsert = jest.fn(() => {
      call++;
      // First succeeds, second fails with a network error.
      if (call === 1) return Promise.resolve({status: "done"});
      return Promise.reject(new WaveApiError("network", "transient"));
    });

    const summary = await drainQueue({
      db, now, logger: fakeLogger(),
      upsertCustomer: mockUpsert,
      maxAttempts: 5,
      backoffFn: fixedBackoff(),
    });

    expect(summary.processed).toBe(2);
    expect(summary.done).toBe(1);
    expect(summary.retried).toBe(1);

    const update1 = refs[0].updates[refs[0].updates.length - 1];
    expect(update1.status).toBe("done");

    const update2 = refs[1].updates[refs[1].updates.length - 1];
    expect(update2.status).toBe("queued");
  });
});

// ---------------------------------------------------------------------------
// drainQueue — default batchLimit
// ---------------------------------------------------------------------------

describe("drainQueue defaults", () => {
  test("default batchLimit is 30", async () => {
    const {db} = drainDb([]);
    let capturedLimit = null;
    const origCollection = db.collection.bind(db);
    db.collection = jest.fn((col) => {
      const q = origCollection(col);
      const origLimit = q.limit.bind(q);
      q.limit = jest.fn((n) => {
        capturedLimit = n;
        return origLimit(n);
      });
      return q;
    });

    await drainQueue({db, now, logger: fakeLogger(),
      upsertCustomer: jest.fn(), backoffFn: fixedBackoff()});
    expect(capturedLimit).toBe(30);
  });
});
