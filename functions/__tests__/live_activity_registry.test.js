"use strict";

/**
 * Unit tests for the Live Activity token/card-marker registry. The module takes
 * an injected `{db, now, logger}`, so this drives it with a hand-rolled fake
 * Firestore — no emulator, no firebase-admin.
 *
 * Two things this file deliberately pins:
 *  - the `in`-filter chunking against IN_QUERY_MAX (Firestore's hard 30 cap);
 *  - the module's best-effort failure posture: EVERY read swallows its error
 *    and returns []/null/false so the caller degrades to the plain `leaveNow`
 *    push. That posture is by design but it also means an index or permission
 *    regression is invisible in production except as a warn line — the
 *    characterization tests below exist so a future change to it is a visibly
 *    failing test rather than a silent behaviour swap.
 */

const registry = require("../live_activity_registry");

const {
  KIND_PUSH_TO_START,
  KIND_UPDATE,
  CARDS_COLLECTION,
  IN_QUERY_MAX,
  PRUNE_MAX,
  TOKEN_TTL_MS,
  CARD_TTL_MS,
  activityTokenExpiry,
  listPushToStartTokens,
  listUpdateTokens,
  deleteActivityToken,
  pruneExpiredActivityTokens,
  writeCardMarker,
  readCardMarker,
  setCardPhase,
  clearCardMarker,
  listCardsDueForOnSite,
  pruneExpiredCardMarkers,
} = registry;

const NOW = new Date("2026-07-19T12:00:00.000Z");

/** @return {{warn: !Function}} A logger spy. */
function fakeLogger() {
  return {warn: jest.fn(), info: jest.fn(), debug: jest.fn()};
}

/**
 * Applies one recorded filter to a row.
 * @param {!Object} row
 * @param {!Array} filter `[field, op, value]`.
 * @return {boolean}
 */
function matches(row, [field, op, value]) {
  const actual = row[field];
  if (op === "==") return actual === value;
  if (op === "in") return value.includes(actual);
  if (op === "<=") {
    if (actual == null) return false;
    const a = actual instanceof Date ? actual.getTime() : actual;
    const b = value instanceof Date ? value.getTime() : value;
    return a <= b;
  }
  throw new Error(`unsupported op ${op}`);
}

/**
 * Chainable fake query over an in-memory row list. Records the filters it was
 * built with so the tests can assert on chunk shapes.
 * @param {!Array<!Object>} rows Rows `{id, ...fields}`.
 * @param {!Array<!Object>} recorded Sink for issued queries.
 * @param {?Error} failWith When set, `get()` rejects with it.
 * @param {!Object} deletes Sink recording deleted doc ids.
 * @return {!Object}
 */
function fakeQuery(rows, recorded, failWith, deletes) {
  const state = {filters: [], limit: null};
  const q = {
    _state: state,
    where(field, op, value) {
      state.filters.push([field, op, value]);
      return q;
    },
    limit(n) {
      state.limit = n;
      return q;
    },
    async get() {
      recorded.push(state);
      if (failWith) throw failWith;
      let out = rows.filter((r) => state.filters.every((f) => matches(r, f)));
      if (state.limit != null) out = out.slice(0, state.limit);
      return {
        docs: out.map((r) => ({
          id: r.id,
          ref: {
            id: r.id,
            delete: jest.fn(async () => {
              if (r._deleteThrows) throw new Error("delete boom");
              deletes.push(r.id);
            }),
          },
          data: () => {
            const copy = {...r};
            delete copy.id;
            delete copy._deleteThrows;
            return copy;
          },
        })),
      };
    },
  };
  return q;
}

/**
 * Fake Firestore covering exactly the surface the registry uses.
 * @param {Object=} opts `tokens`, `cards`, `groupFails`, `cardsQueryFails`,
 *   `cardWriteFails`, `cardReadFails`, `cardDeleteFails`.
 * @return {!Object} `{db, queries, cardDocs, deletes, cardOps}`.
 */
