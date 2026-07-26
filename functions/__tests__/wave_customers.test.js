"use strict";

const {
  WaveValidationError,
  upsertCustomer,
  importCustomers,
  sanitizeInputErrors,
} = require("../wave/customers");
const {WaveApiError} = require("../wave/client");
const {mappedFieldsHash} = require("../wave/mappers");

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

// Stable serverTimestamp sentinel so writes are assertable.
const TS = {__serverTimestamp: true};
const now = () => TS;

/**
 * Fake client document snapshot.
 * @param {Object|null} data Document data, or null for a missing doc.
 * @return {!Object}
 */
function snap(data) {
  return {
    exists: data !== null,
    data: () => data,
  };
}

/**
 * Fake `clients/{id}` doc ref that records update() calls and serves
 * `freshData` (or `data` if unset) as the write-back re-read snapshot.
 * @param {Object|null} data Initial snapshot data.
 * @param {Object=} freshData Snapshot data for the write-back re-read.
 * @return {!Object}
 */
function clientRef(data, freshData) {
  const ref = {
    updates: [],
    _data: data,
    _fresh: freshData !== undefined ? freshData : data,
    get: jest.fn(() => Promise.resolve(snap(ref._data))),
  };
  // The transaction re-reads via tx.get(ref) — serve the fresh snapshot.
  ref._txGet = () => Promise.resolve(snap(ref._fresh));
  return ref;
}

/**
 * Minimal fake Firestore for upsert: a single clients/{id} ref + a
 * wave/connection doc, plus runTransaction.
 * @param {!Object} ref The clients doc ref from clientRef().
 * @param {Object=} opts Connection doc options (`businessId`).
 * @return {!Object}
 */
function upsertDb(ref, opts = {}) {
  const connectionData = opts.businessId !== undefined ?
    {businessId: opts.businessId} : {businessId: "biz-1"};
  return {
    collection: (name) => ({
      doc: (id) => {
        if (name === "clients") return ref;
        if (name === "wave" && id === "connection") {
          return {get: () => Promise.resolve(snap(connectionData))};
        }
        throw new Error(`unexpected doc ${name}/${id}`);
      },
    }),
    runTransaction: async (fn) => {
      const tx = {
        get: (r) => r._txGet(),
        update: (r, u) => r.updates.push(u),
        set: (r, u) => r.updates.push(u),
      };
      return fn(tx);
    },
  };
}

/** A representative full client doc (mapped fields). */
const CLIENT = {
  name: "Acme Corp",
  firstName: "Jane",
  lastName: "Doe",
  email: "jane@acme.com",
  phone: "514-555-1234",
  mobile: "514-555-9876",
  address: "3450 Main St",
  apt: "12",
  city: "Montreal",
  province: "QC",
  country: "Canada",
  postalCode: "H3Z 2Y7",
};

/**
 * Builds a graphql mock that returns each response in sequence and records the
 * mutation + variables of every call.
 * @param {...*} results Values to resolve in order (or Errors to reject).
 * @return {!Function} The mock graphql.
 */
function graphqlSeq(...results) {
  let i = 0;
  const fn = jest.fn((_query, _variables) => {
    const r = results[Math.min(i, results.length - 1)];
    i++;
    if (r instanceof Error) return Promise.reject(r);
    return Promise.resolve(r);
  });
  return fn;
}

// graphql `data` envelope builders for customerCreate / customerPatch.
const createOk = (id) => ({
  customerCreate: {
    didSucceed: true,
    inputErrors: [],
    customer: {id, name: "Acme Corp"},
  },
});

const createFail = (inputErrors) => ({
  customerCreate: {didSucceed: false, inputErrors, customer: null},
});

const patchOk = (id) => ({
  customerPatch: {
    didSucceed: true,
    inputErrors: [],
    customer: {id, name: "Acme Corp"},
  },
});

const patchFail = (inputErrors) => ({
  customerPatch: {didSucceed: false, inputErrors, customer: null},
});

// ---------------------------------------------------------------------------
// upsertCustomer — no-op
// ---------------------------------------------------------------------------

