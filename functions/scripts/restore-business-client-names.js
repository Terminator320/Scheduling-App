#!/usr/bin/env node
// One-off: puts the name back on the businesses that
// `backfill-client-name-with-phone.js` renamed to their phone number, and
// types them `commercial` so nothing renames them again.
//
// WHY: that backfill skips anything `looksLikeBusinessName` recognises, but
// the Wave import sets no `type`, so a company is recognisable only by its
// NAME — a digit, or a company token. "House of Jazz", "La scala", "Yokohama"
// carry neither, so they were renamed like people. On live Wave invoices.
// `docs/audits/audit-renamed-client-names.js` is what found them.
//
// THE MAPPING IS HARDCODED AND DELIBERATELY NOT DERIVED. It cannot be: for
// most of these the business name survives in `firstName`/`lastName`, but for
// Yokohama those halves hold its CONTACT PERSON (Mathieu Gaudreau), so
// restoring from the halves would put a person's name on the company's
// invoices — the same class of mistake this is cleaning up. Every name below
// was read off the audit output by a human and is reproduced verbatim.
//
// SETTING `type` IS THE DURABLE HALF. `name` alone would be undone the next
// time anyone edits the client, because `composeStored` re-derives it; a
// `commercial` doc is `isBusiness` on every path and is never renamed again.
//
// Idempotent, and safe to re-run: a doc whose name is no longer a bare phone
// number has already been fixed and is skipped, so this cannot clobber a
// hand-repair or a later edit.
//
// Usage:
//   $env:GOOGLE_CLOUD_PROJECT = "schedulingapp-88727"
//   node functions/scripts/restore-business-client-names.js --dry-run
//   node functions/scripts/restore-business-client-names.js
//
// Each write fires `waveUpsertCustomer`, which drains inline — that is the
// point, it is what puts the name back in Wave. Eleven docs, so the 60/min
// ceiling is not a concern here.

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const {digitsOf} = require("../client_name_utils");
// The rejection rule comes from the shared `_flags.js`, like every other
// script here — the same "a typo'd --dry-run must not go live" guard, with
// this script's own flag list supplied by the thin wrapper below. It used to
// import the WRAPPER from a sibling script, so retiring that script would
// have silently taken this one's flag guard with it. The target banner is
// shared too — see `_project.js`.
const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");
const {printTargetBanner} = require("./_project");

/** Bare switches, matched EXACTLY - see `_flags.js`. */
const EXACT_FLAGS = ["--dry-run"];

/**
 * Rejects any argument that is not a flag this script knows. The rejection
 * rule itself lives in the shared `_flags.js`; this wrapper only supplies
 * THIS script's flag list.
 * @param {!Array<string>} argv Arguments after the node + script paths.
 */
function assertKnownFlags(argv) {
  rejectUnknownFlags(argv, {exact: EXACT_FLAGS});
}

/**
 * Client doc id -> the business name to restore.
 *
 * Read off the 2026-08-14 run of `audit-renamed-client-names.js`, and
 * confirmed by the owner doc by doc — the audit can only say "this had no
 * first/last behind it", never whether the thing is a company.
 *
 * ONE entry the audit surfaced is NOT here: "Elmo Street"
 * (`6GKdxhkzWH8HWYjwrolZ`), which is not clearly a company. Leaving a person
 * named by their phone number in Wave is recoverable, while renaming a
 * person's customer record to something they are not is confusing on an
 * invoice.
 * @type {!Object<string, string>}
 */