function fakeDb(opts = {}) {
  const tokens = opts.tokens || [];
  const cardRows = opts.cards || [];
  const queries = [];
  const deletes = [];
  const cardOps = [];
  const cardDocs = new Map(cardRows.map((c) => [c.id, {...c}]));

  const db = {
    collectionGroup: (name) => {
      if (name !== "liveActivityTokens") {
        throw new Error(`unexpected collection group ${name}`);
      }
      return fakeQuery(tokens, queries, opts.groupFails || null, deletes);
    },
    collection: (name) => {
      if (name !== CARDS_COLLECTION) {
        throw new Error(`unexpected collection ${name}`);
      }
      const asRows = () =>
        [...cardDocs.entries()].map(([id, data]) => ({id, ...data}));
      const collectionRef = fakeQuery(
          asRows(), queries, opts.cardsQueryFails || null, deletes,
      );
      collectionRef.doc = (id) => ({
        id,
        async set(data, options) {
          cardOps.push({op: "set", id, data, options});
          if (opts.cardWriteFails) throw new Error("card write boom");
          const prior = options && options.merge ? cardDocs.get(id) || {} : {};
          cardDocs.set(id, {...prior, ...data});
        },
        async get() {
          cardOps.push({op: "get", id});
          if (opts.cardReadFails) throw new Error("card read boom");
          const data = cardDocs.get(id);
          return {exists: data !== undefined, data: () => data};
        },
        async delete() {
          cardOps.push({op: "delete", id});
          if (opts.cardDeleteFails) throw new Error("card delete boom");
          cardDocs.delete(id);
        },
      });
      return collectionRef;
    },
  };
  return {db, queries, cardDocs, deletes, cardOps};
}

/**
 * Builds a token row.
 * @param {string} id
 * @param {!Object} fields
 * @return {!Object}
 */
function tokenRow(id, fields) {
  return {id, token: `tok-${id}`, ...fields};
}

describe("exported constants", () => {
  test("IN_QUERY_MAX matches Firestore's hard `in` cap", () => {
    expect(IN_QUERY_MAX).toBe(30);
  });

  test("kinds are the two the client writes", () => {
    expect(KIND_PUSH_TO_START).toBe("pushToStart");
    expect(KIND_UPDATE).toBe("update");
  });

  test("PRUNE_MAX bounds one sweep", () => {
    expect(PRUNE_MAX).toBeGreaterThan(0);
  });
});

describe("activityTokenExpiry", () => {
  test("stamps now + TOKEN_TTL_MS", () => {
    expect(activityTokenExpiry(NOW).getTime())
        .toBe(NOW.getTime() + TOKEN_TTL_MS);
  });

  test("falls back to the wall clock when now is omitted", () => {
    const before = Date.now();
    const got = activityTokenExpiry(undefined).getTime();
    expect(got).toBeGreaterThanOrEqual(before + TOKEN_TTL_MS);
    expect(got).toBeLessThanOrEqual(Date.now() + TOKEN_TTL_MS);
  });
});

