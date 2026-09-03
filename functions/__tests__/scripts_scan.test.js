"use strict";

/** The document-id paging loop the operator scripts share. */

const {scanByName} = require("../scripts/_scan");

/**
 * Collection stand-in over a fixed list of ids, recording every page query.
 * @param {!Array<string>} ids Document ids in order.
 * @return {!Object} `{source, queries}`.
 */
function fakeCollection(ids) {
  const queries = [];
  const make = (after, limit) => ({
    orderBy(field) {
      if (field !== "__name__") throw new Error(`ordered by ${field}`);
      return make(after, limit);
    },
    limit(n) {
      return make(after, n);
    },
    startAfter(doc) {
      return make(doc.id, limit);
    },
    async get() {
      queries.push({after, limit});
      const from = after == null ? 0 : ids.indexOf(after) + 1;
      const page = ids.slice(from, from + limit);
      return {
        empty: page.length === 0,
        size: page.length,
        docs: page.map((id) => ({id})),
      };
    },
  });
  return {source: make(null, null), queries};
}

const idsUpTo = (n) =>
  Array.from({length: n}, (_, i) => `d${String(i).padStart(3, "0")}`);

/**
 * Drains the generator into an array of ids.
 * @param {!Object} source Collection stand-in.
 * @param {number} pageSize Page size.
 * @return {!Promise<!Array<string>>}
 */
async function drain(source, pageSize) {
  const seen = [];
  for await (const doc of scanByName(source, {pageSize})) seen.push(doc.id);
  return seen;
}

describe("scanByName", () => {
  test("yields every document exactly once, in id order", async () => {
    const ids = idsUpTo(12);
    const {source} = fakeCollection(ids);

    expect(await drain(source, 5)).toEqual(ids);
  });

  test("advances the cursor, so it cannot re-scan page one forever",
      async () => {
        const {source, queries} = fakeCollection(idsUpTo(12));

        await drain(source, 5);

        // Page 1 unanchored, then anchored on each page's last doc.
        expect(queries.map((q) => q.after)).toEqual([null, "d004", "d009"]);
      });

  test("stops on a SHORT page without a further read", async () => {
    // 10 docs at a page size of 5 needs a third query to learn it ran out; 12
    // does not, because page 3 comes back short.
    const {source, queries} = fakeCollection(idsUpTo(12));

    await drain(source, 5);

    expect(queries).toHaveLength(3);
  });

  test("an exact multiple costs one extra, empty read", async () => {
    const {source, queries} = fakeCollection(idsUpTo(10));

    expect(await drain(source, 5)).toHaveLength(10);
    expect(queries).toHaveLength(3);
  });

  test("an empty collection yields nothing after one read", async () => {
    const {source, queries} = fakeCollection([]);

    expect(await drain(source, 5)).toEqual([]);
    expect(queries).toHaveLength(1);
  });

  test("a collection smaller than one page needs one read", async () => {
    const {source, queries} = fakeCollection(idsUpTo(3));

    expect(await drain(source, 500)).toHaveLength(3);
    expect(queries).toHaveLength(1);
  });

  test("orders by __name__, never a data field", async () => {
    // An orderBy on a data field makes Firestore EXCLUDE any document missing
    // it — which is exactly the legacy row a backfill or audit exists to find.
    const {source} = fakeCollection(idsUpTo(3));

    await expect(drain(source, 2)).resolves.toHaveLength(3);
  });

  test("passes the caller's page size through", async () => {
    const {source, queries} = fakeCollection(idsUpTo(3));

    await drain(source, 200);

    expect(queries[0].limit).toBe(200);
  });

  test.each([0, -1, 1.5, null, undefined, "500"])(
      "refuses a page size of %p rather than inventing one",
      async (pageSize) => {
        // A default here would let a new script inherit a number nobody chose
        // for it — the same enforcement `pageToCap` applies on the Dart side.
        const {source} = fakeCollection(idsUpTo(3));

        await expect(drain(source, pageSize)).rejects.toThrow(/pageSize/);
      });

  test("rejects a missing options bag", async () => {
    const {source} = fakeCollection(idsUpTo(3));
    const run = async () => {
      for await (const doc of scanByName(source)) void doc;
    };

    await expect(run()).rejects.toThrow(/pageSize/);
  });
});
