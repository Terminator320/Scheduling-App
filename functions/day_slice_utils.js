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
  businessMidnight,
  businessOffsetMs,
} = require("./time_utils");

/**
 * Toronto midnight of the day containing an instant, as epoch ms.
 * @param {number} msValue
 * @return {number}
 */
function dayStartMs(msValue) {
  const [y, m, d] = businessYmd(new Date(msValue));
  return businessMidnight(y, m, d).getTime();
}

/**
 * Toronto midnight `n` days from the day containing an instant, as epoch ms.
 * @param {number} msValue
 * @param {number} n
 * @return {number}
 */
function addDaysMs(msValue, n) {
  const [y, m, d] = businessYmd(new Date(msValue));
  return businessMidnight(y, m, d + n).getTime();
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
 * True when the record's daily window crosses midnight.
 *
 * Equal times count as overnight: a booking at the same clock time on
 * consecutive days is a run of continuous 24-hour windows, and a strict `<`
 * would collapse each of them to zero length.
 * @param {!Object} r
 * @return {boolean}
 */
function isOvernightRecord(r) {
  const s = businessMinutesOfDay(r.startTime);
  const e = businessMinutesOfDay(r.endTime);
  if (s == null || e == null) return false;
  return e <= s;
}

/**
 * Toronto midnight of the last day the crew STARTS work — never the morning an
 * overnight run finishes.
 * @param {!Object} r
 * @return {?number}
 */
function lastWorkDayMs(r) {
  const e = toMillis(r.endTime);
  if (e == null) return null;
  return isOvernightRecord(r) ? addDaysMs(e, -1) : dayStartMs(e);
}

/**
 * How many days (or nights) the record runs, UNCLAMPED. Can come back below 1
 * on a corrupt record whose end precedes its start — callers must guard.
 * @param {!Object} r
 * @return {number}
 */
function dayCountOf(r) {
  const s = toMillis(r.startTime);
  const last = lastWorkDayMs(r);
  if (s == null || last == null) return 0;
  return calendarDaysBetween(s, last) + 1;
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
 * answer on the Dart side. The cap is client-side only, so a doc written by the
 * console or the Admin SDK can exceed it; left unclamped this would report
 * "Day 400 of 900" on a corrupt record.
 * @param {!Object} r
 * @param {number} dayMs Any instant inside the target Toronto day.
 * @return {?{dayIndex: number, dayCount: number, windowStartMs: number,
 *   windowEndMs: number, isOvernight: boolean, isMultiDay: boolean,
 *   record: !Object}}
 */
function sliceForDay(r, dayMs) {
  const startMs = toMillis(r.startTime);
  const endMs = toMillis(r.endTime);
  if (startMs == null || endMs == null) return null;
  const rawCount = dayCountOf(r);
  if (rawCount < 1) return null;
  const count = Math.min(rawCount, MAX_APPOINTMENT_SPAN_DAYS);
  const index = calendarDaysBetween(startMs, dayMs) + 1;
  if (index < 1 || index > count) return null;

  const overnight = isOvernightRecord(r);
  const startMinutes = businessMinutesOfDay(startMs);
  const endMinutes = businessMinutesOfDay(endMs);
  return {
    record: r,
    dayIndex: index,
    dayCount: count,
    windowStartMs: businessWallInstantMs(dayMs, startMinutes),
    windowEndMs: businessWallInstantMs(
        overnight ? addDaysMs(dayMs, 1) : dayMs, endMinutes),
    isOvernight: overnight,
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
  dayCountOf,
  sliceForDay,
};