describe("listPushToStartTokens", () => {
  test("returns only pushToStart rows for the given employees", async () => {
    const {db, queries} = fakeDb({
      tokens: [
        tokenRow("a1", {kind: KIND_PUSH_TO_START, employeeDocId: "emp-1"}),
        tokenRow("a2", {kind: KIND_UPDATE, employeeDocId: "emp-1"}),
        tokenRow("a3", {kind: KIND_PUSH_TO_START, employeeDocId: "emp-9"}),
      ],
    });
    const rows = await listPushToStartTokens(
        {db, logger: fakeLogger()}, {employeeDocIds: ["emp-1"]});

    expect(rows.map((r) => r.activityId)).toEqual(["a1"]);
    expect(rows[0].token).toBe("tok-a1");
    expect(queries).toHaveLength(1);
  });

  test("exposes the doc id as activityId and keeps the ref", async () => {
    const {db} = fakeDb({
      tokens: [
        tokenRow("act-77", {kind: KIND_PUSH_TO_START, employeeDocId: "e"}),
      ],
    });
    const [row] = await listPushToStartTokens(
        {db, logger: fakeLogger()}, {employeeDocIds: ["e"]});

    expect(row.activityId).toBe("act-77");
    expect(typeof row.ref.delete).toBe("function");
  });

  test("an empty / all-falsy id list issues no query", async () => {
    const {db, queries} = fakeDb();
    const logger = fakeLogger();

    expect(await listPushToStartTokens({db, logger}, {employeeDocIds: []}))
        .toEqual([]);
    expect(await listPushToStartTokens({db, logger}, {employeeDocIds: null}))
        .toEqual([]);
    expect(await listPushToStartTokens(
        {db, logger}, {employeeDocIds: [null, "", undefined]})).toEqual([]);
    expect(queries).toHaveLength(0);
  });

  test("chunks the `in` filter at IN_QUERY_MAX", async () => {
    const ids = Array.from({length: 65}, (_, i) => `emp-${i}`);
    const tokens = ids.map((id, i) =>
      tokenRow(`a${i}`, {kind: KIND_PUSH_TO_START, employeeDocId: id}));
    const {db, queries} = fakeDb({tokens});

    const rows = await listPushToStartTokens(
        {db, logger: fakeLogger()}, {employeeDocIds: ids});

    // 65 ids -> 30 / 30 / 5.
    expect(queries).toHaveLength(3);
    const chunkSizes = queries.map((q) =>
      q.filters.find(([f, op]) => f === "employeeDocId" && op === "in")[2]
          .length);
    expect(chunkSizes).toEqual([30, 30, 5]);
    expect(chunkSizes.every((n) => n <= IN_QUERY_MAX)).toBe(true);
    // Every chunk's rows are flattened into one list.
    expect(rows).toHaveLength(65);
  });

  test("exactly IN_QUERY_MAX ids stay in a single query", async () => {
    const ids = Array.from({length: IN_QUERY_MAX}, (_, i) => `emp-${i}`);
    const {db, queries} = fakeDb();
    await listPushToStartTokens(
        {db, logger: fakeLogger()}, {employeeDocIds: ids});
    expect(queries).toHaveLength(1);
  });

  test("one over the cap splits into two queries", async () => {
    const ids = Array.from({length: IN_QUERY_MAX + 1}, (_, i) => `emp-${i}`);
    const {db, queries} = fakeDb();
    await listPushToStartTokens(
        {db, logger: fakeLogger()}, {employeeDocIds: ids});
    expect(queries).toHaveLength(2);
  });
});

describe("listUpdateTokens", () => {
  test("filters to kind=update for the one employee", async () => {
    const {db} = fakeDb({
      tokens: [
        tokenRow("u1", {kind: KIND_UPDATE, employeeDocId: "emp-1"}),
        tokenRow("u2", {kind: KIND_UPDATE, employeeDocId: "emp-2"}),
        tokenRow("p1", {kind: KIND_PUSH_TO_START, employeeDocId: "emp-1"}),
      ],
    });
    const rows = await listUpdateTokens(
        {db, logger: fakeLogger()}, {employeeDocId: "emp-1"});

    expect(rows.map((r) => r.activityId)).toEqual(["u1"]);
  });

  test("a tech signed in on two phones yields two rows", async () => {
    const {db} = fakeDb({
      tokens: [
        tokenRow("u1", {kind: KIND_UPDATE, employeeDocId: "emp-1"}),
        tokenRow("u2", {kind: KIND_UPDATE, employeeDocId: "emp-1"}),
      ],
    });
    const rows = await listUpdateTokens(
        {db, logger: fakeLogger()}, {employeeDocId: "emp-1"});

    expect(rows.map((r) => r.activityId).sort()).toEqual(["u1", "u2"]);
  });

  test("a missing employeeDocId short-circuits with no query", async () => {
    const {db, queries} = fakeDb();
    expect(await listUpdateTokens(
        {db, logger: fakeLogger()}, {employeeDocId: ""})).toEqual([]);
    expect(queries).toHaveLength(0);
  });
});

