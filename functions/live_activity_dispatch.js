"use strict";

/**
 * @fileoverview Orchestrates the iOS "time to leave" Live Activity: registry
 * lookup -> payload build -> direct APNs send -> prune dead rows. The three
 * exported verbs are the ONLY surface the notification hooks call, so
 * `travel_utils.js` / `notification_utils.js` never touch APNs or the registry
 * directly.
 *
 * FCM cannot send `apns-push-type: liveactivity`, which is why this path talks
 * to APNs directly (see apns_client.js).
 *
 * EVERY export here is best-effort and never throws: a Live Activity failure
 * must not change the outcome of the push that hosts it. No token, no APNs
 * credentials, iOS < 17.2, or Live Activities disabled all degrade silently to
 * the existing `leaveNow` push, which fires independently and is unchanged.
 *
 * @module live_activity_dispatch
 */

const {
  buildContentState,
  buildStartPayload,
  buildUpdatePayload,
  buildEndPayload,
  liveActivityStrings,
  phaseFor,
  PHASE_ON_SITE,
} = require("./live_activity_utils");
const {
  listPushToStartTokens,
  listUpdateTokens,
  deleteActivityToken,
  writeCardMarker,
  readCardMarker,
  setCardPhase,
  clearCardMarker,
} = require("./live_activity_registry");
const {sendLiveActivityPush} = require("./apns_client");

/**
 * The ActivityKit `attributes` a push-to-start carries — the immutable half of
 * the activity. Hand-mirrored with the `ActivityAttributes` struct in
 * `ios/ScheduleWidget/LiveActivitiesAppAttributes.swift`; change one, change both.
 * @param {{appointmentId: string, employeeDocId: string,
 *   employeeColorValue: (number|undefined)}} args
 * @return {!Object}
 */
function buildAttributes({appointmentId, employeeDocId, employeeColorValue}) {
  return {
    appointmentId: String(appointmentId || ""),
    employeeDocId: String(employeeDocId || ""),
    employeeColorValue: typeof employeeColorValue === "number" ?
        employeeColorValue : 0,
  };
}

/**
 * The assignee's `colorValue`, which drives the card's colour rail (mirroring
 * `AppointmentCard`). A failed read yields 0 and the Swift side falls back to
 * the amber accent — never a reason to skip the card.
 * @param {!Object} deps `{db, logger}`.
 * @param {string} employeeDocId
 * @return {!Promise<number>}
 */
async function _employeeColorValue(deps, employeeDocId) {
  try {
    const snap = await deps.db.collection("users").doc(employeeDocId).get();
    const value = snap && snap.exists ? (snap.data() || {}).colorValue : null;
    return typeof value === "number" ? value : 0;
  } catch (err) {
    if (deps.logger) {
      deps.logger.warn("liveActivity: colorValue read failed", {err});
    }
    return 0;
  }
}

/**
 * This employee's live update-token rows, but ONLY when the card marker
 * confirms the live card is showing `appointmentId`; `[]` otherwise.
 *
 * The marker is load-bearing, not a convenience. A push-STARTED activity's id
 * is minted by ActivityKit and `live_activities` exposes no way to read a
 * started activity's attributes back, so the device physically cannot stamp
 * `appointmentId` onto its own token row — the rows are only ever keyed by
 * employee. Resolving by employee alone would let a cancel on next week's job
 * end the card for the job the tech is currently driving to; resolving by a
 * row-level `appointmentId` that is never written would match nothing at all.
 * @param {!Object} deps
 * @param {{appointmentId: string, employeeDocId: string}} args
 * @return {!Promise<!Array<!Object>>}
 */
async function _liveRowsFor(deps, {appointmentId, employeeDocId}) {
  if (!employeeDocId) return [];
  const marker = await readCardMarker(deps, {employeeDocId});
  if (!marker || marker.appointmentId !== String(appointmentId)) return [];
  const rows = await listUpdateTokens(deps, {employeeDocId});
  return rows.filter((row) => row && row.token);
}

/**
 * `{authKey, keyId, teamId}` for APNs, or null when the secrets aren't
 * configured — in which case every verb here no-ops. Read lazily so a module
 * load outside a secret-bound function can't throw.
 * @param {!Object} deps
 * @return {?Object}
 */
function _authOf(deps) {
  const auth = deps && deps.apnsAuth;
  if (!auth || !auth.authKey || !auth.keyId || !auth.teamId) return null;
  return auth;
}

/**
 * Sends one payload to one registry row and prunes the row when APNs says the
 * activity is gone. Returns 1 on a delivered push, else 0.
 * @param {!Object} deps `{logger, apnsAuth}`.
 * @param {!Object} row A row from the registry.
 * @param {!Object} payload
 * @param {string} label For the warn line.
 * @return {!Promise<number>}
 */
async function _sendToRow(deps, row, payload, label) {
  const auth = _authOf(deps);
  if (!auth || !row || !row.token) return 0;
  const result = await sendLiveActivityPush({
    token: row.token,
    payload,
    auth,
    collapseId: row.collapseId || undefined,
    logger: deps.logger,
  });
  if (result.gone) {
    await deleteActivityToken(deps, {ref: row.ref});
    return 0;
  }
  if (!result.ok && deps.logger) {
    deps.logger.warn(`liveActivity: ${label} push rejected`, {
      status: result.status,
      reason: result.reason,
    });
  }
  return result.ok ? 1 : 0;
}

/**
 * Content state for a row's locale — card text is built server-side per the
 * per-token `locale` already stored, the same rule the notification bodies
 * follow.
 * @param {!Object} row
 * @param {!Object} ctx `{clientName, address, startTime, leaveAt,
 *   travelMinutes}`.
 * @param {*} nowDate
 * @return {!Object}
 */
