"use strict";

/**
 * @fileoverview The shared terminal/cancelled status vocabulary.
 *
 * This existed at four sites before 2026-08-11 and TWO of them had already
 * dropped the legacy `completed` alias, each failing in the silent direction:
 * the retention purge never became eligible for such a doc, and a flip to
 * `completed` never ended its Live Activity card. Both are unobservable — no
 * error, no log, just work that doesn't happen — so the divergence survived a
 * previous audit. These tests exist to make the next divergence fail loudly.
 */

const {
  TERMINAL_STATUSES,
  isTerminalStatus,
  isCancelledStatus,
  isCompletedStatus,
  normalizedStatus,
} = require("../time_utils");
const {PURGE_STATUSES} = require("../maintenance_policy");

describe("the terminal set", () => {
  test("carries the legacy completed alias", () => {
    // The whole point. `done` and `completed` mean the same thing; only the
    // console and the Admin SDK can still write the alias, which is why
    // dropping it goes unnoticed.
    expect([...TERMINAL_STATUSES]).toEqual(["done", "completed", "cancelled"]);
  });

  test("every consumer derives from it rather than restating it", () => {
    // maintenance_policy dropped `completed` and its own comment still claimed
    // "ONLY terminal appointments are ever purged" while excluding one.
    expect(PURGE_STATUSES).toEqual([...TERMINAL_STATUSES]);
  });
});

describe("the predicates", () => {
  test("terminal covers all three spellings, case-insensitively", () => {
    for (const raw of ["done", "completed", "cancelled", "DONE", "Cancelled"]) {
      expect(isTerminalStatus(raw)).toBe(true);
    }
    for (const raw of ["pending", "in_progress", "confirmed", ""]) {
      expect(isTerminalStatus(raw)).toBe(false);
    }
  });

  test("completed is the terminal set minus cancelled", () => {
    expect(isCompletedStatus("done")).toBe(true);
    expect(isCompletedStatus("completed")).toBe(true);
    expect(isCompletedStatus("cancelled")).toBe(false);
    expect(isCompletedStatus("pending")).toBe(false);
  });

  test("cancelled is case-insensitive", () => {
    // A console-written "Cancelled" must not read as live work on one surface
    // and as cancelled on another.
    expect(isCancelledStatus("Cancelled")).toBe(true);
    expect(isCancelledStatus("CANCELLED")).toBe(true);
    expect(isCancelledStatus("cancel")).toBe(false);
  });

  test("a missing or non-string status is not terminal", () => {
    for (const raw of [undefined, null, 0, false, {}]) {
      expect(isTerminalStatus(raw)).toBe(false);
      expect(isCancelledStatus(raw)).toBe(false);
    }
    expect(normalizedStatus(undefined)).toBe("");
  });
});
