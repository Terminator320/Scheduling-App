"use strict";

// `historySearchScopes` is a denormalized mirror of `employeeIds` written by
// the CLIENT app, and `searchHistory` returns the whole document — client
// name, phone, address, notes. The token scope is a PREFILTER; what a
// technician is actually entitled to read is re-verified against
// `employeeIds`, the field `firestore.rules` itself evaluates.

const {historyScope, mayReadHistoryDoc} = require("../indexed_search");

const admin = {role: "admin", docId: "e-admin"};
const tech = {role: "employee", docId: "e1"};

describe("historyScope", () => {
  test("an admin gets the whole business, or the scope asked for", () => {
    expect(historyScope(admin, "")).toBe("all");
    expect(historyScope(admin, "e9")).toBe("emp:e9");
  });

  test("a technician is pinned to their own scope", () => {
    expect(historyScope(tech, "")).toBe("emp:e1");
    expect(historyScope(tech, "e1")).toBe("emp:e1");
  });

  test("a technician asking for somebody else is refused", () => {
    expect(() => historyScope(tech, "e2")).toThrow(/scope-denied/);
  });

  test("a caller with no usable role is refused", () => {
    expect(() => historyScope({role: "employee", docId: ""}, ""))
        .toThrow(/role-denied/);
    expect(() => historyScope({role: "dispatcher", docId: "e1"}, ""))
        .toThrow(/role-denied/);
  });
});

describe("mayReadHistoryDoc", () => {
  test("an admin reads any document", () => {
    expect(mayReadHistoryDoc(admin, {employeeIds: ["e9"]})).toBe(true);
    expect(mayReadHistoryDoc(admin, {})).toBe(true);
  });

  test("a technician reads a job they are assigned to", () => {
    expect(mayReadHistoryDoc(tech, {employeeIds: ["e2", "e1"]})).toBe(true);
  });

  test("a scope that drifted from employeeIds does NOT grant a read", () => {
    // The whole point: the token scope got the doc into the result set, and
    // this is what keeps it out of the response.
    expect(mayReadHistoryDoc(tech, {
      employeeIds: ["e2"],
      historySearchScopes: ["emp:e1:t:marc"],
    })).toBe(false);
  });

  test("a document with no assignees at all is refused", () => {
    expect(mayReadHistoryDoc(tech, {})).toBe(false);
    expect(mayReadHistoryDoc(tech, {employeeIds: null})).toBe(false);
  });

  test("a caller with no doc id is refused rather than matched loosely", () => {
    expect(mayReadHistoryDoc({role: "employee", docId: ""}, {
      employeeIds: [""],
    })).toBe(false);
  });
});
