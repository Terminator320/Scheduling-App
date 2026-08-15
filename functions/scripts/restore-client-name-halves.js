#!/usr/bin/env node
// One-off: puts a PERSON's name back into `firstName`/`lastName` on the clients
// that `backfill-client-name-with-phone.js` renamed to their phone number and
// left with no halves to fall back on.
//
// WHY: those clients render as a bare phone number on every appointment card,
// in search, and on their own detail page. `ClientNamePolicy.displayFor` shows
// a person's first/last halves and falls through to the stored `name` when
// there are none — and after the 2026-08-14 rename that `name` IS the number.
//
// THE NAME REALLY WAS LOST, and the script that lost it said otherwise. Its
// comment reads "Nothing is lost that was not already missing", which is true
// for a client whose halves were populated and false for exactly the docs this
// one repairs. `backfill-client-phone-from-name.js` (2026-08-08) deliberately
// left `name` alone on a doc with NEITHER half — "a doc with neither half
// keeps its name and still gets its phone" — so those docs carried the only
// copy of the person's name in `name`, and 2026-08-14 overwrote it in place.
//
// THE OLD NAME IS RECOVERABLE FROM SETTLED APPOINTMENTS, and that is the only
// source left. `propagateClientEdits` only rewrites appointments that still
// have work left (`hasWorkLeft`, endTime >= now), so every visit that had
// already ended still carries the `clientName` the client had before the
// rename. Wave cannot help — the rename pushed the number into Wave's customer
// name, and Wave's own first/last fields are populated FROM the halves this is
// trying to fill. Firestore keeps no history.
//
// That is the same evidence `docs/audits/audit-renamed-client-names.js`
// reports; this script is the write half of that audit, and the two are kept
// deliberately in step on how they find it — they had already drifted on which
// remembered names count (see that file's matching comment), which is the one
// way the operator could read one rule's report and run another rule's repair.
//
// IT WRITES THE HALVES ONLY — NEVER `name`. That is the whole design:
//   - `name` is Wave's customer name, and the owner's rule is that a person is
//     identified there by their number. Restoring `name` would undo 2026-08-14
//     on live invoices, which is what `backfill-client-phone-from-name.js` did
//     wrong in the other direction.
//   - `displayFor` prefers the halves for a person, so filling them is enough
//     to fix every in-app surface without touching Wave's identity for the
//     customer at all.
//   - Wave's own `firstName`/`lastName` fields are in `toWaveCustomerInput`, so
//     the push this triggers ADDS the person's name to their Wave record
//     beside the number. That is a gain, not a rename.
//
// THE RULE, per doc — every one of these must hold or the doc is skipped:
//   1. `name` is nothing but this client's own stored number (digit-compared,
//      since the collection holds both "(514) 555-1234" and "5145551234").
//      This is the exact shape the rename leaves behind.
//   2. BOTH halves are empty. A doc with either one is already displaying a
//      name and must never be clobbered — that also makes this idempotent.
//   3. It does not read as a BUSINESS (`type`, `businessName`, or a remembered
//      name that `looksLikeBusinessName` recognises). A company's name is not a
//      first and last name, and splitting one into halves would put a mangled
//      company on its own invoices. Those are the "Yokohama" class and belong
//      to `restore-business-client-names.js`, which sets `type` as well —
//      they are REPORTED here and left alone.
//   4. A settled appointment remembers a name with at least one letter in it.
//
// THE SPLIT IS DUMB ON PURPOSE: the last whitespace-separated token is the
// last name and everything before it is the first. "Marc Tremblay" and
// "Jean Paul Belanger" both come out right; a one-token name becomes a first
// name with no last, which `displayFor` renders unchanged. Every split is
// printed in full so the operator reads them rather than trusting the rule.
//
// ONE TRIGGER FIRES ON EVERY PATCHED DOC: `waveUpsertCustomer` enqueues an
// outbox job AND DRAINS IT IN THE SAME INVOCATION, against Wave's
// 60-calls/min ceiling. Use `--max=N` to stage a large run across several
// passes; the script is idempotent, so each pass picks up where the last
// stopped. Rejected jobs back off and are retried by the daily `runWaveDaily`
// drain, so nothing is lost either way — a big run is just slow and noisy.
//
// Usage:
//   PowerShell:
//     $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\prod-service.json"
//     $env:GOOGLE_CLOUD_PROJECT = "schedulingapp-88727"
//     node functions/scripts/restore-client-name-halves.js --dry-run
//     node functions/scripts/restore-client-name-halves.js --max=100
//
//   Options:
//     --dry-run   report what would change, write nothing
//     --max=N     stop after N docs (default: no limit)
//
// AN UNKNOWN ARGUMENT IS A HARD ERROR, and that is about `--dry-run`
// specifically: it is matched exactly, so `--dryrun` would otherwise read as
// false and take the run LIVE.
//
// ALWAYS dry-run first and READ THE SPLIT LIST. Re-run
// `docs/audits/audit-renamed-client-names.js` afterwards to confirm the set
// shrank the way you expect.

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const {
  digitsOf,
  isBusiness,
  looksLikeBusinessName,
} = require("../client_name_utils");
const {toMillis} = require("../time_utils");
// Shared with the other one-off repairs: `resolveProjectId` prints a real id
// when credentials came from a service-account JSON (applicationDefault keeps
// the project internal), and `explain` is the same operator-facing error
// report. The flag LISTS deliberately stay local to each script — see
// `_flags.js` — so these scripts share the RULE, not the vocabulary.
const {
  explain,
  resolveProjectId,
} = require("./backfill-client-phone-formatting");
// The SAME split the rename itself now applies, imported rather than copied:
// this script repairs what that one wrote, so a divergence between the two
// would leave the collection holding two different splits of the same name.
const {splitName} = require("./backfill-client-name-with-phone");
const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");

