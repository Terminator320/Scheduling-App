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
const {liveActivityCtx} = require("./live_activity_utils");
const {
  toMillis,
  MAX_APPOINTMENT_SPAN_MS,
  isCancelledStatus,
  isCompletedStatus,
} = require("./time_utils");
const {
  buildNotificationMessage,
  buildDigestMessage,
} = require("./notification_messages");

const {
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
  recordOf: _record,
  contextFor: _contextFor,
} = require("./notification_policy");

/**
 * Reads (and caches) one recipient's user doc plus their live token docs.
 *
 * Split out of [sendToEmployee] so a caller can ask "can this push reach
 * anyone?" BEFORE paying for the work that composes it — see the gate in
 * [handleAppointmentWrite]. Both go through the same cache entry, so asking
 * costs nothing extra: the send that follows reuses the reads made here.
 *
 * @param {!Object} deps `{db}`.
 * @param {string} employeeDocId users doc id.
 * @param {!Map<string, {user: ?Object, tokenDocs: ?Array<!Object>}>=} cache
 * @return {!Promise<{user: ?Object, tokenDocs: ?Array<!Object>}>}
 */
async function _loadRecipient(deps, employeeDocId, cache) {
  const {db} = deps;
  const userRef = db.collection("users").doc(employeeDocId);
  let entry = cache && cache.get(employeeDocId);
  if (!entry) {
    const userSnap = await userRef.get();
    const user = userSnap.exists ? (userSnap.data() || {}) : null;
    entry = {user, tokenDocs: null};
    if (cache) cache.set(employeeDocId, entry);
  }
  if (!entry.user) return entry;
  // Tokens are read lazily and then cached beside the user. A `null` means "not
  // fetched yet", distinct from `[]` = "fetched, none registered" — which is
  // what lets a pass that only needed the user doc (the travel sweep's prefs
  // read) seed this cache without paying for a tokens read it may never use.
  if (entry.tokenDocs == null) {
    const tokensSnap = await userRef.collection("fcmTokens").get();
    entry.tokenDocs = (tokensSnap && tokensSnap.docs) || [];
  }
  return entry;
}

/**
 * Whether a push of `roles` can actually reach a loaded recipient — the
 * server-side filter to active accounts of an allowed role that hold at least
 * one live token. The ONE owner of that test; a caller gating ahead of a send
 * must ask this rather than restating it, or the gate and the send can drift
 * on who counts as reachable.
 *
 * @param {{user: ?Object, tokenDocs: ?Array<!Object>}} entry From
 *   [_loadRecipient].
 * @param {!Set<string>=} roles Allowed recipient roles (default employees
 *   only).
 * @return {boolean}
 */
