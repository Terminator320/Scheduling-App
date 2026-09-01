"use strict";

/**
 * @fileoverview Firestore error shapes the at-most-once ledgers depend on.
 *
 * One owner, because both users guard a `create()`-based ledger and a
 * divergence is invisible: `notification_policy.js` uses it to decide a push
 * was already delivered, and `recount_claim.js` to decide a recount is already
 * claimed. Fix one and not the other and you get a DUPLICATE push, or a
 * SUPPRESSED recount, with nothing failing anywhere.
 *
 * The 2026-08-28 audit recorded this pair as de-duplicated; it was not. Two
 * copies is under the usual 3+ bar, which is exactly why it needs an owner
 * rather than another note — so a third cannot appear.
 *
 * Pure: no firebase-admin import, so a policy module that takes an injected
 * `db` can require it without becoming untestable.
 * @module firestore_errors
 */

/**
 * Firestore's gRPC ALREADY_EXISTS status, thrown by `create()` on a live doc.
 */
const ALREADY_EXISTS = 6;

/**
 * True for the error `create()` throws when the document already exists.
 *
 * Both spellings are accepted deliberately: the gRPC path reports the numeric
 * status, the REST/emulator path the string.
 * @param {*} err
 * @return {boolean}
 */
function isAlreadyExists(err) {
  if (!err) return false;
  return err.code === ALREADY_EXISTS || err.code === "already-exists";
}

module.exports = {ALREADY_EXISTS, isAlreadyExists};
