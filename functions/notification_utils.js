"use strict";

/**
 * @fileoverview Push-notification logic for employee job alerts, 30-minute
 * reminders, and the nightly digest. Pure helpers plus orchestration that
 * takes injected `{db, messaging, now, logger}` so jest can drive it with
 * mocks (no admin/scheduler requires here — mirrors client_propagation.js /
 * signup_code_utils.js).
 *
 * Note: the send helper (`sendToEmployee`) lives here rather than in
 * notifications.js so the orchestration is fully unit-testable with an
 * injected Firestore + Messaging; notifications.js only registers the
 * triggers and passes the real `getFirestore()` / `getMessaging()`.
 *
 * @module notification_utils
 */

// 30 minutes before start, in ms.
const REMINDER_WINDOW_MS = 30 * 60 * 1000;

// How long after its endTime a job stays eligible for the overdue prompt; a
// job left open longer than this gets no prompt (accepted v1 gap).
const OVERDUE_LOOKBACK_MS = 24 * 60 * 60 * 1000;

// The overdue sweep queries by startTime (endTime would need a new index),
// so its floor must cover the eligibility window PLUS the longest bookable
// duration (the form caps a visit just under 24h): 48h total.
const OVERDUE_QUERY_WINDOW_MS = 2 * OVERDUE_LOOKBACK_MS;

// Ledger docs are useless once their occurrence ages out of eligibility;
// expiresAt + a Firestore TTL policy on both ledger collections keeps them
// from accumulating forever.
const LEDGER_TTL_MS = 7 * 24 * 60 * 60 * 1000;

// Statuses that still expect the visit to happen. `confirmed` is the retired
// legacy alias (treated as pending; new writes are rejected since 2026-07-09)
// and stays here only so pre-retirement docs still earn reminders/digests.
const PENDING_LIKE = new Set(["pending", "confirmed"]);

// Statuses that leave a job still open once its endTime passes — the app then
// shows it as `overdue` (AppointmentRecord.displayStatus). Deliberately an
// allowlist so terminal statuses (`done`/`cancelled` and the legacy
// `completed` alias of `done`) stay excluded.
const OPEN_LIKE = new Set(["pending", "in_progress", "confirmed"]);

// Dedupe priority when one employee accrues multiple events for one write.
const KIND_PRIORITY = {
  cancelled: 4,
  removed: 3,
  rescheduled: 2,
  assigned: 1,
};

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
 * @return {!Array<{employeeDocId: string, kind: string}>}
 */
