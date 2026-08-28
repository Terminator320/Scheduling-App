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
  businessDayStartMs,
  businessMinutesOfDay,
  hasWorkLeft,
  isCancelledStatus,
} = require("./time_utils");

const DAY_MS = 24 * 60 * 60 * 1000;

// How long after its endTime a job stays eligible for the overdue prompt. A
// job left open longer than this just gets no prompt — an accepted v1 gap.
//
// This is BOTH the eligibility window and the sweep's query floor, because the
// sweep queries `endTime` directly (index `(status, endTime DESC)`). It used
// to query `startTime` and so needed a floor of this PLUS the longest bookable
// span — about 15 days — which meant re-reading every open job started in the
// last fortnight, every 15 minutes, to act on the few that had just ended.
// Querying the field the rule is actually about makes the scan the width of
// the rule. It also drops the span coupling entirely: a run longer than
// MAX_APPOINTMENT_SPAN_DAYS (only reachable by a console or Admin-SDK write,
// which bypass the rules' span bound) is now swept on its real end time
// instead of falling out of the floor.
//
// **The WIDTH is sized against the sweep CADENCE, and the two must be revisited
// together.** It was 24 h under the standalone `sendOverdueJobPrompts` timer
// (`every 15 minutes`, 96 runs/day). Folding that sweep into
// `sendUpcomingJobReminders` on 2026-08-13 tripled the cadence to 288 runs/day
// and left the width alone, so every job sitting open past its end was re-read
// and had its ledger `create()` re-attempted on 287 further sweeps — every one
// of them guaranteed to fail ALREADY_EXISTS. At 2 h the window still gives 24
// examinations per job at the current cadence (fewer wasted, more than the 8
// the old cadence gave over the same two hours), and the ledger — never the
// cadence — is what makes delivery at-most-once. What the extra reach actually
// bought was the retry after a RELEASED claim (a zero-delivery pass releases it
// for a later sweep, so an assignee registering a token late is re-tried) and
// slack across an outage; both now span 2 h rather than a day.
const OVERDUE_LOOKBACK_MS = 2 * 60 * 60 * 1000;

// Safety valve bounding the candidate set so one run can't blow the function
// timeout. Logs a warning instead of silently truncating if it's ever hit.
const OVERDUE_SWEEP_MAX = 500;

// The same valve for the nightly digest, which reads a ~15-day window of open
// jobs business-wide. Larger than OVERDUE_SWEEP_MAX because the window is
// wider and a truncated digest means a crew is told nothing about tomorrow —
// a silent omission, unlike an overdue nudge that simply arrives on the next
// 5-minute run.
const DIGEST_SWEEP_MAX = 1000;

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
// Admin-only fan-outs: something a person did that the managers need to know
// about. `sendToEmployee` re-checks the recipient's role against whichever set
// it is handed, so passing one of the two above would silently deliver nothing
// useful here (they both admit employees).
const ADMIN_RECIPIENT_ROLES = new Set(["admin"]);

/**
 * Normalizes an employeeIds field to an array of usable doc ids.
 *
 * Shape-validated, not merely type-checked: firestore.rules validates scalar
 * id fields with `isValidDocIdField`, but rules cannot iterate a LIST, so
 * `employeeIds` reaches here unchecked. Consumers feed these straight to
 * `db.collection("users").doc(id)`, which throws SYNCHRONOUSLY on a slash —
 * and one poisoned element in one appointment was enough to reject the whole
 * daily-digest batch and silence it for every employee.
 *
 * Deliberately NOT `security.requireDocId`, which owns the same rule for the
 * callables. Two reasons, either alone sufficient: this DROPS a bad element
 * and keeps the rest, where the callable form throws `HttpsError` — turning a
 * trigger's one poisoned id into a thrown request is the exact failure this
 * filter exists to prevent; and this module is the pure-policy half of the
 * push stack (no `deps`, no db, no messaging), so requiring `security.js`
 * would drag firebase-functions and a firebase-admin handle into it. Change
 * the 128 here and in `requireDocId`/`isValidDocIdField` together.
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
 * Epoch ms for a `now` that may be a Date or a number.
 * @param {(Date|number)} now
 * @return {number}
 */
function nowMillis(now) {
  // Delegates to the shared coercion: the private copy this replaced returned
  // NaN for a Firestore Timestamp and skipped the finite check.
  return toMillis(now) ?? NaN;
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
 * Finished appointments (relevant endTime < now) are skipped — the gate is the
 * run's END, not its start, so a multi-day job cancelled mid-run still tells
 * its crew. One event per employee, priority
 * cancelled > removed > rescheduled > assigned.
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

  const isCancelled = (d) => Boolean(d) && isCancelledStatus(d.status);
  const stillLive = (d) => hasWorkLeft(d, nowMs);

  if (!before && after) {
    // Created.
    if (isCancelled(after) || !stillLive(after)) return [];
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
    if (!stillLive(before)) return [];
    for (const id of toIdList(before.employeeIds)) {
      _accumulate(acc, id, "cancelled");
    }
  } else if (before && after) {
    // Updated.
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
 * Filters appointment records to those overdue for a "job finished?" prompt
 * — still open per OPEN_LIKE, with an endTime within OVERDUE_LOOKBACK_MS (2 h),
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
 * Groups the jobs RUNNING tomorrow (Toronto) by employee doc id, cancelled
 * excluded, each list sorted by clock time. Pure — unit-testable.
 *
 * A job counts when its run overlaps tomorrow, not merely when it starts
 * then. This is an instant-span overlap rather than the app's daily-window
 * model (`AppointmentDaySlice`), so an overnight run can still be listed on
 * the morning it finishes — over-inclusive, which is the safe direction here.
 * Plan 2 mirrored that model into JS as `./day_slice_utils` (2026-08-10) and
 * deliberately left the digest on the coarser test; switching it is a
 * behaviour change, not a port.
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
    // Overlap, not "starts tomorrow": a multi-day run booked days ago is
    // still on site tomorrow, and testing startTime alone told that crew
    // "no jobs tomorrow" while they were mid-run. Falls back to the start
    // instant when endTime is missing.
    const runEndsMs = toMillis(r.endTime) ?? ms;
    if (ms >= endMs || runEndsMs < startMs) continue;
    for (const id of toIdList(r.employeeIds)) {
      (grouped[id] = grouped[id] || []).push(r);
    }
  }
  // By CLOCK time, not the absolute instant: a run that began days ago still
  // works its daily window tomorrow, and ordering on the raw instant floated
  // it to the front of the list — so the digest named its time as the day's
  // first job.
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
  recordOf,
  contextFor,
};
