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
 * Wave's own length caps, as PAYLOAD paths paired with the client-doc field an
 * admin would edit to fix them.
 *
 * The values mirror `IMPORT_FIELD_CAPS` (`wave/mappers.js`), which has always
 * applied them on the IMPORT direction only — `capped()` is called solely by
 * `fromWaveCustomer`. The push path capped nothing, which is what left a
 * 201–225 name and a 501–533 address able to dead-letter permanently.
 *
 * `provinceCode`/`countryCode` are absent deliberately: they are GraphQL
 * ENUMS, already membership-tested by `toProvinceCode`/`toCountryCode`, so a
 * length is meaningless for them.
 * @const {!Array<{path: !Array<string>, field: string, cap: number}>}
 */
const PAYLOAD_CAPS = [
  {path: ["name"], field: "name", cap: 200},
  {path: ["firstName"], field: "firstName", cap: 200},
  {path: ["lastName"], field: "lastName", cap: 200},
  {path: ["email"], field: "email", cap: 320},
  {path: ["phone"], field: "phone", cap: 32},
  {path: ["mobile"], field: "mobile", cap: 32},
  {path: ["address", "addressLine1"], field: "address", cap: 500},
  {path: ["address", "addressLine2"], field: "addressLine2", cap: 500},
  {path: ["address", "city"], field: "city", cap: 128},
  {path: ["address", "postalCode"], field: "postalCode", cap: 32},
];

/**
 * Reads a nested payload value, tolerating an absent branch.
 * @param {!Object} payload The Wave customer input.
 * @param {!Array<string>} path Property names, outermost first.
 * @return {*} The value, or undefined.
 */
function readPath(payload, path) {
  let cursor = payload;
  for (const key of path) {
    if (!cursor || typeof cursor !== "object") return undefined;
    cursor = cursor[key];
  }
  return cursor;
}

/**
 * Every field whose composed value exceeds Wave's cap.
 * @param {!Object} payload The Wave customer input.
 * @return {!Array<WaveProblem>}
 */
function overLongProblems(payload) {
  const problems = [];
  for (const rule of PAYLOAD_CAPS) {
    const value = readPath(payload, rule.path);
    if (typeof value !== "string" || value.length <= rule.cap) continue;
    problems.push({
      field: rule.field,
      code: "TOO_LONG",
      detail: {length: value.length, cap: rule.cap},
    });
  }
  return problems;
}

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
  problems.push(...overLongProblems(payload));

  if (problems.length > 0) return {ok: false, problems};
  return {ok: true, payload, hash: mappedFieldsHash(clientFields)};
}

module.exports = {
  buildCustomerPayload,
};