function diffAppointmentForNotifications(before, after, now) {
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
    for (const id of toIdList(after.employeeIds)) {
      _accumulate(acc, id, "assigned");
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
 * Formats a Toronto-local datetime/time string.
 * @param {string} locale 'en' | 'fr'.
 * @param {*} startTime Timestamp/Date/number.
 * @param {!Object} opts Intl.DateTimeFormat options (timeZone added).
 * @return {string}
 */
function _fmt(locale, startTime, opts) {
  const ms = toMillis(startTime);
  if (ms == null) return "";
  const loc = locale === "fr" ? "fr-CA" : "en-CA";
  return new Intl.DateTimeFormat(loc, {
    timeZone: "America/Toronto",
    ...opts,
  }).format(new Date(ms));
}

/**
 * Localized "Wed, Jul 8, 2:00 p.m." style datetime.
 * @param {string} locale
 * @param {*} startTime
 * @return {string}
 */
function _dateTime(locale, startTime) {
  return _fmt(locale, startTime, {
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

/**
 * Localized time only.
 * @param {string} locale
 * @param {*} startTime
 * @return {string}
 */
function _timeOnly(locale, startTime) {
  return _fmt(locale, startTime, {hour: "numeric", minute: "2-digit"});
}

const _MESSAGES = {
  en: {
    who: (c) => (c.clientName || "").trim() || "Client",
    assigned: (c, who) => ({
      title: "New job assigned",
      body: `${who} · ${_dateTime("en", c.startTime)}`,
    }),
    rescheduled: (c, who) => ({
      title: "Job rescheduled",
      body: `${who} · now ${_dateTime("en", c.startTime)}`,
    }),
    cancelled: (c, who) => ({
      title: "Job cancelled",
      body: `${who} · ${_dateTime("en", c.startTime)}`,
    }),
    removed: (c, who) => ({
      title: "Removed from a job",
      body: `${who} · ${_dateTime("en", c.startTime)}`,
    }),
    reminder: (c, who) => {
      const addr = (c.address || "").trim();
      const base = `${who} at ${_timeOnly("en", c.startTime)}`;
      return {
        title: "Upcoming job",
        body: addr ? `${base} · ${addr}` : base,
      };
    },
    doneCheck: (c, who) => ({
      title: "Job finished?",
      body: `Is the job for ${who} done yet? Open the app to update its ` +
          "status.",
    }),
  },
  fr: {
    who: (c) => (c.clientName || "").trim() || "un client",
    assigned: (c, who) => ({
      title: "Nouvelle visite assignée",
      body: `${who} · ${_dateTime("fr", c.startTime)}`,
    }),
    rescheduled: (c, who) => ({
      title: "Visite reportée",
      body: `${who} · maintenant ${_dateTime("fr", c.startTime)}`,
    }),
    cancelled: (c, who) => ({
      title: "Visite annulée",
      body: `${who} · ${_dateTime("fr", c.startTime)}`,
    }),
    removed: (c, who) => ({
      title: "Retiré d'une visite",
      body: `${who} · ${_dateTime("fr", c.startTime)}`,
    }),
    reminder: (c, who) => {
      const addr = (c.address || "").trim();
      const base = `${who} à ${_timeOnly("fr", c.startTime)}`;
      return {
        title: "Visite à venir",
        body: addr ? `${base} · ${addr}` : base,
      };
    },
    doneCheck: (c, who) => ({
      title: "Travail terminé ?",
      body: `Le travail pour ${who} est-il terminé ? ` +
          "Ouvrez l'application pour mettre à jour son statut.",
    }),
  },
};

/**
 * Builds a localized {title, body} for a per-appointment notification.
 * Pure — unit-testable.
 * @param {string} kind
 *   assigned|rescheduled|cancelled|removed|reminder|doneCheck.
 * @param {{clientName: string, startTime: *, address: string}} ctx
 * @param {string} locale 'en' | 'fr'.
 * @return {{title: string, body: string}}
 */
function buildNotificationMessage(kind, ctx, locale) {
  const table = _MESSAGES[locale === "fr" ? "fr" : "en"];
  const build = table[kind];
  if (!build) return {title: "", body: ""};
  const c = ctx || {};
  return build(c, table.who(c));
}

/**
 * Builds the nightly-digest {title, body}. Pure — unit-testable.
 * @param {!Array<!Object>} jobs Tomorrow's jobs for one employee.
 * @param {string} locale 'en' | 'fr'.
 * @return {{title: string, body: string}}
 */
function buildDigestMessage(jobs, locale) {
  const fr = locale === "fr";
  const sorted = [...(jobs || [])].sort(
      (a, b) => (toMillis(a.startTime) || 0) - (toMillis(b.startTime) || 0),
  );
  const n = sorted.length;
  const first = sorted[0];
  const who = first ?
    ((first.clientName || "").trim() || (fr ? "un client" : "Client")) :
    "";
  const time = first ? _timeOnly(fr ? "fr" : "en", first.startTime) : "";
  if (fr) {
    const noun = n === 1 ? "visite" : "visites";
    return {
      title: "Votre horaire de demain",
      body: first ?
        `Vous avez ${n} ${noun} demain. Première : ${who} à ${time}.` :
        "Vous avez des visites demain.",
    };
  }
  const noun = n === 1 ? "job" : "jobs";
  return {
    title: "Tomorrow's schedule",
    body: first ?
      `You have ${n} ${noun} tomorrow. First: ${who} at ${time}.` :
      "You have jobs tomorrow.",
  };
}

/**
 * Filters appointment records to those due for a 30-minute reminder: still
 * pending-like and starting within (now, now+30min]. `in_progress` is
 * excluded (already started). Pure — unit-testable.
 * @param {!Array<!Object>} records Appointment records ({id, status,
 *   startTime, ...}).
 * @param {(Date|number)} now
 * @return {!Array<!Object>}
 */
function selectReminderCandidates(records, now) {
  const nowMs = nowMillis(now);
  const cutoff = nowMs + REMINDER_WINDOW_MS;
  return (records || []).filter((r) => {
    if (!PENDING_LIKE.has(String(r.status || "").toLowerCase())) return false;
    const ms = toMillis(r.startTime);
    return ms != null && ms > nowMs && ms <= cutoff;
  });
}

/**
 * Filters appointment records to those due for an overdue "job finished?"
 * prompt: still open (pending/in_progress/legacy confirmed — the OPEN_LIKE
 * allowlist, so `done`/`cancelled`/legacy `completed` never match) with an
 * endTime that passed within the last OVERDUE_LOOKBACK_MS. Server mirror of
 * the app's AppointmentRecord.displayStatus (appointment_record.dart) — keep
 * the two in sync; nothing is ever stored. Known divergence: a status unknown
 * to OPEN_LIKE renders Overdue in the app but is never swept (the query can't
 * enumerate unknown values). Pure — unit-testable.
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
 * [tomorrow 00:00, day-after 00:00) in Toronto local time, as UTC Dates. DST
 * shifts happen at 02:00, not midnight, so the midnight offset is stable.
 * @param {(Date|number)} now
 * @return {{start: !Date, end: !Date}}
 */
function tomorrowWindowToronto(now) {
  const date = now instanceof Date ? now : new Date(Number(now));
  const [y, m, d] = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Toronto",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date).split("-").map(Number);
  const midnightUtc = (yy, mm, dd) => {
    const guess = Date.UTC(yy, mm - 1, dd, 0, 0, 0);
    return new Date(guess - _torontoOffsetMs(new Date(guess)));
  };
  return {
    start: midnightUtc(y, m, d + 1),
    end: midnightUtc(y, m, d + 2),
  };
}

/**
 * Reminder ledger doc id: one per appointment occurrence, so a reschedule
 * (new startTime) earns a fresh reminder. Pure — unit-testable.
 * @param {string} appointmentId
 * @param {number} startTimeMillis
 * @return {string}
 */
function reminderLedgerId(appointmentId, startTimeMillis) {
  return `${appointmentId}_${startTimeMillis}`;
}

/**
 * Overdue-prompt ledger doc id: keyed on the END time (that's what makes a
 * job overdue), so a reschedule that moves endTime re-arms the prompt.
 * Pure — unit-testable.
 * @param {string} appointmentId
 * @param {number} endTimeMillis
 * @return {string}
 */
function overduePromptLedgerId(appointmentId, endTimeMillis) {
  return `${appointmentId}_${endTimeMillis}`;
}

/**
 * True for FCM error codes that mean the token itself is dead and its doc
 * should be deleted. Deliberately narrow: the generic
 * `messaging/invalid-argument` is NOT included — it can signal a malformed
 * message payload, not a bad token, and treating it as stale would delete
 * valid tokens on any payload bug. Pure — unit-testable.
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
 * Sends one localized message to every live token of an active employee, then
 * deletes any token docs FCM reports as stale. Returns the count sent.
 * Injectable core (db + messaging + logger).
 *
 * @param {!Object} deps `{db, messaging, logger}`.
 * @param {string} employeeDocId users doc id.
 * @param {!Object} data Data payload (string values); `kind` etc.
 * @param {function(string): {title: string, body: string}} buildMsg Localized
 *   message builder keyed by 'en'|'fr'.
 * @return {!Promise<number>}
 */
async function sendToEmployee(deps, employeeDocId, data, buildMsg) {
  const {db, messaging, logger} = deps;
  const userRef = db.collection("users").doc(employeeDocId);
  const userSnap = await userRef.get();
  if (!userSnap.exists) return 0;
  const user = userSnap.data() || {};
  // Recipients are always filtered to active employees server-side.
  if (user.role !== "employee" || user.status !== "active") return 0;

  const tokensSnap = await userRef.collection("fcmTokens").get();
  const tokenDocs = (tokensSnap && tokensSnap.docs) || [];
  if (tokenDocs.length === 0) return 0;

  const messages = tokenDocs.map((doc) => {
    const locale = (doc.data() || {}).locale === "fr" ? "fr" : "en";
    const {title, body} = buildMsg(locale);
    return {
      token: doc.id,
      notification: {title, body},
      data,
      // Without these Android delivery can be doze-deferred and iOS alerts
      // arrive silent.
      android: {priority: "high"},
      apns: {payload: {aps: {sound: "default"}}},
    };
  });

  const resp = await messaging.sendEach(messages);
  const responses = (resp && resp.responses) || [];
  let sent = 0;
  const deletions = [];
  responses.forEach((r, i) => {
    if (r && r.success) {
      sent += 1;
      return;
    }
    const code = r && r.error && r.error.code;
    if (isStaleTokenError(code)) {
      deletions.push(tokenDocs[i].ref.delete().catch((err) => {
        if (logger) logger.warn("fcm: stale-token delete failed", {err});
      }));
    } else if (logger) {
      logger.warn("fcm: send failed", {employeeDocId, code});
    }
  });
  if (deletions.length > 0) await Promise.all(deletions);
  return sent;
}

/**
 * Converts a Firestore doc snapshot to a plain appointment record.
 * @param {!Object} doc
 * @return {!Object}
 */
function _record(doc) {
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
function _contextFor(kind, before, after) {
  const src = (kind === "cancelled" || kind === "removed") ?
    (before || after) : (after || before);
  const d = src || {};
  return {
    clientName: d.clientName,
    startTime: d.startTime,
    address: d.address,
  };
}

/**
 * Orchestrates an appointment write: diff -> per-employee localized send.
 * Injectable deps `{db, messaging, now, logger}`.
 * @param {string} id appointment doc id.
 * @param {?Object} before
 * @param {?Object} after
 * @param {!Object} deps
 * @return {!Promise<{events: number, sent: number}>}
 */
async function handleAppointmentWrite(id, before, after, deps) {
  const now = deps.now || new Date();
  const events = diffAppointmentForNotifications(before, after, now);
  if (events.length === 0) return {events: 0, sent: 0};
  let sent = 0;
  for (const {employeeDocId, kind} of events) {
    const ctx = _contextFor(kind, before, after);
    const data = {appointmentId: String(id), kind};
    sent += await sendToEmployee(
        deps,
        employeeDocId,
        data,
        (locale) => buildNotificationMessage(kind, ctx, locale),
    );
  }
  return {events: events.length, sent};
}

/**
 * Orchestrates the 30-minute reminder sweep. The ledger fires each occurrence
 * at most once; a claim that delivered zero pushes (no live tokens yet, or the
 * send threw) is released so a later sweep can retry while the job is still
 * upcoming. Injectable deps `{db, messaging, now, logger}`.
 * @param {!Object} deps
 * @return {!Promise<{reminded: number}>}
 */
async function runReminderSweep(deps) {
  const {db, now, logger} = deps;
  const nowDate = now || new Date();
  const windowEnd = new Date(nowMillis(nowDate) + REMINDER_WINDOW_MS);
  const snap = await db
      .collection("appointments")
      .where("status", "in", ["pending", "confirmed"])
      .where("startTime", ">", nowDate)
      .where("startTime", "<=", windowEnd)
      .get();
  const candidates = selectReminderCandidates(
      ((snap && snap.docs) || []).map(_record),
      nowDate,
  );
  let reminded = 0;
  for (const c of candidates) {
    const startMs = toMillis(c.startTime);
    const ledgerRef = db
        .collection("appointmentReminders")
        .doc(reminderLedgerId(c.id, startMs));
    try {
      // create() fails if the doc exists -> fires exactly once per occurrence.
      await ledgerRef.create({
        createdAt: nowDate,
        expiresAt: new Date(nowMillis(nowDate) + LEDGER_TTL_MS),
      });
    } catch (err) {
      if (isAlreadyExists(err)) continue;
      if (logger) {
        logger.warn("reminder: ledger create failed", {id: c.id, err});
      }
      continue;
    }
    const ctx = _contextFor("reminder", null, c);
    let sent = 0;
    try {
      for (const employeeDocId of toIdList(c.employeeIds)) {
        sent += await sendToEmployee(
            deps,
            employeeDocId,
            {appointmentId: String(c.id), kind: "reminder"},
            (locale) => buildNotificationMessage("reminder", ctx, locale),
        );
      }
    } catch (err) {
      // A transient send failure must not abort the sweep for the remaining
      // candidates.
      if (logger) logger.warn("reminder: send failed", {id: c.id, err});
    }
    if (sent === 0) {
      // Nothing delivered (no live tokens registered yet, or the send threw)
      // — release the claim so a later sweep can retry while the job is still
      // upcoming. Mirrors runOverduePromptSweep; once sent > 0 the ledger
      // persists, so there is no double-send risk.
      try {
        await ledgerRef.delete();
      } catch (err) {
        if (logger) {
          logger.warn("reminder: ledger release failed", {id: c.id, err});
        }
      }
      continue;
    }
    reminded += sent;
  }
  return {reminded};
}

/**
 * Orchestrates the overdue "job finished?" sweep. Queries by startTime (the
 * existing `(status, startTime)` index; endTime would need a new one) over
 * the last OVERDUE_QUERY_WINDOW_MS — wide enough that the longest bookable
 * visit is still in range when its endTime passes — then filters to
 * ended-within-24h-but-open in code. The endTime-keyed ledger fires each
 * occurrence at most once; a claim that delivered zero pushes is released so
 * a later sweep can retry while the job is still eligible. Injectable deps
 * `{db, messaging, now, logger}`.
 * @param {!Object} deps
 * @return {!Promise<{prompted: number}>}
 */
async function runOverduePromptSweep(deps) {
  const {db, now, logger} = deps;
  const nowDate = now || new Date();
  const nowMs = nowMillis(nowDate);
  const windowStart = new Date(nowMs - OVERDUE_QUERY_WINDOW_MS);
  const snap = await db
      .collection("appointments")
      .where("status", "in", ["pending", "in_progress", "confirmed"])
      .where("startTime", ">=", windowStart)
      .where("startTime", "<=", nowDate)
      .get();
  const candidates = selectOverdueCandidates(
      ((snap && snap.docs) || []).map(_record),
      nowDate,
  );
  let prompted = 0;
  for (const c of candidates) {
    const endMs = toMillis(c.endTime);
    const ledgerRef = db
        .collection("appointmentOverduePrompts")
        .doc(overduePromptLedgerId(c.id, endMs));
    try {
      // create() fails if the doc exists -> fires at most once per occurrence.
      await ledgerRef.create({
        createdAt: nowDate,
        expiresAt: new Date(nowMs + LEDGER_TTL_MS),
      });
    } catch (err) {
      if (isAlreadyExists(err)) continue;
      if (logger) {
        logger.warn("overdue: ledger create failed", {id: c.id, err});
      }
      continue;
    }
    const ctx = _contextFor("doneCheck", null, c);
    let sent = 0;
    try {
      for (const employeeDocId of toIdList(c.employeeIds)) {
        sent += await sendToEmployee(
            deps,
            employeeDocId,
            {appointmentId: String(c.id), kind: "doneCheck"},
            (locale) => buildNotificationMessage("doneCheck", ctx, locale),
        );
      }
    } catch (err) {
      // A transient send failure must not abort the sweep for the remaining
      // candidates.
      if (logger) logger.warn("overdue: send failed", {id: c.id, err});
    }
    if (sent === 0) {
      // Nothing was delivered (no live tokens yet, or the send threw) —
      // release the claim so a later sweep can retry this occurrence.
      try {
        await ledgerRef.delete();
      } catch (err) {
        if (logger) {
          logger.warn("overdue: ledger release failed", {id: c.id, err});
        }
      }
      continue;
    }
    prompted += 1;
  }
  return {prompted};
}

/**
 * Orchestrates the nightly digest. Injectable deps
 * `{db, messaging, now, logger}`.
 * @param {!Object} deps
 * @return {!Promise<{digests: number}>}
 */
async function runDailyDigest(deps) {
  const {db, now} = deps;
  const nowDate = now || new Date();
  const {start, end} = tomorrowWindowToronto(nowDate);
  const snap = await db
      .collection("appointments")
      .where("status", "in", ["pending", "confirmed"])
      .where("startTime", ">=", start)
      .where("startTime", "<", end)
      .get();
  const grouped = groupTomorrowsJobsByEmployee(
      ((snap && snap.docs) || []).map(_record),
      nowDate,
  );
  let digests = 0;
  for (const employeeDocId of Object.keys(grouped)) {
    const jobs = grouped[employeeDocId];
    if (!jobs || jobs.length === 0) continue;
    const sent = await sendToEmployee(
        deps,
        employeeDocId,
        {kind: "digest"},
        (locale) => buildDigestMessage(jobs, locale),
    );
    if (sent > 0) digests += 1;
  }
  return {digests};
}

module.exports = {
  REMINDER_WINDOW_MS,
  OVERDUE_LOOKBACK_MS,
  diffAppointmentForNotifications,
  buildNotificationMessage,
  buildDigestMessage,
  selectReminderCandidates,
  selectOverdueCandidates,
  groupTomorrowsJobsByEmployee,
  tomorrowWindowToronto,
  reminderLedgerId,
  overduePromptLedgerId,
  isStaleTokenError,
  isAlreadyExists,
  sendToEmployee,
  handleAppointmentWrite,
  runReminderSweep,
  runDailyDigest,
  runOverduePromptSweep,
};
