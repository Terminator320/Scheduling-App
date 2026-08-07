"use strict";

/**
 * @fileoverview Server-side mirror of the Flutter widget payload builder
 * (`lib/features/home_widget/application/widget_sync_service.dart`). A
 * change-driven push carries the fresh payload so the iOS home-screen widget
 * can rewrite itself from a background isolate even with the app closed.
 * It's kept pure and dependency-free so jest can load it directly, and its
 * JSON shape stays in lockstep with the Dart builder and the Swift decoder
 * (`ios/ScheduleWidget/ScheduleWidget.swift`).
 *
 * Day boundaries use America/Toronto (`BUSINESS_TIME_ZONE`), so a
 * Toronto-based device computes the same local midnight and server- and
 * app-written payloads agree.
 *
 * @module widget_payload_utils
 */

const {
  toMillis,
  businessYmd,
  businessMidnight,
} = require("./time_utils");

// Terminal statuses filtered out of the widget's job list. Mirrors
// AppointmentStatus.isTerminal (status_chip.dart) — done/cancelled plus the
// legacy `completed` alias.
const TERMINAL_STATUSES = new Set(["done", "completed", "cancelled"]);

// How many days past today the "next job" lookahead spans (matches the Dart
// widget range: [today 00:00, today + 3 days)).
const WIDGET_LOOKAHEAD_DAYS = 3;

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
 * Start of the current Toronto day (00:00) as an epoch-ms UTC instant.
 * @param {(Date|number)} now
 * @return {number}
 */
function torontoDayStartMs(now) {
  return torontoDayStartOffsetMs(now, 0);
}

/**
 * Serializes one appointment record into the widget's job JSON, mirroring
 * `_job` in widget_sync_service.dart. `startTime` is an absolute UTC instant
 * with milliseconds so Swift's ISO8601DateFormatter can parse it, and every
 * other field must be a plain non-null string or the Swift decode fails.
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
    // The widget speaks "All day" instead of the stored midnight–23:59 pair.
    isAllDay: r.isAllDay === true,
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
  const [y, m, d] = businessYmd(date);
  return businessMidnight(y, m, d + n).getTime();
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
 * Builds the widget payload for one employee. It carries both days plus a
 * `rolloverAt` instant so the WidgetKit timeline can flip from today to
 * tomorrow on-device with no app run or push — set once today has no
 * incomplete job left, else null. This is a pure mirror of
 * `buildWidgetPayload` (widget_sync_service.dart) — keep it and the Swift
 * decoder in lockstep.
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
  // "Still ahead of you today". An all-day block starts at midnight, so a
  // start-time test would drop it from today the moment the day began — it
  // stays listed until its 23:59 end passes.
  const stillAhead = (r) => {
    if (r.isAllDay === true) {
      const end = toMillis(r.endTime);
      return end == null || end > nowMs;
    }
    return toMillis(r.startTime) > nowMs;
  };
  const todayJobs = todayIncomplete
      .filter(stillAhead)
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
  isTerminalStatus,
  torontoDayStartMs,
  serializeWidgetJob,
  buildWidgetPayload,
};
