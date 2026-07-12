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

const {
  buildWidgetPayload,
  torontoDayStartMs,
  WIDGET_LOOKAHEAD_DAYS,
} = require("./widget_payload_utils");

const DAY_MS = 24 * 60 * 60 * 1000;

// 30 minutes before start, in ms.
const REMINDER_WINDOW_MS = 30 * 60 * 1000;

// How long after its endTime a job stays eligible for the overdue prompt; a
// job left open longer than this gets no prompt (accepted v1 gap).
const OVERDUE_LOOKBACK_MS = 24 * 60 * 60 * 1000;

// The overdue sweep queries by startTime (endTime would need a new index),
// so its floor must cover the eligibility window PLUS the longest bookable
// duration (the form caps a visit just under 24h): 48h total.
const OVERDUE_QUERY_WINDOW_MS = 2 * OVERDUE_LOOKBACK_MS;

// Safety valve on the serial sweep: bound the candidate set so one run can't
// blow the function timeout under an unexpected backlog. Far above any real
// small-business volume in a 48h window; if it's ever hit we log a warning
// rather than silently truncate (the oldest jobs age out and later runs catch
// the remainder).
const OVERDUE_SWEEP_MAX = 500;

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

// Recipient roles per notification category (all must be status:'active').
// Change-driven pushes (assigned/rescheduled/cancelled/removed) go to
// EMPLOYEES ONLY — an admin usually makes those edits themselves, so a push
// for their own change would be noise. Time-based pushes (reminder / overdue /
// digest) also go to an assigned ADMIN, who still wants the schedule nudges.
const CHANGE_RECIPIENT_ROLES = new Set(["employee"]);
const TIMED_RECIPIENT_ROLES = new Set(["employee", "admin"]);

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
    // A repeating series pre-books many occurrences in one write. Only the
    // anchor (id === seriesId) sends the assignment push, so the employee
    // gets ONE "repeating job" notification instead of one per pre-booked
    // copy. Non-repeating appointments have an empty seriesId and are never
    // suppressed.
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

/**
 * Localized "every 6 months" / "aux 6 mois" recurrence phrase for a
 * RepeatInterval raw value (repeat_interval.dart); "" for none/unknown so a
 * one-off job reads as a plain assignment. Mirrors RepeatInterval.raw.
 * @param {string} raw
 * @param {string} locale 'en' | 'fr'.
 * @return {string}
 */
function _repeatLabel(raw, locale) {
  const fr = locale === "fr";
  switch (String(raw || "").toLowerCase()) {
    case "four_months": return fr ? "aux 4 mois" : "every 4 months";
    case "six_months": return fr ? "aux 6 mois" : "every 6 months";
    case "one_year": return fr ? "chaque année" : "every year";
    default: return "";
  }
}

