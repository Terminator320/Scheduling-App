"use strict";

/**
 * @fileoverview Pure payload logic for the iOS "time to leave" Live Activity.
 * No Firebase, no network — jest loads this directly, the same way it loads
 * `widget_payload_utils.js` / `notification_utils.js`'s pure half.
 *
 * Card text is built HERE, server-side, in EN and FR from a `_STRINGS` table
 * shaped exactly like `notification_utils.js`'s `_MESSAGES` (locale key ->
 * builder functions, `who()` for the client fallback). The rejected
 * alternative was `NSLocalizedString` in Swift, which would fork translations
 * into a second system outside the ARB files.
 *
 * The travel -> on-site flip is CLOCK-DERIVED ([phaseFor]), mirroring
 * `AppointmentRecord.displayStatus`. `in_progress` is never written by the
 * app, and this feature deliberately does not add a `markInProgress` path.
 *
 * @module live_activity_utils
 */

// The Swift `ActivityAttributes` type name the `aps` envelope must name so
// ActivityKit can route a push-to-start to the right activity
// (`ios/ScheduleWidget/LiveActivitiesAppAttributes.swift`).
const ATTRIBUTES_TYPE = "LiveActivitiesAppAttributes";

const PHASE_TRAVEL = "travel";
const PHASE_ON_SITE = "onSite";

/**
 * Milliseconds since epoch for a Firestore Timestamp / Date / number, else
 * null. Mirrors the same helper in widget_payload_utils.js.
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
 * Absolute UTC ISO-8601 for an instant, or null. The Swift decoder uses
 * `ISO8601DateFormatter`, which cannot parse a zone-less local string — the
 * same trap the widget payload already documents.
 * @param {*} value
 * @return {?string}
 */
function toIsoUtc(value) {
  const ms = toMillis(value);
  return ms == null ? null : new Date(ms).toISOString();
}

/**
 * Whole epoch seconds for the `aps` date fields, or null.
 * @param {*} value
 * @return {?number}
 */
function toEpochSeconds(value) {
  const ms = toMillis(value);
  return ms == null ? null : Math.floor(ms / 1000);
}

/**
 * Toronto-local time-of-day string ("7:54"), matching the notification
 * formatter so the card and the push read identically.
 * @param {*} value
 * @param {string} locale 'en' | 'fr'.
 * @return {string}
 */
