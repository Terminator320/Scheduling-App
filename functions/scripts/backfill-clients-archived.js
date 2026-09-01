#!/usr/bin/env node
// One-off: sets `archived: false` on every /clients doc that lacks the field.
//
// WHY this exists: the clients list query filters
// `where('archived','==',false)`, and Firestore EXCLUDES documents missing
// the field a query filters on. Any client without `archived` is therefore
// invisible in the list while still appearing in search (which scans an
// unfiltered window) — a confusing partial disappearance rather than an
// obvious failure.
//
// RUN THIS BEFORE deploying the filtered query. Reversed, every un-backfilled
// client vanishes from the list until this finishes.
//
// Idempotent: a doc that already has the field is skipped.
//
// Usage:
//   For prod:
//     $env:GOOGLE_APPLICATION_CREDENTIALS =
//       "C:\path\to\prod-service-account.json"
//     node functions/scripts/backfill-clients-archived.js
//
//   For the local emulator:
//     $env:FIRESTORE_EMULATOR_HOST = "localhost:8080"
//     $env:GCLOUD_PROJECT = "schedulingapp-88727"
//     node functions/scripts/backfill-clients-archived.js
//
// Pass --dry-run to report what it would do without writing.
//
// AN UNKNOWN ARGUMENT IS A HARD ERROR — see `_flags.js`. `--dryrun` or
// `--dry_run` would otherwise silently read as false and take this LIVE
// against `/clients`.

const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");
const {bootstrapScript} = require("./_project");
// The batched-write loop, shared so `--dry-run` cannot be forgotten at a
// call site — see `_batch.js`.
const {commitInBatches} = require("./_batch");

/** Bare switches, matched EXACTLY — see `_flags.js`. */
const EXACT_FLAGS = ["--dry-run"];

/**
 * Rejects any argument that is not a flag this script knows. The rejection
 * rule itself lives in the shared `_flags.js` — this wrapper only supplies
 * this script's flag list.
 * @param {!Array<string>} argv Arguments after the node + script paths.
 */
function assertKnownFlags(argv) {
  rejectUnknownFlags(argv, {exact: EXACT_FLAGS});
}

const BATCH_SIZE = 400;

/**
 * True when a client doc still needs the `archived` field written.
 *
 * The test is on the TYPE, not on truthiness: `archived: false` is the
 * overwhelmingly common stored value, so `!data.archived` would rewrite
 * every un-archived client on every run — and `archived: true` must never be
 * reset to false by a re-run. Pure so the one decision this script makes is
 * testable without prod credentials.
 *
 * @param {?Object} data The stored client document.
 * @return {boolean}
 */
function needsArchivedField(data) {
  return typeof (data || {}).archived !== "boolean";
}

/**
 * Patches every client doc missing `archived`.
 * @return {!Promise<void>}
 */
async function main() {
  const argv = process.argv.slice(2);
  const {db, dryRun} = bootstrapScript(argv, {assertFlags: assertKnownFlags});

  const snap = await db.collection("clients").get();

  let patched = 0;
  let skipped = 0;
  const writer = commitInBatches(db, {dryRun, batchSize: BATCH_SIZE});

  for (const doc of snap.docs) {
    if (!needsArchivedField(doc.data())) {
      skipped += 1;
      continue;
    }
    patched += 1;
    await writer.stage(doc.ref, {archived: false});
  }
  await writer.flush();

  console.log(
      `${dryRun ? "[dry-run] " : ""}clients: ${patched} patched, ` +
      `${skipped} already had the field`);
}

// Only run when invoked directly, so `assertKnownFlags` is requirable by
// jest without the script reaching for prod credentials.
if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = {assertKnownFlags, needsArchivedField};