function _stateFor(row, ctx, nowDate) {
  return buildContentState({
    clientName: ctx.clientName,
    address: ctx.address,
    startTime: ctx.startTime,
    leaveAt: ctx.leaveAt,
    travelMinutes: ctx.travelMinutes,
    phase: phaseFor({startTime: ctx.startTime, now: nowDate}),
    locale: row.locale,
  });
}

/**
 * Starts the Lock Screen card for ONE (job, assignee) pair via push-to-start.
 * Called from the travel-aware sweep immediately after the reminder's ledger
 * claim succeeded and delivered, so it inherits that claim's exactly-once
 * guarantee rather than adding a second one.
 * @param {!Object} deps `{db, logger, apnsAuth}`.
 * @param {!Object} args `{appointmentId, employeeDocId, ctx, nowDate}`.
 * @return {!Promise<number>} Cards started.
 */
async function startLiveActivity(deps, args) {
  const {appointmentId, employeeDocId, ctx, nowDate} = args;
  if (!_authOf(deps)) return 0;
  try {
    const rows = await listPushToStartTokens(deps, {
      employeeDocIds: [employeeDocId],
    });
    if (rows.length === 0) return 0;
    const attributes = buildAttributes({
      appointmentId,
      employeeDocId,
      employeeColorValue: await _employeeColorValue(deps, employeeDocId),
    });
    let started = 0;
    for (const row of rows) {
      const state = _stateFor(row, ctx, nowDate);
      const strings = liveActivityStrings(row.locale);
      const payload = buildStartPayload({
        contentState: state,
        attributes,
        now: nowDate,
        // The alert body IS the drive line, so it's omitted without one.
        alert: typeof ctx.travelMinutes === "number" ?
            strings.startAlert(ctx, state.clientName) : null,
        // The card is meaningless once the visit has started; ActivityKit
        // greys it out rather than showing a stale "leave at".
        staleDate: ctx.startTime,
      });
      started += await _sendToRow(deps, row, payload, "start");
    }
    // Records which appointment this tech's card is showing, so the update and
    // end hooks can resolve it — see [_liveRowsFor].
    if (started > 0) {
      await writeCardMarker(deps, {
        employeeDocId,
        appointmentId: String(appointmentId),
        startTime: ctx.startTime,
        phase: phaseFor({startTime: ctx.startTime, now: nowDate}),
      });
    }
    return started;
  } catch (err) {
    if (deps.logger) {
      deps.logger.warn("liveActivity: start failed", {id: appointmentId, err});
    }
    return 0;
  }
}

/**
 * Pushes a fresh content state to this employee's live card — the reschedule
 * hook and the on-site phase-flip backstop both land here. A no-op when the
 * employee has no card, or has one for a different appointment.
 * @param {!Object} deps `{db, logger, apnsAuth}`.
 * @param {!Object} args `{appointmentId, employeeDocId, ctx, nowDate}`.
 * @return {!Promise<number>} Cards updated.
 */
async function updateLiveActivity(deps, args) {
  const {appointmentId, employeeDocId, ctx, nowDate} = args;
  if (!_authOf(deps)) return 0;
  try {
    const rows = await _liveRowsFor(deps, {appointmentId, employeeDocId});
    if (rows.length === 0) return 0;
    const phase = phaseFor({startTime: ctx.startTime, now: nowDate});
    let updated = 0;
    for (const row of rows) {
      const payload = buildUpdatePayload({
        contentState: _stateFor(row, ctx, nowDate),
        now: nowDate,
        staleDate: ctx.startTime,
      });
      updated += await _sendToRow(deps, row, payload, "update");
    }
    // Stamping the flip is what makes the on-site backstop fire exactly once.
    if (updated > 0 && phase === PHASE_ON_SITE) {
      await setCardPhase(deps, {employeeDocId, phase: PHASE_ON_SITE});
    }
    return updated;
  } catch (err) {
    if (deps.logger) {
      deps.logger.warn("liveActivity: update failed", {id: appointmentId, err});
    }
    return 0;
  }
}

/**
 * Ends this employee's live card and drops its registry rows + card marker —
 * the cancel/remove hook. `dismissal-date: now` clears it from the Lock Screen
 * immediately; without it ActivityKit lingers for up to four hours.
 * @param {!Object} deps `{db, logger, apnsAuth}`.
 * @param {!Object} args `{appointmentId, employeeDocId, ctx, nowDate}`.
 * @return {!Promise<number>} Cards ended.
 */
async function endLiveActivity(deps, args) {
  const {appointmentId, employeeDocId, ctx, nowDate} = args;
  if (!_authOf(deps)) return 0;
  try {
    const rows = await _liveRowsFor(deps, {appointmentId, employeeDocId});
    if (rows.length === 0) return 0;
    let ended = 0;
    for (const row of rows) {
      const payload = buildEndPayload({
        contentState: _stateFor(row, ctx || {}, nowDate),
        now: nowDate,
        dismissalDate: nowDate,
      });
      ended += await _sendToRow(deps, row, payload, "end");
      // The activity is over either way — a row kept here would be pruned
      // only by the TTL sweep days later.
      await deleteActivityToken(deps, {ref: row.ref});
    }
    await clearCardMarker(deps, {employeeDocId});
    return ended;
  } catch (err) {
    if (deps.logger) {
      deps.logger.warn("liveActivity: end failed", {id: appointmentId, err});
    }
    return 0;
  }
}

module.exports = {
  buildAttributes,
  startLiveActivity,
  updateLiveActivity,
  endLiveActivity,
};
