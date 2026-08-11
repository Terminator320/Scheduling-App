"use strict";

const {sendToActiveAdmins} = require("../notification_utils");

/**
 * Minimal Firestore stand-in: `.collection().where().where().get()`.
 *
 * @param {!Array<!Object>} docs Docs the query resolves to.
 * @param {!Array<!Object>} calls Collected `.where()` arguments.
 * @return {!Object}
 */
function fakeDb(docs, calls) {
  const query = {
    where: (field, op, value) => {
      calls.push([field, op, value]);
      return query;
    },
    get: async () => ({docs}),
  };
  return {collection: () => query};
}

/**
 * @param {string} id Doc id.
 * @return {!Object}
 */
function adminDoc(id) {
  return {id, data: () => ({role: "admin", status: "active"})};
}

describe("sendToActiveAdmins", () => {
  let deps;
  let logged;

  beforeEach(() => {
    logged = [];
    deps = {
      messaging: {},
      logger: {warn: (msg, meta) => logged.push([msg, meta])},
    };
  });

  test("sends one message per active admin", async () => {
    const sent = [];
    deps.db = fakeDb([adminDoc("a1"), adminDoc("a2")], []);

    await sendToActiveAdmins(
        deps, {kind: "x"}, () => ({title: "t", body: "b"}),
        {sendToEmployee: async (_d, id) => {
          sent.push(id);
          return 1;
        }},
    );

    expect(sent).toEqual(["a1", "a2"]);
  });

  test("constrains the query to active admins", async () => {
    // The role/status filter has to be in the QUERY, not a post-filter: this
    // runs on the Admin SDK so rules are bypassed, but an unfiltered scan of
    // /users would grow with the roster for no reason.
    const calls = [];
    deps.db = fakeDb([], calls);

    await sendToActiveAdmins(
        deps, {kind: "x"}, () => ({title: "t", body: "b"}),
        {sendToEmployee: async () => 1},
    );

    expect(calls).toEqual([
      ["role", "==", "admin"],
      ["status", "==", "active"],
    ]);
  });

  test("excludes the person who caused the notice", async () => {
    const sent = [];
    deps.db = fakeDb([adminDoc("a1"), adminDoc("a2")], []);

    await sendToActiveAdmins(
        deps, {kind: "x"}, () => ({title: "t", body: "b"}),
        {
          excludeDocId: "a1",
          sendToEmployee: async (_d, id) => {
            sent.push(id);
            return 1;
          },
        },
    );

    expect(sent).toEqual(["a2"]);
  });

  test("one bad recipient does not stop the rest", async () => {
    // Best-effort: whatever prompted the notice already committed, so a push
    // failure must never surface as a failed operation.
    const sent = [];
    deps.db = fakeDb([adminDoc("a1"), adminDoc("a2")], []);

    await expect(
        sendToActiveAdmins(deps, {kind: "x"}, () => ({title: "t", body: "b"}), {
          sendToEmployee: async (_d, id) => {
            if (id === "a1") throw new Error("boom");
            sent.push(id);
            return 1;
          },
        }),
    ).resolves.toBeUndefined();

    expect(sent).toEqual(["a2"]);
    expect(logged.length).toBe(1);
  });

  test("a failed query resolves instead of throwing", async () => {
    deps.db = {
      collection: () => ({
        where: () => ({
          where: () => ({
            get: async () => {
              throw new Error("unavailable");
            },
          }),
        }),
      }),
    };

    await expect(
        sendToActiveAdmins(deps, {kind: "x"}, () => ({title: "t", body: "b"}), {
          sendToEmployee: async () => 1,
        }),
    ).resolves.toBeUndefined();

    expect(logged.length).toBe(1);
  });

  test("works with no options at all", async () => {
    deps.db = fakeDb([], []);

    await expect(
        sendToActiveAdmins(deps, {kind: "x"}, () => ({title: "t", body: "b"})),
    ).resolves.toBeUndefined();
  });
});
