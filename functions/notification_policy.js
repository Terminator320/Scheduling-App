"use strict";

/**
 * @fileoverview Pure notification POLICY — the clock/data decisions behind
 * push, extracted from notification_utils.js so the rules can be read and
 * tested without the Firestore/FCM orchestration wrapped around them.
 * Everything here is a pure function of its arguments (plus the injected
 * `now`): no db, no messaging, no I/O. That is the boundary — if a helper
 * needs `deps`, it belongs in notification_utils.js, not here.
 * notification_utils.js re-exports every symbol below under its original
 * name, so existing call sites and tests are unaffected.
 * @module notification_policy
 */

const {
  toMillis,
  nowMillis,
  businessDayStartMs,
  businessMinutesOfDay,
  hasWorkLeft,
  isCancelledStatus,
  isCompletedStatus,
  isTerminalStatus,
  normalizedStatus,
} = require("./time_utils");
const {isAlreadyExists} = require("./firestore_errors");

const DAY_MS = 24 * 60 * 60 * 1000;

// How long after its endTime a job stays eligible for the overdue prompt.
const OVERDUE_LOOKBACK_MS = 2 * 60 * 60 * 1000;

// Safety valve bounding the candidate set so one run can't blow the function
// timeout.
const OVERDUE_SWEEP_MAX = 500;

// The same valve for the nightly digest, which reads a ~15-day window of open
// jobs business-wide.
const DIGEST_SWEEP_MAX = 1000;

// FCM's hard cap on a message's data map is 4 KB.
const WIDGET_PAYLOAD_MAX_BYTES = 3000;

// Ledger docs are useless once their occurrence ages out of eligibility, so
// expiresAt plus a Firestore TTL policy on both ledger collections keeps them
// from piling up forever.
const LEDGER_TTL_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * The body every claim-ledger doc in this file is written with.
 * @param {!Date} nowDate Sweep/trigger time.
 * @return {{createdAt: !Date, expiresAt: !Date}}
 */
function ledgerBody(nowDate) {
  return {
    createdAt: nowDate,
    expiresAt: new Date(nowMillis(nowDate) + LEDGER_TTL_MS),
  };
}

// Statuses that leave a job open past endTime (shown as `overdue`).
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
// edits themselves.
const CHANGE_RECIPIENT_ROLES = new Set(["employee"]);
const TIMED_RECIPIENT_ROLES = new Set(["employee", "admin"]);
// Admin-only fan-outs: something a person did that the managers need to know
// about.
const ADMIN_RECIPIENT_ROLES = new Set(["admin"]);

/**
 * Normalizes an employeeIds field to an array of usable doc ids.
 * @param {*} value
 * @return {!Array<string>}
 */
function toIdList(value) {
  if (!Array.isArray(value)) return [];
  return value.filter(
      (v) =>
        typeof v === "string" &&
      v !== "" &&
      v.length <= 128 &&
      !v.includes("/"),
  );
}

/**
 * Whether this write is a job the CREW just finished, worth telling the
 * dispatcher about.
 * @param {?Object} before Pre-write appointment data, or null on create.
 * @param {?Object} after Post-write appointment data, or null on delete.
 * @return {boolean}
 */
function isCrewCompletion(before, after) {
  if (!after || !before) return false;
  if (after.isPersonal === true || after.isDayOff === true) return false;
  return isCompletedStatus(after.status) && !isCompletedStatus(before.status);
}

/**
 * The job time record's two stamps, decided from one write.
 * @param {?Object} before Pre-write appointment fields (null on create).
 * @param {?Object} after Post-write appointment fields (null on delete).
 * @param {(Date|number)} now
 * @return {{startedAt: (Date|undefined), completedAt: (Date|undefined)}}
 */
function lifecycleStamps(before, after, now) {
  const stamps = {};
  if (!after) return stamps;
  if (after.isPersonal === true || after.isDayOff === true) return stamps;
  const prev = before ? normalizedStatus(before.status) : "";
  const next = normalizedStatus(after.status);
  const nowDate = new Date(nowMillis(now));
  if (next === "in_progress" && prev !== "in_progress" &&
      after.startedAt == null) {
    stamps.startedAt = nowDate;
  }
  if (isCompletedStatus(next) && !isCompletedStatus(prev) &&
      after.completedAt == null) {
    stamps.completedAt = nowDate;
  }
  return stamps;
}

/** The two crew signals an assignee may put on an open job. */
const CREW_STATUS_VALUES = new Set(["onMyWay", "runningLate"]);

/**
 * Which crew signal this write just SENT, or null.
 * @param {?Object} before Pre-write appointment fields (null on create).
 * @param {?Object} after Post-write appointment fields (null on delete).
 * @return {?string} `onMyWay` | `runningLate` | null.
 */
function crewStatusSignal(before, after) {
  if (!after) return null;
  if (after.isPersonal === true || after.isDayOff === true) return null;
  if (isTerminalStatus(after.status)) return null;
  const next = String(after.crewStatus || "");
  if (!CREW_STATUS_VALUES.has(next)) return null;
  const prev = before ? String(before.crewStatus || "") : "";
  return next === prev ? null : next;
}

