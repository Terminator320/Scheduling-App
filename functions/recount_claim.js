"use strict";

/**
 * @fileoverview The claim ledger that collapses one batch's N recount triggers
 * into one aggregate write.
 *
 * ONE owner, because the RELEASE-BEFORE-AGGREGATE ordering is the whole design
 * and is silent when wrong. Two counters need it — appointment `pictureCount`
 * (a photo batch writes N image docs under one parent) and client `jobCount`
 * (a run or repeat series writes up to 16 appointments carrying one clientId)
 * — and a second hand-written copy is a second chance to get that order, the
 * staleness takeover, or the fail-open backwards.
 *
 * Every body takes an injected `db`, in the same shape as
 * `maintenance_policy.js`, so the protocol is testable without emulator
 * credentials.
 * @module recount_claim
 */

/** Firestore's already-exists code, thrown by `create()` on a live claim. */
const ALREADY_EXISTS = 6;

/**
 * A claim older than this is presumed abandoned (an invocation killed between
 * claiming and releasing) and is taken over. Deliberately a handful of
 * seconds: a claim that outlives its usefulness suppresses the recount that
 * would have corrected the counter.
 */
const CLAIM_STALE_MS = 15 * 1000;

/**
 * Absolute lifetime stamped on `expiresAt` for the Firestore TTL policy.
 * Housekeeping only — a claim is inert after `CLAIM_STALE_MS` whether or not
 * the policy has swept it, and the normal path deletes it explicitly.
 */
const CLAIM_TTL_MS = 5 * 60 * 1000;

/**
 * True for the error `create()` throws when the document already exists.
 * @param {*} err
 * @return {boolean}
 */
function isAlreadyExists(err) {
  if (!err) return false;
  return err.code === ALREADY_EXISTS || err.code === "already-exists";
}

/**
 * The body every claim is written with.
 * @param {!Date} nowDate
 * @return {{claimedAt: !Date, expiresAt: !Date}}
 */
function claimBody(nowDate) {
  return {
    claimedAt: nowDate,
    expiresAt: new Date(nowDate.getTime() + CLAIM_TTL_MS),
  };
}

/**
 * Claims `key` in `collection`.
 *
 * FAILS OPEN: any ledger error returns true, so a broken claim collection
 * degrades to the un-debounced behaviour rather than silently stopping every
 * recount.
 * @param {string} collection Claim ledger collection.
 * @param {string} key Document id to claim.
 * @param {!Object} deps `{db, logger, now}`.
 * @return {!Promise<boolean>} True when this invocation owns the recount.
 */
async function claimRecount(collection, key, deps) {
  const {db, logger: log, now} = deps;
  const nowDate = now || new Date();
  // Inside the try: `.doc()` throws SYNCHRONOUSLY on a reserved id ("."/".."),
  // and the fail-open contract above has to cover that too — otherwise the one
  // error that precedes the guard is the one it doesn't catch.
  let ref;
  try {
    ref = db.collection(collection).doc(key);
    await ref.create(claimBody(nowDate));
    return true;
  } catch (err) {
    if (!isAlreadyExists(err)) {
      if (log) log.warn("recount claim failed; recounting anyway", {err});
      return true;
    }
  }
  // A claim exists. Take over one older than the window so an invocation
  // killed between claiming and releasing can't suppress recounts until the
  // TTL policy gets round to it — and so a genuinely later write always
  // recounts.
  try {
    const snap = await ref.get();
    const claimed = snap.get("claimedAt");
    const claimedMs = claimed && typeof claimed.toMillis === "function" ?
      claimed.toMillis() :
      (claimed instanceof Date ? claimed.getTime() : null);
    if (claimedMs != null &&
        nowDate.getTime() - claimedMs < CLAIM_STALE_MS) {
      return false;
    }
    await ref.set(claimBody(nowDate));
    return true;
  } catch (err) {
    if (log) {
      log.warn("recount claim takeover failed; recounting anyway", {err});
    }
    return true;
  }
}

/**
 * Releases this invocation's claim. Best-effort: a failed delete leaves a
 * claim the staleness takeover above already treats as inert.
 * @param {string} collection Claim ledger collection.
 * @param {string} key Document id to release.
 * @param {!Object} deps `{db, logger}`.
 * @return {!Promise<void>}
 */
async function releaseRecount(collection, key, deps) {
  const {db, logger: log} = deps;
  try {
    await db.collection(collection).doc(key).delete();
  } catch (err) {
    if (log) log.warn("recount claim release failed", {err});
  }
}

/**
 * Claims `key`, settles to absorb the rest of the batch, releases, then runs
 * `recount`.
 *
 * The ORDER is the design. The claim is released BEFORE the aggregate so a
 * recount that throws is free to re-claim on the trigger's retry rather than
 * suppressing itself, and so a sibling arriving after the settle window
 * recounts again — which is exactly the old, correct behaviour. Correctness
 * never depends on `settleMs`; it only decides how much of a batch one
 * recount swallows.
 * @param {string} collection Claim ledger collection.
 * @param {string} key Document id to debounce on.
 * @param {function(): !Promise<*>} recount The aggregate to run once.
 * @param {!Object} deps `{db, logger, now, sleep, settleMs}`.
 * @return {!Promise<{skipped: boolean, result: *}>}
 */
async function debounceRecount(collection, key, recount, deps) {
  const mine = await claimRecount(collection, key, deps);
  if (!mine) return {skipped: true, result: null};
  const sleep = deps.sleep || ((ms) => new Promise((r) => setTimeout(r, ms)));
  const settleMs = deps.settleMs == null ? 2000 : deps.settleMs;
  await sleep(settleMs);
  await releaseRecount(collection, key, deps);
  const result = await recount();
  return {skipped: false, result};
}

module.exports = {
  claimRecount,
  releaseRecount,
  debounceRecount,
  isAlreadyExists,
  claimBody,
  CLAIM_STALE_MS,
  CLAIM_TTL_MS,
  ALREADY_EXISTS,
};
