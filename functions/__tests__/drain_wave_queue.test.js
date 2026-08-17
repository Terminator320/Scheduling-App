"use strict";

const {
  assertKnownFlags,
  pacingDelayMs,
  parsePositiveInt,
} = require("../scripts/drain-wave-queue");

describe("assertKnownFlags", () => {
  test("accepts the real flags", () => {
    expect(() => assertKnownFlags([])).not.toThrow();
    expect(() => assertKnownFlags(["--dry-run", "--rate=40", "--max=100",
      "--max-idle=3"])).not.toThrow();
  });

  test("refuses a MISTYPED --dry-run rather than starting to push", () => {
    for (const typo of ["--dryrun", "--dry_run", "-dry-run", "--dry"]) {
      expect(() => assertKnownFlags([typo])).toThrow(/unknown argument/);
    }
  });

  test("refuses a token passed as a flag", () => {
    // It must come from the environment — a flag leaks into shell history
    // and `ps`.
    expect(() => assertKnownFlags(["--token=abc"])).toThrow(/unknown argument/);
  });
});

describe("parsePositiveInt", () => {
  test("falls back when the flag is absent", () => {
    expect(parsePositiveInt([], "--rate=", 50)).toBe(50);
  });

  test("reads an explicit value", () => {
    expect(parsePositiveInt(["--rate=30"], "--rate=", 50)).toBe(30);
  });

  test("throws rather than silently reading as the default", () => {
    // A pacing flag that quietly falls back hammers Wave at a rate the
    // operator thought they had turned down.
    expect(() => parsePositiveInt(["--rate=fast"], "--rate=", 50)).toThrow();
    expect(() => parsePositiveInt(["--rate=0"], "--rate=", 50)).toThrow();
    expect(() => parsePositiveInt(["--rate=-5"], "--rate=", 50)).toThrow();
  });

  test("enforces the ceiling", () => {
    // Past Wave's own limit the rejections just go back on the queue.
    expect(() => parsePositiveInt(["--rate=200"], "--rate=", 50, 60))
        .toThrow(/at most 60/);
  });
});

describe("pacingDelayMs", () => {
  test("owes the time a round of jobs costs at the rate", () => {
    // 20 jobs at 50/min is 24 s of budget; the round already spent 4 s.
    expect(pacingDelayMs(20, 4000, 50)).toBe(20000);
  });

  test("asks for no delay when the round was already slow enough", () => {
    expect(pacingDelayMs(20, 30000, 50)).toBe(0);
  });

  test("never returns a negative delay", () => {
    expect(pacingDelayMs(1, 999999, 50)).toBe(0);
  });

  test("does not pace a round that dispatched nothing", () => {
    // Nothing was pushed, so nothing was spent — the caller polls instead.
    expect(pacingDelayMs(0, 0, 50)).toBe(0);
  });

  test("a lower rate buys a longer sleep", () => {
    expect(pacingDelayMs(20, 0, 20)).toBeGreaterThan(pacingDelayMs(20, 0, 60));
  });
});
