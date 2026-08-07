#!/usr/bin/env node
// One-off: sets `archived: false` on every /clients doc that lacks the field.
//
// WHY this exists: the clients list query filters `where('archived','==',false)`,
// and Firestore EXCLUDES documents missing the field a query filters on. Any
// client without `archived` is therefore invisible in the list while still
// appearing in search (which scans an unfiltered window) — a confusing partial
// disappearance rather than an obvious failure.
//
// RUN THIS BEFORE deploying the filtered query. Reversed, every un-backfilled
// client vanishes from the list until this finishes.
//
// Idempotent: a doc that already has the field is skipped.
//
// Usage:
//   For prod:
//     $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\prod-service-account.json"
//     node functions/scripts/backfill-clients-archived.js
//
//   For the local emulator:
//     $env:FIRESTORE_EMULATOR_HOST = "localhost:8080"
//     $env:GCLOUD_PROJECT = "schedulingapp-88727"
//     node functions/scripts/backfill-clients-archived.js
//
// Pass --dry-run to report what it would do without writing.

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const DRY_RUN = process.argv.includes("--dry-run");
const BATCH_SIZE = 400;

/**
 * Patches every client doc missing `archived`.
 * @return {!Promise<void>}
 */
async function main() {
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
    if (DRY_RUN) continue;
    batch.update(doc.ref, {archived: false});
    pending += 1;
    if (pending >= BATCH_SIZE) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (!DRY_RUN && pending > 0) await batch.commit();

  console.log(
      `${DRY_RUN ? "[dry-run] " : ""}clients: ${patched} patched, ` +
      `${skipped} already had the field`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
