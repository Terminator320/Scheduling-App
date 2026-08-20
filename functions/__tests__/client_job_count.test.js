"use strict";

const {clientsToRecount, recountOne, NOT_FOUND} =
  require("../client_job_count");

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
});

// ---------------------------------------------------------------------------
// recountOne
// ---------------------------------------------------------------------------

/**
 * Fake Firestore recording the aggregate query it was asked for and the write
 * it received.
 * @param {{count: number, updateError: ?Object}} opts
 * @return {!Object} `{db, calls}`
 */
function fakeDb({count = 0, updateError = null} = {}) {
  const calls = {where: null, doc: null, update: [], set: []};
  const db = {
    collection(name) {
      if (name === "appointments") {
        return {
          where(field, op, value) {
            calls.where = {field, op, value};
            return {
              count: () => ({get: async () => ({data: () => ({count})})}),
            };
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
