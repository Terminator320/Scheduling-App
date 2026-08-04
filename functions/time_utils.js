"use strict";

/**
 * @fileoverview Instant + Toronto-local formatting primitives shared by every
 * pure payload module. It deliberately requires nothing else, so it can sit
 * under `notification_utils` -> `live_activity_dispatch` ->
 * `live_activity_utils` without closing a require cycle.
 *
 * @module time_utils
 */

/**
 * The one business time zone (Quebec) — every user-facing time renders here.
 */
const BUSINESS_TIME_ZONE = "America/Toronto";

/**
 * The longest span a job may be booked for, in days.
 *
 * HAND-MIRRORED from `maxAppointmentSpanDays` in
 * `lib/features/calendar/domain/appointment_day_slice.dart` — the cap is
 * enforced client-side only (firestore.rules constrains neither instant), so
 * this copy exists purely to size the backend's query windows. Every sweep
 * that filters on `startTime` must reach at least this far back, or a job
 * already under way is invisible to it. Raise both together.
 */
const MAX_APPOINTMENT_SPAN_DAYS = 14;

/**
 * The same cap in milliseconds — the usual form for widening a query floor.
 */
const MAX_APPOINTMENT_SPAN_MS = MAX_APPOINTMENT_SPAN_DAYS * 24 * 60 * 60 * 1000;

/**
 * Minutes past business-local midnight for an instant, or null.
 *
 * The ordering key for anything listing a DAY's jobs. A multi-day run's stored
 * `startTime` is the first morning of the run, so sorting a day's list by the
 * absolute instant floats that run to the front however late in the day it
 * actually works — the two stored times are a daily WINDOW, and this is the
 * clock time inside it.
 * @param {*} value Timestamp/Date/number.
 * @return {?number}
 */
function businessMinutesOfDay(value) {
  const ms = toMillis(value);
  if (ms == null) return null;
  const local = ms + businessOffsetMs(new Date(ms));
  const dayMs = 24 * 60 * 60 * 1000;
  return Math.floor((((local % dayMs) + dayMs) % dayMs) / 60000);
}

/**
 * Milliseconds since epoch for a Firestore Timestamp / Date / number, else
 * null.
 * @param {*} value
 * @return {?number}
 */
function toMillis(value) {
  if (value == null) return null;
  if (typeof value.toMillis === "function") {
    const ms = value.toMillis();
    return typeof ms === "number" && Number.isFinite(ms) ? ms : null;
  }
  if (value instanceof Date) {
    const ms = value.getTime();
    return Number.isFinite(ms) ? ms : null;
  }
  // Finite-checked so NaN/Infinity degrade to "" like every other bad input
  // here, instead of throwing RangeError out of Intl/new Date() and taking
  // down a notification build in a best-effort consumer.
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  return null;
}

/**
 * True when an appointment still has work left at `nowMs` — NOT "does it start
 * in the future".
 *
 * Under the daily-window model a run can be days past its `startTime` and
 * still have a week of work left, so every sweep asking "is this job still
 * live?" must test the END. Gating on the start meant cancelling or deleting a
 * job mid-run pushed NOTHING to the crew (who turned up the next morning), and
 * a client's corrected suite number never reached a tech already on site.
 * Falls back to the start when `endTime` is missing.
 *
 * This is the ONE owner: it was a per-module closure in `notification_policy`
 * and `client_propagation`, which is the drift shape that bit `displayStatusAt`
 * and `_who` — a future carve-out patched into one copy and missed in the
 * other. Route any new "is this job still live?" test through it.
 * @param {*} record Appointment data; null/undefined reads as no work left.
 * @param {number} nowMs Reference instant, ms since epoch.
 * @return {boolean}
 */
function hasWorkLeft(record, nowMs) {
  if (!record) return false;
  const ms = toMillis(record.endTime) ?? toMillis(record.startTime);
  return ms != null && ms >= nowMs;
}

/**
 * Formats an instant in the business time zone, or "" when it isn't one.
 * @param {string} locale 'en' | 'fr'.
 * @param {*} value Timestamp/Date/number.
 * @param {!Object} opts Intl.DateTimeFormat options (time zone is added).
 * @return {string}
 */
function formatBusinessTime(locale, value, opts) {
  const ms = toMillis(value);
  if (ms == null) return "";
  return new Intl.DateTimeFormat(locale === "fr" ? "fr-CA" : "en-CA", {
    timeZone: BUSINESS_TIME_ZONE,
    ...opts,
  }).format(new Date(ms));
}

/**
 * Localized time of day ("7:54"), the one form the card and the push must
 * agree on.
 * @param {string} locale 'en' | 'fr'.
 * @param {*} value
 * @return {string}
 */
function formatTimeOfDay(locale, value) {
  return formatBusinessTime(locale, value, {
    hour: "numeric",
    minute: "2-digit",
  });
}

/**
 * The business-local year/month/day of an instant, as numbers.
 * @param {!Date} date
 * @return {!Array<number>} `[year, month, day]` (month is 1-based).
 */
function businessYmd(date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: BUSINESS_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  })
      .format(date)
      .split("-")
      .map(Number);
}

/**
 * Business-zone UTC offset (ms to add to a UTC instant to get local wall time)
 * at `date`.
 * @param {!Date} date
 * @return {number}
 */
function businessOffsetMs(date) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: BUSINESS_TIME_ZONE,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(date).reduce((acc, p) => {
    acc[p.type] = p.value;
    return acc;
  }, {});
  const asUtc = Date.UTC(
      Number(parts.year),
      Number(parts.month) - 1,
      Number(parts.day),
      Number(parts.hour),
      Number(parts.minute),
      Number(parts.second),
  );
  return asUtc - date.getTime();
}

/**
 * Business-local midnight of a calendar date as a UTC Date. This stays
 * stable because DST shifts happen at 02:00, not midnight.
 * @param {number} year
 * @param {number} month 1-based.
 * @param {number} day May overflow (day + 1 rolls the month).
 * @return {!Date}
 */
function businessMidnight(year, month, day) {
  const guess = Date.UTC(year, month - 1, day, 0, 0, 0);
  return new Date(guess - businessOffsetMs(new Date(guess)));
}

module.exports = {
  BUSINESS_TIME_ZONE,
  MAX_APPOINTMENT_SPAN_DAYS,
  MAX_APPOINTMENT_SPAN_MS,
  businessMinutesOfDay,
  toMillis,
  hasWorkLeft,
  formatBusinessTime,
  formatTimeOfDay,
  businessYmd,
  businessOffsetMs,
  businessMidnight,
};
