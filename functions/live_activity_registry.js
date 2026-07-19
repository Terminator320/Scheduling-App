"use strict";

/**
 * @fileoverview Reads and prunes the Live Activity token registry at
 * `users/{docId}/liveActivityTokens/{activityId}` — the doc id IS the
 * ActivityKit activity id. Fields: `{token, kind: 'pushToStart'|'update',
 * appointmentId, employeeDocId, locale, uid, platform, createdAt, updatedAt,
 * expiresAt}`. Written self-only by the client; read here across employees
 * with the Admin SDK via `collectionGroup`, the same shape as the admin
 * presence read.
 *
 * Deps are injected (`{db, now, logger}`) so jest drives this without
 * firebase-admin. Best-effort by contract, matching the design doc's failure
 * posture: a read that throws returns `[]` and the caller degrades to the
 * plain `leaveNow` push.
 *
 * Also owns the **card marker** at `liveActivityCards/{employeeDocId}` — the
 * server's record of which appointment that tech's live card is showing. The
 * marker exists because a PUSH-STARTED activity's id is minted by ActivityKit
 * and the `live_activities` plugin exposes no way to read a started activity's
 * attributes back, so the device physically cannot stamp `appointmentId` onto
 * its own update-token row. Without the marker, cancelling a job next week
 * would end the card for the job the tech is currently driving to. One doc per
 * actively-traveling tech (at most one card per tech by design), Admin-SDK-only
 * — clients cannot read or write it.
 *
 * @module live_activity_registry
 */

const KIND_PUSH_TO_START = "pushToStart";
const KIND_UPDATE = "update";

const CARDS_COLLECTION = "liveActivityCards";

// A card outlives its job by at most a few hours; this is the marker's own
// TTL backstop for the case where no end push ever lands.
const CARD_TTL_MS = 12 * 60 * 60 * 1000;

// Firestore caps an `in` filter at 30 values — same constraint the
// `whereArrayContainsAny` chunking in the appointments repository documents.
const IN_QUERY_MAX = 30;

// Safety valve on a single prune pass so one run can't blow the timeout.
const PRUNE_MAX = 400;

// How long a registered token stays valid without a refresh. The client
// re-upserts on every account-doc emission, so a row older than this belongs
// to an activity the server never got to end (design doc, "Still open").
const TOKEN_TTL_MS = 3 * 24 * 60 * 60 * 1000;

/**
 * Splits a list into chunks of at most `size`.
 * @param {!Array<*>} list
 * @param {number} size
 * @return {!Array<!Array<*>>}
 */
function _chunk(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) {
    out.push(list.slice(i, i + size));
  }
  return out;
}

/**
 * Flattens one query snapshot into registry rows. `activityId` is the doc id;
 * `ref` is kept so the caller can prune a dead row without re-deriving a path.
 * @param {*} snap
 * @return {!Array<!Object>}
 */
function _rows(snap) {
  return ((snap && snap.docs) || []).map((d) => ({
    activityId: d.id,
    ref: d.ref,
    ...(d.data() || {}),
  }));
}

/**
 * Expiry stamp for a freshly written/refreshed token row.
 * @param {(Date|undefined)} now
 * @return {!Date}
 */
function activityTokenExpiry(now) {
  return new Date((now ? now.getTime() : Date.now()) + TOKEN_TTL_MS);
}

/**
 * Runs one collection-group query and never throws.
 * @param {!Object} deps `{db, logger}`.
 * @param {function(!Object): !Object} build Applies the filters.
 * @param {string} label Log label.
 * @return {!Promise<!Array<!Object>>}
 */
async function _query(deps, build, label) {
  const {db, logger} = deps;
  try {
    const snap = await build(db.collectionGroup("liveActivityTokens")).get();
    return _rows(snap);
  } catch (err) {
    if (logger) logger.warn(`liveActivity: ${label} failed`, {err});
    return [];
  }
}

/**
 * The push-to-start tokens for the given employees — one per device, used to
 * start a card on a closed, locked phone. Chunked to the Firestore `in` cap.
 * @param {!Object} deps `{db, logger}`.
 * @param {{employeeDocIds: !Array<string>}} args
 * @return {!Promise<!Array<!Object>>}
 */