const _MESSAGES = {
  en: {
    who: (c) => (c.clientName || "").trim() || "Client",
    assigned: (c, who) => {
      const repeat = _repeatLabel(c.repeat, "en");
      return repeat ? {
        title: "New repeating job assigned",
        body: `${who} · ${_dateTime("en", c.startTime)} · repeats ${repeat}`,
      } : {
        title: "New job assigned",
        body: `${who} · ${_dateTime("en", c.startTime)}`,
      };
    },
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
    assigned: (c, who) => {
      const repeat = _repeatLabel(c.repeat, "fr");
      return repeat ? {
        title: "Nouvelle visite récurrente",
        body: `${who} · ${_dateTime("fr", c.startTime)} · se répète ${repeat}`,
      } : {
        title: "Nouvelle visite assignée",
        body: `${who} · ${_dateTime("fr", c.startTime)}`,
      };
    },
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
 * Reminder ledger doc id: one per (occurrence, recipient), so a reschedule
 * (new startTime) earns a fresh reminder and each assignee is tracked
 * independently — an assignee whose token registers late is retried without
 * re-sending to assignees already delivered. Pure — unit-testable.
 * @param {string} appointmentId
 * @param {number} startTimeMillis
 * @param {string} employeeDocId
 * @return {string}
 */
function reminderLedgerId(appointmentId, startTimeMillis, employeeDocId) {
  return `${appointmentId}_${startTimeMillis}_${employeeDocId}`;
}

/**
 * Overdue-prompt ledger doc id: keyed on the END time (that's what makes a
 * job overdue) and the recipient, so a reschedule that moves endTime re-arms
 * the prompt and each assignee is tracked independently. Pure —
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
 * @param {!Set<string>=} roles Allowed recipient roles (default: employees
 *   only). Time-based sweeps pass [TIMED_RECIPIENT_ROLES] to also reach an
 *   assigned admin.
 * @param {!Map<string, {user: ?Object, tokenDocs: !Array<!Object>}>=} cache
 *   Per-sweep read cache keyed by employee doc id. An employee assigned to
 *   several jobs in one sweep is otherwise re-read once per job; a sweep passes
 *   a fresh Map so each employee's user doc + token list is fetched at most
 *   once. Stale-token pruning still works (deletes are idempotent, and the
 *   ledger — not the token list — is what prevents a duplicate push).
 * @param {function(string): !Object=} augmentData Optional per-token extra data
 *   fields, keyed by the token's locale ('en'|'fr') — used to attach a
 *   locale-correct `widgetPayload` so the change push can rewrite the iOS
 *   home-screen widget from a background isolate. When the merged data carries
 *   a non-empty `widgetPayload`, the APNs payload also sets `content-available`
 *   so iOS wakes the app to apply it with the app closed.
 * @return {!Promise<number>}
 */
async function sendToEmployee(deps, employeeDocId, data, buildMsg, roles,
    cache, augmentData) {
  const {db, messaging, logger} = deps;
  const userRef = db.collection("users").doc(employeeDocId);

  let entry = cache && cache.get(employeeDocId);
  if (!entry) {
    const userSnap = await userRef.get();
    const user = userSnap.exists ? (userSnap.data() || {}) : null;
    const tokensSnap = user ?
      await userRef.collection("fcmTokens").get() : null;
    entry = {user, tokenDocs: (tokensSnap && tokensSnap.docs) || []};
    if (cache) cache.set(employeeDocId, entry);
  }
  const {user, tokenDocs} = entry;
  if (!user) return 0;
  // Recipients are filtered server-side to active accounts of an allowed role
  // (change-driven: employees only; time-based: employees + assigned admins).
  const allowed = roles || CHANGE_RECIPIENT_ROLES;
  if (!allowed.has(user.role) || user.status !== "active") return 0;
  if (tokenDocs.length === 0) return 0;

  const messages = tokenDocs.map((doc) => {
    const locale = (doc.data() || {}).locale === "fr" ? "fr" : "en";
    const {title, body} = buildMsg(locale);
    const msgData = augmentData ? {...data, ...augmentData(locale)} : data;
    const aps = {sound: "default"};
    // A change push that carries a fresh widget payload also wakes the app in
    // the background (iOS) so the background handler can rewrite the
    // home-screen widget with the app closed. content-available needs the
    // `remote-notification` UIBackgroundMode + the registered background
    // handler; the visible alert still shows alongside it.
    if (typeof msgData.widgetPayload === "string" && msgData.widgetPayload) {
      aps["content-available"] = 1;
    }
    return {
      token: doc.id,
      notification: {title, body},
      data: msgData,
      // Without these Android delivery can be doze-deferred and iOS alerts
      // arrive silent.
      android: {priority: "high"},
      apns: {payload: {aps}},
    };
  });

  const resp = await messaging.sendEach(messages);
  // Once sendEach resolves the pushes are already delivered. Nothing below may
  // throw OUT of this function: the caller reads a 0 return as "nothing went
  // out" and releases the idempotency claim, so a post-delivery throw here
  // would re-send an already-delivered message on the next sweep. Bookkeeping
  // (success count + stale-token pruning) is therefore fully self-contained.
  try {
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
  } catch (err) {
    // Post-delivery bookkeeping failed. We can't recount reliably, but the
    // batch DID go out — report the batch size so the caller keeps the claim
    // rather than re-sending. Erring toward a possible missed stale-token
    // cleanup (self-heals next send) over a duplicate push.
    if (logger) {
      logger.warn("fcm: post-send bookkeeping failed", {employeeDocId, err});
    }
    return messages.length;
  }
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
    repeat: d.repeat,
  };
}

/**
 * Reads an employee's appointments in the widget lookahead window
 * ([today 00:00 Toronto, +WIDGET_LOOKAHEAD_DAYS days)) so the change push can
 * carry a freshly-rebuilt widget payload. Served by the existing
 * `(employeeIds CONTAINS, startTime ASC)` composite index. Never throws — a
 * failed read just yields an empty window so the notification still sends
 * (the widget then updates on the next app run, as before this feature).
 * @param {!Object} db
 * @param {string} employeeDocId
 * @param {(Date|number)} now
 * @param {?Object=} logger
 * @return {!Promise<!Array<!Object>>}
 */
async function fetchEmployeeWidgetWindow(db, employeeDocId, now, logger) {
  try {
    const startMs = torontoDayStartMs(now);
    const start = new Date(startMs);
    const end = new Date(startMs + WIDGET_LOOKAHEAD_DAYS * DAY_MS);
    const snap = await db
        .collection("appointments")
        .where("employeeIds", "array-contains", employeeDocId)
        .where("startTime", ">=", start)
        .where("startTime", "<", end)
        .get();
    return ((snap && snap.docs) || []).map(_record);
  } catch (err) {
    if (logger) {
      logger.warn("widget: window query failed", {employeeDocId, err});
    }
    return [];
  }
}

/**
 * Orchestrates an appointment write: diff -> per-employee localized send. Each
 * change push also carries a fresh, locale-correct `widgetPayload` (+ APNs
 * content-available) so the employee's iOS home-screen widget updates even with
 * the app closed. Injectable deps `{db, messaging, now, logger}`.
 * @param {string} id appointment doc id.
 * @param {?Object} before
 * @param {?Object} after
 * @param {!Object} deps
 * @return {!Promise<{events: number, sent: number}>}
 */
async function handleAppointmentWrite(id, before, after, deps) {
  const now = deps.now || new Date();
  const events = diffAppointmentForNotifications(before, after, now, id);
  if (events.length === 0) return {events: 0, sent: 0};
  let sent = 0;
  // One window read per distinct employee across this write's events.
  const windows = new Map();
  for (const {employeeDocId, kind} of events) {
    const ctx = _contextFor(kind, before, after);
    const data = {appointmentId: String(id), kind};
    if (!windows.has(employeeDocId)) {
      windows.set(
          employeeDocId,
          await fetchEmployeeWidgetWindow(
              deps.db, employeeDocId, now, deps.logger),
      );
    }
    const records = windows.get(employeeDocId);
    sent += await sendToEmployee(
        deps,
        employeeDocId,
        data,
        (locale) => buildNotificationMessage(kind, ctx, locale),
        undefined,
        undefined,
        (locale) => ({
          widgetPayload: JSON.stringify(
              buildWidgetPayload(records, now, locale)),
        }),
    );
  }
  return {events: events.length, sent};
}

/**
 * Claim → send → release for ONE (occurrence, recipient) pair, keyed on a
 * per-recipient ledger doc. `create()` is the atomic exactly-once claim: a
 * recipient already delivered keeps its claim and is never re-sent, while a
 * claim that delivered zero pushes (no live token registered yet, or the send
 * threw) is released so a later sweep retries THAT recipient while the job is
 * still eligible — and a newly-added assignee simply earns its own claim on a
 * later sweep. Because the claim is per-recipient (not per-occurrence), one
 * assignee with a late-registering token no longer suppresses reminders for
 * the others (and no assignee is permanently missed). Concurrent sweeps are
 * safe: `create()` is atomic, so at most one wins the claim per recipient.
 * Returns the number of pushes delivered to this recipient.
 * @param {!Object} deps `{db, messaging, now, logger}`.
 * @param {!Object} opts
 * @return {!Promise<number>}
 */
async function _deliverRecipientOnce(deps, opts) {
  const {db, logger} = deps;
  const {collection, ledgerId, appointmentId, employeeDocId, kind, buildMsg,
    nowDate, label, roles, cache} = opts;
  const ledgerRef = db.collection(collection).doc(ledgerId);
  try {
    // create() fails if the doc exists -> fires at most once per recipient.
    await ledgerRef.create({
      createdAt: nowDate,
      expiresAt: new Date(nowMillis(nowDate) + LEDGER_TTL_MS),
    });
  } catch (err) {
    if (isAlreadyExists(err)) return 0;
    if (logger) {
      logger.warn(`${label}: ledger create failed`, {id: appointmentId, err});
    }
    return 0;
  }
  let sent = 0;
  try {
    sent = await sendToEmployee(
        deps,
        employeeDocId,
        {appointmentId, kind},
        buildMsg,
        roles,
        cache,
    );
  } catch (err) {
    // A transient send failure must not abort the sweep for the remaining
    // recipients/candidates.
    if (logger) logger.warn(`${label}: send failed`, {id: appointmentId, err});
  }
  if (sent === 0) {
    try {
      await ledgerRef.delete();
    } catch (err) {
      if (logger) {
        logger.warn(
            `${label}: ledger release failed`, {id: appointmentId, err});
      }
    }
  }
  return sent;
}

/**
 * Orchestrates the 30-minute reminder sweep. Each assignee is claimed on its
 * own per-recipient ledger (see [_deliverRecipientOnce]): fired at most once,
 * retried while upcoming if nothing was delivered, and never re-sent once
 * delivered. Injectable deps `{db, messaging, now, logger}`.
 * @param {!Object} deps
 * @return {!Promise<{reminded: number}>}
 */
async function runReminderSweep(deps) {
  const {db, now} = deps;
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
  const cache = new Map();
  for (const c of candidates) {
    const startMs = toMillis(c.startTime);
    const ctx = _contextFor("reminder", null, c);
    for (const employeeDocId of toIdList(c.employeeIds)) {
      reminded += await _deliverRecipientOnce(deps, {
        collection: "appointmentReminders",
        ledgerId: reminderLedgerId(String(c.id), startMs, employeeDocId),
        appointmentId: String(c.id),
        employeeDocId,
        kind: "reminder",
        buildMsg: (locale) =>
          buildNotificationMessage("reminder", ctx, locale),
        nowDate,
        label: "reminder",
        roles: TIMED_RECIPIENT_ROLES,
        cache,
      });
    }
  }
  return {reminded};
}

/**
 * Orchestrates the overdue "job finished?" sweep. Queries by startTime (the
 * existing `(status, startTime)` index; endTime would need a new one) over
 * the last OVERDUE_QUERY_WINDOW_MS — wide enough that the longest bookable
 * visit is still in range when its endTime passes — then filters to
 * ended-within-24h-but-open in code. Each assignee is claimed on its own
 * endTime-keyed per-recipient ledger (see [_deliverRecipientOnce]): fired at
 * most once, retried while eligible if nothing was delivered, never re-sent
 * once delivered. Injectable deps `{db, messaging, now, logger}`.
 * @param {!Object} deps
 * @return {!Promise<{prompted: number}>}
 */
async function runOverduePromptSweep(deps) {
  const {db, now} = deps;
  const nowDate = now || new Date();
  const nowMs = nowMillis(nowDate);
  const windowStart = new Date(nowMs - OVERDUE_QUERY_WINDOW_MS);
  const snap = await db
      .collection("appointments")
      .where("status", "in", ["pending", "in_progress", "confirmed"])
      .where("startTime", ">=", windowStart)
      .where("startTime", "<=", nowDate)
      .limit(OVERDUE_SWEEP_MAX)
      .get();
  if (snap && snap.size === OVERDUE_SWEEP_MAX && deps.logger) {
    deps.logger.warn(
        "runOverduePromptSweep: candidate cap hit; " +
        "newest jobs deferred to a later run", {cap: OVERDUE_SWEEP_MAX});
  }
  const candidates = selectOverdueCandidates(
      ((snap && snap.docs) || []).map(_record),
      nowDate,
  );
  let prompted = 0;
  const cache = new Map();
  for (const c of candidates) {
    const endMs = toMillis(c.endTime);
    const ctx = _contextFor("doneCheck", null, c);
    for (const employeeDocId of toIdList(c.employeeIds)) {
      const delivered = await _deliverRecipientOnce(deps, {
        collection: "appointmentOverduePrompts",
        ledgerId: overduePromptLedgerId(String(c.id), endMs, employeeDocId),
        appointmentId: String(c.id),
        employeeDocId,
        kind: "doneCheck",
        buildMsg: (locale) =>
          buildNotificationMessage("doneCheck", ctx, locale),
        nowDate,
        label: "overdue",
        roles: TIMED_RECIPIENT_ROLES,
        cache,
      });
      // Count recipients actually prompted (a job with N assignees can prompt
      // up to N); single-assignee jobs — the common case — read as before.
      if (delivered > 0) prompted += 1;
    }
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
  const cache = new Map();
  for (const employeeDocId of Object.keys(grouped)) {
    const jobs = grouped[employeeDocId];
    if (!jobs || jobs.length === 0) continue;
    const sent = await sendToEmployee(
        deps,
        employeeDocId,
        {kind: "digest"},
        (locale) => buildDigestMessage(jobs, locale),
        TIMED_RECIPIENT_ROLES,
        cache,
    );
    if (sent > 0) digests += 1;
  }
  return {digests};
}

module.exports = {
  REMINDER_WINDOW_MS,
  OVERDUE_LOOKBACK_MS,
  CHANGE_RECIPIENT_ROLES,
  TIMED_RECIPIENT_ROLES,
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
  fetchEmployeeWidgetWindow,
  handleAppointmentWrite,
  runReminderSweep,
  runDailyDigest,
  runOverduePromptSweep,
};