/**
 * The display name of the assignee who sent the crew signal, or "" when the
 * record does not carry one.
 * @param {?Object} after Post-write appointment fields.
 * @return {string} The name, or "" — which every message builder already
 * renders as a nameless variant rather than a dangling sentence.
 */
function crewStatusSenderName(after) {
  if (!after) return "";
  const ids = Array.isArray(after.employeeIds) ? after.employeeIds : [];
  const names = Array.isArray(after.employeeNames) ? after.employeeNames : [];
  const at = ids.indexOf(String(after.crewStatusBy || ""));
  return at < 0 ? "" : String(names[at] || "").trim();
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
 * @param {?Object} before Pre-write appointment fields (null on create).
 * @param {?Object} after Post-write appointment fields (null on delete).
 * @param {(Date|number)} now
 * @param {string=} id This appointment's doc id (for repeat-series anchor
 * dedup; only meaningful on create).
 * @return {!Array<{employeeDocId: string, kind: string}>}
 */
function diffAppointmentForNotifications(before, after, now, id) {
  const nowMs = nowMillis(now);
  const acc = {};

  const isCancelled = (d) => Boolean(d) && isCancelledStatus(d.status);
  const stillLive = (d) => hasWorkLeft(d, nowMs);

  if (!before && after) {
    if (isCancelled(after) || !stillLive(after)) return [];
    // Only the anchor (id === seriesId) sends the assignment push, so a
    // repeating series notifies once instead of once per pre-booked occurrence.
    const seriesId = String((after && after.seriesId) || "");
    if (seriesId !== "" && seriesId !== String(id)) return [];
    for (const eid of toIdList(after.employeeIds)) {
      _accumulate(acc, eid, "assigned");
    }
  } else if (before && !after) {
    if (!stillLive(before)) return [];
    for (const id of toIdList(before.employeeIds)) {
      _accumulate(acc, id, "cancelled");
    }
  } else if (before && after) {
    if (isCancelled(after) && !isCancelled(before)) {
      if (!stillLive(after)) return [];
      for (const id of toIdList(before.employeeIds)) {
        _accumulate(acc, id, "cancelled");
      }
    } else if (!isCancelled(after)) {
      if (!stillLive(after)) return [];
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
 * Filters appointment records to those overdue for a "job finished?" prompt —
 * still open per OPEN_LIKE, with an endTime within OVERDUE_LOOKBACK_MS (2 h),
 * mirroring the app's AppointmentRecord.displayStatus.
 * @param {!Array<!Object>} records Appointment records ({id, status,
 * endTime, ...}).
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
    // overdue either (AppointmentRecord.displayStatus).
    if (r.isPersonal === true) return false;
    const ms = toMillis(r.endTime);
    return ms != null && ms <= nowMs && ms > floorMs;
  });
}

/**
 * Groups the jobs RUNNING tomorrow (Toronto) by employee doc id, cancelled
 * excluded, each list sorted by clock time.
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
    if (isCancelledStatus(r.status)) continue;
    const ms = toMillis(r.startTime);
    if (ms == null) continue;
    // Overlap, not "starts tomorrow": a multi-day run booked days ago is still
    // on site tomorrow, and testing startTime alone told that crew "no jobs
    // tomorrow" while they were mid-run.
    const runEndsMs = toMillis(r.endTime) ?? ms;
    if (ms >= endMs || runEndsMs < startMs) continue;
    for (const id of toIdList(r.employeeIds)) {
      (grouped[id] = grouped[id] || []).push(r);
    }
  }
  // By CLOCK time, not the absolute instant: a run that began days ago still
  // works its daily window tomorrow, and ordering on the raw instant floated it
  // to the front of the list — so the digest named its time as the day's first
  // job.
  for (const id of Object.keys(grouped)) {
    grouped[id].sort(
        (a, b) =>
          (businessMinutesOfDay(a.startTime) ?? 0) -
        (businessMinutesOfDay(b.startTime) ?? 0),
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
  return {
    start: new Date(businessDayStartMs(now, 1)),
    end: new Date(businessDayStartMs(now, 2)),
  };
}

/**
 * Overdue-prompt ledger doc id, keyed on the END time (that's what makes a job
 * overdue) and the recipient.
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
 * @param {string} code
 * @return {boolean}
 */
function isStaleTokenError(code) {
  return code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token";
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
    // The run's end, so a multi-day job's message reads a date RANGE rather
    // than naming only the first morning.
    endTime: d.endTime,
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
  OVERDUE_SWEEP_MAX,
  DIGEST_SWEEP_MAX,
  WIDGET_PAYLOAD_MAX_BYTES,
  OPEN_STATUSES,
  CHANGE_RECIPIENT_ROLES,
  TIMED_RECIPIENT_ROLES,
  ADMIN_RECIPIENT_ROLES,
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
  isCrewCompletion,
  lifecycleStamps,
  crewStatusSignal,
  crewStatusSenderName,
  CREW_STATUS_VALUES,
  recordOf,
  contextFor,
};