function _canReachRecipient(entry, roles) {
  const {user, tokenDocs} = entry || {};
  if (!user) return false;
  const allowed = roles || CHANGE_RECIPIENT_ROLES;
  if (!allowed.has(user.role) || user.status !== "active") return false;
  return ((tokenDocs && tokenDocs.length) || 0) > 0;
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
  const {messaging, logger} = deps;

  const entry = await _loadRecipient(deps, employeeDocId, cache);
  if (!_canReachRecipient(entry, roles)) return 0;
  const {tokenDocs} = entry;

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
 * Tail guard on the widget window. An 8-day slice of one person's jobs is
 * small in steady state, but this runs once per assignee on EVERY notified
 * appointment write, and a bulk import or a wide repeat series landing in the
 * window is otherwise an unbounded fan-out.
 */
const WIDGET_WINDOW_MAX = 200;

/**
 * Reads an employee's appointments for the widget payload, so the change push
 * can carry a fresh one. Never throws — a failed read just yields an empty
 * window, and the notification still sends.
 *
 * The window is the jobs that OVERLAP `[today 00:00 Toronto,
 * +WIDGET_LOOKAHEAD_DAYS days)`, asked as an overlap directly:
 * `endTime >= todayStart AND startTime < end`. Served by the existing
 * `(employeeIds CONTAINS, endTime ASC, startTime ASC)` composite.
 *
 * It used to floor `startTime` at `todayStart − MAX_APPOINTMENT_SPAN_MS` and
 * let `buildWidgetPayload` drop the rest, because a query on `startTime` alone
 * cannot see a multi-day run that began earlier but still WORKS today. That
 * back-scan read a fortnight of this employee's history on every notified
 * write — ~17 days of documents to render 3 — and it ran once per assignee.
 * Firestore has supported two inequality fields since 2023, so the overlap is
 * now expressible as the query rather than approximated by a wider one.
 *
 * Two consequences, both fine here. Results arrive ordered by `endTime` (the
 * first inequality field), not `startTime` — `buildWidgetPayload` sorts every
 * bucket by window start itself, so it never depended on query order. And a
 * document missing EITHER instant is absent from a composite index, where the
 * old form only required `startTime`; such a record has no parseable window,
 * so `sliceForDay` already dropped it one step later.
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
        .where("endTime", ">=", start)
        .where("startTime", "<", end)
        .limit(WIDGET_WINDOW_MAX)
        .get();
    const docs = (snap && snap.docs) || [];
    if (docs.length >= WIDGET_WINDOW_MAX && logger) {
      // Same posture as TRAVEL_SWEEP_MAX / OVERDUE_SWEEP_MAX / DIGEST_SWEEP_MAX
      // beside it: this was the one sweep read left with no ceiling, and a
      // silent truncation here ships a PARTIAL home-screen widget payload.
      logger.warn("widget: window hit the scan cap", {
        employeeDocId,
        cap: WIDGET_WINDOW_MAX,
      });
    }
    return docs.map(_record);
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
  const statusOf = (d) => (d || {}).status;
  const targets = new Set();
  if (before && !after) {
    // Deleted.
    for (const e of toIdList(before.employeeIds)) targets.add(e);
  } else if (before && after) {
    // Through the shared owners rather than a literal "done": this tested
    // `=== "done"` and so left the card running forever on a flip to the legacy
    // `completed` alias.
    const becameDone = !isCompletedStatus(statusOf(before)) &&
        isCompletedStatus(statusOf(after));
    const becameCancelled = !isCancelledStatus(statusOf(before)) &&
        isCancelledStatus(statusOf(after));
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
        ctx: liveActivityCtx(src),
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
  // One user + tokens read per distinct employee across this write's events —
  // the same per-sweep cache runOverduePromptSweep and the travel sweep use.
  // Without it, two events for the same person in one write read that user
  // twice.
  const recipients = new Map();
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
        // Spread, not a hand-picked field list: liveActivityCtx field-picks
        // already, and re-listing here reintroduces the silent-drop the
        // helper exists to prevent.
        ctx: liveActivityCtx(
            {...ctx, endTime: (after || before || {}).endTime}),
        nowDate: now,
      });
    }
    // Eligibility FIRST, and deliberately above the series claim as well as
    // the widget window: change-driven pushes are employees-only
    // (CHANGE_RECIPIENT_ROLES), so an assigned ADMIN — or anyone with no live
    // token — used to pay a widget-window query, a users read, a tokens read
    // and, in a series, a claim-ledger WRITE, for a push `sendToEmployee` then
    // refused at its role gate. Nothing delivered changes: the claim is keyed
    // per (operation, kind, EMPLOYEE), so skipping it for a recipient who
    // cannot be reached can only ever suppress that same recipient's sends,
    // which were already zero. The reads land in `recipients`, so the send
    // below reuses them rather than repeating them.
    const recipient = await _loadRecipient(deps, employeeDocId, recipients);
    if (!_canReachRecipient(recipient, CHANGE_RECIPIENT_ROLES)) continue;
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
        CHANGE_RECIPIENT_ROLES,
        recipients,
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
  // Reachability BEFORE the claim, the same order [handleAppointmentWrite] and
  // the digest use. Claiming first cost 2 writes (create + release) and 2
  // reads per unreachable (job, assignee) pair on EVERY sweep run — ~48 of
  // each over the overdue window's 2 h at a 5-minute cadence. Semantics are
  // unchanged: "no ledger written" is indistinguishable from "written then
  // released", so the late-token retry the release exists for still works.
  // The reads land in `cache`, so the send below reuses them.
  try {
    const recipient = await _loadRecipient(deps, employeeDocId, cache);
    if (!_canReachRecipient(recipient, roles)) return 0;
  } catch (err) {
    // This read used to sit inside `sendToEmployee`, under the catch below, so
    // a transient failure must still not abort the sweep for the remaining
    // recipients — and returning 0 unclaimed is what the release branch would
    // have left behind anyway.
    if (logger) {
      logger.warn(`${label}: recipient load failed`, {id: appointmentId, err});
    }
    return 0;
  }
  let ledgerRef;
  try {
    // Built INSIDE the try: .doc() throws synchronously on an id containing
    // "/", and rules only length-check employeeIds (they can't iterate a
    // list), so one poisoned element would otherwise kill the whole sweep.
    ledgerRef = db.collection(collection).doc(ledgerId);
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
 * Orchestrates the overdue "job finished?" sweep. It queries `endTime` over
 * OVERDUE_LOOKBACK_MS — the eligibility window itself — and claims each
 * assignee on its own endTime-keyed per-recipient ledger (see
 * [_deliverRecipientOnce]). Injectable deps `{db, messaging, now, logger}`.
 * @param {!Object} deps
 * @return {!Promise<{prompted: number}>}
 */
async function runOverduePromptSweep(deps) {
  const {db, now} = deps;
  const nowDate = now || new Date();
  const nowMs = nowMillis(nowDate);
  const windowStart = new Date(nowMs - OVERDUE_LOOKBACK_MS);
  // Bounds mirror selectOverdueCandidates EXACTLY — `> floor`, `<= now` — so
  // the query is the rule rather than a superset of it. This rides the
  // 5-minute reminder timer, so it runs 288x a day (it was 96 under the
  // deleted `every 15 minutes` scheduler, which is what OVERDUE_LOOKBACK_MS
  // was originally sized against — see the constant's note). The old startTime
  // form re-read every open job started in the last ~15 days on each run to
  // prompt the handful that had just ended.
  //
  // Ordered newest-first so the cap keeps the jobs most likely to still be
  // eligible. Without this, Firestore orders by the inequality field ascending
  // and spends the cap on the jobs closest to aging out. Needs the
  // `(status, endTime DESC)` composite index — deploy firestore:indexes with
  // this, or the sweep fails FAILED_PRECONDITION and prompts nobody.
  //
  // A doc with no `endTime` is excluded by this filter, where the startTime
  // form read it and dropped it in code (`selectOverdueCandidates` requires a
  // parseable endTime). Same outcome, one less read.
  const snap = await db
      .collection("appointments")
      .where("status", "in", OPEN_STATUSES)
      .where("endTime", ">", windowStart)
      .where("endTime", "<=", nowDate)
      .orderBy("endTime", "desc")
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
  // Widened by the max span: the query filters on startTime, so a run that
  // began days ago but is still on site tomorrow is only fetched if the floor
  // reaches back that far. groupTomorrowsJobsByEmployee then does the real
  // overlap test.
  const queryStart = new Date(start.getTime() - MAX_APPOINTMENT_SPAN_MS);
  // Bounded like the travel and overdue sweeps beside it — this was the last
  // one without a ceiling. The 15-day window keeps it small in practice, so
  // the cap is a tail guard rather than a steady-state bound: a bulk import or
  // a wide repeat series landing in it is otherwise an unbounded fan-out that
  // then costs a widget-window read and a send per grouped employee, against a
  // 60 s timeout.
  //
  // `startTime` **DESC**, and the direction is the whole point of the cap.
  // The floor is 15 days in the PAST (see above), so ascending would make the
  // limit keep the OLDEST still-open jobs and discard the newest — i.e.
  // tomorrow's, the only ones this digest is about. Once a stale tail of
  // unclosed jobs exceeds the cap, every crew silently gets no digest at all.
  // Descending keeps the window's newest, which is what
  // `groupTomorrowsJobsByEmployee` then overlap-tests; the sibling sweep with
  // this shape (`runOverduePromptSweep`) orders `endTime` DESC for the same
  // reason. Served by the existing `(status, startTime DESC)` composite — no
  // new index.
  const snap = await db
      .collection("appointments")
      .where("status", "in", OPEN_STATUSES)
      .where("startTime", ">=", queryStart)
      .where("startTime", "<", end)
      .orderBy("startTime", "desc")
      .limit(DIGEST_SWEEP_MAX)
      .get();
  if (snap && snap.size === DIGEST_SWEEP_MAX && deps.logger) {
    deps.logger.warn(
        "runDailyDigest: candidate cap hit; " +
        "some crews may not receive a digest", {cap: DIGEST_SWEEP_MAX});
  }
  // Back to ascending before grouping, so the per-employee job lists the
  // digest text renders stay in chronological order.
  const grouped = groupTomorrowsJobsByEmployee(
      ((snap && snap.docs) || []).map(_record).reverse(),
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
        try {
          // Reachability BEFORE the widget-window query, the order
          // [handleAppointmentWrite] already establishes: an inactive, wrong-
          // role or tokenless employee costs a 200-doc read and a whole
          // payload build/JSON encode, every day, for a send that returns 0.
          // Both reads land in the same `cache` entry, so the send below pays
          // nothing extra for asking.
          const recipient = await _loadRecipient(deps, employeeDocId, cache);
          if (!_canReachRecipient(recipient, TIMED_RECIPIENT_ROLES)) return 0;
          // The 18:00 digest also carries a fresh widget payload (+ content-
          // available) so the home-screen widget rolls forward to tomorrow
          // with the app closed, matching the digest text.
          const records = await fetchEmployeeWidgetWindow(
              db, employeeDocId, nowDate, deps.logger,
          );
          return await sendToEmployee(
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
        } catch (err) {
          // A transient read/send failure must not abort the digest for the
          // remaining employees. There is no ledger and this runs once a day,
          // so a dropped batch means those people lose tomorrow entirely.
          if (deps.logger) {
            deps.logger.warn("digest: send failed", {id: employeeDocId, err});
          }
          return 0;
        }
      });
  const sentCounts = await Promise.all(sends);
  const digests = sentCounts.filter((sent) => sent > 0).length;
  return {digests};
}

/**
 * Ceiling on one admin fan-out, with the warn-at-cap posture the three sweep
 * ceilings use. Admins are a handful in practice, so this is a tail guard —
 * but this was the last unbounded collection query in the push stack, and it
 * is the fan-out P6's time-off requests will build on.
 */
const ADMIN_FANOUT_MAX = 100;

/**
 * Pushes one localized message to every ACTIVE ADMIN.
 *
 * Shared fan-out: the self-service email change needs it, and P6's time-off
 * requests will too — built once here rather than inlined at each call site,
 * beside `sendToEmployee` and for the same reason (one owner for "who has live
 * tokens, and is this recipient still entitled").
 *
 * **Best-effort, and it never throws.** Whatever prompted the notice has
 * already committed, so a push failure must not surface as a failed operation
 * — that would hand the caller an error for something that worked. Each
 * recipient is isolated too, so one bad token cannot suppress the rest.
 *
 * @param {!Object} deps `{db, messaging, logger}`.
 * @param {!Object} data Data payload (string values); `kind` etc.
 * @param {function(string): {title: string, body: string}} buildMsg Localized
 *   message builder keyed by 'en'|'fr'.
 * @param {{excludeDocId: (string|undefined),
 *          sendToEmployee: (!Function|undefined)}=} opts `excludeDocId` skips
 *   the person who caused the notice — they do not need telling what they just
 *   did. `sendToEmployee` is injectable for tests only.
 * @return {!Promise<void>}
 */
async function sendToActiveAdmins(deps, data, buildMsg, opts) {
  const {db, logger} = deps;
  const options = opts || {};
  const send = options.sendToEmployee || sendToEmployee;
  try {
    const snap = await db.collection("users")
        .where("role", "==", "admin")
        .where("status", "==", "active")
        .limit(ADMIN_FANOUT_MAX)
        .get();
    if (snap && snap.size === ADMIN_FANOUT_MAX && logger) {
      logger.warn(
          "sendToActiveAdmins: recipient cap hit; " +
          "some admins were not notified", {cap: ADMIN_FANOUT_MAX});
    }
    // Seeds the recipient cache from the docs just read, so `_loadRecipient`
    // doesn't re-`get()` a users doc already in hand — that was +1 redundant
    // read per active admin per notice. `tokenDocs: null` means "not fetched
    // yet", so the fcmTokens read still happens exactly once per admin.
    const cache = new Map(snap.docs.map(
        (doc) => [doc.id, {user: doc.data() || {}, tokenDocs: null}]));
    await Promise.all(snap.docs
        .filter((doc) => doc.id !== options.excludeDocId)
        .map((doc) => send(
            deps, doc.id, data, buildMsg, ADMIN_RECIPIENT_ROLES, cache,
        ).catch((e) => {
          if (logger) {
            logger.warn("sendToActiveAdmins: recipient failed",
                {docId: doc.id, err: String(e)});
          }
        })));
  } catch (e) {
    if (logger) {
      logger.warn("sendToActiveAdmins: fan-out failed", {err: String(e)});
    }
  }
}

module.exports = {
  // Every notification_policy symbol is re-exported here under its original
  // name, so a call site never has to know which of the two modules a pure
  // rule ended up in. `notification_utils.test.js` reads both module surfaces
  // back and fails if a policy export is ever added without its re-export —
  // ten of these were missing while functions/CLAUDE.md asserted the
  // invariant held.
  DAY_MS,
  OVERDUE_LOOKBACK_MS,
  OVERDUE_SWEEP_MAX,
  DIGEST_SWEEP_MAX,
  WIDGET_PAYLOAD_MAX_BYTES,
  OPEN_STATUSES,
  CHANGE_RECIPIENT_ROLES,
  TIMED_RECIPIENT_ROLES,
  ADMIN_RECIPIENT_ROLES,
  ADMIN_FANOUT_MAX,
  ledgerBody,
  isAlreadyExists,
  recordOf: _record,
  contextFor: _contextFor,
  SERIES_CLAIM_WINDOW_MS,
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
  sendToActiveAdmins,
  deliverRecipientOnce: _deliverRecipientOnce,
  handleAppointmentWrite,
  runDailyDigest,
  runOverduePromptSweep,
};
