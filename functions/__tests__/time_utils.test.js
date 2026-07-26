"use strict";

/**
 * Tests for the shared instant + business-time-zone primitives. These focus
 * on DST boundaries, since a push, a Live Activity card, and the widget
 * payload all need to render the same instant identically in America/Toronto.
 */

const {
  BUSINESS_TIME_ZONE,
  toMillis,
  formatBusinessTime,
  formatTimeOfDay,
  businessYmd,
  businessOffsetMs,
  businessMidnight,
} = require("../time_utils");

const HOUR_MS = 60 * 60 * 1000;
const EST_OFFSET_MS = -5 * HOUR_MS;
const EDT_OFFSET_MS = -4 * HOUR_MS;

describe("BUSINESS_TIME_ZONE", () => {
  test("is the single Quebec business zone", () => {
    expect(BUSINESS_TIME_ZONE).toBe("America/Toronto");
  });
});

describe("toMillis", () => {
  test("unwraps a Firestore Timestamp via toMillis()", () => {
    const ts = {toMillis: () => 1735689600000};
    expect(toMillis(ts)).toBe(1735689600000);
  });

  test("reads a Date's epoch millis", () => {
    const d = new Date("2026-07-19T12:34:56.000Z");
    expect(toMillis(d)).toBe(d.getTime());
  });

  test("passes a number through unchanged", () => {
    expect(toMillis(0)).toBe(0);
    expect(toMillis(1735689600000)).toBe(1735689600000);
  });

  test("null / undefined resolve to null", () => {
    expect(toMillis(null)).toBeNull();
    expect(toMillis(undefined)).toBeNull();
  });

  test("an ISO string is NOT accepted (returns null)", () => {
    expect(toMillis("2026-07-19T12:00:00Z")).toBeNull();
  });

  test("a plain object without toMillis resolves to null", () => {
    expect(toMillis({seconds: 12345})).toBeNull();
  });
});

