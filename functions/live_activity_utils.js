"use strict";

/**
 * @fileoverview Pure payload logic for the iOS "time to leave" Live
 * Activity. No Firebase, no network, so jest can load this directly (same
 * as `widget_payload_utils.js`/`notification_utils.js`'s pure half).
 *
 * Card text is built here, server-side, in EN and FR from a `_STRINGS` table
 * shaped like `notification_utils.js`'s `_MESSAGES`. We deliberately skip
 * Swift-side `NSLocalizedString`, so translations can't fork outside the ARB
 * files.
 *
 * The travel -> on-site flip is derived straight from the clock
 * ([phaseFor]), mirroring `AppointmentRecord.displayStatus`. The app never
 * writes `in_progress`, and this feature deliberately has no
 * `markInProgress` path.
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
 * Absolute UTC ISO-8601 for an instant, or null. The Swift decoder's
 * `ISO8601DateFormatter` can't parse a zone-less local string — same trap
 * the widget payload docs call out.
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

/**
 * Who a card names the job after: the client, or — for a personal job, which
 * has none — its title. Same fallback the pushes use in
 * `notification_messages._who`; the card and the `leaveNow` push beside it must
 * not call the same job two different things.
 * @param {!Object} c Content-state input.
 * @param {string} generic Localized "Client" placeholder.
 * @return {string}
 */
function _who(c, generic) {
  return (c.clientName || "").trim() || (c.title || "").trim() || generic;
}

/**
 * The `ctx` every start/update/end dispatch is fed, built from an appointment
 * record.
 *
 * ONE owner on purpose. `_stateFor` FIELD-PICKS its ctx into
 * `buildContentState`, so a call site that forgets a key fails SILENTLY — the
 * Lock Screen card just reads "Client" instead of the job's title, which is
 * exactly the bug that shipped once already. Four hand-written copies of this
 * literal had also started to drift on address normalization (two trimmed, two
 * passed `undefined` straight through).
 *
 * @param {?Object} record Appointment fields; null/undefined yields {}.
 * @param {{leaveAt: *, travelMinutes: *}=} opts Travel overlay, both null on
 *   an on-site or terminal card.
 * @return {!Object}
 */
function liveActivityCtx(record, opts) {
  if (!record) return {};
  const o = opts || {};
  return {
    clientName: record.clientName,
    title: record.title,
    address: String(record.address || "").trim(),
    startTime: record.startTime,
    endTime: record.endTime,
    leaveAt: o.leaveAt ?? null,
    travelMinutes: o.travelMinutes ?? null,
  };
}

const _STRINGS = {
  en: {
    who: (c) => _who(c, "Client"),
    status: (phase) => phase === PHASE_ON_SITE ? "On site" : "On the way",
    leaveAt: (t) => `Leave at ${t}`,
    startsAt: (t) => `Starts at ${t}`,
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
    who: (c) => _who(c, "un client"),
    status: (phase) => phase === PHASE_ON_SITE ? "Sur place" : "En route",
    leaveAt: (t) => `Départ à ${t}`,
    startsAt: (t) => `Débute à ${t}`,
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
 * The card's phase, derived from the clock alone: `travel` strictly before
 * `startTime`, `onSite` after, mirroring `AppointmentRecord.displayStatus`.
 * An unreadable `startTime` stays `travel` — the card would rather
 * under-promise than claim the tech is already on site.
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
 * Builds the ActivityKit content state the Swift `ContentState` decodes,
 * with all display text localized here (the extension just renders strings
 * verbatim). `endTime` feeds the on-site countdown, which counts down to the
 * scheduled end rather than up from the start.
 * @param {{clientName: string, address: string, startTime: *, endTime: *,
 *   leaveAt: *, travelMinutes: ?number, phase: string,
 *   locale: (string|undefined)}} args
 * @return {!Object}
 */
function buildContentState({clientName, title, address, startTime, endTime,
  leaveAt, travelMinutes, phase, locale}) {
  const loc = locale === "fr" ? "fr" : "en";
  const t = liveActivityStrings(loc);
  const onSite = phase === PHASE_ON_SITE;
  // A travel card with no known departure instant must NEVER label the job's
  // own `startTime` as "Leave at" — that reads as a departure time and would
  // send the tech off a whole drive-time late. Callers that can't supply a
  // `leaveAt` (the reschedule hook, before the marker's lead is known) get the
  // honest "Starts at" instead.
  const leaveKnown = !onSite && leaveAt != null;
  const timeSource = onSite || !leaveKnown ? startTime : leaveAt;
  const timeText = _timeOnly(timeSource, loc);
  const minutes = typeof travelMinutes === "number" ? travelMinutes : null;
  let timeLabel = "";
  if (timeText) {
    if (onSite) timeLabel = t.startedAt(timeText);
    else timeLabel = leaveKnown ? t.leaveAt(timeText) : t.startsAt(timeText);
  }
  return {
    clientName: t.who({clientName, title}),
    address: (address || "").trim(),
    startTime: toIsoUtc(startTime),
    endTime: toIsoUtc(endTime),
    leaveAt: toIsoUtc(leaveAt),
    travelMinutes: minutes,
    phase: onSite ? PHASE_ON_SITE : PHASE_TRAVEL,
    statusLabel: t.status(onSite ? PHASE_ON_SITE : PHASE_TRAVEL),
    timeLabel,
    driveLabel: !onSite && minutes != null ? t.drive(minutes) : "",
    directionsLabel: t.directions,
    completeLabel: t.complete,
  };
}

/**
 * Shared `aps` skeleton, omitting optional date/alert fields rather than
 * sending null since APNs rejects a null `stale-date`.
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
 * Push-to-start payload — `attributes-type`/`attributes` are required on
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
 * End payload — without a `dismissal-date` the card lingers on the Lock
 * Screen up to four hours, so the caller normally passes `now`.
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
  liveActivityStrings,
  liveActivityCtx,
  phaseFor,
  buildContentState,
  buildStartPayload,
  buildUpdatePayload,
  buildEndPayload,
};
