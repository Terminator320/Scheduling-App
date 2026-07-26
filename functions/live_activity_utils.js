"use strict";

/**
 * @fileoverview Pure payload logic for the iOS "time to leave" Live Activity —
 * no Firebase, no network, so jest loads this directly (same as
 * `widget_payload_utils.js`/`notification_utils.js`'s pure half).
 *
 * Card text is built here, server-side, in EN and FR from a `_STRINGS` table
 * shaped like `notification_utils.js`'s `_MESSAGES`, rejecting Swift-side
 * `NSLocalizedString` so translations don't fork outside the ARB files.
 *
 * The travel -> on-site flip is clock-derived ([phaseFor]), mirroring
 * `AppointmentRecord.displayStatus`; `in_progress` is never written by the
 * app, and this feature deliberately has no `markInProgress` path.
 *
 * @module live_activity_utils
 */

// The Swift `ActivityAttributes` type name the `aps` envelope must name so
// ActivityKit can route a push-to-start to the right activity
// (`ios/ScheduleWidget/LiveActivitiesAppAttributes.swift`).
const ATTRIBUTES_TYPE = "LiveActivitiesAppAttributes";

const PHASE_TRAVEL = "travel";
const PHASE_ON_SITE = "onSite";

const {toMillis, formatTimeOfDay} = require("./time_utils");

/**
 * Absolute UTC ISO-8601 for an instant, or null — the Swift decoder's
 * `ISO8601DateFormatter` can't parse a zone-less local string (the same trap
 * the widget payload documents).
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
 * Toronto-local time-of-day string ("7:54"), sharing [formatTimeOfDay] with
 * the notification text so the card and push read identically.
 * @param {*} value
 * @param {string} locale 'en' | 'fr'.
 * @return {string}
 */
function _timeOnly(value, locale) {
  return formatTimeOfDay(locale, value);
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
 * The EN or FR card-string table, falling back to EN for unknown/empty
 * locales like `buildNotificationMessage`.
 * @param {string} locale 'en' | 'fr'.
 * @return {!Object}
 */
function liveActivityStrings(locale) {
  return _STRINGS[locale === "fr" ? "fr" : "en"];
}

/**
 * The card's phase, derived from the clock alone (`travel` strictly before
 * `startTime`, `onSite` after, mirroring `AppointmentRecord.displayStatus`) —
 * an unreadable `startTime` stays `travel` since the card would rather
 * under-promise than claim the tech is on site.
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
 * `endTime` feeds the on-site remaining-time countdown (the card counts DOWN
 * to the scheduled end, not up from the start).
 * @param {{clientName: string, address: string, startTime: *, endTime: *,
 *   leaveAt: *, travelMinutes: ?number, phase: string,
 *   locale: (string|undefined)}} args
 * @return {!Object}
 */
function buildContentState({clientName, address, startTime, endTime, leaveAt,
  travelMinutes, phase, locale}) {
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
    endTime: toIsoUtc(endTime),
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
