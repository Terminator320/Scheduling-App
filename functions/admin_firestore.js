"use strict";

// The lazy `firebase-admin/firestore` require, shared.
//
// Four modules carried a byte-identical private copy of this, each with its own
// wording of the same reason, and they had already started to drift — one
// JSDoc promised `Timestamp` and the others did not, so a reader could not tell
// whether that field was safe to use from the others.
//
// The RULE it encodes is the one `functions/CLAUDE.md` states: a module that
// touches admin at LOAD cannot be `require()`d from a jest test. Resolving it
// inside the call keeps every one of these modules unit-testable with an
// injected `db`, and a test that injects one never reaches this at all.

/**
 * Resolves `firebase-admin/firestore` at call time, not at module load.
 * @return {{getFirestore: !Function, FieldValue: !Object, Timestamp: !Object}}
 */
function adminFirestore() {
  // eslint-disable-next-line global-require
  return require("firebase-admin/firestore");
}

module.exports = {
  adminFirestore,
};