function _timeOnly(value, locale) {
  const ms = toMillis(value);
  if (ms == null) return "";
  return new Intl.DateTimeFormat(locale === "fr" ? "fr-CA" : "en-CA", {
    timeZone: "America/Toronto",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(ms));
}

const _STRINGS = {
  en: {
    who: (c) => (c.clientName || "").trim() || "Client",
    status: (phase) => phase === PHASE_ON_SITE ? "On site" : "On the way",
    leaveAt: (t) => `Leave at ${t}`,
    startedAt: (t) => `Started at ${t}`,
    drive: (m) => `About ${m} min drive`,
    directions: "Directions",
    complete: "Complete",
    startAlert: (c, who) => {
      const addr = (c.address || "").trim();
      const drive = `About ${c.travelMinutes} min drive`;
      return {
        title: `Time to leave — ${who} at ${_timeOnly(c.startTime, "en")}`,
        body: addr ? `${drive} · ${addr}` : drive,
      };
    },
  },
  fr: {
    who: (c) => (c.clientName || "").trim() || "un client",
    status: (phase) => phase === PHASE_ON_SITE ? "Sur place" : "En route",
    leaveAt: (t) => `Départ à ${t}`,
    startedAt: (t) => `Début à ${t}`,
    drive: (m) => `Environ ${m} min de route`,
    directions: "Itinéraire",
    complete: "Terminer",
    startAlert: (c, who) => {
      const addr = (c.address || "").trim();
      const drive = `Environ ${c.travelMinutes} min de route`;
      return {
        title: `C'est l'heure de partir — ${who} à ` +
            `${_timeOnly(c.startTime, "fr")}`,
        body: addr ? `${drive} · ${addr}` : drive,
      };
    },
  },
};

/**
 * The EN or FR card-string table. Unknown/empty locales fall back to EN,
 * exactly like `buildNotificationMessage`.
 * @param {string} locale 'en' | 'fr'.
 * @return {!Object}
 */
function liveActivityStrings(locale) {
  return _STRINGS[locale === "fr" ? "fr" : "en"];
}

/**
 * The card's phase, derived from the clock alone: `travel` strictly before
 * `startTime`, `onSite` from `startTime` onward. Mirrors
 * `AppointmentRecord.displayStatus`, which flips to `in_progress` once now is
 * within [start, end]. An unreadable `startTime` stays in `travel` — the card
 * would rather under-promise than claim the tech is on site.
 * @param {{startTime: *, now: *}} args
 * @return {string} PHASE_TRAVEL | PHASE_ON_SITE.
 */
function phaseFor({startTime, now}) {
  const startMs = toMillis(startTime);
  const nowMs = toMillis(now);
  if (startMs == null || nowMs == null) return PHASE_TRAVEL;
  return nowMs >= startMs ? PHASE_ON_SITE : PHASE_TRAVEL;
}

/**
 * Builds the ActivityKit content state the Swift `ContentState` decodes. All
 * display text is localized here; the extension renders strings verbatim.
 * @param {{clientName: string, address: string, startTime: *, leaveAt: *,
 *   travelMinutes: ?number, phase: string, locale: (string|undefined)}} args
 * @return {!Object}
 */
function buildContentState(
    {clientName, address, startTime, leaveAt, travelMinutes, phase, locale}) {
  const loc = locale === "fr" ? "fr" : "en";
  const t = liveActivityStrings(loc);
  const onSite = phase === PHASE_ON_SITE;
  const timeSource = onSite ? startTime : (leaveAt != null ? leaveAt :
      startTime);
  const timeText = _timeOnly(timeSource, loc);
  const minutes = typeof travelMinutes === "number" ? travelMinutes : null;
  return {
    clientName: (clientName || "").trim() || t.who({}),
    address: (address || "").trim(),
    startTime: toIsoUtc(startTime),
    leaveAt: toIsoUtc(leaveAt),
    travelMinutes: minutes,
    phase: onSite ? PHASE_ON_SITE : PHASE_TRAVEL,
    statusLabel: t.status(onSite ? PHASE_ON_SITE : PHASE_TRAVEL),
    timeLabel: timeText ?
      (onSite ? t.startedAt(timeText) : t.leaveAt(timeText)) : "",
    driveLabel: !onSite && minutes != null ? t.drive(minutes) : "",
    directionsLabel: t.directions,
    completeLabel: t.complete,
  };
}

/**
 * Shared `aps` skeleton. Optional date/alert fields are omitted rather than
 * sent null — APNs rejects a null `stale-date`.
 * @param {string} event start|update|end.
 * @param {!Object} contentState
 * @param {{now: *, alert: (?Object|undefined), staleDate: *,
 *   dismissalDate: *}} opts
 * @return {!Object}
 */
function _envelope(event, contentState, opts) {
  const aps = {
    "timestamp": toEpochSeconds(opts.now) ||
        Math.floor(Date.now() / 1000),
    "event": event,
    "content-state": contentState || {},
  };
  if (opts.alert) aps["alert"] = opts.alert;
  const stale = toEpochSeconds(opts.staleDate);
  if (stale != null) aps["stale-date"] = stale;
  const dismissal = toEpochSeconds(opts.dismissalDate);
  if (dismissal != null) aps["dismissal-date"] = dismissal;
  return {aps};
}

/**
 * Push-to-start payload. `attributes-type` + `attributes` are required on a
 * start and rejected on update/end.
 * @param {{contentState: !Object, attributes: !Object, now: *,
 *   alert: (?Object|undefined), staleDate: *,
 *   attributesType: (string|undefined)}} args
 * @return {!Object}
 */
function buildStartPayload(
    {contentState, attributes, now, alert, staleDate, attributesType}) {
  const payload = _envelope("start", contentState, {
    now, alert, staleDate, dismissalDate: null,
  });
  payload.aps["attributes-type"] = attributesType || ATTRIBUTES_TYPE;
  payload.aps["attributes"] = attributes || {};
  return payload;
}

/**
 * Update payload for a live card (phase flip, reschedule).
 * @param {{contentState: !Object, now: *, alert: (?Object|undefined),
 *   staleDate: *}} args
 * @return {!Object}
 */
function buildUpdatePayload({contentState, now, alert, staleDate}) {
  return _envelope("update", contentState, {
    now, alert, staleDate, dismissalDate: null,
  });
}

/**
 * End payload. Without a `dismissal-date` the card lingers on the Lock Screen
 * for up to four hours, so the caller normally passes `now`.
 * @param {{contentState: !Object, now: *, dismissalDate: *,
 *   alert: (?Object|undefined)}} args
 * @return {!Object}
 */
function buildEndPayload({contentState, now, dismissalDate, alert}) {
  return _envelope("end", contentState, {
    now, alert, staleDate: null, dismissalDate,
  });
}

module.exports = {
  ATTRIBUTES_TYPE,
  PHASE_TRAVEL,
  PHASE_ON_SITE,
  toMillis,
  toIsoUtc,
  toEpochSeconds,
  liveActivityStrings,
  phaseFor,
  buildContentState,
  buildStartPayload,
  buildUpdatePayload,
  buildEndPayload,
};