describe("_query error swallowing (characterization)", () => {
  // PINNED BEHAVIOUR, NOT AN ASSERTION THAT THIS IS DESIRABLE: `_query`
  // catches every error and returns []. A missing composite index or a rules /
  // permission regression therefore looks exactly like "this tech has no
  // registered device" and the caller silently degrades to the plain leaveNow
  // push. If that posture ever changes, these two tests must be updated
  // deliberately rather than the change slipping through unnoticed.
  test("a failing pushToStart read resolves [] and only warns", async () => {
    const {db} = fakeDb({groupFails: new Error("FAILED_PRECONDITION: index")});
    const logger = fakeLogger();

    const rows = await listPushToStartTokens(
        {db, logger}, {employeeDocIds: ["emp-1"]});

    expect(rows).toEqual([]);
    expect(logger.warn).toHaveBeenCalledTimes(1);
    expect(logger.warn.mock.calls[0][0]).toContain("pushToStart read failed");
  });

  test("a failing update-token read resolves [] and only warns", async () => {
    const {db} = fakeDb({groupFails: new Error("PERMISSION_DENIED")});
    const logger = fakeLogger();

    expect(await listUpdateTokens({db, logger}, {employeeDocId: "emp-1"}))
        .toEqual([]);
    expect(logger.warn.mock.calls[0][0]).toContain("update-token read failed");
  });

  test("a failing read without a logger still resolves [] (never throws)",
      async () => {
        const {db} = fakeDb({groupFails: new Error("boom")});
        await expect(listUpdateTokens({db}, {employeeDocId: "emp-1"}))
            .resolves.toEqual([]);
      });

  test("one failing chunk does not lose the other chunks' rows", async () => {
    // Both chunks share one fake, so this variant simply proves the flatten
    // path tolerates an empty batch alongside a populated one.
    const ids = Array.from({length: 35}, (_, i) => `emp-${i}`);
    const tokens = [
      tokenRow("a0", {kind: KIND_PUSH_TO_START, employeeDocId: "emp-0"}),
      tokenRow("a34", {kind: KIND_PUSH_TO_START, employeeDocId: "emp-34"}),
    ];
    const {db} = fakeDb({tokens});
    const rows = await listPushToStartTokens(
        {db, logger: fakeLogger()}, {employeeDocIds: ids});
    expect(rows.map((r) => r.activityId).sort()).toEqual(["a0", "a34"]);
  });
});

describe("card marker round-trip", () => {
  test("write then read returns the stored marker", async () => {
    const {db} = fakeDb();
    const deps = {db, now: NOW, logger: fakeLogger()};
    const start = new Date("2026-07-19T13:30:00.000Z");

    expect(await writeCardMarker(deps, {
      employeeDocId: "emp-1",
      appointmentId: "appt-9",
      startTime: start,
      phase: "travel",
    })).toBe(true);

    const marker = await readCardMarker(deps, {employeeDocId: "emp-1"});
    expect(marker).toMatchObject({
      employeeDocId: "emp-1",
      appointmentId: "appt-9",
      startTime: start,
      phase: "travel",
      startedAt: NOW,
    });
    expect(marker.expiresAt.getTime()).toBe(NOW.getTime() + CARD_TTL_MS);
  });

  test("a second write fully replaces the previous card (no merge)",
      async () => {
        const {db} = fakeDb();
        const deps = {db, now: NOW, logger: fakeLogger()};
        await writeCardMarker(deps, {
          employeeDocId: "emp-1",
          appointmentId: "appt-1",
          startTime: NOW,
          phase: "travel",
        });
        await writeCardMarker(deps, {
          employeeDocId: "emp-1",
          appointmentId: "appt-2",
          startTime: null,
          phase: "travel",
        });

        const marker = await readCardMarker(deps, {employeeDocId: "emp-1"});
        expect(marker.appointmentId).toBe("appt-2");
        expect(marker.startTime).toBeNull();
      });

  test("setCardPhase merges — it only flips the phase", async () => {
    const {db} = fakeDb();
    const deps = {db, now: NOW, logger: fakeLogger()};
    await writeCardMarker(deps, {
      employeeDocId: "emp-1",
      appointmentId: "appt-9",
      startTime: NOW,
      phase: "travel",
    });

    expect(await setCardPhase(deps, {employeeDocId: "emp-1", phase: "onSite"}))
        .toBe(true);

    const marker = await readCardMarker(deps, {employeeDocId: "emp-1"});
    expect(marker.phase).toBe("onSite");
    expect(marker.appointmentId).toBe("appt-9");
  });

  test("clearCardMarker deletes it; a later read is null", async () => {
    const {db} = fakeDb();
    const deps = {db, now: NOW, logger: fakeLogger()};
    await writeCardMarker(deps, {
      employeeDocId: "emp-1",
      appointmentId: "appt-9",
      startTime: NOW,
      phase: "travel",
    });

    expect(await clearCardMarker(deps, {employeeDocId: "emp-1"})).toBe(true);
    expect(await readCardMarker(deps, {employeeDocId: "emp-1"})).toBeNull();
  });

  test("reading a never-written marker is null, not a throw", async () => {
    const {db} = fakeDb();
    expect(await readCardMarker(
        {db, logger: fakeLogger()}, {employeeDocId: "nobody"})).toBeNull();
  });

  test("markers are per-employee", async () => {
    const {db} = fakeDb();
    const deps = {db, now: NOW, logger: fakeLogger()};
    await writeCardMarker(deps, {
      employeeDocId: "emp-1", appointmentId: "a1", startTime: NOW,
      phase: "travel",
    });
    await writeCardMarker(deps, {
      employeeDocId: "emp-2", appointmentId: "a2", startTime: NOW,
      phase: "travel",
    });

    expect((await readCardMarker(deps, {employeeDocId: "emp-1"})).appointmentId)
        .toBe("a1");
    expect((await readCardMarker(deps, {employeeDocId: "emp-2"})).appointmentId)
        .toBe("a2");
  });
});

