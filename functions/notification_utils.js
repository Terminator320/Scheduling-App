"use strict";

/**
 * @fileoverview Push-notification logic for employee job alerts, 30-minute
 * reminders, and the nightly digest. Both the pure helpers and the
 * orchestration functions take injected `{db, messaging, now, logger}` so
 * jest can drive them with mocks.
 *
 * `sendToEmployee` lives here (not in notifications.js) so it's unit-testable
 * with an injected Firestore + Messaging.
 *
 * @module notification_utils
 */

const {
  buildWidgetPayload,
  torontoDayStartMs,
  WIDGET_LOOKAHEAD_DAYS,
} = require("./widget_payload_utils");
const {
  updateLiveActivity,
  endLiveActivity,
} = require("./live_activity_dispatch");
const {
  toMillis,
} = require("./time_utils");
const {
  buildNotificationMessage,
  buildDigestMessage,
} = require("./notification_messages");

const {
  DAY_MS,
  OVERDUE_QUERY_WINDOW_MS,
  OVERDUE_SWEEP_MAX,
  WIDGET_PAYLOAD_MAX_BYTES,
  OPEN_STATUSES,
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
  recordOf: _record,
  contextFor: _contextFor,
} = require("./notification_policy");

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
 * @param {!Set<string>=} roles Allowed recipient roles (default employees
 *   only; time-based sweeps pass [TIMED_RECIPIENT_ROLES] to also reach an
 *   assigned admin).
 * @param {!Map<string, {user: ?Object, tokenDocs: !Array<!Object>}>=} cache
 *   Per-sweep read cache keyed by employee doc id, so an employee assigned to
 *   several jobs in one sweep is fetched at most once. Stale-token pruning
 *   still works fine with this cache, since deletes are idempotent and it's
 *   the ledger, not the token list, that actually prevents duplicate pushes.
 * @param {function(string): !Object=} augmentData Optional per-token extra
 *   data keyed by locale ('en'|'fr'), used to attach a locale-correct
 *   `widgetPayload`. A non-empty payload also sets APNs `content-available`
 *   so iOS applies it even with the app closed.
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
  // Recipients are filtered server-side to active accounts of an allowed role.
  const allowed = roles || CHANGE_RECIPIENT_ROLES;
  if (!allowed.has(user.role) || user.status !== "active") return 0;
  if (tokenDocs.length === 0) return 0;

  const messages = tokenDocs.map((doc) => {
    const locale = (doc.data() || {}).locale === "fr" ? "fr" : "en";
    const {title, body} = buildMsg(locale);
    let msgData = augmentData ? {...data, ...augmentData(locale)} : data;
    // Drop widgetPayload if it would push us over the 4 KB FCM data-map cap
    // and lose the whole message. We measure UTF-8 bytes since accented text
    // is 2 bytes but only 1 code unit. msgData is copied first since it may
    // alias the caller's `data`.
    if (typeof msgData.widgetPayload === "string" &&
        Buffer.byteLength(msgData.widgetPayload, "utf8") >
          WIDGET_PAYLOAD_MAX_BYTES) {
      msgData = {...msgData};
      delete msgData.widgetPayload;
    }
    const aps = {sound: "default"};
    // A fresh widget payload also sets APNs content-available, so iOS wakes
    // the app in the background to rewrite the widget. That needs the
    // remote-notification UIBackgroundMode plus a registered background
    // handler on the client; the visible alert still shows alongside it.
    if (typeof msgData.widgetPayload === "string" && msgData.widgetPayload) {
      aps["content-available"] = 1;
    }
    // Marked time-sensitive so a departure alert isn't buried in a
    // Focus-mode summary. This needs the Xcode Time Sensitive Notifications
    // entitlement on the client, or iOS silently downgrades it to `active` —
    // safe to ship server-first either way.
    if (msgData.kind === "leaveNow") {
      aps["interruption-level"] = "time-sensitive";
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
  // Nothing below may throw. The caller treats a 0 return as "nothing sent"
  // and releases the idempotency claim, so a post-delivery throw here would
  // cause a resend of an already-delivered message.
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
    // Bookkeeping failed but the batch already went out, so report the
    // batch size to keep the claim. Better to risk a missed stale-token
    // cleanup, which self-heals, than to risk a duplicate push.
    if (logger) {
      logger.warn("fcm: post-send bookkeeping failed", {employeeDocId, err});
    }
    return messages.length;
  }
}


/**
 * Reads an employee's appointments in the widget lookahead window
 * ([today 00:00 Toronto, +WIDGET_LOOKAHEAD_DAYS days)), so the change push
 * can carry a fresh widget payload (served by the existing `(employeeIds
 * CONTAINS, startTime ASC)` index). Never throws — a failed read just
 * yields an empty window, and the notification still sends.
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
 * Ends any live card for a job that hit a terminal transition (done,
 * cancelled, deleted, or unassigned). This is deliberately unconditional on
 * start time, since that's exactly when the notification diff would
 * otherwise suppress the event as past. Best-effort and non-throwing —
 * it resolves through the server-owned card marker, so it's a safe no-op
 * for any other target.
 * @param {string} id appointment doc id.
 * @param {?Object} before
 * @param {?Object} after
 * @param {!Object} deps
 * @param {!Date} now
 * @return {!Promise<void>}
 */
async function endCardOnTerminal(id, before, after, deps, now) {
  const statusOf = (d) => String((d || {}).status || "").toLowerCase();
  const targets = new Set();
  if (before && !after) {
    // Deleted.
    for (const e of toIdList(before.employeeIds)) targets.add(e);
  } else if (before && after) {
    const becameDone = statusOf(before) !== "done" &&
        statusOf(after) === "done";
    const becameCancelled = statusOf(before) !== "cancelled" &&
        statusOf(after) === "cancelled";
    if (becameDone || becameCancelled) {
      // Union both sides, since one save can change status and assignees
      // at the same time.
      for (const e of toIdList(before.employeeIds)) targets.add(e);
      for (const e of toIdList(after.employeeIds)) targets.add(e);
    } else {
      // Unassigned mid-flight.
      const kept = new Set(toIdList(after.employeeIds));
      for (const e of toIdList(before.employeeIds)) {
        if (!kept.has(e)) targets.add(e);
      }
    }
  }
  if (targets.size === 0) return;
  const src = after || before || {};
  for (const employeeDocId of targets) {
    try {
      await endLiveActivity(deps, {
        appointmentId: String(id),
        employeeDocId,
        ctx: {
          clientName: src.clientName,
          title: src.title,
          address: src.address,
          startTime: src.startTime,
          endTime: src.endTime,
          leaveAt: null,
          travelMinutes: null,
        },
        nowDate: now,
      });
    } catch (err) {
      if (deps.logger) {
        deps.logger.warn("liveActivity: end-on-terminal failed",
            {id, employeeDocId, err});
      }
    }
  }
}

/**
 * Orchestrates an appointment write: diff, then a per-employee localized
 * send. Each change push also carries a fresh, locale-correct
 * `widgetPayload` (plus APNs content-available), so the widget updates even
 * with the app closed. Injectable deps `{db, messaging, now, logger}`.
 * @param {string} id appointment doc id.
 * @param {?Object} before
 * @param {?Object} after
 * @param {!Object} deps
 * @return {!Promise<{events: number, sent: number}>}
 */
async function handleAppointmentWrite(id, before, after, deps) {
  const now = deps.now || new Date();
  // Every terminal transition ends the card here, server-side and
  // unconditionally. The device can't tell which card belongs to which
  // appointment, so doing it server-side means a tech marking one job done
  // won't wrongly kill the card for a job they're still driving to.
  await endCardOnTerminal(id, before, after, deps, now);
  const events = diffAppointmentForNotifications(before, after, now, id);
  if (events.length === 0) return {events: 0, sent: 0};
  let sent = 0;
  // A repeat-series batch rewrites up to ~15 sibling docs, each firing this
  // trigger, so without a claim one delete/reschedule would send ~15
  // pushes. The claim below covers delete/cancel/reschedule/unassign; create
  // is already deduped by the differ's anchor rule.
  const seriesId = String(((after || before) || {}).seriesId || "");
  // A fresh op-id is only trustworthy on a write, since after.seriesOpId was
  // minted by this operation. A delete has none — before.seriesOpId is
  // stale and shared by every future delete — so we pass an empty string
  // and let claimSeriesNotice fall back to its seriesId+window logic
  // instead.
  const freshOpId = after ? String(after.seriesOpId || "") : "";
  // One window read per distinct employee across this write's events.
  const windows = new Map();
  for (const {employeeDocId, kind} of events) {
    const ctx = _contextFor(kind, before, after);
    // A reschedule refreshes an existing Lock Screen card. Card ends are
    // handled unconditionally by endCardOnTerminal above, and `assigned`
    // starts no card at all (only the travel-aware "leave now" sweep does
    // that).
    // This runs before the series claim gate, unlike the push, because the
    // card is per-occurrence while the claim collapses a whole reschedule to
    // one nondeterministic winner. updateLiveActivity is a cheap no-op for
    // any occurrence that isn't the live card, so refreshing per-occurrence
    // still lands on the right one regardless of which sibling wins the
    // claim.
    // Best-effort: never throws, and never affects `sent`.
    if (kind === "rescheduled") {
      await updateLiveActivity(deps, {
        appointmentId: String(id),
        employeeDocId,
        ctx: {
          clientName: ctx.clientName,
          title: ctx.title,
          address: ctx.address,
          startTime: ctx.startTime,
          endTime: ((after || before) || {}).endTime,
          leaveAt: null,
          travelMinutes: null,
        },
        nowDate: now,
      });
    }
    if (seriesId !== "") {
      const mine = await claimSeriesNotice(deps, {
        seriesId, seriesOpId: freshOpId, kind, employeeDocId, nowDate: now,
      });
      // A sibling in this same batch already claimed it and will send the
      // push for the series — the card was already refreshed per-occurrence
      // above.
      if (!mine) continue;
    }
    const data = {appointmentId: String(id), kind};
    if (!windows.has(employeeDocId)) {
      windows.set(
          employeeDocId,
          await fetchEmployeeWidgetWindow(
              deps.db, employeeDocId, now, deps.logger),
      );
    }
    const records = windows.get(employeeDocId);
    const delivered = await sendToEmployee(
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
    sent += delivered;
  }
  return {events: events.length, sent};
}

/**
 * Claim, send, then release for one (occurrence, recipient) pair, via a
 * per-recipient ledger doc. `create()` atomically claims exactly once, which
 * is safe under concurrent sweeps, and we release the claim on zero
 * delivered so a later sweep retries. Keying the ledger per-recipient
 * rather than per-occurrence also means one slow-to-register assignee
 * doesn't suppress reminders for the others.
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
    await ledgerRef.create(ledgerBody(nowDate));
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
 * DELETE-fallback window (see [claimSeriesNotice]). Covers
 * trigger-scheduling jitter and a retry, since siblings in one batch fire
 * within seconds of each other. Kept short — seconds, not minutes — so a
 * genuinely separate later delete of the same series still notifies.
 */
const SERIES_CLAIM_WINDOW_MS = 45 * 1000;

const SERIES_CLAIM_COLLECTION = "appointmentSeriesNotices";

/**
 * Claims the right to notify `employeeDocId` about `kind` for one
 * repeat-series operation (first writer wins) so a batch rewriting N
 * occurrences sends one push instead of N — needed because
 * `diffAppointmentForNotifications`'s CREATE-only anchor dedupe can't cover
 * delete/cancel/reschedule, where the anchor doc is often absent from the
 * batch.
 *
 * TWO KEYING MODES:
 *  - **freshOpId present** (precise path): every doc written in one batch
 *    shares a fresh `seriesOpId` (`_newSeriesOpId` in
 *    `firebase_appointments_repository.dart`), so `create()` failing with
 *    ALREADY_EXISTS definitively means a sibling of this batch already
 *    claimed — no time window needed.
 *  - **freshOpId absent** (fallback, deletes): a delete's `before.seriesOpId`
 *    is stale and shared by every future delete, so it falls back to
 *    (seriesId, kind, employee) plus a short window and stale-takeover.
 *
 * This fails open everywhere — any error, or an unreadable fallback claim,
 * returns true (send). Failing open only risks an extra push, while failing
 * closed could drop a cancellation for a tech who's already on the road.
 *
 * @param {!Object} deps `{db, logger}`.
 * @param {{seriesId: string, seriesOpId: string, kind: string,
 *   employeeDocId: string, nowDate: !Date}} opts `seriesOpId` is `""` for a
 *   delete (fallback path).
 * @return {!Promise<boolean>} True when this invocation should send.
 */
async function claimSeriesNotice(deps, opts) {
  const {db, logger} = deps;
  const {seriesId, seriesOpId, kind, employeeDocId, nowDate} = opts;
  const nowMs = nowMillis(nowDate);
  let ref;
  try {
    // Built inside the try because `.doc()` throws synchronously on an id
    // containing "/", and seriesId's contents aren't constrained. A fresh
    // op-id (uuid) is always slash-safe, but sharing this try block also
    // covers the fallback's raw seriesId.
    const docId = seriesOpId !== "" ?
      `op_${seriesOpId}_${kind}_${employeeDocId}` :
      `${seriesId}_${kind}_${employeeDocId}`;
    ref = db.collection(SERIES_CLAIM_COLLECTION).doc(docId);
    await ref.create(ledgerBody(nowDate));
    return true;
  } catch (err) {
    if (!isAlreadyExists(err)) {
      if (logger) {
        logger.warn("series claim failed; sending anyway",
            {seriesId, kind, err});
      }
      return true;
    }
    // A claim already exists. With a fresh op-id that's definitive — only a
    // sibling of this batch could have written it — so we suppress the send
    // with no time window needed.
    if (seriesOpId !== "") return false;
  }
  // Fallback path, for deletes: take over a claim older than the window so
  // a later, genuinely separate delete still notifies. A race on takeover
  // risks a duplicate send, never a miss.
  try {
    const snap = await ref.get();
    const createdMs = toMillis(snap.get("createdAt"));
    // A null createdMs means the doc vanished or carries no usable
    // timestamp — the opposite of a live claim — so we take it over and
    // send. Treating it as live here would mean failing closed, in a
    // function that's supposed to fail open.
    if (createdMs != null && nowMs - createdMs < SERIES_CLAIM_WINDOW_MS) {
      return false;
    }
    await ref.set(ledgerBody(nowDate));
    return true;
  } catch (err) {
    if (logger) {
      logger.warn("series claim refresh failed; sending anyway",
          {seriesId, kind, err});
    }
    return true;
  }
}

/**
 * Orchestrates the overdue "job finished?" sweep. It queries by startTime
 * (endTime would need a new index) over OVERDUE_QUERY_WINDOW_MS, then
 * filters to ended-within-24h-but-open in code, and claims each assignee on
 * its own endTime-keyed per-recipient ledger (see [_deliverRecipientOnce]).
 * Injectable deps `{db, messaging, now, logger}`.
 * @param {!Object} deps
 * @return {!Promise<{prompted: number}>}
 */
async function runOverduePromptSweep(deps) {
  const {db, now} = deps;
  const nowDate = now || new Date();
  const nowMs = nowMillis(nowDate);
  const windowStart = new Date(nowMs - OVERDUE_QUERY_WINDOW_MS);
  // Ordered newest-first so the cap keeps the jobs most likely to still be
  // within the eligible 24h window. Without this, Firestore defaults to
  // oldest-first and spends the cap on jobs that have already aged out —
  // this uses the existing `(status, startTime DESC)` index.
  const snap = await db
      .collection("appointments")
      .where("status", "in", OPEN_STATUSES)
      .where("startTime", ">=", windowStart)
      .where("startTime", "<=", nowDate)
      .orderBy("startTime", "desc")
      .limit(OVERDUE_SWEEP_MAX)
      .get();
  if (snap && snap.size === OVERDUE_SWEEP_MAX && deps.logger) {
    deps.logger.warn(
        "runOverduePromptSweep: candidate cap hit; " +
        "oldest jobs deferred to a later run", {cap: OVERDUE_SWEEP_MAX});
  }
  const candidates = selectOverdueCandidates(
      ((snap && snap.docs) || []).map(_record),
      nowDate,
  );
  const cache = new Map();
  // One flat list of (candidate, assignee) pairs, delivered concurrently.
  // Each pair is an independent ~3 round-trip chain against a distinct ledger
  // id, so serialising them only added wall-clock — and the sweep runs against
  // the 60s default timeout as headcount grows. The shared `cache` Map is safe:
  // JS is single-threaded, so the worst case is a duplicated user read when two
  // pairs miss simultaneously.
  const deliveries = [];
  for (const c of candidates) {
    const endMs = toMillis(c.endTime);
    const ctx = _contextFor("doneCheck", null, c);
    for (const employeeDocId of toIdList(c.employeeIds)) {
      deliveries.push({c, endMs, ctx, employeeDocId});
    }
  }
  const results = await Promise.all(deliveries.map(
      ({c, endMs, ctx, employeeDocId}) => _deliverRecipientOnce(deps, {
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
      }),
  ));
  // Count recipients actually prompted — a job with N assignees can prompt
  // up to N of them. Single-assignee jobs read exactly as before.
  const prompted = results.filter((delivered) => delivered > 0).length;
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
      .where("status", "in", OPEN_STATUSES)
      .where("startTime", ">=", start)
      .where("startTime", "<", end)
      .get();
  const grouped = groupTomorrowsJobsByEmployee(
      ((snap && snap.docs) || []).map(_record),
      nowDate,
  );
  const cache = new Map();
  // Concurrent per employee — see the note in runOverduePromptSweep. Each
  // employee is ~3 sequential round-trips; serialising the outer loop put the
  // whole sweep at N x that against a 60s timeout.
  const sends = Object.keys(grouped)
      .filter((id) => grouped[id] && grouped[id].length > 0)
      .map(async (employeeDocId) => {
        const jobs = grouped[employeeDocId];
        // The 18:00 digest also carries a fresh widget payload (+ content-
        // available) so the home-screen widget rolls forward to tomorrow with
        // the app closed, matching the digest text.
        const records = await fetchEmployeeWidgetWindow(
            db, employeeDocId, nowDate, deps.logger,
        );
        return sendToEmployee(
            deps,
            employeeDocId,
            {kind: "digest"},
            (locale) => buildDigestMessage(jobs, locale),
            TIMED_RECIPIENT_ROLES,
            cache,
            (locale) => ({
              widgetPayload: JSON.stringify(
                  buildWidgetPayload(records, nowDate, locale)),
            }),
        );
      });
  const sentCounts = await Promise.all(sends);
  const digests = sentCounts.filter((sent) => sent > 0).length;
  return {digests};
}

module.exports = {
  OPEN_STATUSES,
  SERIES_CLAIM_WINDOW_MS,
  TIMED_RECIPIENT_ROLES,
  toMillis,
  nowMillis,
  toIdList,
  diffAppointmentForNotifications,
  buildNotificationMessage,
  buildDigestMessage,
  selectOverdueCandidates,
  groupTomorrowsJobsByEmployee,
  tomorrowWindowToronto,
  overduePromptLedgerId,
  isStaleTokenError,
  // The one owner of "push to an employee's live tokens" — token fetch, role +
  // active gate, and stale-token pruning. A new push path calls this rather
  // than re-deriving any of it (changeEmployeeEmail is the first non-job one).
  sendToEmployee,
  deliverRecipientOnce: _deliverRecipientOnce,
  handleAppointmentWrite,
  runDailyDigest,
  runOverduePromptSweep,
};
