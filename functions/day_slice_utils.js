"use strict";

/**
 * @fileoverview Server-side mirror of the Dart day-slice rule
 * (`lib/features/calendar/domain/appointment_day_slice.dart`). An appointment's
 * two stored times describe a DAILY WINDOW — 9:00-17:00 means 9-to-5 on each
 * day of the run, not one unbroken stretch through the nights.
 *
 * Keep this and the Dart original in lockstep: the jest cases in
 * `__tests__/day_slice_utils.test.js` use the same worked examples as the Dart
 * tests, so a divergence fails rather than ships.
 *
 * Day boundaries use `America/Toronto` (`BUSINESS_TIME_ZONE`) like every other
 * server-side day computation, so this and `widget_payload_utils` agree.
 *
 * @module day_slice_utils
 */

const {
  MAX_APPOINTMENT_SPAN_DAYS,
  toMillis,
  businessYmd,
  businessMinutesOfDay,
  businessDayStartMs,
  businessOffsetMs,
} = require("./time_utils");

/**
 * Toronto midnight of the day containing an instant, as epoch ms.
 * @param {number} msValue
 * @return {number}
 */
function dayStartMs(msValue) {
  return businessDayStartMs(msValue, 0);
}

/**
 * Toronto midnight `n` days from the day containing an instant, as epoch ms.
 * @param {number} msValue
 * @param {number} n
 * @return {number}
 */
function addDaysMs(msValue, n) {
  return businessDayStartMs(msValue, n);
}

/**
 * The instant at `minutes` past midnight, Toronto WALL CLOCK, on the day
 * containing `dayMs`.
 *
 * Deliberately not `dayStartMs(dayMs) + minutes * 60000`: on the two DST shift
 * days an hour is skipped or repeated, so adding elapsed minutes to midnight
 * lands an hour off the wall clock. The crew works 9-to-5 by the clock, not by
 * elapsed hours — which is also what the Dart original's
 * `DateTime(y, m, d, hour, minute)` produces.
 * @param {number} dayMs Any instant inside the target Toronto day.
 * @param {number} minutes Minutes past local midnight; may exceed a day.
 * @return {number}
 */
function businessWallInstantMs(dayMs, minutes) {
  const [y, m, d] = businessYmd(new Date(dayMs));
  const guess = Date.UTC(y, m - 1, d, 0, minutes);
  return guess - businessOffsetMs(new Date(guess));
}

/**
 * Whole calendar days between two instants' Toronto days.
 * @param {number} fromMs
 * @param {number} toMs
 * @return {number}
 */
function calendarDaysBetween(fromMs, toMs) {
  const [fy, fm, fd] = businessYmd(new Date(fromMs));
  const [ty, tm, td] = businessYmd(new Date(toMs));
  return Math.round(
      (Date.UTC(ty, tm - 1, td) - Date.UTC(fy, fm - 1, fd)) / 86400000);
}

/**
 * The record's daily window resolved to plain numbers, or null when it carries
 * no usable start.
 *
 * Equal start/end times count as OVERNIGHT: a booking at the same clock time on
 * consecutive days is a run of continuous 24-hour windows, and a strict `<`
 * would collapse each of them to zero length.
 *
 * A record with **no** `endTime` is a different case and must not take that
 * branch. Legacy and console-written docs exist without one, and the Dart model
 * never emits it as null, so the server is the only side that sees it. It is
 * treated as a single-day job whose window collapses onto its start — the same
 * fallback `hasWorkLeft` uses. Reading it as overnight instead would count the
 * run backwards to zero days and drop the job out of every mirror silently.
 * @param {!Object} r
 * @return {?{startMs: number, endMs: number, overnight: boolean}}
 */
function resolveWindow(r) {
  const startMs = toMillis(r.startTime);
  if (startMs == null) return null;
  const endMs = toMillis(r.endTime);
  if (endMs == null) return {startMs, endMs: startMs, overnight: false};
  return {
    startMs,
    endMs,
    overnight: businessMinutesOfDay(endMs) <= businessMinutesOfDay(startMs),
  };
}

/**
 * True when the record's daily window crosses midnight.
 * @param {!Object} r
 * @return {boolean}
 */
function isOvernightRecord(r) {
  const w = resolveWindow(r);
  return w != null && w.overnight;
}

/**
 * The window-taking forms. Every public helper below resolves the window ONCE
 * and threads it down: `resolveWindow` runs `businessMinutesOfDay` twice and
 * each of those formats through `Intl`, so the old record-taking chain
 * (`sliceForDay` → `dayCountOf` → `lastWorkDayMs`) resolved the same window
 * three times per probe. Keep new internals on this form.
 * @param {!{startMs: number, endMs: number, overnight: boolean}} w
 * @return {number}
 */