const BATCH_SIZE = 200;

/**
 * Past appointments read per candidate client.
 *
 * Small because the scan is ORDERED newest-first — it takes the latest
 * settled visits rather than an arbitrary slice, so a handful is already more
 * evidence than the operator will read. `audit-renamed-client-names.js` scans
 * the same way for the same reason.
 */
const HISTORY_SCAN = 25;

/** Bare switches, matched EXACTLY — see the header. */
const EXACT_FLAGS = ["--dry-run"];

/** Flags that carry a value, matched by their `--name=` prefix. */
const PREFIX_FLAGS = ["--max="];

/**
 * Rejects any argument that is not a flag this script knows.
 *
 * The rejection rule itself lives in the shared `_flags.js` — this wrapper
 * only supplies THIS script's flag list.
 *
 * @param {!Array<string>} argv Arguments after the node + script paths.
 */
function assertKnownFlags(argv) {
  rejectUnknownFlags(argv, {exact: EXACT_FLAGS, prefixes: PREFIX_FLAGS});
}

/**
 * Reads `--max=N` off argv.
 *
 * Throws rather than falling back: silently treating a mistyped bound as "no
 * limit" would fire an unbounded burst of Wave pushes, which is the one thing
 * the flag exists to stage.
 *
 * @param {!Array<string>} argv Process arguments.
 * @return {number} The cap, or Infinity when not supplied.
 */
function parseMax(argv) {
  const arg = argv.find((a) => a.startsWith("--max="));
  if (!arg) return Infinity;
  const raw = arg.slice("--max=".length);
  if (!/^\d+$/.test(raw) || raw === "0") {
    throw new Error(`--max must be a positive whole number, got "${raw}"`);
  }
  return Number(raw);
}

/**
 * Whether `name` is nothing but this client's OWN stored number — the shape
 * the 2026-08-14 rename leaves behind.
 *
 * Compared as DIGITS because the stored formatting varies across the
 * collection: the rename wrote `phone` verbatim, and that field holds both
 * "(514) 555-1234" and bare "5145551234".
 *
 * @param {!Object} data The stored client document.
 * @return {boolean}
 */
function isRenamed(data) {
  const digits = digitsOf(String(data.name || "").trim());
  if (!digits) return false;
  return digits === digitsOf(data.phone) || digits === digitsOf(data.mobile);
}

/**
 * The composed first+last name, or "" when neither half is present.
 *
 * @param {!Object} data The stored client document.
 * @return {string}
 */
function composedName(data) {
  return [
    String(data.firstName || "").trim(),
    String(data.lastName || "").trim(),
  ].filter(Boolean).join(" ");
}