async function listPushToStartTokens(deps, {employeeDocIds}) {
  const ids = (employeeDocIds || []).filter(Boolean);
  if (ids.length === 0) return [];
  const batches = await Promise.all(_chunk(ids, IN_QUERY_MAX).map((chunk) =>
    _query(
        deps,
        (q) => q
            .where("kind", "==", KIND_PUSH_TO_START)
            .where("employeeDocId", "in", chunk),
        "pushToStart read",
    ),
  ));
  return batches.flat();
}

/**
 * The per-activity update tokens one employee's device(s) registered. Keyed by
 * employee, NOT by appointment: the device can't know which appointment a
 * push-started card belongs to (see the card-marker note in the file header),
 * so the caller pairs this with [readCardMarker] to confirm the live card is
 * the one it means to update or end. A tech signed in on two phones yields two
 * rows.
 * @param {!Object} deps `{db, logger}`.
 * @param {{employeeDocId: string}} args
 * @return {!Promise<!Array<!Object>>}
 */
async function listUpdateTokens(deps, {employeeDocId}) {
  if (!employeeDocId) return [];
  return _query(
      deps,
      (q) => q
          .where("kind", "==", KIND_UPDATE)
          .where("employeeDocId", "==", employeeDocId),
      "update-token read",
  );
}

/**
 * Records that this employee's live card now shows `appointmentId`. Absolute
 * write (no merge) — a new card fully replaces the previous one.
 * @param {!Object} deps `{db, now, logger}`.
 * @param {{employeeDocId: string, appointmentId: string, startTime: *,
 *   phase: string}} args
 * @return {!Promise<boolean>}
 */
async function writeCardMarker(
    deps, {employeeDocId, appointmentId, startTime, phase}) {
  const {db, now, logger} = deps;
  if (!employeeDocId || !appointmentId) return false;
  const nowDate = now || new Date();
  try {
    await db.collection(CARDS_COLLECTION).doc(employeeDocId).set({
      employeeDocId,
      appointmentId,
      startTime: startTime || null,
      phase,
      startedAt: nowDate,
      expiresAt: new Date(nowDate.getTime() + CARD_TTL_MS),
    });
    return true;
  } catch (err) {
    if (logger) logger.warn("liveActivity: card marker write failed", {err});
    return false;
  }
}

/**
 * The employee's current card marker, or null when no card is live.
 * @param {!Object} deps `{db, logger}`.
 * @param {{employeeDocId: string}} args
 * @return {!Promise<?Object>}
 */
async function readCardMarker(deps, {employeeDocId}) {
  const {db, logger} = deps;
  if (!employeeDocId) return null;
  try {
    const snap = await db
        .collection(CARDS_COLLECTION).doc(employeeDocId).get();
    return snap && snap.exists ? (snap.data() || null) : null;
  } catch (err) {
    if (logger) logger.warn("liveActivity: card marker read failed", {err});
    return null;
  }
}

/**
 * Marks the employee's card as flipped to on-site so the backstop pass pushes
 * the flip exactly once. Never throws.
 * @param {!Object} deps `{db, logger}`.
 * @param {{employeeDocId: string, phase: string}} args
 * @return {!Promise<boolean>}
 */
async function setCardPhase(deps, {employeeDocId, phase}) {
  const {db, logger} = deps;
  if (!employeeDocId) return false;
  try {
    await db.collection(CARDS_COLLECTION).doc(employeeDocId)
        .set({phase}, {merge: true});
    return true;
  } catch (err) {
    if (logger) logger.warn("liveActivity: card phase write failed", {err});
    return false;
  }
}

/**
 * Drops the employee's card marker once the card has been ended.
 * @param {!Object} deps `{db, logger}`.
 * @param {{employeeDocId: string}} args
 * @return {!Promise<boolean>}
 */
async function clearCardMarker(deps, {employeeDocId}) {
  const {db, logger} = deps;
  if (!employeeDocId) return false;
  try {
    await db.collection(CARDS_COLLECTION).doc(employeeDocId).delete();
    return true;
  } catch (err) {
    if (logger) logger.warn("liveActivity: card marker clear failed", {err});
    return false;
  }
}

/**
 * Card markers still in the `travel` phase whose `startTime` has passed — the
 * candidate set for the on-site flip backstop. No `phase` filter in the query
 * (that would need a composite index for a collection holding one doc per
 * actively-traveling tech); the phase is filtered in code, the same trade the
 * client job-history query documents. Never throws.
 * @param {!Object} deps `{db, now, logger}`.
 * @param {{limit: (number|undefined)}=} args
 * @return {!Promise<!Array<!Object>>}
 */
