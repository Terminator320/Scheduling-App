"use strict";

/**
 * @fileoverview What a job is CALLED, wherever it is spoken to a person.
 *
 * One owner, because the contract is a cross-surface one and was stated only
 * in prose: `live_activity_utils.js` carried the sentence "the card and the
 * `leaveNow` push beside it must not call the same job two different things"
 * while holding its own byte-identical copy of the rule. A rule stated in two
 * files has no owner — the next edit lands in one of them, both keep passing,
 * and a technician gets a Lock Screen card and a push naming the same visit
 * differently.
 *
 * Pure: no Firestore, no messaging, no locale data. The localized "Client"
 * placeholder is passed IN, because the caller is the one that knows the
 * recipient's language.
 * @module job_naming
 */

/**
 * Who a card or push names the job after: the client, or — for a personal job,
 * which has none — its title. Only a record with neither falls back to
 * [generic].
 * @param {!Object} c Message context, content-state input, or appointment
 *   record. Anything carrying `clientName` / `title`.
 * @param {string} generic Localized "Client" placeholder.
 * @return {string}
 */
function whoFor(c, generic) {
  return (c.clientName || "").trim() || (c.title || "").trim() || generic;
}

module.exports = {whoFor};