function lastWorkDayOfWindow(w) {
  return w.overnight ? addDaysMs(w.endMs, -1) : dayStartMs(w.endMs);
}

/**
 * @param {?{startMs: number, endMs: number, overnight: boolean}} w
 * @return {number}
 */
function dayCountOfWindow(w) {
  if (w == null) return 0;
  return calendarDaysBetween(w.startMs, lastWorkDayOfWindow(w)) + 1;
}

/**
 * Toronto midnight of the last day the crew STARTS work — never the morning an
 * overnight run finishes.
 * @param {!Object} r
 * @return {?number}
 */
function lastWorkDayMs(r) {
  const w = resolveWindow(r);
  if (w == null) return null;
  return lastWorkDayOfWindow(w);
}

/**
 * How many days (or nights) the record runs, UNCLAMPED. Can come back below 1
 * on a corrupt record whose end precedes its start — callers must guard.
 * @param {!Object} r
 * @return {number}
 */
function dayCountOf(r) {
  return dayCountOfWindow(resolveWindow(r));
}

/**
 * `lastWorkDayMs`, clamped to `MAX_APPOINTMENT_SPAN_DAYS` from the start day.
 *
 * The clamped form for anything that RENDERS the run's tail. `lastWorkDayMs`
 * is deliberately raw, and `sliceForDay`/`dayCountOf` clamp on the way out — so
 * the push text was the one day-scoping consumer reading a corrupt doc's real
 * end, printing "Wed, Aug 1, 9:00 a.m. – Sun, Mar 12 2028" while the widget
 * counter, the Siri snapshot and the card all said "Day n of 14". Only the
 * console and the Admin SDK can write such a doc, since `firestore.rules`
 * bounds client writes to the same cap.
 * @param {!Object} r
 * @return {?number}
 */
function clampedLastWorkDayMs(r) {
  const w = resolveWindow(r);
  if (w == null) return null;
  const last = lastWorkDayOfWindow(w);
  const cap = addDaysMs(w.startMs, MAX_APPOINTMENT_SPAN_DAYS - 1);
  return last > cap ? cap : last;
}

/**
 * The record as it appears on the Toronto day containing `dayMs`, or null when
 * it doesn't run that day.
 *
 * Slices are generated per WORK day — each day the window BEGINS — not per
 * calendar day the stored span touches. That is what keeps a night shift off
 * the morning it ends.
 *
 * The count is clamped to `MAX_APPOINTMENT_SPAN_DAYS` like every day-scoping
 * answer on the Dart side. `firestore.rules` bounds client writes to the same
 * cap, but the console and the Admin SDK bypass rules, so a doc can still
 * exceed it; left unclamped this would report "Day 400 of 900" on a corrupt
 * record.
 * @param {!Object} r
 * @param {number} dayMs Any instant inside the target Toronto day.
 * @return {?{dayIndex: number, dayCount: number, windowStartMs: number,
 *   windowEndMs: number, isOvernight: boolean, isMultiDay: boolean,
 *   record: !Object}}
 */
function sliceForDay(r, dayMs) {
  const w = resolveWindow(r);
  if (w == null) return null;
  const rawCount = dayCountOfWindow(w);
  if (rawCount < 1) return null;
  const count = Math.min(rawCount, MAX_APPOINTMENT_SPAN_DAYS);
  const index = calendarDaysBetween(w.startMs, dayMs) + 1;
  if (index < 1 || index > count) return null;

  return {
    record: r,
    dayIndex: index,
    dayCount: count,
    windowStartMs: businessWallInstantMs(
        dayMs, businessMinutesOfDay(w.startMs)),
    windowEndMs: businessWallInstantMs(
        w.overnight ? addDaysMs(dayMs, 1) : dayMs,
        businessMinutesOfDay(w.endMs)),
    isOvernight: w.overnight,
    isMultiDay: count > 1,
  };
}

module.exports = {
  // Re-exported rather than restated: `time_utils` already owns the JS copy of
  // the Dart `maxAppointmentSpanDays`, and a second copy here would be a third
  // owner of a constant this module exists to keep in lockstep.
  MAX_APPOINTMENT_SPAN_DAYS,
  calendarDaysBetween,
  isOvernightRecord,
  lastWorkDayMs,
  clampedLastWorkDayMs,
  dayCountOf,
  sliceForDay,
};
