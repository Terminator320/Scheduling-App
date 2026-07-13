"use strict";

/**
 * @fileoverview Server-side mirror of the Flutter widget payload builder
 * (`lib/features/home_widget/application/widget_sync_service.dart`). A
 * change-driven push carries the fresh payload so the iOS home-screen widget
 * can be rewritten from a background isolate — with the app closed — instead of
 * only when the app next runs. Kept a pure, dependency-free module so jest can
 * load it directly and so the JSON shape stays in lockstep with the Dart
 * builder and the Swift decoder (`ios/ScheduleWidget/ScheduleWidget.swift`).
 *
 * Day boundaries use America/Toronto (the business time zone the rest of the
 * notification backend already hardcodes); a Toronto-based device computes the
 * same local midnight, so the server- and app-written payloads agree.
 *
 * @module widget_payload_utils
 */

// Terminal statuses are filtered out of the widget's job list. Mirrors
// AppointmentStatus.isTerminal (status_chip.dart): done/cancelled, plus the
// legacy `completed` alias of done.
const TERMINAL_STATUSES = new Set(["done", "completed", "cancelled"]);

// How many days past today the "next job" lookahead spans (matches the Dart
// widget range: [today 00:00, today + 3 days)).
const WIDGET_LOOKAHEAD_DAYS = 3;

/**
 * Milliseconds since epoch for a Firestore Timestamp / Date / number, else
 * null.
 * @param {*} value
 * @return {?number}
 */
function toMillis(value) {
  if (value == null) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  return null;
}

/**
 * Epoch ms for a `now` that may be a Date or a number.
 * @param {(Date|number)} now
 * @return {number}
 */
function nowMillis(now) {
  return now instanceof Date ? now.getTime() : Number(now);
}

/**
 * True for a status the widget hides (done/cancelled/legacy completed).
 * @param {*} status
 * @return {boolean}
 */
function isTerminalStatus(status) {
  return TERMINAL_STATUSES.has(String(status || "").toLowerCase());
}

/**
 * The Toronto-local year/month/day of an instant, as numbers.
 * @param {!Date} date
 * @return {!Array<number>} `[year, month, day]` (month is 1-based).
 */
function _torontoYmd(date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Toronto",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  })
      .format(date)
      .split("-")
      .map(Number);
}

/**
 * Toronto UTC offset (ms to add to a UTC instant to get local wall time) at
 * `date`.
 * @param {!Date} date
 * @return {number}
 */