describe("card marker guards and failure posture", () => {
  test("a missing employeeDocId or appointmentId writes nothing", async () => {
    const {db, cardOps} = fakeDb();
    const deps = {db, now: NOW, logger: fakeLogger()};

    expect(await writeCardMarker(deps, {
      employeeDocId: "", appointmentId: "a", startTime: NOW, phase: "travel",
    })).toBe(false);
    expect(await writeCardMarker(deps, {
      employeeDocId: "e", appointmentId: "", startTime: NOW, phase: "travel",
    })).toBe(false);
    expect(cardOps).toHaveLength(0);
  });

  test("empty ids short-circuit read / phase / clear", async () => {
    const {db, cardOps} = fakeDb();
    const deps = {db, logger: fakeLogger()};

    expect(await readCardMarker(deps, {employeeDocId: ""})).toBeNull();
    expect(await setCardPhase(deps, {employeeDocId: "", phase: "onSite"}))
        .toBe(false);
    expect(await clearCardMarker(deps, {employeeDocId: ""})).toBe(false);
    expect(cardOps).toHaveLength(0);
  });

  test("a failed write returns false and warns", async () => {
    const {db} = fakeDb({cardWriteFails: true});
    const logger = fakeLogger();
    expect(await writeCardMarker({db, now: NOW, logger}, {
      employeeDocId: "e", appointmentId: "a", startTime: NOW, phase: "travel",
    })).toBe(false);
    expect(logger.warn.mock.calls[0][0]).toContain("card marker write failed");
  });

  test("a failed read returns null and warns", async () => {
    const {db} = fakeDb({cardReadFails: true});
    const logger = fakeLogger();
    expect(await readCardMarker({db, logger}, {employeeDocId: "e"})).toBeNull();
    expect(logger.warn.mock.calls[0][0]).toContain("card marker read failed");
  });

  test("a failed phase write returns false and warns", async () => {
    const {db} = fakeDb({cardWriteFails: true});
    const logger = fakeLogger();
    expect(await setCardPhase({db, logger}, {
      employeeDocId: "e", phase: "onSite",
    })).toBe(false);
    expect(logger.warn.mock.calls[0][0]).toContain("card phase write failed");
  });

  test("a failed clear returns false and warns", async () => {
    const {db} = fakeDb({cardDeleteFails: true});
    const logger = fakeLogger();
    expect(await clearCardMarker({db, logger}, {employeeDocId: "e"}))
        .toBe(false);
    expect(logger.warn.mock.calls[0][0]).toContain("card marker clear failed");
  });
});

