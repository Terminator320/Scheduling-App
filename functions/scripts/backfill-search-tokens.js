#!/usr/bin/env node
// One-off: adds `searchTokens` to clients and `historySearchScopes` to
// appointments so the mobile app can use indexed callables instead of capped
// client-side scans.
//
// Usage:
//   For prod:
//     export GOOGLE_APPLICATION_CREDENTIALS=/path/to/prod-service-account.json
//     node functions/scripts/backfill-search-tokens.js --dry-run
//     node functions/scripts/backfill-search-tokens.js
//
//   For the local emulator:
//     export FIRESTORE_EMULATOR_HOST=localhost:8080
//     export GCLOUD_PROJECT=schedulingapp-88727
//     node functions/scripts/backfill-search-tokens.js
//
//   Options:
//     --dry-run   report what would change, write nothing

const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");
const {commitInBatches} = require("./_batch");
const {bootstrapScript} = require("./_project");
const {
  appointmentHistoryScopes,
  clientSearchTokens,
} = require("../search_tokens");

const BATCH_SIZE = 400;
const EXACT_FLAGS = ["--dry-run"];

/**
 * Rejects any flag this script does not know.
 * @param {!Array<string>} argv Arguments after node + script paths.
 */
function assertKnownFlags(argv) {
  rejectUnknownFlags(argv, {exact: EXACT_FLAGS});
}

/**
 * True when two arrays carry the same primitive values in the same order.
 * @param {!Array<*>} a First value.
 * @param {!Array<*>} b Second value.
 * @return {boolean}
 */
function sameArray(a, b) {
  if (a.length !== b.length) return false;
  return a.every((value, index) => value === b[index]);
}

/**
 * Returns the token patch for one document, or null when no change is needed.
 * @param {!Object} data Stored document data.
 * @param {!Array<string>} next Expected tokens.
 * @param {string} field Field to patch.
 * @return {?Object}
 */
function patchFor(data, next, field) {
  const current = Array.isArray(data[field]) ? data[field] : [];
  if (sameArray(current, next)) return null;
  return {[field]: next};
}

/**
 * Backfills one collection.
 * @param {!Object} db Firestore instance.
 * @param {string} collection Collection name.
 * @param {string} field Token field.
 * @param {!Function} tokensFor Token builder.
 * @param {boolean} dryRun Whether to write.
 * @return {!Promise<{scanned: number, patched: number}>}
 */
async function backfillCollection(db, collection, field, tokensFor, dryRun) {
  const snap = await db.collection(collection).get();
  const writer = commitInBatches(db, {dryRun, batchSize: BATCH_SIZE});
  let patched = 0;
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const patch = patchFor(data, tokensFor(data), field);
    if (!patch) continue;
    patched += 1;
    await writer.stage(doc.ref, patch);
  }
  await writer.flush();
  return {scanned: snap.size, patched};
}

/**
 * Runs the backfill.
 * @return {!Promise<void>}
 */
async function main() {
  const argv = process.argv.slice(2);
  const {db, dryRun} = bootstrapScript(argv, {assertFlags: assertKnownFlags});
  const tag = dryRun ? "[dry-run] " : "";

  const clients = await backfillCollection(
      db,
      "clients",
      "searchTokens",
      clientSearchTokens,
      dryRun,
  );
  const appointments = await backfillCollection(
      db,
      "appointments",
      "historySearchScopes",
      appointmentHistoryScopes,
      dryRun,
  );

  console.log(
      `${tag}clients: ${clients.scanned} scanned, ` +
      `${clients.patched} token rows patched`);
  console.log(
      `${tag}appointments: ${appointments.scanned} scanned, ` +
      `${appointments.patched} token rows patched`);
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = {
  assertKnownFlags,
  patchFor,
  sameArray,
};