/**
 * The distinct `clientName` values on this client's SETTLED appointments,
 * newest first.
 *
 * Only settled visits are evidence: anything still live was rewritten by
 * `propagateClientEdits` when the rename saved, so it echoes the NEW name and
 * would "remember" the phone number back at us.
 *
 * ORDERED, and the `orderBy` is what makes the `limit` mean anything — the
 * same lesson `fetchClientHistory` learned on 2026-08-13. Without it Firestore
 * falls back to `__name__` order, so a client with more appointments than the
 * cap gets an ARBITRARY slice: one whose slice happens to land on future
 * visits reports "no usable evidence" for a name that is sitting right there.
 * The `(clientId ASC, startTime DESC)` composite already exists and serves
 * this. Consequence, accepted: an `orderBy` excludes a doc with no
 * `startTime`, but such a doc has no parseable window and was dropped by the
 * `!end` test one step later anyway.
 *
 * @param {!Object} db Firestore instance.
 * @param {string} clientId The client doc id.
 * @return {!Promise<!Array<string>>} Distinct historical names, newest first.
 */
async function historicalNames(db, clientId) {
  const now = Date.now();
  const snap = await db.collection("appointments")
      .where("clientId", "==", clientId)
      .where("startTime", "<", new Date(now))
      .orderBy("startTime", "desc")
      .limit(HISTORY_SCAN)
      .get();

  // A Set, not a Map: the query already returns newest-first, so insertion
  // order IS the answer and there is no timestamp left to sort by.
  const seen = new Set();
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    // `toMillis` rather than a local parser: it finite-checks and accepts the
    // Date/number shapes a console or Admin-SDK write can leave behind.
    const end = toMillis(d.endTime) || toMillis(d.startTime) || 0;
    // A job that STARTED in the past can still be running, and a running one
    // was rewritten by the rename. The query bound prunes the future; this
    // drops what is merely under way.
    if (!end || end >= now) continue;

    const clientName = String(d.clientName || "").trim();
    if (!clientName) continue;
    // A remembered value with no letters in it is another phone number, and
    // remembers nothing this script can use.
    if (!/[a-z]/i.test(clientName)) continue;

    // Newest first already, so the first sighting of a name IS its latest.
    seen.add(clientName);
  }

  return [...seen];
}

/**
 * Why this doc is or is not a candidate, before any appointment is read.
 *
 * ONE classifier returning a REASON rather than a pair of booleans: the
 * caller tallies by that reason, so a typed business can never be counted
 * under "already has a name" — which is the line the header tells the
 * operator to read. Running before the history lookup keeps the expensive
 * per-client query off docs that could never be patched.
 *
 * @param {!Object} data The stored client document.
 * @return {string} `candidate`, or the reason it was skipped.
 */
function classify(data) {
  if (!isRenamed(data)) return "notRenamed";
  // Rule 2 — never clobber a half that is already there. This is also what
  // makes the script idempotent.
  if (composedName(data)) return "hasName";
  // Rule 3, first pass. The remembered name gets the same test later.
  if (isBusiness(data)) return "typedBusiness";
  return "candidate";
}

/**
 * Restores the first/last halves on every eligible renamed client.
 * @return {!Promise<void>}
 */