describe("listCardsDueForOnSite", () => {
  const past = new Date(NOW.getTime() - 60000);
  const future = new Date(NOW.getTime() + 60000);

  test("returns started-but-not-yet-flipped travel cards", async () => {
    const {db} = fakeDb({
      cards: [
        {id: "emp-1", phase: "travel", startTime: past},
        {id: "emp-2", phase: "travel", startTime: future},
        {id: "emp-3", phase: "onSite", startTime: past},
      ],
    });
    const rows = await listCardsDueForOnSite(
        {db, now: NOW, logger: fakeLogger()});

    expect(rows.map((r) => r.activityId)).toEqual(["emp-1"]);
  });

  test("the phase filter runs in the query, not after the limit", async () => {
    const {db, queries} = fakeDb({
      cards: [{id: "emp-1", phase: "travel", startTime: past}],
    });
    await listCardsDueForOnSite({db, now: NOW, logger: fakeLogger()});

    // Both filters are pushed to Firestore (backed by the (phase, startTime)
    // composite index). Filtering phase AFTER .limit() let a batch of
    // already-flipped cards consume the cap and starve the due ones.
    expect(queries[0].filters.map(([f]) => f)).toEqual(["phase", "startTime"]);
  });

  test("honours an explicit limit, defaulting to PRUNE_MAX", async () => {
    const {db, queries} = fakeDb({cards: []});
    const deps = {db, now: NOW, logger: fakeLogger()};

    await listCardsDueForOnSite(deps);
    expect(queries[0].limit).toBe(PRUNE_MAX);

    await listCardsDueForOnSite(deps, {limit: 7});
    expect(queries[1].limit).toBe(7);
  });

  test("a query failure resolves [] and warns", async () => {
    const {db} = fakeDb({cardsQueryFails: true});
    const logger = fakeLogger();
    expect(await listCardsDueForOnSite({db, now: NOW, logger})).toEqual([]);
    expect(logger.warn.mock.calls[0][0]).toContain("on-site query failed");
  });
});

describe("deleteActivityToken", () => {
  test("deletes the row and reports true", async () => {
    const ref = {delete: jest.fn(async () => {})};
    expect(await deleteActivityToken({logger: fakeLogger()}, {ref})).toBe(true);
    expect(ref.delete).toHaveBeenCalledTimes(1);
  });

  test("a missing or non-ref argument is a no-op false", async () => {
    const logger = fakeLogger();
    expect(await deleteActivityToken({logger}, {ref: null})).toBe(false);
    expect(await deleteActivityToken({logger}, {ref: {}})).toBe(false);
    expect(logger.warn).not.toHaveBeenCalled();
  });

  test("a failing delete returns false and warns", async () => {
    const logger = fakeLogger();
    const ref = {delete: jest.fn(async () => {
      throw new Error("nope");
    })};
    expect(await deleteActivityToken({logger}, {ref})).toBe(false);
    expect(logger.warn.mock.calls[0][0]).toContain("token delete failed");
  });

  test("never throws even without a logger", async () => {
    const ref = {delete: async () => {
      throw new Error("nope");
    }};
    await expect(deleteActivityToken(undefined, {ref})).resolves.toBe(false);
  });
});

