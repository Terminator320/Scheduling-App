"use strict";

/**
 * @fileoverview Firestore error shapes the at-most-once ledgers depend on.
 * @module firestore_errors
 */

/** Firestore's gRPC ALREADY_EXISTS, thrown by `create()` on a live doc. */
const ALREADY_EXISTS = 6;

/**
 * True for the error `create()` throws when the document already exists.
 * @param {*} err
 * @return {boolean}
 */
function isAlreadyExists(err) {
  if (!err) return false;
  return err.code === ALREADY_EXISTS || err.code === "already-exists";
}

module.exports = {ALREADY_EXISTS, isAlreadyExists};