async function listCardsDueForOnSite(deps, args) {
  const {db, now, logger} = deps;
  const nowDate = now || new Date();
  try {
    const snap = await db
        .collection(CARDS_COLLECTION)
        .where("startTime", "<=", nowDate)
        .limit((args && args.limit) || PRUNE_MAX)
        .get();
    return _rows(snap).filter((row) => row.phase !== "onSite");
  } catch (err) {
    if (logger) logger.warn("liveActivity: on-site query failed", {err});
    return [];
  }
}

/**
 * Deletes one registry row. Called when APNs reports the activity is gone
 * (410 / BadDeviceToken) and after the server ends a card. Never throws.
 * @param {!Object} deps `{logger}`.
 * @param {{ref: !Object}} args The `ref` from a listed row.
 * @return {!Promise<boolean>} True when the row is gone.
 */
async function deleteActivityToken(deps, {ref}) {
  if (!ref || typeof ref.delete !== "function") return false;
  try {
    await ref.delete();
    return true;
  } catch (err) {
    if (deps && deps.logger) {
      deps.logger.warn("liveActivity: token delete failed", {err});
    }
    return false;
  }
}

/**
 * Deletes rows of `query` whose `expiresAt` has passed. Bounded by `cap` — a
 * hit cap just defers the remainder to the next run. Never throws.
 * @param {!Object} deps `{now, logger}`.
 * @param {!Object} collection A collection or collection-group ref.
 * @param {number} cap
 * @param {string} label Distinguishes the two sweeps in the warn lines.
 * @return {!Promise<{pruned: number}>}
 */
async function _pruneExpired(deps, collection, cap, label) {
  const {now, logger} = deps;
  let rows = [];
  try {
    const snap = await collection
        .where("expiresAt", "<=", now || new Date())
        .limit(cap)
        .get();
    rows = _rows(snap);
  } catch (err) {
    if (logger) logger.warn(`liveActivity: ${label} prune query failed`, {err});
    return {pruned: 0};
  }
  let pruned = 0;
  for (const row of rows) {
    // Serial deletes: the expired set is tiny and a failure on one row must
    // not abort the rest.
    if (await deleteActivityToken(deps, row)) pruned += 1;
  }
  if (rows.length === cap && logger) {
    logger.warn(`liveActivity: ${label} prune cap hit; deferred`, {cap});
  }
  return {pruned};
}

/**
 * Deletes token rows whose `expiresAt` has passed. A card the server never got
 * to end would otherwise leak its token row forever; this is the TTL sweep the
 * design doc's "Still open" section flagged.
 * @param {!Object} deps `{db, now, logger}`.
 * @param {{limit: (number|undefined)}=} args
 * @return {!Promise<{pruned: number}>}
 */
function pruneExpiredActivityTokens(deps, args) {
  return _pruneExpired(
      deps,
      deps.db.collectionGroup("liveActivityTokens"),
      (args && args.limit) || PRUNE_MAX,
      "token",
  );
}

/**
 * Deletes card markers whose `expiresAt` has passed — the backstop for a card
 * that was started but whose end push never landed.
 * @param {!Object} deps `{db, now, logger}`.
 * @param {{limit: (number|undefined)}=} args
 * @return {!Promise<{pruned: number}>}
 */
function pruneExpiredCardMarkers(deps, args) {
  return _pruneExpired(
      deps,
      deps.db.collection(CARDS_COLLECTION),
      (args && args.limit) || PRUNE_MAX,
      "card",
  );
}

module.exports = {
  KIND_PUSH_TO_START,
  KIND_UPDATE,
  CARDS_COLLECTION,
  IN_QUERY_MAX,
  PRUNE_MAX,
  TOKEN_TTL_MS,
  CARD_TTL_MS,
  activityTokenExpiry,
  listPushToStartTokens,
  listUpdateTokens,
  deleteActivityToken,
  pruneExpiredActivityTokens,
  writeCardMarker,
  readCardMarker,
  setCardPhase,
  clearCardMarker,
  listCardsDueForOnSite,
  pruneExpiredCardMarkers,
};
