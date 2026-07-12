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
 * End of the current Toronto day (next 00:00) as an epoch-ms UTC instant —
 * i.e. the "today" cutoff the widget uses for its remaining-today list.
 * @param {(Date|number)} now
 * @return {number}
 */
function torontoDayEndMs(now) {
  const date = now instanceof Date ? now : new Date(Number(now));
  const [y, m, d] = _torontoYmd(date);
  return _torontoMidnightMs(y, m, d + 1);
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
 * Builds the widget payload for one employee: today's remaining non-terminal
 * jobs plus the next upcoming job (which may be on a later day). Pure mirror of
 * `buildWidgetPayload` (widget_sync_service.dart) — keep the two and the Swift
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
  const dayEndMs = torontoDayEndMs(now);
  const upcoming = (records || [])
      .filter((r) => {
        const ms = toMillis(r.startTime);
        return !isTerminalStatus(r.status) && ms != null && ms > nowMs;
      })
      .sort((a, b) => toMillis(a.startTime) - toMillis(b.startTime));
  const todayRemaining = upcoming.filter(
      (r) => toMillis(r.startTime) < dayEndMs,
  );
  return {
    locale: loc,
    generatedAt: new Date(nowMs).toISOString(),
    todayCount: todayRemaining.length,
    jobs: todayRemaining.map(serializeWidgetJob),
    nextJob: upcoming.length === 0 ? null : serializeWidgetJob(upcoming[0]),
  };
}

module.exports = {
  WIDGET_LOOKAHEAD_DAYS,
  isTerminalStatus,
  torontoDayStartMs,
  torontoDayEndMs,
  serializeWidgetJob,
  buildWidgetPayload,
};
