"use strict";

/**
 * @fileoverview Pure notification POLICY — the clock/data decisions behind
 * push, extracted from notification_utils.js so the rules can be read and
 * tested without the Firestore/FCM orchestration wrapped around them.
 *
 * Everything here is a pure function of its arguments (plus the injected
 * `now`): no db, no messaging, no I/O. That is the boundary — if a helper
 * needs `deps`, it belongs in notification_utils.js, not here.
 *
 * notification_utils.js re-exports every symbol below under its original
 * name, so existing call sites and tests are unaffected.
 *
 * @module notification_policy
 */

const {
  toMillis,
  businessYmd,
  businessMidnight,
} = require("./time_utils");

const DAY_MS = 24 * 60 * 60 * 1000;

// How long after its endTime a job stays eligible for the overdue prompt. A
// job left open longer than this just gets no prompt — an accepted v1 gap.
const OVERDUE_LOOKBACK_MS = 24 * 60 * 60 * 1000;

// The overdue sweep queries by startTime (endTime would need a new index),
// so its floor must cover the eligibility window PLUS the longest bookable
// duration (the form caps a visit just under 24h): 48h total.
const OVERDUE_QUERY_WINDOW_MS = 2 * OVERDUE_LOOKBACK_MS;

// Safety valve bounding the candidate set so one run can't blow the function
// timeout. Logs a warning instead of silently truncating if it's ever hit.
const OVERDUE_SWEEP_MAX = 500;

// FCM's hard cap on a message's data map is 4 KB. This leaves headroom for
// the other data keys (kind, appointment id, deep link) alongside the payload.
const WIDGET_PAYLOAD_MAX_BYTES = 3000;

// Ledger docs are useless once their occurrence ages out of eligibility, so
// expiresAt plus a Firestore TTL policy on both ledger collections keeps
// them from piling up forever.
const LEDGER_TTL_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * The body every claim-ledger doc in this file is written with. `expiresAt`
 * is the ABSOLUTE deletion instant, so the Firestore TTL policy on these
 * collections must use expiration offset 0.
 *
 * @param {!Date} nowDate Sweep/trigger time.
 * @return {{createdAt: !Date, expiresAt: !Date}}
 */
function ledgerBody(nowDate) {
  return {
    createdAt: nowDate,
    expiresAt: new Date(nowMillis(nowDate) + LEDGER_TTL_MS),
  };
}

// Statuses that leave a job open past endTime (shown as `overdue`). This is
// deliberately an allowlist, so terminal statuses (`done`/`cancelled`,
// legacy `completed`) stay excluded.
const OPEN_LIKE = new Set(["pending", "in_progress", "confirmed"]);

// Same allowlist as an array for `where("status", "in", ...)` queries,
// single-sourced so it can't drift from OPEN_LIKE.
const OPEN_STATUSES = [...OPEN_LIKE];

// Dedupe priority when one employee accrues multiple events for one write.
const KIND_PRIORITY = {
  cancelled: 4,
  removed: 3,
  rescheduled: 2,
  assigned: 1,
};

// Change-driven pushes go to employees only — an admin usually makes those
// edits themselves. Time-based pushes also reach an assigned admin.
const CHANGE_RECIPIENT_ROLES = new Set(["employee"]);
const TIMED_RECIPIENT_ROLES = new Set(["employee", "admin"]);

/**
 * Normalizes an employeeIds field to an array of strings.
 * @param {*} value
 * @return {!Array<string>}
 */