function _torontoOffsetMs(date) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Toronto",
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  })
      .formatToParts(date)
      .reduce((acc, p) => {
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
 * The UTC instant (ms) of Toronto-local midnight on (y, m, d). DST shifts
 * happen at 02:00, not midnight, so the midnight offset is stable.
 * @param {number} y
 * @param {number} m One-based month.
 * @param {number} d
 * @return {number}
 */
function _torontoMidnightMs(y, m, d) {
  const guess = Date.UTC(y, m - 1, d, 0, 0, 0);
  return guess - _torontoOffsetMs(new Date(guess));
}

/**
 * Start of the current Toronto day (00:00) as an epoch-ms UTC instant.
 * @param {(Date|number)} now
 * @return {number}
 */
function torontoDayStartMs(now) {
  const date = now instanceof Date ? now : new Date(Number(now));
  const [y, m, d] = _torontoYmd(date);
  return _torontoMidnightMs(y, m, d);
}

/**
 * Serializes one appointment record into the widget's job JSON. Mirrors `_job`
 * in widget_sync_service.dart — `startTime` is an absolute UTC instant with
 * milliseconds (…Z) so the Swift ISO8601DateFormatter (with fractional
 * seconds) parses it; every other field is a plain string (never null, or the
 * Swift non-optional decode of the whole payload fails).
 * @param {!Object} r Appointment record (`{id, startTime, clientName, ...}`).
 * @return {!Object}
 */
function serializeWidgetJob(r) {
  const ms = toMillis(r.startTime);
  return {
    id: String(r.id == null ? "" : r.id),
    startTime: ms == null ? "" : new Date(ms).toISOString(),
    clientName: String(r.clientName == null ? "" : r.clientName),
    title: String(r.title == null ? "" : r.title),
    address: String(r.address == null ? "" : r.address),
    status: String(r.status == null ? "pending" : r.status),
  };
}

/**
 * Start of the Toronto day `n` days from `now` (n=0 today, 1 tomorrow, ...) as
 * an epoch-ms UTC instant.
 * @param {(Date|number)} now
 * @param {number} n
 * @return {number}
 */
function torontoDayStartOffsetMs(now, n) {
  const date = now instanceof Date ? now : new Date(Number(now));
  const [y, m, d] = _torontoYmd(date);
  return _torontoMidnightMs(y, m, d + n);
}

// How long after the last job of the day is finished the widget keeps showing
// today before rolling forward to tomorrow (mirrors widgetRolloverGrace in
// widget_sync_service.dart).
const ROLLOVER_GRACE_MS = 60 * 60 * 1000;

/**
 * True for a cancelled job (excluded when computing the last job's end time).
 * @param {*} status
 * @return {boolean}
 */
function isCancelledStatus(status) {
  return String(status || "").toLowerCase() === "cancelled";
}

/**
 * Builds the widget payload for one employee. Carries BOTH days plus a
 * `rolloverAt` instant so the WidgetKit timeline flips today -> tomorrow
 * on-device, with no app run or push: `todayJobs`/`tomorrowJobs` are each day's
 * upcoming non-terminal visits; `rolloverAt` is set only once today has no
 * incomplete job left (then last-job `endTime` + 1h; empty/all-cancelled today
 * rolls immediately). Pure mirror of `buildWidgetPayload`
 * (widget_sync_service.dart) — keep the two and the Swift decoder in lockstep.
 * @param {!Array<!Object>} records The employee's appointments in the lookahead
 *   window.
 * @param {(Date|number)} now
 * @param {string=} locale 'en' | 'fr'.
 * @return {!Object}
 */
function buildWidgetPayload(records, now, locale) {
  const loc = locale === "fr" ? "fr" : "en";
  const nowMs = nowMillis(now);
  const startTodayMs = torontoDayStartOffsetMs(now, 0);
  const startTomorrowMs = torontoDayStartOffsetMs(now, 1);
  const startDayAfterMs = torontoDayStartOffsetMs(now, 2);
  const inRange = (r, lo, hi) => {
    const ms = toMillis(r.startTime);
    return ms != null && ms >= lo && ms < hi;
  };
  const sortByStart = (a, b) => toMillis(a.startTime) - toMillis(b.startTime);

  const todayAll = (records || [])
      .filter((r) => inRange(r, startTodayMs, startTomorrowMs));
  const todayIncomplete = todayAll.filter((r) => !isTerminalStatus(r.status));
  const todayJobs = todayIncomplete
      .filter((r) => toMillis(r.startTime) > nowMs)
      .sort(sortByStart);
  const tomorrowJobs = (records || [])
      .filter((r) =>
        inRange(r, startTomorrowMs, startDayAfterMs) &&
        !isTerminalStatus(r.status))
      .sort(sortByStart);

  let rolloverMs = null;
  if (todayIncomplete.length === 0) {
    const finished = todayAll.filter((r) => !isCancelledStatus(r.status));
    if (finished.length === 0) {
      rolloverMs = startTodayMs;
    } else {
      const lastEnd = finished.reduce((mx, r) => {
        const e = toMillis(r.endTime);
        return e != null && e > mx ? e : mx;
      }, -Infinity);
      rolloverMs = lastEnd === -Infinity ?
        startTodayMs : lastEnd + ROLLOVER_GRACE_MS;
    }
  }

  const iso = (ms) => new Date(ms).toISOString();
  return {
    locale: loc,
    generatedAt: iso(nowMs),
    todayDate: iso(startTodayMs),
    tomorrowDate: iso(startTomorrowMs),
    rolloverAt: rolloverMs == null ? null : iso(rolloverMs),
    todayJobs: todayJobs.map(serializeWidgetJob),
    tomorrowJobs: tomorrowJobs.map(serializeWidgetJob),
  };
}

module.exports = {
  WIDGET_LOOKAHEAD_DAYS,
  ROLLOVER_GRACE_MS,
  isTerminalStatus,
  isCancelledStatus,
  torontoDayStartMs,
  serializeWidgetJob,
  buildWidgetPayload,
};
