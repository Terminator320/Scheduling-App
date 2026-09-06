"use strict";

// Pins `backfill-search-tokens.js` — one of the two scripts that MUST run
// against production before the next app build, and until now the only one in
// `scripts/` with no test at all.
//
// The properties that matter are the ones that make an unattended bulk write
// safe: `--dry-run` writes nothing, a re-run writes nothing, the paging loop
// terminates, and the tokens it writes are the ones the callables query.

const {
  backfillCollection,
  patchFor,
  sameArray,
  PAGE_SIZE,
} = require("../scripts/backfill-search-tokens");
const {clientSearchTokens} = require("../search_tokens");

/**
 * A Firestore stand-in over one in-memory collection.
 * @param {!Array<{id: string, data: !Object}>} docs Seed documents.
 * @return {!Object}
 */
function fakeDb(docs) {
  const committed = [];
  const pages = [];
  const makeDoc = (d) => ({
    id: d.id,
    ref: {id: d.id},
    data: () => d.data,
  });
  const query = (after) => {
    const start = after ? docs.findIndex((d) => d.id === after.id) + 1 : 0;
    const slice = docs.slice(start, start + PAGE_SIZE).map(makeDoc);
    pages.push(slice.length);
    return {
      docs: slice,
      size: slice.length,
      empty: slice.length === 0,
    };
  };
  const chain = (after) => ({
    orderBy: () => chain(after),
    limit: () => chain(after),
    startAfter: (cursor) => chain(cursor),
    get: async () => query(after),
  });
  return {
    committed,
    pages,
    collection: () => chain(null),
    batch: () => ({
      update: (ref, patch) => committed.push({id: ref.id, patch}),
      commit: async () => {},
    }),
  };
}

describe("sameArray", () => {
  test("order matters — the index is a positional token list", () => {
    expect(sameArray(["a", "b"], ["b", "a"])).toBe(false);
    expect(sameArray(["a", "b"], ["a", "b"])).toBe(true);
    expect(sameArray(["a"], ["a", "b"])).toBe(false);
  });
});

describe("patchFor", () => {
  test("patches a document that carries no tokens at all", () => {
    expect(patchFor({}, ["t:marc"], "searchTokens"))
        .toEqual({searchTokens: ["t:marc"]});
  });

  test("IDEMPOTENT — an already-tokenized doc is skipped", () => {
    expect(patchFor({searchTokens: ["t:marc"]}, ["t:marc"], "searchTokens"))
        .toBeNull();
  });

  test("a non-array stored value is treated as absent, never read", () => {
    expect(patchFor({searchTokens: "nope"}, ["t:marc"], "searchTokens"))
        .toEqual({searchTokens: ["t:marc"]});
  });
});

describe("backfillCollection", () => {
  const clients = [
    {id: "c1", data: {name: "Marc Tremblay", phone: "5145554321"}},
    {id: "c2", data: {name: "Plomberie Vogas"}},
  ];

  test("writes the tokens the callables query", async () => {
    const db = fakeDb(clients);
    const result = await backfillCollection(
        db, "clients", "searchTokens", clientSearchTokens, false);

    expect(result).toEqual({scanned: 2, patched: 2});
    expect(db.committed.map((c) => c.id)).toEqual(["c1", "c2"]);
    expect(db.committed[0].patch).toEqual({
      searchTokens: clientSearchTokens(clients[0].data),
    });
  });

  test("--dry-run reports the same counts and writes NOTHING", async () => {
    // The failure this guards against has happened in this directory: a
    // backfill whose `--dry-run` wrote everything and then threw.
    const db = fakeDb(clients);
    const result = await backfillCollection(
        db, "clients", "searchTokens", clientSearchTokens, true);

    expect(result).toEqual({scanned: 2, patched: 2});
    expect(db.committed).toEqual([]);
  });

  test("a second run over its own output writes nothing", async () => {
    const tokenized = clients.map((c) => ({
      id: c.id,
      data: {...c.data, searchTokens: clientSearchTokens(c.data)},
    }));
    const db = fakeDb(tokenized);

    const result = await backfillCollection(
        db, "clients", "searchTokens", clientSearchTokens, false);

    expect(result).toEqual({scanned: 2, patched: 0});
    expect(db.committed).toEqual([]);
  });

  test("pages past the page size and terminates", async () => {
    const many = Array.from({length: PAGE_SIZE + 3}, (_, i) => ({
      id: `c${String(i).padStart(4, "0")}`,
      data: {name: `Client ${i}`},
    }));
    const db = fakeDb(many);

    const result = await backfillCollection(
        db, "clients", "searchTokens", clientSearchTokens, true);

    expect(result.scanned).toBe(PAGE_SIZE + 3);
    expect(db.pages).toEqual([PAGE_SIZE, 3]);
  });

  test("an empty collection is one page and no writes", async () => {
    const db = fakeDb([]);
    expect(await backfillCollection(
        db, "clients", "searchTokens", clientSearchTokens, false))
        .toEqual({scanned: 0, patched: 0});
    expect(db.committed).toEqual([]);
  });
});
