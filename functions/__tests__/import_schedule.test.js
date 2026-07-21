"use strict";

const {isImportDue, SCHEDULE_VALUES} = require("../wave/import_schedule");

const DAY_MS = 24 * 60 * 60 * 1000;
const WEEK_MS = 7 * DAY_MS;
const MONTH_MS = 30 * DAY_MS;

describe("SCHEDULE_VALUES", () => {
  test("is the fixed off/weekly/monthly wire list", () => {
    expect(SCHEDULE_VALUES).toEqual(["off", "weekly", "monthly"]);
  });
});

describe("isImportDue", () => {
  test("off is never due, even with a stale lastAutoImportMs", () => {
    expect(isImportDue("off", 0, MONTH_MS * 10)).toBe(false);
  });

  test("off is never due when it has never run", () => {
    expect(isImportDue("off", null, 1_000)).toBe(false);
  });

  test("an unknown schedule value is treated as off", () => {
    expect(isImportDue("daily", null, MONTH_MS * 10)).toBe(false);
  });

  test("undefined schedule is treated as off", () => {
    expect(isImportDue(undefined, null, MONTH_MS * 10)).toBe(false);
  });

  test("empty-string schedule is treated as off", () => {
    expect(isImportDue("", null, MONTH_MS * 10)).toBe(false);
  });

  describe("weekly, never run before", () => {
    test("null lastAutoImportMs is due", () => {
      expect(isImportDue("weekly", null, 1_000)).toBe(true);
    });

    test("undefined lastAutoImportMs is due", () => {
      expect(isImportDue("weekly", undefined, 1_000)).toBe(true);
    });

    test("a non-number lastAutoImportMs is treated as never-run", () => {
      expect(isImportDue("weekly", "not-a-number", 1_000)).toBe(true);
    });
  });

  describe("monthly, never run before", () => {
    test("null lastAutoImportMs is due", () => {
      expect(isImportDue("monthly", null, 1_000)).toBe(true);
    });

    test("undefined lastAutoImportMs is due", () => {
      expect(isImportDue("monthly", undefined, 1_000)).toBe(true);
    });
  });

  describe("weekly threshold", () => {
    const last = 10_000_000;

    test("exactly at the week boundary is NOT yet due (strict >)", () => {
      expect(isImportDue("weekly", last, last + WEEK_MS)).toBe(false);
    });

    test("one ms under the week boundary is not due", () => {
      expect(isImportDue("weekly", last, last + WEEK_MS - 1)).toBe(false);
    });

    test("one ms over the week boundary is due", () => {
      expect(isImportDue("weekly", last, last + WEEK_MS + 1)).toBe(true);
    });
  });

  describe("monthly threshold", () => {
    const last = 10_000_000;

    test("exactly at the month boundary is NOT yet due (strict >)", () => {
      expect(isImportDue("monthly", last, last + MONTH_MS)).toBe(false);
    });

    test("one ms under the month boundary is not due", () => {
      expect(isImportDue("monthly", last, last + MONTH_MS - 1)).toBe(false);
    });

    test("one ms over the month boundary is due", () => {
      expect(isImportDue("monthly", last, last + MONTH_MS + 1)).toBe(true);
    });
  });
});
