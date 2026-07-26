"use strict";

/**
 * @fileoverview Instant + Toronto-local formatting primitives shared by every
 * pure payload module; requires nothing, deliberately, so it can sit under
 * `notification_utils` -> `live_activity_dispatch` -> `live_activity_utils`
 * without closing a require cycle.
 *
 * @module time_utils
 */

/** The one business time zone (Quebec); every user-facing time renders here. */
const BUSINESS_TIME_ZONE = "America/Toronto";

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
 * Business-local midnight of a calendar date as a UTC Date; stable because
 * DST shifts happen at 02:00, not midnight.
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
  toMillis,
  formatBusinessTime,
  formatTimeOfDay,
  businessYmd,
  businessOffsetMs,
  businessMidnight,
};
