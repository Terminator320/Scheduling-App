"use strict";

const {performDeleteClient} = require("../clients");

/**
 * Minimal Firestore fake: a clients doc that may or may not exist, and an
 * appointments count() aggregate that returns a fixed number.
 * @param {{count: number, exists: (boolean|undefined)}} opts Fake config.
 * @return {!Object} A db fake with a `deleted` log.
 */
function fakeDb({count, exists = true}) {
  const deleted = [];
  return {
    deleted,
    collection: (name) => ({
      doc: (id) => ({
        get: async () => ({exists, id}),
        delete: async () => {
          deleted.push({collection: name, id});
        },
      }),
      where: () => ({
        count: () => ({get: async () => ({data: () => ({count})})}),
      }),
    }),
  };
}

describe("performDeleteClient", () => {
  test("refuses a client that has appointments", async () => {
    const db = fakeDb({count: 3});
    await expect(performDeleteClient(db, "c1"))
        .rejects.toThrow(/client-has-history/);
    expect(db.deleted).toHaveLength(0);
  });

  test("refuses on a single appointment, not just on many", async () => {
    const db = fakeDb({count: 1});
    await expect(performDeleteClient(db, "c1"))
        .rejects.toThrow(/client-has-history/);
    expect(db.deleted).toHaveLength(0);
  });

  test("deletes a client with no appointments", async () => {
    const db = fakeDb({count: 0});
    await performDeleteClient(db, "c1");
    expect(db.deleted).toEqual([{collection: "clients", id: "c1"}]);
  });

  test("refuses a client that does not exist", async () => {
    const db = fakeDb({count: 0, exists: false});
    await expect(performDeleteClient(db, "c1"))
        .rejects.toThrow(/client-not-found/);
  });
});
