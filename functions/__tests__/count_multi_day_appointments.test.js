"use strict";

/**
 * Tests for `countMultiDay` — the tally in
 * `scripts/count-multi-day-appointments.js`.
 *
 * This is a SIZING script: its numbers decide whether a multi-day backfill is
 * worth writing and how much work it would be. Every branch below silently
 * changes an answer rather than failing — a run counted as closed when it is
 * open shrinks the work, `openHistogram` keyed on the raw count instead of the
 * clamped one mis-sizes the split, and an early exit from the paging loop
 * under-reports everything at once.
 */

const {countMultiDay} = require("../scripts/count-multi-day-appointments");
const {MAX_APPOINTMENT_SPAN_DAYS} = require("../day_slice_utils");

/** Mirrors `PAGE_SIZE` in the script. */
const PAGE_SIZE = 500;

/**
 * An appointment spanning `days` calendar days from a fixed start.
 * @param {string} id
 * @param {number} days
 * @param {!Object=} over Extra stored fields.
 * @return {!Object} A document double.
 */
function appt(id, days, over = {}) {
  const start = new Date("2026-08-03T13:00:00Z");
  const end = new Date(start.getTime());
  end.setUTCDate(end.getUTCDate() + (days - 1));
  end.setUTCHours(17);
  return {
    id,
    data: () => ({
      startTime: start,
      endTime: end,
      status: "pending",
      ...over,
    }),
  };
}

/**
 * A Firestore double serving `pages` one at a time.
 * @param {!Array<!Array<!Object>>} pages
 * @param {!Array<string>=} cursors Filled with each `startAfter` doc id.
 * @return {!Object}
 */
function makeDb(pages, cursors = []) {
  let index = 0;
  const query = {
    orderBy: () => query,
    limit: () => query,
    startAfter: (doc) => {
      cursors.push(doc.id);
      return query;
    },
    get: async () => {
      const docs = pages[index] || [];
      index += 1;
      return {empty: docs.length === 0, size: docs.length, docs};
    },
  };
  return {collection: () => query};
}

describe("countMultiDay classification", () => {
  test("a single-day job is scanned but is not multi-day", async () => {
    const tally = await countMultiDay(makeDb([[appt("a1", 1)]]), false);

    expect(tally.scanned).toBe(1);
    expect(tally.multiDay).toBe(0);
    expect(tally.open).toBe(0);
  });

  test("an open multi-day run counts its days into openWorkDays", async () => {
    const tally = await countMultiDay(makeDb([[appt("a1", 3)]]), false);

    expect(tally.multiDay).toBe(1);
    expect(tally.open).toBe(1);
    expect(tally.closed).toBe(0);
    expect(tally.openWorkDays).toBe(3);
    expect(tally.openHistogram.get(3)).toBe(1);
    expect(tally.longest).toBe(3);
  });

  test("a terminal run is CLOSED and contributes no work", async () => {
    // Live work is what a backfill has to move; a done run is history.
    for (const status of ["done", "cancelled"]) {
      const tally = await countMultiDay(
          makeDb([[appt("a1", 3, {status})]]), false);

      expect(tally.closed).toBe(1);
      expect(tally.open).toBe(0);
      expect(tally.openWorkDays).toBe(0);
      expect(tally.openHistogram.size).toBe(0);
    }
  });

  test("time off is DERIVED from both flags, never the raw isDayOff",
      async () => {
        // A client visit carrying a stray `isDayOff` from a console edit is
        // still real work, and counting it as time off would drop it from
        // the sizing entirely.
        const stray = await countMultiDay(
            makeDb([[appt("a1", 3, {isDayOff: true})]]), false);
        expect(stray.timeOff).toBe(0);
        expect(stray.openWorkDays).toBe(3);

        const real = await countMultiDay(
            makeDb([[appt("a2", 3, {isDayOff: true, isPersonal: true})]]),
            false);
        expect(real.timeOff).toBe(1);
        expect(real.openTimeOff).toBe(1);
        expect(real.openWorkDays).toBe(0);
      });

  test("counts photos and series membership only on open work", async () => {
    const tally = await countMultiDay(makeDb([[
      appt("a1", 2, {pictureCount: 3, seriesId: "s1"}),
      appt("a2", 2, {pictureCount: 3, seriesId: "s1", status: "done"}),
    ]]), false);

    expect(tally.withPhotos).toBe(1);
    expect(tally.inSeries).toBe(1);
  });

  test("a blank seriesId is not membership", async () => {
    const tally = await countMultiDay(
        makeDb([[appt("a1", 2, {seriesId: "   "})]]), false);

    expect(tally.inSeries).toBe(0);
  });
});

describe("countMultiDay and the span cap", () => {
  test("counts the RAW span as over-cap but histograms the CLAMPED one",
      async () => {
        // The raw count is what says a document exceeds the cap at all; the
        // clamped one is what a split would actually produce. Keying the
        // histogram on the raw count would over-size the work.
        const over = MAX_APPOINTMENT_SPAN_DAYS + 5;
        const tally = await countMultiDay(makeDb([[appt("a1", over)]]), false);

        expect(tally.overCap).toBe(1);
        expect(tally.longest).toBe(over);
        expect(tally.openWorkDays).toBe(MAX_APPOINTMENT_SPAN_DAYS);
        expect(tally.openHistogram.get(MAX_APPOINTMENT_SPAN_DAYS)).toBe(1);
        expect(tally.openHistogram.get(over)).toBeUndefined();
      });

  test("a run exactly at the cap is not over it", async () => {
    const tally = await countMultiDay(
        makeDb([[appt("a1", MAX_APPOINTMENT_SPAN_DAYS)]]), false);

    expect(tally.overCap).toBe(0);
  });
});

describe("countMultiDay paging", () => {
  test("a FULL page continues the walk and pages on its last doc", async () => {
    const cursors = [];
    const full = [];
    for (let i = 0; i < PAGE_SIZE; i += 1) full.push(appt(`a${i}`, 2));

    const tally = await countMultiDay(
        makeDb([full, [appt("z1", 2)]], cursors), false);

    expect(tally.scanned).toBe(PAGE_SIZE + 1);
    expect(tally.multiDay).toBe(PAGE_SIZE + 1);
    expect(cursors).toEqual([`a${PAGE_SIZE - 1}`]);
  });

  test("an empty collection reports a zeroed tally", async () => {
    const tally = await countMultiDay(makeDb([[]]), false);

    expect(tally.scanned).toBe(0);
    expect(tally.multiDay).toBe(0);
    expect(tally.openHistogram.size).toBe(0);
  });
});