const RESTORE = {
  "3YCCKXnipIwnfZQcR9z6": "Yokohama",
  "NMbGQgwv2b8EW0C7XR0E": "Dr Peter Liarakos",
  "afVN59t0X3xbdE5ks2NB": "House of Jazz",
  "HeN9Ybh4t3ysRP5SKgx7": "La scala",
  "zJfcpmciUVXmkgsHsE8Q": "La belle province vimont",
  "vYHHUmRkgCYMBhZ9b8ta": "B.J pizza",
  "giXgLpJIUVes29KmGN9u": "Sako Electric",
  "mWDo6BT0KjJ3CrbJTm6F": "Jemac management service",
  "TXgh6pWpoiyNH2eBkjU0": "Parcours Rénovation",
  "SnSVSycIloD7F8h03fcF": "Bellepros Boisbriand",
  "oU8V1KhGMggBUew9t08s": "GC Milonopoulos",
  "tYyHi4I4pJ5hSbu9ZAsL": "Rixton",
};

/**
 * The patch for one client, or null when it must be left alone.
 *
 * The guard is what makes this re-runnable: it only acts on a doc whose name
 * is still nothing but its own stored number, which is exactly the state the
 * rename left. A doc already carrying a real name has been repaired — by an
 * earlier run of this script, by hand, or by an edit — and must not be
 * overwritten with a value read off a report that is by then out of date.
 *
 * @param {!Object} data The stored client document.
 * @param {string} restored The business name to put back.
 * @return {?{name: string, type: string}} A field patch, or null to skip.
 */
function patchFor(data, restored) {
  const name = String(data.name || "").trim();
  const nameDigits = digitsOf(name);
  if (!nameDigits || /[a-z]/i.test(name)) return null;

  const isOwnNumber = nameDigits === digitsOf(data.phone) ||
    nameDigits === digitsOf(data.mobile);
  if (!isOwnNumber) return null;

  return {name: restored, type: "commercial"};
}

/**
 * Restores each named business.
 * @return {!Promise<void>}
 */
async function main() {
  const argv = process.argv.slice(2);
  assertKnownFlags(argv);
  const dryRun = argv.includes("--dry-run");

  const app = initializeApp({credential: applicationDefault()});
  const db = getFirestore();

  printTargetBanner(app, {dryRun});

  let restored = 0;
  const skipped = [];
  const missing = [];

  for (const [id, name] of Object.entries(RESTORE)) {
    const ref = db.collection("clients").doc(id);
    const doc = await ref.get();
    if (!doc.exists) {
      missing.push(id);
      continue;
    }

    const data = doc.data() || {};
    const patch = patchFor(data, name);
    if (!patch) {
      skipped.push({id, name: String(data.name || "").trim()});
      continue;
    }

    console.log(`  ${id}`);
    console.log(`    "${data.name}" -> "${patch.name}"  (type: commercial)`);
    restored += 1;
    if (!dryRun) await ref.update(patch);
  }

  const tag = dryRun ? "[dry-run] " : "";
  console.log(`\n${tag}${restored} business name(s) restored.`);

  if (skipped.length > 0) {
    console.log(
        `\n${tag}${skipped.length} already carry a real name and were left ` +
        "alone — repaired earlier, or edited since the audit ran:");
    for (const s of skipped) console.log(`  ${s.id}  "${s.name}"`);
  }

  if (missing.length > 0) {
    console.log(`\n${tag}${missing.length} doc id(s) no longer exist:`);
    for (const id of missing) console.log(`  ${id}`);
  }

  if (!dryRun && restored > 0) {
    console.log(
        `\n${restored} Wave customer pushes are draining — that is what puts ` +
        "these names back in Wave.");
  }
}

// Only run when invoked directly, so the rules are requirable by jest without
// the script reaching for prod credentials.
if (require.main === module) {
  main().catch((err) => {
    if (/Unable to detect a Project Id/i.test(String(err && err.message))) {
      console.error(
          "No project id in this shell. Credentials were found, but not a " +
          "project.\n\n" +
          "  PowerShell:  $env:GOOGLE_CLOUD_PROJECT = \"schedulingapp-88727\"");
      process.exit(1);
    }
    console.error(err);
    process.exit(1);
  });
}

module.exports = {assertKnownFlags, patchFor, RESTORE};
