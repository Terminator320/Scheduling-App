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
} = require("../client_propagation");

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
