"use strict";

const {isImportDue, SCHEDULE_VALUES} = require("../import_schedule");

const DAY = 24 * 60 * 60 * 1000;
const NOW = 1_000 * DAY; // arbitrary fixed "now" in ms

describe("isImportDue", () => {
  test("off is never due", () => {
    expect(isImportDue("off", null, NOW)).toBe(false);
    expect(isImportDue("off", NOW - 999 * DAY, NOW)).toBe(false);
  });

  test("unknown/empty schedule is never due", () => {
    expect(isImportDue("", null, NOW)).toBe(false);
    expect(isImportDue("yearly", null, NOW)).toBe(false);
    expect(isImportDue(undefined, null, NOW)).toBe(false);
  });

  test("weekly is due when never run", () => {
    expect(isImportDue("weekly", null, NOW)).toBe(true);
  });

  test("weekly is due just past 7 days, not before", () => {
    expect(isImportDue("weekly", NOW - 7 * DAY - 1, NOW)).toBe(true);
    expect(isImportDue("weekly", NOW - 7 * DAY + 1, NOW)).toBe(false);
    expect(isImportDue("weekly", NOW - 6 * DAY, NOW)).toBe(false);
  });

  test("monthly is due when never run", () => {
    expect(isImportDue("monthly", null, NOW)).toBe(true);
  });

  test("monthly is due just past 30 days, not before", () => {
    expect(isImportDue("monthly", NOW - 30 * DAY - 1, NOW)).toBe(true);
    expect(isImportDue("monthly", NOW - 30 * DAY + 1, NOW)).toBe(false);
    expect(isImportDue("monthly", NOW - 8 * DAY, NOW)).toBe(false);
  });

  test("SCHEDULE_VALUES lists exactly the accepted strings", () => {
    expect(SCHEDULE_VALUES).toEqual(["off", "weekly", "monthly"]);
  });
});
