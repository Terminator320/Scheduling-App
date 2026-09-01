"use strict";

/**
 * Tests for `toIdList` — the `employeeIds` filter in `notification_policy.js`.
 *
 * It had ZERO direct coverage across twelve call sites, and its own docstring
 * names a coupling nothing enforced: *"Change the 128 here and in
 * `requireDocId`/`isValidDocIdField` together."* The `security.js` half IS
 * pinned by `security.test.js` and the rules half is pinned by nothing on this
 * side, so the three could drift silently and in opposite directions.
 *
 * Both directions of drift are invisible in production. Over-rejecting means
 * an employee quietly receives no push and no travel alert, with nothing
 * logged. Under-rejecting reinstates the failure this filter was written for:
 * `db.collection("users").doc(id)` throws SYNCHRONOUSLY on a slash, and one
 * poisoned element in one appointment was enough to reject the whole
 * daily-digest batch and silence it for every employee.
 */

const fs = require("fs");
const path = require("path");

const {toIdList} = require("../notification_policy");
const {requireDocId} = require("../security");

/** The cap all three copies of the rule are supposed to share. */
const MAX_LEN = 128;

describe("toIdList rejection rules", () => {
  test("a non-array is an empty list, never a throw", () => {
    for (const value of [undefined, null, "abc", 7, {}, true]) {
      expect(toIdList(value)).toEqual([]);
    }
  });

  test("drops a non-string element", () => {
    expect(toIdList(["ok", 7, null, undefined, {}, ["nested"]]))
        .toEqual(["ok"]);
  });

  test("drops an empty string", () => {
    expect(toIdList(["", "ok"])).toEqual(["ok"]);
  });

  test("drops an id containing a slash", () => {
    // The load-bearing half: `.doc("a/b")` throws synchronously.
    expect(toIdList(["a/b", "/lead", "trail/", "ok"])).toEqual(["ok"]);
  });

  test("drops an over-long id", () => {
    expect(toIdList(["a".repeat(MAX_LEN + 1), "ok"])).toEqual(["ok"]);
  });

  test("KEEPS the good ids beside a bad one", () => {
    // The documented difference from `requireDocId`, and the whole reason
    // this filter exists rather than reusing the callable-side owner: a
    // trigger must not turn one poisoned id into a thrown batch.
    expect(toIdList(["e1", "bad/id", "e2", "", "e3"]))
        .toEqual(["e1", "e2", "e3"]);
  });

  test("preserves order and does not de-duplicate", () => {
    expect(toIdList(["e2", "e1", "e2"])).toEqual(["e2", "e1", "e2"]);
  });
});

describe("toIdList length boundary", () => {
  test("accepts exactly 128 and rejects 129", () => {
    expect(toIdList(["a".repeat(MAX_LEN)])).toEqual(["a".repeat(MAX_LEN)]);
    expect(toIdList(["a".repeat(MAX_LEN + 1)])).toEqual([]);
  });
});

describe("the documented coupling to the other two copies of the rule", () => {
  test("agrees with security.js's requireDocId at the boundary", () => {
    // Asserted through BEHAVIOUR rather than a shared constant, because
    // `DOC_ID_MAX_LEN` is deliberately private to `security.js` — the two
    // owners are separate on purpose, so what must match is the answer, not
    // the spelling.
    const atCap = "a".repeat(MAX_LEN);
    const overCap = "a".repeat(MAX_LEN + 1);

    expect(requireDocId({id: atCap}, "id")).toBe(atCap);
    expect(toIdList([atCap])).toEqual([atCap]);

    expect(() => requireDocId({id: overCap}, "id")).toThrow();
    expect(toIdList([overCap])).toEqual([]);
  });

  test("agrees with requireDocId on rejecting a slash", () => {
    expect(() => requireDocId({id: "a/b"}, "id")).toThrow();
    expect(toIdList(["a/b"])).toEqual([]);
  });

  test("agrees with isValidDocIdField's cap in firestore.rules", () => {
    // The third copy, in CEL, which no JS test could otherwise reach. If
    // someone raises the cap here they have to raise it there too, and this
    // is what says so out loud.
    const rules = fs.readFileSync(
        path.join(__dirname, "..", "..", "firestore.rules"), "utf8");
    const declaration = /function isValidDocIdField\(v\)\s*\{\s*return[^}]*?/;
    const cap = /v\.size\(\)\s*<=\s*(\d+)/;
    const match = rules.match(
        new RegExp(declaration.source + cap.source));

    expect(match).not.toBeNull();
    expect(Number(match[1])).toBe(MAX_LEN);
  });
});
