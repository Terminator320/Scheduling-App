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

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");

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
 * Patches every client doc missing `archived`.
 * @return {!Promise<void>}
 */
async function main() {
  const argv = process.argv.slice(2);
  assertKnownFlags(argv);
  const dryRun = argv.includes("--dry-run");

  initializeApp({credential: applicationDefault()});
  const db = getFirestore();
  const snap = await db.collection("clients").get();

  let patched = 0;
  let skipped = 0;
  let batch = db.batch();
  let pending = 0;

  for (const doc of snap.docs) {
    if (typeof doc.data().archived === "boolean") {
      skipped += 1;
      continue;
    }
    patched += 1;
    if (dryRun) continue;
    batch.update(doc.ref, {archived: false});
    pending += 1;
    if (pending >= BATCH_SIZE) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (!dryRun && pending > 0) await batch.commit();

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

module.exports = {assertKnownFlags};
