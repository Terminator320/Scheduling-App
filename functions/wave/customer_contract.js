"use strict";

/**
 * @fileoverview The single owner of "will Wave accept this client?".
 *
 * Every Wave incident on record has one root: the app sent a value Wave
 * refuses, found out at push time, and had no way back. `WaveValidationError`
 * is non-retryable by design, so "Retry failed" re-sends the identical payload
 * into the identical refusal. Wave was being used as the validator and its
 * "no" was permanent.
 *
 * This module moves that verdict to the boundary. It answers with either a
 * payload or a structured list of PROBLEMS naming the client-doc field at
 * fault, so a failure becomes something an admin can fix rather than a counter
 * in Settings.
 *
 * Pure and synchronous — no Firebase, no network. In PHASE 1 it is additive:
 * `wave/customers.js` still builds its own payload and nothing is blocked. It
 * becomes the only producer in Phase 2.
 *
 * Design: `docs/plans/2026-08-30-wave-validated-contract-design.md`.
 * @module wave/customer_contract
 */

const {toWaveCustomerInput, mappedFieldsHash} = require("./mappers");

/**
 * @typedef {{field: string, code: string, detail: ?Object}} WaveProblem
 *   `field` names the CLIENT DOC field an admin edits, never the Wave payload
 *   path — the UI points at an input with it.
 */

/**
 * Builds the Wave customer payload for a client, or says why it cannot.
 * @param {!Object} clientFields Firestore `clients` document fields.
 * @return {{ok: boolean, payload: (!Object|undefined),
 *   hash: (string|undefined), problems: (!Array<WaveProblem>|undefined)}}
 */
function buildCustomerPayload(clientFields) {
  const payload = toWaveCustomerInput(clientFields);
  const problems = [];

  if (!payload.name || !payload.name.trim()) {
    problems.push({field: "name", code: "EMPTY", detail: null});
  }

  if (problems.length > 0) return {ok: false, problems};
  return {ok: true, payload, hash: mappedFieldsHash(clientFields)};
}

module.exports = {
  buildCustomerPayload,
};
