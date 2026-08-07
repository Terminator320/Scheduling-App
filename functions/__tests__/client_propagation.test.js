"use strict";

/**
 * Tests for the pure core of the client -> future-appointments propagation
 * trigger, propagateClientEdits. The actual Firestore fan-out
 * (propagateClientChange) is integration-heavy, so it isn't covered here.
 */

const {
  clientDisplayName,
  relevantClientChange,
  buildAppointmentPatch,
  propagateClientChange,
} = require("../client_propagation");

const {MAX_APPOINTMENT_SPAN_MS} = require("../time_utils");

/**
 * Minimal Firestore double: one page of appointment docs, capturing the
 * query's startTime floor and every batch update.
 * @param {!Array<!Object>} docs Appointment doc data, each with an `id`.
 * @return {!Object}
 */
function makeDb(docs) {
  const captured = {floor: null, updates: []};
  const snapDocs = docs.map((data) => ({
    data: () => data,
    ref: {id: data.id},
  }));
  const query = {
    where(field, op, value) {
      if (field === "startTime") captured.floor = value;
      return query;
    },
    orderBy: () => query,
    limit: () => query,
    startAfter: () => query,
    get: async () => ({docs: snapDocs}),
  };
  return {
    captured,
    collection: () => query,
    batch: () => ({
      update: (ref, patch) => captured.updates.push({id: ref.id, patch}),
      commit: async () => {},
    }),
  };
}

describe("clientDisplayName", () => {
  test("uses name when present, trimmed", () => {
    expect(clientDisplayName({name: "  Ada  "})).toBe("Ada");
  });

  test("falls back to businessName when name is blank", () => {
    expect(clientDisplayName({name: "", businessName: "Acme Inc"}))
        .toBe("Acme Inc");
  });

  test("returns empty string when both are blank or missing", () => {
    expect(clientDisplayName({})).toBe("");
    expect(clientDisplayName(null)).toBe("");
  });
});

describe("relevantClientChange", () => {
  test("returns null when nothing relevant changed", () => {
    const doc = {name: "Ada", phone: "555", address: "1 St"};
    expect(relevantClientChange(doc, {...doc})).toBeNull();
  });

  test("detects a name change", () => {
    const change = relevantClientChange({name: "Ada"}, {name: "Bea"});
    expect(change).toEqual({clientName: "Bea", address: null});
  });

  test("detects a phone change", () => {
    const change = relevantClientChange({phone: "111"}, {phone: "222"});
    expect(change).toEqual({clientPhone: "222", address: null});
  });

  test("detects a name change via the legacy businessName fallback", () => {
    const change = relevantClientChange(
        {name: "", businessName: "Old Co"},
        {name: "", businessName: "New Co"});
    expect(change).toEqual({clientName: "New Co", address: null});
  });

  test("propagates an address change from a NON-EMPTY previous value", () => {
    const change = relevantClientChange(
        {address: "1 Old St"}, {address: "2 New Rd"});
    expect(change).toEqual({address: {from: "1 Old St", to: "2 New Rd"}});
  });

  test("does NOT propagate when the previous address was empty", () => {
    // An empty stored appointment address means custom/none. Matching on ""
    // would clobber those, so an empty-from change carries no instruction.
    expect(relevantClientChange({address: ""}, {address: "2 New Rd"}))
        .toBeNull();
  });
});

describe("buildAppointmentPatch", () => {
  test("patches clientName only when it differs", () => {
    const change = {clientName: "Bea"};
    expect(buildAppointmentPatch(change, {clientName: "Ada"}))
        .toEqual({clientName: "Bea"});
    expect(buildAppointmentPatch(change, {clientName: "Bea"})).toBeNull();
  });

  test("follows the client address when the stored one matches from", () => {
    const change = {address: {from: "1 Old St", to: "2 New Rd"}};
    expect(buildAppointmentPatch(change, {address: "1 Old St"}))
        .toEqual({address: "2 New Rd"});
  });

  test("leaves a per-appointment custom address untouched", () => {
    const change = {address: {from: "1 Old St", to: "2 New Rd"}};
    expect(buildAppointmentPatch(change, {address: "Custom Site"})).toBeNull();
  });

  test("is idempotent: an already-propagated address is not re-patched", () => {
    const change = {address: {from: "1 Old St", to: "2 New Rd"}};
    expect(buildAppointmentPatch(change, {address: "2 New Rd"})).toBeNull();
  });
});

describe("propagateClientChange has-work-left gate", () => {
  const now = new Date("2026-08-04T12:00:00Z");
  const before = {name: "Ada", phone: "555"};
  const after = {name: "Bea", phone: "555"};
  const logger = {info: () => {}};

  test("queries back a full appointment span, not from now", async () => {
    const db = makeDb([]);
    await propagateClientChange("c1", before, after, {db, now, logger});
    expect(db.captured.floor.getTime())
        .toBe(now.getTime() - MAX_APPOINTMENT_SPAN_MS);
  });

  test("patches a run started days ago that is still under way", async () => {
    // Started Aug 1, runs through Aug 8 — the crew is on site right now.
    const db = makeDb([{
      id: "mid-run",
      startTime: new Date("2026-08-01T13:00:00Z"),
      endTime: new Date("2026-08-08T21:00:00Z"),
      clientName: "Ada",
    }]);

    const result =
        await propagateClientChange("c1", before, after, {db, now, logger});

    expect(result.updated).toBe(1);
    expect(db.captured.updates[0].id).toBe("mid-run");
    expect(db.captured.updates[0].patch.clientName).toBe("Bea");
  });

  test("leaves a finished run inside the widened window alone", async () => {
    // Pulled in by the wider floor, but its work ended yesterday — history
    // records what was true at the time of the visit.
    const db = makeDb([{
      id: "finished",
      startTime: new Date("2026-07-28T13:00:00Z"),
      endTime: new Date("2026-08-03T21:00:00Z"),
      clientName: "Ada",
    }]);

    const result =
        await propagateClientChange("c1", before, after, {db, now, logger});

    expect(result.updated).toBe(0);
    expect(db.captured.updates).toHaveLength(0);
  });

  test("falls back to startTime when endTime is missing", async () => {
    const db = makeDb([
      {id: "past-no-end", startTime: new Date("2026-08-01T13:00:00Z")},
      {id: "future-no-end", startTime: new Date("2026-08-06T13:00:00Z")},
    ]);

    const result =
        await propagateClientChange("c1", before, after, {db, now, logger});

    expect(result.updated).toBe(1);
    expect(db.captured.updates[0].id).toBe("future-no-end");
  });
});