describe("upsertCustomer no-op", () => {
  test("linked + unchanged hash → noop, graphql not called", async () => {
    const hash = mappedFieldsHash(CLIENT);
    const data = {
      ...CLIENT,
      waveCustomerId: "wave-1",
      wave: {syncState: "synced", lastSyncedHash: hash},
    };
    const ref = clientRef(data);
    const graphql = jest.fn();
    const result = await upsertCustomer("c1", {
      db: upsertDb(ref), graphql, businessId: "biz-1", now,
    });
    expect(result).toEqual({status: "noop"});
    expect(graphql).not.toHaveBeenCalled();
    expect(ref.updates).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// upsertCustomer — patch
// ---------------------------------------------------------------------------

describe("upsertCustomer patch", () => {
  test("linked + changed field → patch with id, no businessId", async () => {
    const data = {
      ...CLIENT,
      waveCustomerId: "wave-1",
      wave: {syncState: "synced", lastSyncedHash: "stale-hash"},
    };
    const ref = clientRef(data);
    const graphql = graphqlSeq(patchOk("wave-1"));
    const result = await upsertCustomer("c1", {
      db: upsertDb(ref), graphql, businessId: "biz-1", now,
    });

    expect(result).toEqual({status: "patched", waveCustomerId: "wave-1"});
    expect(graphql).toHaveBeenCalledTimes(1);
    const [, vars] = graphql.mock.calls[0];
    expect(vars.input.id).toBe("wave-1");
    expect(vars.input).not.toHaveProperty("businessId");
    // Write-back sets synced state + hash, leaves the link untouched.
    expect(ref.updates).toHaveLength(1);
    const u = ref.updates[0];
    expect(u["wave.syncState"]).toBe("synced");
    expect(u["wave.lastSyncedHash"]).toBe(mappedFieldsHash(CLIENT));
    expect(u["wave.syncError"]).toBeNull();
    expect(u).not.toHaveProperty("waveCustomerId");
  });
});

// ---------------------------------------------------------------------------
// upsertCustomer — create
// ---------------------------------------------------------------------------

describe("upsertCustomer create", () => {
  test("unlinked → create, write-back sets id + synced + hash", async () => {
    const data = {...CLIENT}; // no waveCustomerId
    const ref = clientRef(data);
    const graphql = graphqlSeq(createOk("wave-new"));
    const result = await upsertCustomer("c1", {
      db: upsertDb(ref), graphql, businessId: "biz-1", now,
    });

    expect(result).toEqual({status: "created", waveCustomerId: "wave-new"});
    const [, vars] = graphql.mock.calls[0];
    expect(vars.input.businessId).toBe("biz-1");
    expect(ref.updates).toHaveLength(1);
    const u = ref.updates[0];
    expect(u.waveCustomerId).toBe("wave-new");
    expect(u["wave.syncState"]).toBe("synced");
    expect(u["wave.lastSyncedHash"]).toBe(mappedFieldsHash(CLIENT));
    expect(u["wave.lastSyncedAt"]).toBe(TS);
  });

  test("write-back guard: existing id not overwritten on create", async () => {
    const data = {...CLIENT};
    // By write-back time, a concurrent create already linked the doc.
    const fresh = {...CLIENT, waveCustomerId: "wave-concurrent"};
    const ref = clientRef(data, fresh);
    const graphql = graphqlSeq(createOk("wave-mine"));
    const result = await upsertCustomer("c1", {
      db: upsertDb(ref), graphql, businessId: "biz-1", now,
    });

    expect(result).toEqual({status: "created", waveCustomerId: "wave-mine"});
    const u = ref.updates[0];
    // Guard keeps the existing link, never overwrites it.
    expect(u).not.toHaveProperty("waveCustomerId");
    expect(u["wave.syncState"]).toBe("synced");
  });

  test("businessId read from wave/connection when not injected", async () => {
    const data = {...CLIENT};
    const ref = clientRef(data);
    const graphql = graphqlSeq(createOk("wave-new"));
    await upsertCustomer("c1", {
      db: upsertDb(ref, {businessId: "biz-from-doc"}), graphql, now,
    });
    const [, vars] = graphql.mock.calls[0];
    expect(vars.input.businessId).toBe("biz-from-doc");
  });

  test("write-back no-ops when doc deleted before txn (exists:false)",
      async () => {
        const data = {...CLIENT};
        // The write-back re-read returns a missing snapshot.
        const ref = clientRef(data, null);
        const graphql = graphqlSeq(createOk("wave-new"));
        // Should complete without throwing even though the doc is gone.
        const result = await upsertCustomer("c1", {
          db: upsertDb(ref), graphql, businessId: "biz-1", now,
        });
        expect(result).toEqual({status: "created", waveCustomerId: "wave-new"});
        // Guard skipped the update — no writes recorded.
        expect(ref.updates).toHaveLength(0);
      });
});

// ---------------------------------------------------------------------------
// upsertCustomer — validation failure
// ---------------------------------------------------------------------------

describe("upsertCustomer validation failure", () => {
  test("non-phone didSucceed:false → error state, throws, no retry",
      async () => {
        const data = {...CLIENT};
        const ref = clientRef(data);
        const inputErrors = [
          {code: "INVALID_EMAIL", message: "raw wave msg", path: ["email"]},
        ];
        const graphql = graphqlSeq(createFail(inputErrors));
        await expect(upsertCustomer("c1", {
          db: upsertDb(ref), graphql, businessId: "biz-1", now,
        })).rejects.toBeInstanceOf(WaveValidationError);

        // No retry: exactly one graphql call.
        expect(graphql).toHaveBeenCalledTimes(1);
        const u = ref.updates[0];
        expect(u["wave.syncState"]).toBe("error");
        // Sanitized — never Wave's raw message.
        expect(u["wave.syncError"]).not.toContain("raw wave msg");
        expect(u["wave.syncError"]).toContain("email");
      });

  test("WaveValidationError carries inputErrors and retryable=false",
      async () => {
        const data = {...CLIENT};
        const ref = clientRef(data);
        const inputErrors = [{code: "MISSING_REQUIRED", path: ["name"]}];
        const graphql = graphqlSeq(createFail(inputErrors));
        let caught;
        try {
          await upsertCustomer("c1", {
            db: upsertDb(ref), graphql, businessId: "biz-1", now,
          });
        } catch (e) {
          caught = e;
        }
        expect(caught).toBeInstanceOf(WaveValidationError);
        expect(caught.retryable).toBe(false);
        expect(caught.inputErrors).toEqual(inputErrors);
      });
});

// ---------------------------------------------------------------------------
// upsertCustomer — phone/mobile create fallback
// ---------------------------------------------------------------------------

describe("upsertCustomer phone/mobile create fallback", () => {
  test("phone-rejected create → retry without phone, then patch, synced",
      async () => {
        const data = {...CLIENT};
        const ref = clientRef(data);
        const phoneErrors = [
          {code: "GENERIC_ERROR", message: "bad", path: ["phone"]},
          {code: "GENERIC_ERROR", message: "bad", path: ["mobile"]},
        ];
        // Create with phone fails, then create without phone succeeds, then patches
        // the phone onto the new id.
        const graphql = graphqlSeq(
            createFail(phoneErrors),
            createOk("wave-new"),
            patchOk("wave-new"),
        );
        const result = await upsertCustomer("c1", {
          db: upsertDb(ref), graphql, businessId: "biz-1", now,
        });

        expect(result).toEqual({status: "created", waveCustomerId: "wave-new"});
        expect(graphql).toHaveBeenCalledTimes(3);

        // Call 1: create WITH phone/mobile.
        expect(graphql.mock.calls[0][1].input).toHaveProperty("phone");
        // Call 2: create WITHOUT phone/mobile.
        const retryInput = graphql.mock.calls[1][1].input;
        expect(retryInput).not.toHaveProperty("phone");
        expect(retryInput).not.toHaveProperty("mobile");
        expect(retryInput.businessId).toBe("biz-1");
        // Call 3: patch phone/mobile onto the new id.
        const patchInput = graphql.mock.calls[2][1].input;
        expect(patchInput.id).toBe("wave-new");
        expect(patchInput.phone).toBe(CLIENT.phone);
        expect(patchInput.mobile).toBe(CLIENT.mobile);

        // Final state synced.
        const u = ref.updates[0];
        expect(u["wave.syncState"]).toBe("synced");
        expect(u.waveCustomerId).toBe("wave-new");
      });

  test("phone patch fails → synced hash excludes phone (retries later)",
      async () => {
        const data = {...CLIENT};
        const ref = clientRef(data);
        const phoneErrors = [
          {code: "GENERIC_ERROR", message: "bad", path: ["phone"]},
        ];
        // create-with-phone fails, create-without-phone OK, phone patch FAILS.
        const graphql = graphqlSeq(
            createFail(phoneErrors),
            createOk("wave-new"),
            patchFail(phoneErrors),
        );
        const result = await upsertCustomer("c1", {
          db: upsertDb(ref), graphql, businessId: "biz-1", now,
        });

        expect(result).toEqual({status: "created", waveCustomerId: "wave-new"});
        const u = ref.updates[0];
        // The customer ends up linked and synced, but the recorded hash
        // reflects what actually reached Wave — without the phone. That way
        // a later upsert notices the difference and retries the phone
        // instead of treating it as done forever.
        expect(u["wave.syncState"]).toBe("synced");
        expect(u["wave.lastSyncedHash"]).toBe(
            mappedFieldsHash({...CLIENT, phone: "", mobile: ""}),
        );
        expect(u["wave.lastSyncedHash"]).not.toBe(mappedFieldsHash(CLIENT));
      });

  test("mixed errors (phone + email) → not treated as phone fallback",
      async () => {
        const data = {...CLIENT};
        const ref = clientRef(data);
        const mixed = [
          {code: "GENERIC_ERROR", path: ["phone"]},
          {code: "INVALID_EMAIL", path: ["email"]},
        ];
        const graphql = graphqlSeq(createFail(mixed));
        await expect(upsertCustomer("c1", {
          db: upsertDb(ref), graphql, businessId: "biz-1", now,
        })).rejects.toBeInstanceOf(WaveValidationError);
        // No retry — a non-phone error is present.
        expect(graphql).toHaveBeenCalledTimes(1);
      });
});

// ---------------------------------------------------------------------------
// upsertCustomer — crash-retry create idempotency (F2)
// ---------------------------------------------------------------------------

describe("upsertCustomer crash-retry create idempotency", () => {
  // A Wave list page whose node matches CLIENT's identity (name + email).
  const matchingNode = {
    id: "wave-existing",
    name: "Acme Corp",
    firstName: "Jane",
    lastName: "Doe",
    email: "jane@acme.com",
    phone: "",
    mobile: "",
    isArchived: false,
    address: null,
  };

  const listPage1 = (nodes) => ({
    business: {
      customers: {
        pageInfo: {currentPage: 1, totalPages: 1, totalCount: nodes.length},
        edges: nodes.map((node) => ({node})),
      },
    },
  });

  test("priorAttempts > 0 + matching Wave customer → linked (patched), " +
    "NO duplicate create", async () => {
    const data = {...CLIENT}; // unlinked
    const ref = clientRef(data);
    // LIST_CUSTOMERS returns the match, then patches it with current fields.
    const graphql = graphqlSeq(
        listPage1([matchingNode]),
        patchOk("wave-existing"),
    );
    const result = await upsertCustomer("c1", {
      db: upsertDb(ref), graphql, businessId: "biz-1", now,
      priorAttempts: 1,
    });

    expect(result).toEqual({status: "linked", waveCustomerId: "wave-existing"});
    expect(graphql).toHaveBeenCalledTimes(2);
    // First call is the list query (has page vars, no input).
    expect(graphql.mock.calls[0][1]).toEqual(
        expect.objectContaining({id: "biz-1", page: 1}));
    // Second call patches the FOUND id with the doc's current fields.
    const patchInput = graphql.mock.calls[1][1].input;
    expect(patchInput.id).toBe("wave-existing");
    expect(patchInput.name).toBe("Acme Corp");
    expect(patchInput).not.toHaveProperty("businessId");
    // Write-back links the found customer.
    const u = ref.updates[0];
    expect(u.waveCustomerId).toBe("wave-existing");
    expect(u["wave.syncState"]).toBe("synced");
  });

  test("priorAttempts > 0 but no match → create proceeds normally",
      async () => {
        const data = {...CLIENT};
        const ref = clientRef(data);
        const graphql = graphqlSeq(
            listPage1([{...matchingNode, email: "someone-else@x.com"}]),
            createOk("wave-new"),
        );
        const result = await upsertCustomer("c1", {
          db: upsertDb(ref), graphql, businessId: "biz-1", now,
          priorAttempts: 2,
        });

        expect(result).toEqual({status: "created", waveCustomerId: "wave-new"});
        // Call 2 is the create (carries businessId).
        expect(graphql.mock.calls[1][1].input.businessId).toBe("biz-1");
      });

  test("archived match is ignored (not linked)", async () => {
    const data = {...CLIENT};
    const ref = clientRef(data);
    const graphql = graphqlSeq(
        listPage1([{...matchingNode, isArchived: true}]),
        createOk("wave-new"),
    );
    const result = await upsertCustomer("c1", {
      db: upsertDb(ref), graphql, businessId: "biz-1", now,
      priorAttempts: 1,
    });
    expect(result.status).toBe("created");
  });

  test("first attempt (priorAttempts 0/absent) → NO Wave search before " +
    "create", async () => {
    const data = {...CLIENT};
    const ref = clientRef(data);
    const graphql = graphqlSeq(createOk("wave-new"));
    const result = await upsertCustomer("c1", {
      db: upsertDb(ref), graphql, businessId: "biz-1", now,
    });

    expect(result).toEqual({status: "created", waveCustomerId: "wave-new"});
    expect(graphql).toHaveBeenCalledTimes(1);
    // The single call is the create, not a list.
    expect(graphql.mock.calls[0][1].input.businessId).toBe("biz-1");
  });

  test("retry of a LINKED doc is unaffected (patch path, no search)",
      async () => {
        const data = {
          ...CLIENT,
          waveCustomerId: "wave-1",
          wave: {syncState: "synced", lastSyncedHash: "stale"},
        };
        const ref = clientRef(data);
        const graphql = graphqlSeq(patchOk("wave-1"));
        const result = await upsertCustomer("c1", {
          db: upsertDb(ref), graphql, businessId: "biz-1", now,
          priorAttempts: 3,
        });
        expect(result).toEqual({status: "patched", waveCustomerId: "wave-1"});
        expect(graphql).toHaveBeenCalledTimes(1);
      });
});

// ---------------------------------------------------------------------------
// upsertCustomer — transport error propagation
// ---------------------------------------------------------------------------

describe("upsertCustomer transport errors", () => {
  test("WaveApiError(network) propagates unchanged", async () => {
    const data = {...CLIENT};
    const ref = clientRef(data);
    const transport = new WaveApiError("network", "boom");
    const graphql = graphqlSeq(transport);
    let caught;
    try {
      await upsertCustomer("c1", {
        db: upsertDb(ref), graphql, businessId: "biz-1", now,
      });
    } catch (e) {
      caught = e;
    }
    expect(caught).toBe(transport);
    expect(caught).toBeInstanceOf(WaveApiError);
    expect(caught.kind).toBe("network");
    // No write-back on transport failure.
    expect(ref.updates).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// upsertCustomer — missing doc
// ---------------------------------------------------------------------------

describe("upsertCustomer missing doc", () => {
  test("missing client doc → skipped, no graphql call", async () => {
    const ref = clientRef(null);
    const graphql = jest.fn();
    const result = await upsertCustomer("gone", {
      db: upsertDb(ref), graphql, businessId: "biz-1", now,
    });
    expect(result).toEqual({status: "skipped", reason: "missing-doc"});
    expect(graphql).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// not connected (wave/connection businessId missing)
// ---------------------------------------------------------------------------

describe("not connected (missing businessId)", () => {
  test("upsertCustomer rejects when no injected or stored businessId",
      async () => {
        const ref = clientRef({...CLIENT});
        const graphql = jest.fn();
        await expect(
            upsertCustomer("c1", {
              db: upsertDb(ref, {businessId: ""}), graphql, now,
            }),
        ).rejects.toThrow(/not connected/);
        expect(graphql).not.toHaveBeenCalled();
      });

  test("importCustomers rejects when no injected or stored businessId",
      async () => {
        const {db} = importDb([], {businessId: ""});
        const graphql = jest.fn();
        await expect(
            importCustomers({db, graphql, now}),
        ).rejects.toThrow(/not connected/);
        expect(graphql).not.toHaveBeenCalled();
      });
});

// ---------------------------------------------------------------------------
// importCustomers
// ---------------------------------------------------------------------------

/**
 * Builds a fake batch that records set() ops and counts commits.
 * @param {{sets: !Array, commits: number[]}} log Shared mutable log.
 * @return {!Object}
 */
function fakeBatch(log) {
  return {
    set: (ref, data, opts) => log.sets.push({ref, data, opts}),
    update: (ref, data) => log.sets.push({ref, data, update: true}),
    commit: () => {
      log.commits.push(log.sets.length);
      return Promise.resolve();
    },
  };
}

/**
 * Fake Firestore for import: a clients collection whose .get() returns
 * existing docs, .doc() mints auto-id refs, and batches are recorded.
 * @param {!Array<Object>} existingDocs Pre-existing client docs (with .data /
 *   .ref).
 * @param {Object=} opts Connection options (`businessId`).
 * @return {!Object} `{db, batchLog, newRefs}`.
 */
function importDb(existingDocs, opts = {}) {
  const batchLog = {sets: [], commits: []};
  const newRefs = [];
  let autoId = 0;
  // This mirrors upsertDb — an explicit "" still needs to reach
  // readBusinessId as not-connected, so we only fall back to "biz-1" when
  // businessId is left out entirely.
  const connectionData = opts.businessId !== undefined ?
    {businessId: opts.businessId} : {businessId: "biz-1"};
  const waveColl = {
    doc: () => ({get: () => Promise.resolve(snap(connectionData))}),
  };
  const db = {
    collection: (name) => {
      if (name === "clients") {
        return {
          get: () => Promise.resolve({docs: existingDocs}),
          doc: () => {
            const ref = {id: `auto-${autoId++}`};
            newRefs.push(ref);
            return ref;
          },
        };
      }
      if (name === "wave") return waveColl;
      throw new Error(`unexpected collection ${name}`);
    },
    batch: () => fakeBatch(batchLog),
  };
  return {db, batchLog, newRefs};
}

// Builds a Wave list-customers page envelope.
const listPage = (currentPage, totalPages, totalCount, nodes) => ({
  business: {
    customers: {
      pageInfo: {currentPage, totalPages, totalCount},
      edges: nodes.map((node) => ({node})),
    },
  },
});

/**
 * A Wave customer node.
 * @param {string} id Wave id.
 * @param {string} name Customer name.
 * @param {Object=} extra Field overrides.
 * @return {!Object}
 */
function waveNode(id, name, extra = {}) {
  return {
    id,
    name,
    firstName: "",
    lastName: "",
    email: `${name}@x.com`,
    phone: "",
    mobile: "",
    isArchived: false,
    address: null,
    ...extra,
  };
}

describe("importCustomers", () => {
  test("paginates 2 pages, skips archived, batches, returns summary",
      async () => {
        const {db, batchLog, newRefs} = importDb([]);
        const graphql = graphqlSeq(
            listPage(1, 2, 3, [
              waveNode("w1", "Alpha"),
              waveNode("w2", "Beta", {isArchived: true}),
            ]),
            listPage(2, 2, 3, [waveNode("w3", "Gamma")]),
        );
        const summary = await importCustomers({
          db, graphql, businessId: "biz-1", pageSize: 100, now,
        });

        expect(graphql).toHaveBeenCalledTimes(2);
        // Page args advance 1 → 2.
        expect(graphql.mock.calls[0][1].page).toBe(1);
        expect(graphql.mock.calls[1][1].page).toBe(2);

        expect(summary).toEqual({
          totalCount: 3,
          imported: 2, // Alpha + Gamma
          updated: 0,
          skippedArchived: 1, // Beta
          pages: 2,
        });
        // Two new auto-id docs created; one final commit.
        expect(newRefs).toHaveLength(2);
        expect(batchLog.commits).toHaveLength(1);
        // Each set carries the synced wave sub-map + the waveCustomerId.
        const first = batchLog.sets[0];
        expect(first.data.waveCustomerId).toBe("w1");
        expect(first.data.wave.syncState).toBe("synced");
        expect(first.data.wave.lastSyncedHash).toEqual(expect.any(String));
        // New docs MUST carry createdAt/updatedAt — the clients list orders by
        // createdAt and Firestore hides docs missing it.
        expect(first.data.createdAt).toBe(TS);
        expect(first.data.updatedAt).toBe(TS);
      });

  test("idempotent: existing waveCustomerId updates same ref, no duplicate",
      async () => {
        const existingRef = {id: "existing-doc"};
        const existingDoc = {
          data: () => ({waveCustomerId: "w1", name: "Old"}),
          ref: existingRef,
        };
        const {db, batchLog, newRefs} = importDb([existingDoc]);
        const graphql = graphqlSeq(
            listPage(1, 1, 1, [waveNode("w1", "Alpha")]),
        );
        const summary = await importCustomers({
          db, graphql, businessId: "biz-1", now,
        });

        expect(summary.updated).toBe(1);
        expect(summary.imported).toBe(0);
        // No new doc minted — the existing ref is reused.
        expect(newRefs).toHaveLength(0);
        const op = batchLog.sets[0];
        expect(op.ref).toBe(existingRef);
        expect(op.opts).toEqual({merge: true});
        expect(op.data.name).toBe("Alpha");
        // updatedAt is always refreshed. createdAt gets backfilled too, since
        // the existing doc didn't have one — otherwise an earlier import
        // that omitted it would stay hidden forever.
        expect(op.data.updatedAt).toBe(TS);
        expect(op.data.createdAt).toBe(TS);
      });

  test("update preserves an existing createdAt (no overwrite)",
      async () => {
        const existingRef = {id: "existing-doc"};
        const existingDoc = {
          data: () => ({
            waveCustomerId: "w1",
            name: "Old",
            createdAt: {__earlier: true},
          }),
          ref: existingRef,
        };
        const {db, batchLog} = importDb([existingDoc]);
        const graphql = graphqlSeq(
            listPage(1, 1, 1, [waveNode("w1", "Alpha")]),
        );
        await importCustomers({db, graphql, businessId: "biz-1", now});

        const op = batchLog.sets[0];
        // createdAt is left untouched; only updatedAt is refreshed.
        expect(op.data).not.toHaveProperty("createdAt");
        expect(op.data.updatedAt).toBe(TS);
      });

  test("reads businessId from wave/connection when not injected", async () => {
    const {db} = importDb([], {businessId: "biz-xyz"});
    const graphql = graphqlSeq(listPage(1, 1, 0, []));
    await importCustomers({db, graphql, now});
    expect(graphql.mock.calls[0][1].id).toBe("biz-xyz");
  });
});

// ---------------------------------------------------------------------------
// sanitizeInputErrors
// ---------------------------------------------------------------------------
// Wave's raw `message` text must never reach our UI or logs — we only ever
// surface messages mapped from a known `code`.
describe("sanitizeInputErrors", () => {
  test("maps a known code to its safe message", () => {
    expect(sanitizeInputErrors([{code: "INVALID_EMAIL"}]))
        .toBe("The customer email address is not valid.");
  });

  test("never echoes Wave's raw message text", () => {
    const raw = "secret-internal-detail-from-wave";
    const out = sanitizeInputErrors([{code: "INVALID_EMAIL", message: raw}]);
    expect(out).not.toContain(raw);
  });

  test("falls back to the generic message for an unknown code", () => {
    expect(sanitizeInputErrors([{code: "SOMETHING_NEW"}]))
        .toBe("Wave rejected the customer data.");
  });

  test("joins distinct codes and de-duplicates repeats", () => {
    const out = sanitizeInputErrors([
      {code: "TOO_LONG"},
      {code: "INVALID_PHONE"},
      {code: "TOO_LONG"},
    ]);
    expect(out).toBe(
        "A customer field is too long for Wave. " +
        "The customer phone number is not valid.");
  });

  test("tolerates non-array and malformed entries", () => {
    expect(sanitizeInputErrors(null)).toBe("Wave rejected the customer data.");
    expect(sanitizeInputErrors([null, {}, {code: 7}]))
        .toBe("Wave rejected the customer data.");
  });
});
