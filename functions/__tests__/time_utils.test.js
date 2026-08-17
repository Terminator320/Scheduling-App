"use strict";

/**
 * Tests for the shared instant + business-time-zone primitives. These focus
 * on DST boundaries, since a push, a Live Activity card, and the widget
 * payload all need to render the same instant identically in America/Toronto.
 */

const {
  BUSINESS_TIME_ZONE,
  toMillis,
  businessMinutesOfDay,
  hasWorkLeft,
  formatBusinessTime,
  formatTimeOfDay,
  businessYmd,
  businessOffsetMs,
  businessMidnight,
  businessDayStartMs,
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

describe("businessDayStartMs", () => {
  // The one owner of the `businessMidnight(...businessYmd(x), d + n)`
  // composition that was spelled out at four call sites. Its whole reason for
  // existing is that the offset must be applied as a CALENDAR day and then
  // re-resolved against the zone — adding `n * 86400000` instead lands an hour
  // off on the two DST shift days, which is the documented bug shape.
  const at = (iso) => new Date(iso).getTime();

  test("offset 0 is that Toronto day's midnight", () => {
    // 16:00Z on Jul 15 is noon EDT — same Toronto day.
    expect(businessDayStartMs(at("2026-07-15T16:00:00Z"), 0))
        .toBe(at("2026-07-15T04:00:00Z"));
  });

  test("the offset defaults to 0", () => {
    expect(businessDayStartMs(at("2026-07-15T16:00:00Z")))
        .toBe(at("2026-07-15T04:00:00Z"));
  });

  test("a Date and its epoch ms give the same answer", () => {
    const iso = "2026-01-15T18:30:00Z";
    expect(businessDayStartMs(new Date(iso), 1))
        .toBe(businessDayStartMs(at(iso), 1));
  });

  test("an instant just after local midnight belongs to the new day", () => {
    // 05:00Z on Jan 1 is exactly 00:00 EST.
    expect(businessDayStartMs(at("2026-01-01T05:00:00Z"), 0))
        .toBe(at("2026-01-01T05:00:00Z"));
    // One minute earlier is still Dec 31.
    expect(businessDayStartMs(at("2026-01-01T04:59:00Z"), 0))
        .toBe(at("2025-12-31T05:00:00Z"));
  });

  test("a positive offset rolls into the next month", () => {
    expect(businessDayStartMs(at("2026-01-31T20:00:00Z"), 1))
        .toBe(at("2026-02-01T05:00:00Z"));
  });

  test("a negative offset walks backwards across a year boundary", () => {
    expect(businessDayStartMs(at("2026-01-01T12:00:00Z"), -1))
        .toBe(at("2025-12-31T05:00:00Z"));
  });

  test("spring-forward: +1 day is 23 hours, not 24", () => {
    // Mar 8 2026 is the shift day; its midnight is still EST (05:00Z) and the
    // next midnight is EDT (04:00Z).
    const shiftDay = at("2026-03-08T12:00:00Z");
    const start = businessDayStartMs(shiftDay, 0);
    const next = businessDayStartMs(shiftDay, 1);
    expect(start).toBe(at("2026-03-08T05:00:00Z"));
    expect(next).toBe(at("2026-03-09T04:00:00Z"));
    expect(next - start).toBe(23 * HOUR_MS);
    // The naive elapsed-ms form would have landed here — the bug this owner
    // exists to make unrepeatable.
    expect(next).not.toBe(start + 24 * HOUR_MS);
  });

  test("fall-back: +1 day is 25 hours, not 24", () => {
    const shiftDay = at("2026-11-01T12:00:00Z");
    const start = businessDayStartMs(shiftDay, 0);
    const next = businessDayStartMs(shiftDay, 1);
    expect(start).toBe(at("2026-11-01T04:00:00Z"));
    expect(next).toBe(at("2026-11-02T05:00:00Z"));
    expect(next - start).toBe(25 * HOUR_MS);
  });

  test("stepping across a shift day one day at a time lands on midnights",
      () => {
        // Every intermediate answer must still be a real Toronto midnight —
        // an accumulated hour would leave the whole chain an hour out.
        let cursor = at("2026-03-06T12:00:00Z");
        for (const expected of [
          "2026-03-07T05:00:00Z",
          "2026-03-08T05:00:00Z",
          "2026-03-09T04:00:00Z",
          "2026-03-10T04:00:00Z",
        ]) {
          cursor = businessDayStartMs(cursor, 1);
          expect(new Date(cursor).toISOString())
              .toBe(new Date(at(expected)).toISOString());
        }
      });

  test("agrees with the composition it replaced", () => {
    for (const iso of [
      "2026-03-08T12:00:00Z",
      "2026-11-01T12:00:00Z",
      "2026-07-15T16:00:00Z",
    ]) {
      for (const n of [-1, 0, 1, 2, 14]) {
        const [y, m, d] = businessYmd(new Date(iso));
        expect(businessDayStartMs(at(iso), n))
            .toBe(businessMidnight(y, m, d + n).getTime());
      }
    }
  });
});

describe("businessMinutesOfDay", () => {
  // Minutes past Toronto midnight is the ordering key for a day's job list AND
  // the input to overnight detection (`day_slice_utils.resolveWindow` asks
  // `minutes(end) <= minutes(start)`). An error here silently reclassifies a
  // normal job as a night shift, which moves the day the crew is told to
  // show up.
  const at = (iso) => new Date(iso).getTime();

  test("a summer wall-clock time converts to minutes past local midnight",
      () => {
        // 13:00Z is 09:00 EDT — the crew's usual start.
        expect(businessMinutesOfDay(at("2026-08-01T13:00:00.000Z"))).toBe(540);
      });

  test("a winter wall-clock time uses the EST offset, not the summer one",
      () => {
        // 17:00Z is noon EST. Reusing the EDT offset would report 13:00.
        expect(businessMinutesOfDay(at("2026-01-15T17:00:00.000Z"))).toBe(720);
      });

  test("Toronto midnight is 0, and the minute before it is 1439", () => {
    // The wrap has to land on 0 rather than a full day, or a midnight-start
    // all-day block sorts to the END of its own day.
    expect(businessMinutesOfDay(at("2026-08-01T04:00:00.000Z"))).toBe(0);
    expect(businessMinutesOfDay(at("2026-08-01T03:59:00.000Z"))).toBe(1439);
  });

  test("a pre-epoch instant wraps positively, not negatively", () => {
    // The double modulo `((x % d) + d) % d` exists for this: a bare `%` in JS
    // keeps the sign, so a negative epoch instant would yield a negative
    // minute-of-day and invert every ordering and overnight comparison.
    // 1969-12-31 20:00Z is 15:00 EST.
    expect(businessMinutesOfDay(at("1969-12-31T20:00:00.000Z"))).toBe(900);
  });

  test("spring forward skips 02:00-02:59, it does not shift the clock", () => {
    // Mar 8 2026 jumps 02:00 EST -> 03:00 EDT. Computing the offset once for
    // the whole day (or from midnight) would report 02:00 here and hand every
    // job on that day a one-hour error.
    expect(businessMinutesOfDay(at("2026-03-08T06:59:00.000Z"))).toBe(119);
    expect(businessMinutesOfDay(at("2026-03-08T07:00:00.000Z"))).toBe(180);
  });

  test("fall back repeats 01:00, so two instants share a minute-of-day", () => {
    // Nov 1 2026 rewinds 02:00 EDT -> 01:00 EST. Both 05:00Z and 06:00Z are
    // "01:00" locally. This is real and must stay true of the wall clock —
    // resolving the offset per instant is what keeps 07:00Z reading 02:00
    // instead of 03:00.
    expect(businessMinutesOfDay(at("2026-11-01T05:00:00.000Z"))).toBe(60);
    expect(businessMinutesOfDay(at("2026-11-01T06:00:00.000Z"))).toBe(60);
    expect(businessMinutesOfDay(at("2026-11-01T07:00:00.000Z"))).toBe(120);
  });

  test("a 9-to-5 job on either DST day is still not overnight", () => {
    // The consumer that matters: `minutes(end) <= minutes(start)` decides
    // overnight. A DST slip of an hour in either direction on these two days
    // would make an ordinary day job look like a night shift.
    const springStart = businessMinutesOfDay(at("2026-03-08T14:00:00.000Z"));
    const springEnd = businessMinutesOfDay(at("2026-03-08T22:00:00.000Z"));
    expect(springEnd > springStart).toBe(true);
    const fallStart = businessMinutesOfDay(at("2026-11-01T14:00:00.000Z"));
    const fallEnd = businessMinutesOfDay(at("2026-11-01T22:00:00.000Z"));
    expect(fallEnd > fallStart).toBe(true);
  });

  test("a value that is not an instant resolves to null, never NaN", () => {
    // A NaN would compare false against everything and quietly make every
    // record on the surface non-overnight.
    expect(businessMinutesOfDay(null)).toBeNull();
    expect(businessMinutesOfDay(undefined)).toBeNull();
    expect(businessMinutesOfDay("2026-08-01T13:00:00.000Z")).toBeNull();
    expect(businessMinutesOfDay(Number.NaN)).toBeNull();
  });
});

describe("hasWorkLeft", () => {
  // The ONE owner of "is this job still live?". It was a per-module closure in
  // `notification_policy` and `client_propagation`; route new tests through
  // here rather than re-deriving `endTime ?? startTime` at a call site.
  const NOW_MS = new Date("2026-07-08T16:00:00.000Z").getTime();
  const DAY = 24 * 60 * 60 * 1000;

  test("a run under way but not finished still has work left", () => {
    // THE documented bug: gating on `startTime` meant a job cancelled or
    // deleted on day 4 of 10 pushed NOTHING, and the crew already on site
    // turned up again the next morning.
    const run = {
      startTime: NOW_MS - 3 * DAY,
      endTime: NOW_MS + 6 * DAY,
    };
    expect(hasWorkLeft(run, NOW_MS)).toBe(true);
  });

  test("a run whose end has passed has no work left", () => {
    expect(hasWorkLeft({
      startTime: NOW_MS - 9 * DAY,
      endTime: NOW_MS - 2 * DAY,
    }, NOW_MS)).toBe(false);
  });

  test("the boundary is inclusive: ending exactly now still counts", () => {
    // `>=`, not `>`. A sweep firing on the same millisecond as the end must
    // not drop the job into the gap between the two comparisons.
    expect(hasWorkLeft({endTime: NOW_MS}, NOW_MS)).toBe(true);
    expect(hasWorkLeft({endTime: NOW_MS - 1}, NOW_MS)).toBe(false);
  });

  test("a record with no endTime falls back to its start", () => {
    // Legacy and console-written docs carry no end. Reading the absent end as
    // "no work left" would silence every push for those jobs.
    expect(hasWorkLeft({startTime: NOW_MS + 3 * 60 * 60 * 1000}, NOW_MS))
        .toBe(true);
    expect(hasWorkLeft({startTime: NOW_MS - 3 * 60 * 60 * 1000}, NOW_MS))
        .toBe(false);
  });

  test("an unusable endTime falls back to the start rather than failing shut",
      () => {
        // `toMillis` returns null for an ISO string, and `??` is what routes
        // that to the start — a `||` here would do the same for a legitimate
        // epoch 0, but the real risk is a doc whose end is unparseable
        // dropping out of every sweep silently.
        expect(hasWorkLeft(
            {startTime: NOW_MS + DAY, endTime: "2026-07-09T16:00:00.000Z"},
            NOW_MS)).toBe(true);
      });

  test("a record with neither instant has no work left", () => {
    expect(hasWorkLeft({}, NOW_MS)).toBe(false);
    expect(hasWorkLeft({startTime: null, endTime: null}, NOW_MS)).toBe(false);
  });

  test("a missing record reads as no work left, it does not throw", () => {
    // Callers hand it `before`/`after` straight off a trigger, and a delete
    // has no `after`.
    expect(hasWorkLeft(null, NOW_MS)).toBe(false);
    expect(hasWorkLeft(undefined, NOW_MS)).toBe(false);
  });
});