function toIdList(value) {
  if (!Array.isArray(value)) return [];
  return value.filter((v) => typeof v === "string" && v !== "");
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
 * Adds `kind` for `employeeDocId` to the accumulator, keeping the
 * higher-priority kind if the employee already has one.
 * @param {!Object<string, string>} acc
 * @param {string} employeeDocId
 * @param {string} kind
 */
function _accumulate(acc, employeeDocId, kind) {
  const existing = acc[employeeDocId];
  if (!existing || KIND_PRIORITY[kind] > KIND_PRIORITY[existing]) {
    acc[employeeDocId] = kind;
  }
}

/**
 * Computes the per-employee notification events for one appointment write.
 * Pure — unit-testable.
 *
 * kinds: assigned | rescheduled | cancelled | removed.
 *   - created           -> assigned for every employeeId (skipped if the doc
 *                          is created already cancelled).
 *   - deleted           -> cancelled for before.employeeIds.
 *   - status->cancelled -> cancelled for before.employeeIds.
 *   - ids removed       -> removed; ids added -> assigned; startTime changed
 *                          -> rescheduled for the ids that stayed.
 * Past appointments (relevant startTime < now) are skipped. One event per
 * employee, priority cancelled > removed > rescheduled > assigned.
 *
 * @param {?Object} before Pre-write appointment fields (null on create).
 * @param {?Object} after Post-write appointment fields (null on delete).
 * @param {(Date|number)} now
 * @param {string=} id This appointment's doc id (for repeat-series anchor
 *   dedup; only meaningful on create).
 * @return {!Array<{employeeDocId: string, kind: string}>}
 */
function diffAppointmentForNotifications(before, after, now, id) {
  const nowMs = nowMillis(now);
  const acc = {};

  const isCancelled = (d) =>
    d && String(d.status || "").toLowerCase() === "cancelled";
  const notPast = (startTime) => {
    const ms = toMillis(startTime);
    return ms != null && ms >= nowMs;
  };

  if (!before && after) {
    // Created.
    if (isCancelled(after) || !notPast(after.startTime)) return [];
    // Only the anchor (id === seriesId) sends the assignment push, so a
    // repeating series notifies once instead of once per pre-booked
    // occurrence. Non-repeating appointments (empty seriesId) are never
    // suppressed by this check.
    const seriesId = String((after && after.seriesId) || "");
    if (seriesId !== "" && seriesId !== String(id)) return [];
    for (const eid of toIdList(after.employeeIds)) {
      _accumulate(acc, eid, "assigned");
    }
  } else if (before && !after) {
    // Deleted.
    if (!notPast(before.startTime)) return [];
    for (const id of toIdList(before.employeeIds)) {
      _accumulate(acc, id, "cancelled");
    }
  } else if (before && after) {
    // Updated.
    if (isCancelled(after) && !isCancelled(before)) {
      if (!notPast(after.startTime)) return [];
      for (const id of toIdList(before.employeeIds)) {
        _accumulate(acc, id, "cancelled");
      }
    } else if (!isCancelled(after)) {
      if (!notPast(after.startTime)) return [];
      const beforeIds = toIdList(before.employeeIds);
      const afterIds = toIdList(after.employeeIds);
      const beforeSet = new Set(beforeIds);
      const afterSet = new Set(afterIds);
      const timeChanged =
        toMillis(before.startTime) !== toMillis(after.startTime);
      for (const id of beforeIds) {
        if (!afterSet.has(id)) _accumulate(acc, id, "removed");
      }
      for (const id of afterIds) {
        if (!beforeSet.has(id)) {
          _accumulate(acc, id, "assigned");
        } else if (timeChanged) {
          _accumulate(acc, id, "rescheduled");
        }
      }
    }
  }

  return Object.keys(acc).map((employeeDocId) => ({
    employeeDocId,
    kind: acc[employeeDocId],
  }));
}

/**
 * Filters appointment records to those overdue for a "job finished?" prompt
 * — still open per OPEN_LIKE, with an endTime within OVERDUE_LOOKBACK_MS,
 * mirroring the app's AppointmentRecord.displayStatus. A status OPEN_LIKE
 * doesn't recognize is never swept. Pure — unit-testable.
 * @param {!Array<!Object>} records Appointment records ({id, status,
 *   endTime, ...}).
 * @param {(Date|number)} now
 * @return {!Array<!Object>}
 */
function selectOverdueCandidates(records, now) {
  const nowMs = nowMillis(now);
  const floorMs = nowMs - OVERDUE_LOOKBACK_MS;
  return (records || []).filter((r) => {
    if (!OPEN_LIKE.has(String(r.status || "").toLowerCase())) return false;
    // A personal block is not a job to finish — "job finished?" is the wrong
    // question for a dentist appointment, and the app never shows one as
    // overdue either (AppointmentRecord.displayStatus). Keep the two in sync.
    if (r.isPersonal === true) return false;
    const ms = toMillis(r.endTime);
    return ms != null && ms <= nowMs && ms > floorMs;
  });
}

/**
 * Groups tomorrow's (Toronto) jobs by employee doc id, cancelled excluded,
 * each list sorted by startTime. Pure — unit-testable.
 * @param {!Array<!Object>} records Appointment records.
 * @param {(Date|number)} now
 * @return {!Object<string, !Array<!Object>>}
 */
function groupTomorrowsJobsByEmployee(records, now) {
  const {start, end} = tomorrowWindowToronto(now);
  const startMs = start.getTime();
  const endMs = end.getTime();
  const grouped = {};
  for (const r of records || []) {
    if (String(r.status || "").toLowerCase() === "cancelled") continue;
    const ms = toMillis(r.startTime);
    if (ms == null || ms < startMs || ms >= endMs) continue;
    for (const id of toIdList(r.employeeIds)) {
      (grouped[id] = grouped[id] || []).push(r);
    }
  }
  for (const id of Object.keys(grouped)) {
    grouped[id].sort(
        (a, b) => (toMillis(a.startTime) || 0) - (toMillis(b.startTime) || 0),
    );
  }
  return grouped;
}

/**
 * [tomorrow 00:00, day-after 00:00) in Toronto local time, as UTC Dates.
 * @param {(Date|number)} now
 * @return {{start: !Date, end: !Date}}
 */
function tomorrowWindowToronto(now) {
  const date = now instanceof Date ? now : new Date(Number(now));
  const [y, m, d] = businessYmd(date);
  return {
    start: businessMidnight(y, m, d + 1),
    end: businessMidnight(y, m, d + 2),
  };
}

/**
 * Overdue-prompt ledger doc id, keyed on the END time (that's what makes a
 * job overdue) and the recipient. That way a reschedule that moves endTime
 * re-arms the prompt, and each assignee is tracked independently. Pure —
 * unit-testable.
 * @param {string} appointmentId
 * @param {number} endTimeMillis
 * @param {string} employeeDocId
 * @return {string}
 */
function overduePromptLedgerId(appointmentId, endTimeMillis, employeeDocId) {
  return `${appointmentId}_${endTimeMillis}_${employeeDocId}`;
}

/**
 * True for FCM error codes meaning the token is dead and should be deleted.
 * Deliberately excludes `messaging/invalid-argument`, since that can signal
 * a bad payload rather than a bad token. Pure — unit-testable.
 * @param {string} code
 * @return {boolean}
 */
function isStaleTokenError(code) {
  return code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token";
}

/**
 * True for a Firestore create() that failed because the doc already exists.
 * @param {*} err
 * @return {boolean}
 */
function isAlreadyExists(err) {
  return !!err && (err.code === 6 || err.code === "already-exists");
}

/**
 * Converts a Firestore doc snapshot to a plain appointment record.
 * @param {!Object} doc
 * @return {!Object}
 */
function recordOf(doc) {
  return {id: doc.id, ...(doc.data() || {})};
}

/**
 * Message context from the appointment record relevant to `kind` (cancelled /
 * removed describe the job as it WAS, so read `before`).
 * @param {string} kind
 * @param {?Object} before
 * @param {?Object} after
 * @return {!Object}
 */
function contextFor(kind, before, after) {
  const src = (kind === "cancelled" || kind === "removed") ?
    (before || after) : (after || before);
  const d = src || {};
  return {
    clientName: d.clientName,
    // A personal job carries no client, so the message names it by title
    // instead — same fallback the widget and the Siri intents already use.
    title: d.title,
    startTime: d.startTime,
    // An all-day block stores a midnight start; the message speaks the date
    // alone rather than "12:00 a.m.".
    isAllDay: d.isAllDay === true,
    address: d.address,
    repeat: d.repeat,
  };
}

module.exports = {
  DAY_MS,
  OVERDUE_LOOKBACK_MS,
  OVERDUE_QUERY_WINDOW_MS,
  OVERDUE_SWEEP_MAX,
  WIDGET_PAYLOAD_MAX_BYTES,
  LEDGER_TTL_MS,
  OPEN_LIKE,
  OPEN_STATUSES,
  KIND_PRIORITY,
  CHANGE_RECIPIENT_ROLES,
  TIMED_RECIPIENT_ROLES,
  ledgerBody,
  toIdList,
  nowMillis,
  diffAppointmentForNotifications,
  selectOverdueCandidates,
  groupTomorrowsJobsByEmployee,
  tomorrowWindowToronto,
  overduePromptLedgerId,
  isStaleTokenError,
  isAlreadyExists,
  recordOf,
  contextFor,
};
