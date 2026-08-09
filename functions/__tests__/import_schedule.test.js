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

// ---------------------------------------------------------------------------
// Delta-import window
// ---------------------------------------------------------------------------
//
// This decides which customers an import is even allowed to see. Every wrong
// answer is silent: too narrow and changed customers are skipped forever, too
// wide and it merely costs a little more.

const {
  resolveImportWindow,
  watermarkPatch,
  FULL_RESYNC_INTERVAL_MS,
} = require("../wave/import_schedule");

describe("resolveImportWindow", () => {
  const DAY = DAY_MS;
  const NOW = 1_800_000_000_000;

  test("no watermark yet → full import", () => {
    expect(resolveImportWindow(
        {deltaSinceMs: null, lastFullMs: NOW, nowMs: NOW}))
        .toEqual({since: "", reason: "no-watermark"});
  });

  test("a stale full pass forces another one", () => {
    // The backstop for Wave not bumping modifiedAt on some change we map —
    // which we trust and cannot verify.
    expect(resolveImportWindow({
      deltaSinceMs: NOW - 60_000,
      lastFullMs: NOW - 8 * DAY,
      nowMs: NOW,
    })).toEqual({since: "", reason: "periodic-full-resync"});
  });

  test("a watermark in the future is refused, not honoured", () => {
    // Honouring it would ask Wave for changes after a time that hasn't
    // happened — importing nothing, every run, forever.
    expect(resolveImportWindow({
      deltaSinceMs: NOW + DAY,
      lastFullMs: NOW - DAY,
      nowMs: NOW,
    })).toEqual({since: "", reason: "watermark-ahead"});
  });

  test("otherwise a delta from the stored instant", () => {
    const result = resolveImportWindow({
      deltaSinceMs: NOW - 60_000,
      lastFullMs: NOW - DAY,
      nowMs: NOW,
    });
    expect(result.reason).toBe("delta");
    expect(result.since).toBe(new Date(NOW - 60_000).toISOString());
  });

  test("a scheduled run whose last full pass was a cadence ago goes full",
      () => {
        // Documented consequence, pinned so it stays visible: the resync
        // interval is <= both cadences, and isImportDue only fires once the
        // cadence has elapsed — so when the scheduled import is the only
        // thing running, lastFullImportAt is always at least that old and it
        // goes full every time. The delta then only benefits the INTERACTIVE
        // sync. Cheap to accept; lengthening the interval past MONTH_MS to
        // "fix" it would trade a real staleness guarantee for that
        // non-saving.
        expect(FULL_RESYNC_INTERVAL_MS).toBeLessThanOrEqual(WEEK_MS);
        for (const cadence of [WEEK_MS, MONTH_MS]) {
          expect(resolveImportWindow({
            deltaSinceMs: NOW - 1000,
            lastFullMs: NOW - cadence,
            nowMs: NOW,
          }).reason).toBe("periodic-full-resync");
        }
      });

  test("but a recent interactive full pass does let a scheduled run go delta",
      () => {
        // lastFullImportAt is shared between the two callers, so the above is
        // a common case, not an invariant. Both outcomes are correct — a full
        // pass really did just run.
        expect(resolveImportWindow({
          deltaSinceMs: NOW - 1000,
          lastFullMs: NOW - 1000,
          nowMs: NOW,
        }).reason).toBe("delta");
      });
});

describe("watermarkPatch", () => {
  const NOW = 1_800_000_000_000;

  test("rewinds behind the run start", () => {
    // From the run's END it would drop anything edited while it was in
    // flight; with no overlap, anything edited in the same second the query
    // went out, and no slack for clock skew against Wave.
    const patch = watermarkPatch({startedAtMs: NOW, wasFull: false});
    expect(patch.customerDeltaSince.getTime()).toBeLessThan(NOW);
    expect(patch).not.toHaveProperty("lastFullImportAt");
  });

  test("a full run also restarts the resync clock", () => {
    const patch = watermarkPatch({startedAtMs: NOW, wasFull: true});
    expect(patch.lastFullImportAt.getTime()).toBe(NOW);
  });
});