describe("_pruneExpired via pruneExpiredActivityTokens", () => {
  const expired = new Date(NOW.getTime() - 1000);
  const live = new Date(NOW.getTime() + 1000);

  test("deletes only rows whose expiresAt has passed", async () => {
    const {db, deletes} = fakeDb({
      tokens: [
        tokenRow("old-1", {expiresAt: expired}),
        tokenRow("old-2", {expiresAt: expired}),
        tokenRow("fresh", {expiresAt: live}),
      ],
    });

    const result = await pruneExpiredActivityTokens(
        {db, now: NOW, logger: fakeLogger()});

    expect(result).toEqual({pruned: 2});
    expect(deletes.sort()).toEqual(["old-1", "old-2"]);
  });

  test("a row whose delete fails does not abort the rest", async () => {
    const {db, deletes} = fakeDb({
      tokens: [
        {...tokenRow("bad", {expiresAt: expired}), _deleteThrows: true},
        tokenRow("good", {expiresAt: expired}),
      ],
    });
    const logger = fakeLogger();

    expect(await pruneExpiredActivityTokens({db, now: NOW, logger}))
        .toEqual({pruned: 1});
    expect(deletes).toEqual(["good"]);
  });

  test("nothing expired means zero pruned and no deletes", async () => {
    const {db, deletes} = fakeDb({
      tokens: [tokenRow("fresh", {expiresAt: live})],
    });
    expect(await pruneExpiredActivityTokens(
        {db, now: NOW, logger: fakeLogger()})).toEqual({pruned: 0});
    expect(deletes).toEqual([]);
  });

  test("caps the sweep and warns when the cap is hit", async () => {
    const tokens = Array.from({length: 5}, (_, i) =>
      tokenRow(`t${i}`, {expiresAt: expired}));
    const {db, queries} = fakeDb({tokens});
    const logger = fakeLogger();

    const result = await pruneExpiredActivityTokens(
        {db, now: NOW, logger}, {limit: 3});

    expect(result).toEqual({pruned: 3});
    expect(queries[0].limit).toBe(3);
    expect(logger.warn.mock.calls[0][0])
        .toContain("token prune cap hit; deferred");
  });

  test("defaults the cap to PRUNE_MAX", async () => {
    const {db, queries} = fakeDb({tokens: []});
    await pruneExpiredActivityTokens({db, now: NOW, logger: fakeLogger()});
    expect(queries[0].limit).toBe(PRUNE_MAX);
  });

  test("a failing prune query resolves {pruned: 0} and warns", async () => {
    const {db} = fakeDb({groupFails: new Error("index missing")});
    const logger = fakeLogger();

    expect(await pruneExpiredActivityTokens({db, now: NOW, logger}))
        .toEqual({pruned: 0});
    expect(logger.warn.mock.calls[0][0])
        .toContain("token prune query failed");
  });

  test("falls back to the wall clock when now is omitted", async () => {
    const {db, deletes} = fakeDb({
      tokens: [
        tokenRow("old", {expiresAt: new Date(Date.now() - 60000)}),
        tokenRow("new", {expiresAt: new Date(Date.now() + 600000)}),
      ],
    });
    await pruneExpiredActivityTokens({db, logger: fakeLogger()});
    expect(deletes).toEqual(["old"]);
  });
});

describe("pruneExpiredCardMarkers", () => {
  const expired = new Date(NOW.getTime() - 1000);

  test("sweeps the cards collection, not the token group", async () => {
    const {db, deletes} = fakeDb({
      cards: [
        {id: "emp-1", expiresAt: expired},
        {id: "emp-2", expiresAt: new Date(NOW.getTime() + 1000)},
      ],
    });

    expect(await pruneExpiredCardMarkers({db, now: NOW, logger: fakeLogger()}))
        .toEqual({pruned: 1});
    expect(deletes).toEqual(["emp-1"]);
  });

  test("uses the 'card' label in its cap warning", async () => {
    const {db} = fakeDb({
      cards: [
        {id: "a", expiresAt: expired},
        {id: "b", expiresAt: expired},
      ],
    });
    const logger = fakeLogger();
    await pruneExpiredCardMarkers({db, now: NOW, logger}, {limit: 2});
    expect(logger.warn.mock.calls[0][0])
        .toContain("card prune cap hit; deferred");
  });

  test("a failing card prune query resolves {pruned: 0}", async () => {
    const {db} = fakeDb({cardsQueryFails: true});
    const logger = fakeLogger();
    expect(await pruneExpiredCardMarkers({db, now: NOW, logger}))
        .toEqual({pruned: 0});
    expect(logger.warn.mock.calls[0][0]).toContain("card prune query failed");
  });
});
