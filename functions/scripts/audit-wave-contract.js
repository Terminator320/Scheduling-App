#!/usr/bin/env node
// One-off, READ-ONLY: replays the Wave customer contract over every client and
// reports what it would refuse.
//
// WHY: every Wave incident on record was a value Wave refused, discovered at
// push time, where the rejection is non-retryable and therefore permanent.
// This is the check that moves that discovery before the deploy. Run it after
// any change to the contract, the mappers, or ClientNamePolicy.
//
// It reports BOTH severities, and the split is the point:
//   BLOCKING  — Wave would refuse it; the push dead-letters permanently.
//   ADVISORY  — Wave accepts it, but the data is wrong (a phone nobody can
//               dial). Syncs fine; still worth fixing.
// Reporting only the blocked clients would hide exactly the case this audit
// first turned up on 2026-08-30.
//
// It writes NOTHING. Safe against production at any time.
//
// Usage:
//   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/prod-service-account.json
//   node functions/scripts/audit-wave-contract.js
//   node functions/scripts/audit-wave-contract.js --verbose
//
//   --verbose  lists every affected client id and its problems, not just the
//              per-code tally.

"use strict";

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");
const {printTargetBanner} = require("./_project");
const {buildCustomerPayload} = require("../wave/customer_contract");

/** Bare switches, matched EXACTLY - see `_flags.js`. */
const EXACT_FLAGS = ["--verbose"];

/**
 * Rejects any argument this script does not recognize. The rule itself lives
 * in the shared `_flags.js`; this wrapper only supplies THIS script's list.
 * @param {!Array<string>} argv Arguments after the node + script paths.
 */
function assertKnownFlags(argv) {
  rejectUnknownFlags(argv, {exact: EXACT_FLAGS});
}

/** Read-only, so this is a round-trip dial rather than a write bound. */
const PAGE_SIZE = 500;

/**
 * Replays the contract over every client document.
 * @param {!Object} db The Firestore handle.
 * @return {!Promise<{scanned: number, refused: number, flagged: number,
 *   byCode: !Object<string, number>, offenders: !Array<!Object>}>} The tally.
 *   `refused` counts clients with a BLOCKING problem (the push would
 *   dead-letter); `flagged` also counts advisory-only ones, which sync fine
 *   but carry data worth fixing.
 */
async function audit(db) {
  const byCode = {};
  const offenders = [];
  let scanned = 0;
  let refused = 0;
  let cursor = null;

  // Paged on `__name__` so this needs no index and no orderBy field, which
  // matters: an orderBy makes Firestore EXCLUDE any doc missing that field,
  // and a legacy doc missing one is exactly the shape most likely to fail.
  for (;;) {
    let query = db.collection("clients").orderBy("__name__").limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const snap = await query.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      scanned += 1;
      // NOT gated on `ok`: an ADVISORY problem rides along on a perfectly good
      // result, and reporting only the blocked clients would hide the case
      // this audit first turned up.
      const {ok, problems} = buildCustomerPayload(doc.data() || {});
      const found = Array.isArray(problems) ? problems : [];
      if (found.length === 0) continue;
      if (!ok) refused += 1;
      offenders.push({id: doc.id, blocked: !ok, problems: found});
      for (const problem of found) {
        const key = `${problem.severity}  ${problem.field}:${problem.code}`;
        byCode[key] = (byCode[key] || 0) + 1;
      }
    }

    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break;
  }

  return {scanned, refused, flagged: offenders.length, byCode, offenders};
}

/**
 * Entry point.
 * @return {!Promise<void>}
 */
async function main() {
  assertKnownFlags(process.argv.slice(2));
  const verbose = process.argv.includes("--verbose");

  const app = initializeApp({credential: applicationDefault()});
  // `dryRun: false` like the other read-only scripts: this NEVER writes, so
  // the banner must not carry a "[dry-run]" prefix implying a live run exists
  // behind it. The second argument is required — omitting it throws before the
  // first read.
  printTargetBanner(app, {dryRun: false});
  const db = getFirestore();

  const {scanned, refused, flagged, byCode, offenders} = await audit(db);

  console.log(`\nScanned ${scanned} clients.`);
  console.log(`${refused} would be REFUSED by Wave (blocking).`);
  console.log(`${flagged - refused} sync fine but carry advisory problems.\n`);

  const keys = Object.keys(byCode).sort();
  if (keys.length === 0) {
    console.log("  No client fails the contract.");
  } else {
    for (const key of keys) console.log(`  ${key}: ${byCode[key]}`);
  }

  if (verbose && offenders.length > 0) {
    console.log("\nAffected clients:");
    for (const {id, blocked, problems} of offenders) {
      const summary = problems.map((p) => `${p.field}:${p.code}`).join(", ");
      console.log(`  ${blocked ? "BLOCKED " : "advisory"}  ${id}  ${summary}`);
    }
  }

  await app.delete();
}

main().catch((err) => {
  console.error(err && err.message ? err.message : err);
  process.exit(1);
});
