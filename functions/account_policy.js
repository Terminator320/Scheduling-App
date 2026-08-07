"use strict";

/**
 * @fileoverview Pure account-deletion POLICY — the orchestration behind
 * `deleteAccount`, extracted so it can be tested without the firebase-admin
 * handles wrapped around it.
 *
 * Same split as `maintenance_policy` / `maintenance`: everything here takes
 * its I/O as injected deps (`db`, `auth`, `logger`), so a jest suite can drive
 * the whole sequence with doubles. `account.js` keeps only the callable's
 * guards (auth, payload shape, re-auth staleness, rate limit).
 *
 * This module owns the three rules that make an IRREVERSIBLE deletion safe:
 *   1. the users doc is resolved BEFORE anything destructive runs — once the
 *      Auth user is gone the caller can never retry, so a doc we failed to
 *      find first is a doc stranded forever;
 *   2. Auth is deleted BEFORE the doc, so a partial run can only ever leave
 *      recoverable orphaned data, never a live login with no profile;
 *   3. a doc delete that fails AFTER Auth is gone is logged and reported as
 *      success — the caller's credentials no longer work either way, and
 *      failing here would tell them to retry something they cannot.
 *
 * @module account_policy
 */

/**
 * Finds the caller's `users` doc id, preferring the `usersByUid` bridge and
 * falling back to a direct uid query.
 *
 * Both lookups swallow their errors on purpose: this runs before the
 * destructive steps, and a lookup failure must not block a deletion the user
 * is entitled to. A null result means "delete Auth only", which is the safe
 * outcome — the orphaned doc is recoverable, a blocked deletion is not.
 *
 * @param {!Object} db Firestore instance.
 * @param {string} uid Firebase Auth uid.
 * @param {!Object} logger Logger with `warn`.
 * @return {!Promise<?string>} The users doc id, or null.
 */
async function resolveUserDocId(db, uid, logger) {
  const bridgeSnap = await db
      .collection("usersByUid")
      .doc(uid)
      .get()
      .catch((err) => {
        logger.warn("deleteAccount: bridge read failed", {
          uid,
          err: err.message,
        });
        return null;
      });

  const fromBridge = bridgeSnap && bridgeSnap.exists ?
    bridgeSnap.data().docId :
    null;
  if (fromBridge) return fromBridge;

  // No bridge row — fall back to a direct uid lookup so we don't strand the
  // profile doc.
  logger.warn("deleteAccount: no bridge for uid; querying users by uid", {uid});
  try {
    const q = await db
        .collection("users")
        .where("uid", "==", uid)
        .limit(1)
        .get();
    if (!q.empty) return q.docs[0].id;
  } catch (err) {
    logger.warn("deleteAccount: uid-fallback lookup failed", {
      uid,
      err: err.message,
    });
  }
  return null;
}

/**
 * Deletes the caller's Auth user and `users` doc, in that order.
 *
 * @param {{db: !Object, auth: !Object, logger: !Object,
 *   limiter: {refund: !Function}}} deps Injected I/O. `limiter.refund` gives
 *   back the rate-limit slot when the failure was ours, not the caller's.
 * @param {string} uid Firebase Auth uid of the caller.
 * @return {!Promise<{deleted: boolean, docId: ?string}>}
 * @throws {*} Whatever `onAuthFailure` builds, when the Auth delete fails.
 */
async function runAccountDeletion(deps, uid) {
  const {db, auth, logger, limiter, onAuthFailure} = deps;

  const docId = await resolveUserDocId(db, uid, logger);

  // Auth FIRST. The other order risks a live login with no profile doc; this
  // order can only leave recoverable orphaned data.
  try {
    await auth.deleteUser(uid);
  } catch (err) {
    logger.error("deleteAccount: auth delete failed", {uid, err: err.message});
    // Best-effort refund — this was a server-side failure, so legitimate
    // retries shouldn't be locked out by our own errors.
    if (limiter) await limiter.refund();
    throw onAuthFailure();
  }

  if (docId) {
    try {
      // recursiveDelete removes the users doc and all its subcollections
      // (fcmTokens, presence). A plain doc delete would orphan them, leaving a
      // deleted account that still receives pushes.
      await db.recursiveDelete(db.collection("users").doc(docId));
    } catch (err) {
      // The Auth user is already gone, so log for cleanup but report success —
      // the caller's credentials no longer work anyway.
      logger.error("deleteAccount: users doc delete failed after auth " +
          "delete — orphaned users doc needs cleanup", {
        uid,
        docId,
        err: err.message,
      });
    }
  }

  logger.info("deleteAccount: user account deleted", {uid, docId});
  return {deleted: true, docId};
}

module.exports = {
  resolveUserDocId,
  runAccountDeletion,
};
