"use strict";

/**
 * Unit tests for the server-side day-slice mirror. These are deliberately the
 * SAME worked examples as
 * `test/features/calendar/domain/appointment_day_slice_test.dart`, so a
 * divergence between the Dart original and this hand-mirror fails a test
 * instead of shipping.
 *
 * Instants are written as explicit UTC so the suite is timezone-independent
 * (the neighbouring widget-payload suite does the same). August is EDT, so
 * Toronto is UTC-4 throughout.
 */

const {
  MAX_APPOINTMENT_SPAN_DAYS,
  sliceForDay,
  dayCountOf,
  lastWorkDayMs,
  calendarDaysBetween,
  isOvernightRecord,
} = require("../day_slice_utils");

// Epoch ms of a Toronto wall-clock instant given its UTC ISO form.
const at = (iso) => new Date(iso).getTime();

// Toronto midnights, used as the `dayMs` argument.
const JUL31 = at("2026-07-31T04:00:00.000Z");
const AUG1 = at("2026-08-01T04:00:00.000Z");
const AUG2 = at("2026-08-02T04:00:00.000Z");
const AUG3 = at("2026-08-03T04:00:00.000Z");
const AUG4 = at("2026-08-04T04:00:00.000Z");
const AUG6 = at("2026-08-06T04:00:00.000Z");
const AUG12 = at("2026-08-12T04:00:00.000Z");

// Aug 1 09:00 -> Aug 5 17:00 Toronto: a five-day 9-to-5 run.
const dayJob = {
  startTime: at("2026-08-01T13:00:00.000Z"),
  endTime: at("2026-08-05T21:00:00.000Z"),
};

// Aug 1 22:00 -> Aug 4 06:00 Toronto: three NIGHTS, the last starting Aug 3.
const nightShift = {
  startTime: at("2026-08-02T02:00:00.000Z"),
  endTime: at("2026-08-04T10:00:00.000Z"),
};

describe("day_slice_utils", () => {
  test("the cap matches the Dart constant", () => {
    expect(MAX_APPOINTMENT_SPAN_DAYS).toBe(14);
  });

  test("a single-day job is day 1 of 1", () => {
    const r = {
      startTime: at("2026-08-01T13:00:00.000Z"),
      endTime: at("2026-08-01T21:00:00.000Z"),
    };
    expect(dayCountOf(r)).toBe(1);
    const s = sliceForDay(r, AUG1);
    expect(s.dayIndex).toBe(1);
    expect(s.dayCount).toBe(1);
    expect(s.isMultiDay).toBe(false);
  });

  test("a 5-day job reports the same daily window on every day", () => {
    const s = sliceForDay(dayJob, AUG3);
    expect(s.dayIndex).toBe(3);
    expect(s.dayCount).toBe(5);
    expect(s.isMultiDay).toBe(true);
    expect(s.windowStartMs).toBe(at("2026-08-03T13:00:00.000Z"));
    expect(s.windowEndMs).toBe(at("2026-08-03T21:00:00.000Z"));
    expect(s.isOvernight).toBe(false);
  });

  test("a day outside the run has no slice", () => {
    expect(sliceForDay(dayJob, JUL31)).toBeNull();
    expect(sliceForDay(dayJob, AUG6)).toBeNull();
  });

  test("a night shift counts nights and ends the next morning", () => {
    expect(dayCountOf(nightShift)).toBe(3);
    expect(lastWorkDayMs(nightShift)).toBe(AUG3);
    const s = sliceForDay(nightShift, AUG2);
    expect(s.dayIndex).toBe(2);
    expect(s.isOvernight).toBe(true);
    expect(s.windowStartMs).toBe(at("2026-08-03T02:00:00.000Z"));
    expect(s.windowEndMs).toBe(at("2026-08-03T10:00:00.000Z"));
  });

  test("a night shift has no slice on the morning it finishes", () => {
    expect(sliceForDay(nightShift, AUG4)).toBeNull();
  });

  test("an all-day run is not overnight", () => {
    const r = {
      startTime: at("2026-08-10T04:00:00.000Z"),
      endTime: at("2026-08-15T03:59:00.000Z"),
    };
    expect(dayCountOf(r)).toBe(5);
    expect(sliceForDay(r, AUG12).isOvernight).toBe(false);
  });

  test("an over-long window is clamped to the cap", () => {
    // Written by the console or another build — the rules constrain neither
    // instant, so the clamp is the only thing keeping a day counter sane.
    const corrupt = {
      startTime: at("2026-08-01T13:00:00.000Z"),
      endTime: at("2026-09-30T21:00:00.000Z"),
    };
    expect(dayCountOf(corrupt)).toBe(61);
    expect(sliceForDay(corrupt, AUG3).dayCount).toBe(MAX_APPOINTMENT_SPAN_DAYS);
    // Day 15 of the raw run is past the clamp, so it renders nowhere.
    expect(sliceForDay(corrupt, at("2026-08-15T04:00:00.000Z"))).toBeNull();
  });

  test("a corrupt pair whose end precedes its start has no slice", () => {
    const backwards = {
      startTime: at("2026-08-05T13:00:00.000Z"),
      endTime: at("2026-08-01T21:00:00.000Z"),
    };
    expect(sliceForDay(backwards, AUG3)).toBeNull();
  });

  test("a missing instant has no slice", () => {
    expect(sliceForDay({startTime: null, endTime: null}, AUG3)).toBeNull();
    expect(dayCountOf({})).toBe(0);
  });

  test("a record with no endTime is a single-day job, not a vanished one",
      () => {
        // Legacy and console-written docs exist without one. Reading the
        // absent end as "equal times" would make it overnight, count the run
        // backwards to zero days, and drop the job out of every mirror.
        const r = {startTime: at("2026-08-03T13:00:00.000Z")};
        expect(isOvernightRecord(r)).toBe(false);
        expect(dayCountOf(r)).toBe(1);
        const s = sliceForDay(r, AUG3);
        expect(s.dayIndex).toBe(1);
        expect(s.dayCount).toBe(1);
        expect(s.windowStartMs).toBe(at("2026-08-03T13:00:00.000Z"));
        expect(s.windowEndMs).toBe(at("2026-08-03T13:00:00.000Z"));
      });

  test("a window on a DST shift day keeps its wall clock", () => {
    // Mar 8 2026 springs forward at 02:00, so that Toronto day is 23 hours
    // long. A 9-to-5 crew still starts at 9 by the clock — computing the
    // window as midnight plus 540 ELAPSED minutes would land it at 10:00.
    const r = {
      startTime: at("2026-03-06T14:00:00.000Z"), // Mar 6 09:00 EST
      endTime: at("2026-03-10T21:00:00.000Z"), // Mar 10 17:00 EDT
    };
    const s = sliceForDay(r, at("2026-03-08T05:00:00.000Z"));
    expect(s.dayIndex).toBe(3);
    expect(s.windowStartMs).toBe(at("2026-03-08T13:00:00.000Z")); // 09:00 EDT
    expect(s.windowEndMs).toBe(at("2026-03-08T21:00:00.000Z")); // 17:00 EDT
  });

  test("calendarDaysBetween counts whole Toronto days", () => {
    expect(calendarDaysBetween(AUG1, AUG3)).toBe(2);
    expect(calendarDaysBetween(AUG3, AUG1)).toBe(-2);
    expect(calendarDaysBetween(dayJob.startTime, AUG1)).toBe(0);
  });
});