async function main() {
  const argv = process.argv.slice(2);
  assertKnownFlags(argv);
  const dryRun = argv.includes("--dry-run");
  const max = parseMax(argv);

  const app = initializeApp({credential: applicationDefault()});
  const db = getFirestore();

  // Printed BEFORE anything is read. Running a bulk repair against the wrong
  // project is the unrecoverable mistake here, and this banner is the only
  // thing standing in the way.
  const emulator = process.env.FIRESTORE_EMULATOR_HOST;
  console.log(
      `${dryRun ? "[dry-run] " : ""}target: ${resolveProjectId(app)}` +
      `${emulator ? ` via emulator ${emulator}` : " (LIVE)"}\n`);

  const snap = await db.collection("clients").get();

  const restored = [];
  const business = [];
  const typedBusiness = [];
  const noEvidence = [];
  const skipped = {notRenamed: 0, hasName: 0};

  let batch = db.batch();
  let pending = 0;
  // Counted rather than read off `snap.size`: `--max` BREAKS the loop, so on a
  // staged run the collection size would tell the operator the whole roster was
  // examined when a tail of it was never looked at — and every tally below is a
  // tally of this prefix only.
  let examined = 0;

  for (const doc of snap.docs) {
    if (restored.length >= max) break;
    const data = doc.data() || {};
    examined += 1;

    const reason = classify(data);
    if (reason === "typedBusiness") {
      typedBusiness.push({id: doc.id, now: String(data.name || "").trim()});
      continue;
    }
    if (reason !== "candidate") {
      skipped[reason] += 1;
      continue;
    }

    const past = await historicalNames(db, doc.id);
    if (past.length === 0) {
      noEvidence.push({id: doc.id, now: String(data.name || "").trim()});
      continue;
    }

    const remembered = past[0];
    // Rule 3, second pass — the same heuristic the rename itself used, re-run
    // on the REMEMBERED name. A company here is a Yokohama: its name belongs
    // in `name` with `type` set, not chopped into two halves.
    if (looksLikeBusinessName(remembered)) {
      business.push({id: doc.id, remembered});
      continue;
    }

    // `splitName` cannot return an empty first name here — `historicalNames`
    // only yields trimmed, non-empty strings carrying a letter.
    const halves = splitName(remembered);
    restored.push({id: doc.id, remembered, ...halves, past});

    if (dryRun) continue;
    batch.update(doc.ref, halves);
    pending += 1;
    if (pending >= BATCH_SIZE) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (!dryRun && pending > 0) await batch.commit();

  const tag = dryRun ? "[dry-run] " : "";

  if (restored.length > 0) {
    console.log(
        `${tag}${restored.length} client(s) to restore. READ THIS LIST — the ` +
        "split is mechanical (last token is the surname) and only you can " +
        "tell a mis-split from a real name:");
    for (const r of restored) {
      const others = r.past.length > 1 ?
        `  (history also saw: ${r.past.slice(1).map((n) => `"${n}"`)
            .join(", ")})` :
        "";
      console.log(`  ${r.id}  "${r.remembered}"` +
        `  ->  first "${r.firstName}"  last "${r.lastName}"${others}`);
    }
    console.log("");
  }

  console.log(
      `${tag}clients: ${examined} of ${snap.size} examined, ` +
      `${restored.length} restored, ` +
      `${business.length + typedBusiness.length} left for the business ` +
      `repair, ${noEvidence.length} with no usable evidence, ` +
      `${skipped.hasName} skipped (already has a name), ` +
      `${skipped.notRenamed} skipped (not renamed)`);
  if (examined < snap.size) {
    console.log(
        `${tag}--max stopped the run early — ${snap.size - examined} ` +
        "client(s) were never looked at. Re-run to pick up where this " +
        "pass stopped.");
  }

  if (business.length > 0 || typedBusiness.length > 0) {
    console.log(
        `\n${tag}${business.length + typedBusiness.length} client(s) read as ` +
        "a BUSINESS. Left alone on purpose — a company name is not a first " +
        "and last name. Restore these with " +
        "`restore-business-client-names.js`, which also sets `type` so " +
        "nothing renames them again. NOTE its " +
        "mapping is HARDCODED, so an id below that is not already in its " +
        "`RESTORE` table gets nothing until you add it:");
    for (const b of business) {
      console.log(`  ${b.id}  remembered "${b.remembered}"`);
    }
    // Already typed/legacy-flagged as a business, so no appointment was ever
    // read for it — there is no remembered name to print, only what it is
    // called now.
    for (const b of typedBusiness) {
      console.log(`  ${b.id}  now "${b.now}"  (already typed as a business)`);
    }
  }

  if (noEvidence.length > 0) {
    console.log(
        `\n${tag}${noEvidence.length} client(s) have no settled appointment ` +
        "remembering a name, so nothing here can restore them. They will " +
        "keep showing their phone number until someone types a name in:");
    for (const n of noEvidence) console.log(`  ${n.id}  now "${n.now}"`);
  }

  if (!dryRun && restored.length > 0) {
    console.log(
        `\n${restored.length} Wave customer pushes are now draining — they ` +
        "add the person's name to Wave's own first/last fields and leave the " +
        "customer name (the number) alone. Let them settle before running an " +
        "import, and re-run docs/audits/audit-renamed-client-names.js to " +
        "confirm the set shrank.");
  }
}

// Only run when invoked directly, so the rules here are requirable by jest
// without the script reaching for prod credentials.
if (require.main === module) {
  main().catch((err) => {
    explain(err);
    process.exit(1);
  });
}

module.exports = {
  assertKnownFlags,
  classify,
  composedName,
  historicalNames,
  isRenamed,
  parseMax,
  splitName,
};