describe("formatBusinessTime", () => {
  test("renders in Toronto, not UTC", () => {
    // 2026-07-15T16:00Z is noon EDT — a UTC render would say 16:00/4 PM.
    const out = formatBusinessTime("en", new Date("2026-07-15T16:00:00Z"), {
      hour: "numeric",
      minute: "2-digit",
    });
    expect(out).toMatch(/^12:00/);
  });

  test("returns '' for a value that is not an instant", () => {
    expect(formatBusinessTime("en", null, {hour: "numeric"})).toBe("");
    expect(formatBusinessTime("en", "nope", {hour: "numeric"})).toBe("");
  });

  test("honours the requested Intl options", () => {
    const out = formatBusinessTime("en", new Date("2026-07-15T16:00:00Z"), {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    expect(out).toContain("2026");
    expect(out).toContain("07");
    expect(out).toContain("15");
  });
});

describe("formatTimeOfDay", () => {
  test("EDT (summer): 16:00Z renders as noon", () => {
    expect(formatTimeOfDay("en", new Date("2026-07-15T16:00:00Z")))
        .toMatch(/^12:00/);
  });

  test("EST (winter): 17:00Z renders as noon", () => {
    expect(formatTimeOfDay("en", new Date("2026-01-15T17:00:00Z")))
        .toMatch(/^12:00/);
  });

  test("fr renders the same instant in French form", () => {
    const fr = formatTimeOfDay("fr", new Date("2026-07-15T16:00:00Z"));
    // fr-CA uses a 24h clock ("12 h 00"), so we only check that the hour and
    // minute agree.
    expect(fr).toContain("12");
    expect(fr).toContain("00");
  });

  test("an unknown locale falls back to en-CA rather than throwing", () => {
    expect(formatTimeOfDay("de", new Date("2026-07-15T16:00:00Z")))
        .toMatch(/^12:00/);
  });

  test("a non-instant renders as ''", () => {
    expect(formatTimeOfDay("en", undefined)).toBe("");
  });

  test("a Firestore Timestamp and the equivalent Date agree", () => {
    const d = new Date("2026-07-15T16:00:00Z");
    const ts = {toMillis: () => d.getTime()};
    expect(formatTimeOfDay("en", ts)).toBe(formatTimeOfDay("en", d));
  });
});

describe("businessOffsetMs", () => {
  test("winter is EST (UTC-5)", () => {
    expect(businessOffsetMs(new Date("2026-01-15T12:00:00Z")))
        .toBe(EST_OFFSET_MS);
  });

  test("summer is EDT (UTC-4)", () => {
    expect(businessOffsetMs(new Date("2026-07-15T12:00:00Z")))
        .toBe(EDT_OFFSET_MS);
  });

  // Spring forward 2026: Sun Mar 8, 02:00 EST -> 03:00 EDT (07:00Z).
  test("one minute before spring forward is still EST", () => {
    expect(businessOffsetMs(new Date("2026-03-08T06:59:00Z")))
        .toBe(EST_OFFSET_MS);
  });

  test("at the spring-forward instant the zone is EDT", () => {
    expect(businessOffsetMs(new Date("2026-03-08T07:00:00Z")))
        .toBe(EDT_OFFSET_MS);
  });

  // Fall back 2026: Sun Nov 1, 02:00 EDT -> 01:00 EST (06:00Z).
  test("the first (EDT) 01:00 on fall-back day is UTC-4", () => {
    expect(businessOffsetMs(new Date("2026-11-01T05:00:00Z")))
        .toBe(EDT_OFFSET_MS);
  });

  test("the second (EST) 01:00 on fall-back day is UTC-5", () => {
    expect(businessOffsetMs(new Date("2026-11-01T06:00:00Z")))
        .toBe(EST_OFFSET_MS);
  });
});

describe("businessYmd", () => {
  test("returns [year, month(1-based), day] in Toronto", () => {
    expect(businessYmd(new Date("2026-07-15T16:00:00Z")))
        .toEqual([2026, 7, 15]);
  });

  test("late-UTC instants still belong to the previous Toronto day", () => {
    // 2026-01-01T04:59Z is 2025-12-31 23:59 EST.
    expect(businessYmd(new Date("2026-01-01T04:59:00Z")))
        .toEqual([2025, 12, 31]);
  });

  test("the Toronto day rolls at local midnight, not UTC midnight", () => {
    expect(businessYmd(new Date("2026-01-01T05:00:00Z")))
        .toEqual([2026, 1, 1]);
  });

  test("spring-forward day resolves to that calendar day", () => {
    expect(businessYmd(new Date("2026-03-08T07:00:00Z")))
        .toEqual([2026, 3, 8]);
  });
});

describe("businessMidnight", () => {
  test("a plain winter day is 05:00Z", () => {
    expect(businessMidnight(2026, 1, 15).toISOString())
        .toBe("2026-01-15T05:00:00.000Z");
  });

  test("a plain summer day is 04:00Z", () => {
    expect(businessMidnight(2026, 7, 15).toISOString())
        .toBe("2026-07-15T04:00:00.000Z");
  });

  test("spring-forward day's midnight is still EST (05:00Z)", () => {
    // The shift happens at 02:00, so midnight on Mar 8 is pre-shift.
    expect(businessMidnight(2026, 3, 8).toISOString())
        .toBe("2026-03-08T05:00:00.000Z");
  });

  test("the day after spring forward is only 23 hours long", () => {
    const a = businessMidnight(2026, 3, 8);
    const b = businessMidnight(2026, 3, 9);
    expect(b.getTime() - a.getTime()).toBe(23 * HOUR_MS);
  });

  test("fall-back day's midnight is still EDT (04:00Z)", () => {
    expect(businessMidnight(2026, 11, 1).toISOString())
        .toBe("2026-11-01T04:00:00.000Z");
  });

  test("fall-back day is 25 hours long", () => {
    const a = businessMidnight(2026, 11, 1);
    const b = businessMidnight(2026, 11, 2);
    expect(b.getTime() - a.getTime()).toBe(25 * HOUR_MS);
  });

  test("an overflowing day rolls into the next month", () => {
    // day 32 of January == February 1.
    expect(businessMidnight(2026, 1, 32).toISOString())
        .toBe(businessMidnight(2026, 2, 1).toISOString());
  });

  test("round-trips with businessYmd", () => {
    for (const [y, m, d] of [[2026, 3, 8], [2026, 11, 1], [2026, 7, 15]]) {
      expect(businessYmd(businessMidnight(y, m, d))).toEqual([y, m, d]);
    }
  });
});
