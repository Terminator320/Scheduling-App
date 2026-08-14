#!/usr/bin/env node
// One-off: puts each client's phone number back on the end of its `name`, so
// the Wave customer name reads "Marc Tremblay (514) 555-1234" again.
//
// WHY this exists: `backfill-client-phone-from-name.js` ran against prod on
// 2026-08-08. It lifted the phone number out of `name` into the `phone` field
// and renamed `name` to "First Last" — correct for the app, but `name` is
// synced VERBATIM as the Wave customer name (`toWaveCustomerInput`,
// `wave/mappers.js`), so every one of those clients was renamed in Wave too
// and lost the number the invoicing workflow identifies customers by. Owner
// call 2026-08-14: the number goes back in the name, and the APP shows the
// first/last halves instead (`ClientNamePolicy`, hand-mirrored here as
// `client_name_utils.js`). This is the data half of that change.
//
// THE RULE, per doc:
//   1. Skip any client created ON OR AFTER --since (default 2026-08-08, the
//      day the rename ran). "Don't touch the ones that were just added" —
//      owner call. A doc with NO `createdAt` is treated as OLD and patched:
//      the field is backfilled lazily, so its absence means legacy, not new.
//   2. Skip any client with no phone AND no mobile. There is nothing to
//      append and nothing about the doc is wrong.
//   3. Otherwise set `name` to `composeStored(name, phone)` — the stored name
//      with its own trailing number stripped, then the number appended. That
//      strip is what makes this IDEMPOTENT: a second run finds the number
//      already there and produces the same string, so nothing is written.
//
// THE BASE NAME IS THE STORED `name`, NOT THE DISPLAY NAME. A Wave-imported
// business carries the business in `name` and a CONTACT PERSON in
// first/last — writing the display name back would rename "Vogas Plumbing" to
// "Marc Tremblay" IN WAVE, on real invoices, unrecoverably from the doc. The
// first/last halves are used only when `name` is empty once stripped, which is
// the junk case the 2026-08-08 rename was cleaning up in the first place.
//
// TWO TRIGGERS FIRE ON EVERY PATCHED DOC, both wanted, neither free:
//   - `propagateClientEdits` fans the name onto that client's FUTURE
//     appointments. Harmless here and worth having: it writes the DISPLAY name
//     (`clientDisplayName` strips the number back off), so the appointment
//     copies converge on the same clean name the app writes at booking.
//   - `waveUpsertCustomer` enqueues an outbox job AND DRAINS IT IN THE SAME
//     INVOCATION (the 5-minute `waveSyncWorker` was deleted 2026-08-13). That
//     is the point of this script — but it means a few hundred Wave GraphQL
//     mutations fire within seconds of the last batch, against Wave's
//     60-calls/min ceiling. RUN THIS WHEN THE QUEUE IS QUIET and let it settle
//     before the next import; jobs that get rejected back off and are picked
//     up by `waveScheduledImport`'s drain, so nothing is lost, but a run in
//     the middle of a sync will be slow and noisy.
//
// Usage:
//   For prod:
//     export GOOGLE_APPLICATION_CREDENTIALS=/path/to/prod-service-account.json
//     node functions/scripts/backfill-client-name-with-phone.js --dry-run
//     node functions/scripts/backfill-client-name-with-phone.js
//
//   For the local emulator:
//     export FIRESTORE_EMULATOR_HOST=localhost:8080
//     export GCLOUD_PROJECT=schedulingapp-88727
//     node functions/scripts/backfill-client-name-with-phone.js
//
//   Options:
//     --dry-run          report what would change, write nothing
//     --since=YYYY-MM-DD skip clients created on or after this date
//                        (default 2026-08-08; pass --since=9999-01-01 to
//                        include every client regardless of age)
//
// AN UNKNOWN ARGUMENT IS A HARD ERROR, and that is about `--dry-run`
// specifically: it is matched exactly, so `--dryrun` or `--dry_run` would
// otherwise read as false and take the run LIVE. Every typo of the safety flag
// now fails before a document is read.
//
// It prints the TARGET PROJECT before reading anything — running this against
// the wrong project is the other unrecoverable mistake, and that banner is the
// only thing standing in the way.
//
// A crash mid-run leaves the earlier batches committed. That is safe: the
// rename is idempotent, so re-running finishes the job and re-writes nothing
// it already did.
//
// ALWAYS dry-run against prod first and READ THE SAMPLE plus the two warning
// lists at the end. This rewrites the customer name in Wave; it is not
// reversible from here.

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const {composeStored, digitsOf, stripPhone} = require("../client_name_utils");

const BATCH_SIZE = 400;
const SAMPLE_SIZE = 25;

/** Clients created on or after this instant are left alone. */
const DEFAULT_SINCE = "2026-08-08";

/**
 * Bare switches, matched EXACTLY — the same way the code that reads them
 * matches. A prefix test here would accept `--dry-run=true`, which
 * `argv.includes("--dry-run")` then reads as false: the guard would wave
 * through the precise input it exists to catch.
 */
const EXACT_FLAGS = ["--dry-run"];

/** Flags that carry a value, matched by their `--name=` prefix. */
const PREFIX_FLAGS = ["--since="];

/**
 * Rejects any argument that is not a flag this script knows.
 *
 * THE POINT IS `--dry-run` ITSELF. It is matched exactly, so `--dryrun`,
 * `--dry_run` or `-dry-run` silently evaluate to FALSE and the run goes
 * LIVE — a mistyped safety flag becoming a live bulk rename of Wave customer
 * names is the worst failure this script has. Refusing unknown arguments
 * converts every one of those typos into an error before a document is read.
 *
 * @param {!Array<string>} argv Arguments after the node + script paths.
 */
function assertKnownFlags(argv) {
  for (const arg of argv) {
    if (EXACT_FLAGS.includes(arg)) continue;
    if (PREFIX_FLAGS.some((f) => arg.startsWith(f))) continue;
    throw new Error(
        `unknown argument "${arg}" — did you mean --dry-run? Known flags: ` +
        `${[...EXACT_FLAGS, ...PREFIX_FLAGS].join(", ")}`);
  }
}

/**
 * Reads `--since=YYYY-MM-DD` off argv.
 *
 * Throws rather than falling back on an unparseable value: silently widening
 * the scope of a bulk rename to "every client ever" is exactly the mistake
 * this flag exists to prevent.
 *
 * @param {!Array<string>} argv Process arguments.
 * @return {number} Epoch ms; docs created at or after this are skipped.
 */
function parseSince(argv) {
  const arg = argv.find((a) => a.startsWith("--since="));
  const raw = arg ? arg.slice("--since=".length) : DEFAULT_SINCE;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    throw new Error(`--since must be YYYY-MM-DD, got "${raw}"`);
  }
  const ms = Date.parse(`${raw}T00:00:00Z`);
  if (Number.isNaN(ms)) throw new Error(`--since is not a real date: "${raw}"`);
  return ms;
}

/**
 * Any run of digits long enough to be a phone number. Note this deliberately
 * spans separators (a real number contains spaces and brackets), so a string
 * holding two numbers matches as ONE run — which is why `otherNumbersIn`
 * removes the appended number by SUFFIX first rather than trying to tell the
 * runs apart.
 */
const NUMBER_RUN = /\+?\d[\d\s().+-]{5,}\d/g;

/** Below this many digits a run is a street number, a year or a unit. */
const MIN_PHONE_DIGITS = 7;

/**
 * The numbers a finished name still holds BESIDES the one just appended.
 *
 * Used only to REPORT. A doc whose name already carried a number that is not
 * the one stored in `phone` (an old line, a second contact) keeps it —
 * `stripPhone` only ever removes THIS client's number — so the result is a
 * Wave customer name with two numbers in it. That is not data loss, and not
 * something a bulk script should silently pick a winner for, but the operator
 * has to see the whole list rather than whichever few land in the sample.
 *
 * @param {string} finalName The composed name.
 * @param {string} appended The number `composeStored` put on the end.
 * @return {!Array<string>} Digits of each leftover number, in order.
 */
function otherNumbersIn(finalName, appended) {
  const name = String(finalName || "");
  const suffix = String(appended || "");
  const base = suffix && name.endsWith(suffix) ?
    name.slice(0, name.length - suffix.length) : name;

  return (base.match(NUMBER_RUN) || [])
      .map(digitsOf)
      .filter((digits) => digits.length >= MIN_PHONE_DIGITS);
}

/**
 * Epoch ms for a Firestore Timestamp / Date / number, or null when the doc
 * carries no usable `createdAt`.
 * @param {*} value Stored createdAt.
 * @return {?number}
 */
function createdAtMs(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  return null;
}

/**
 * The clean name to append the number to.
 *
 * The stored `name` first — see the header: the display name would rename a
 * business to its contact person in Wave. The halves and the legacy
 * `businessName` are reached only when the stored name is empty once its own
 * number is stripped off.
 *
 * @param {!Object} data Client document fields.
 * @param {{phone: string, mobile: string}} numbers The doc's stored numbers.
 * @return {string} Possibly empty.
 */
function baseNameFor(data, numbers) {
  const stored = stripPhone(data.name, numbers);
  if (stored) return stored;

  const composed = [
    String(data.firstName || "").trim(),
    String(data.lastName || "").trim(),
  ].filter(Boolean).join(" ");
  if (composed) return composed;

  return stripPhone(data.businessName, numbers);
}

/**
 * The patch for one client doc, or null when it needs no change.
 *
 * @param {!Object} data The stored client document.
 * @param {number} sinceMs Docs created at or after this are skipped.
 * @return {?{name: string}} A field patch, or null to skip the doc.
 */
function patchFor(data, sinceMs) {
  const created = createdAtMs(data.createdAt);
  // A doc with no createdAt is legacy, not new — `createdAt` is backfilled
  // lazily by the Wave import, so plenty of real old docs lack it.
  if (created !== null && created >= sinceMs) return null;

  const phone = String(data.phone || "").trim();
  const mobile = String(data.mobile || "").trim();
  if (!phone && !mobile) return null;

  const name = composeStored({
    baseName: baseNameFor(data, {phone, mobile}),
    phone,
    mobile,
  });
  if (!name || name === String(data.name || "").trim()) return null;
  return {name};
}

/**
 * Puts every eligible client's phone number back into its name.
 * @return {!Promise<void>}
 */
async function main() {
  const argv = process.argv.slice(2);
  assertKnownFlags(argv);
  const dryRun = argv.includes("--dry-run");
  const sinceMs = parseSince(argv);

  const app = initializeApp({credential: applicationDefault()});
  const db = getFirestore();

  // Printed BEFORE anything is read. Running a bulk rename against the wrong
  // project is the other unrecoverable mistake here, and the only defence is
  // the operator seeing which one they hit.
  const target = app.options.projectId ||
    process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT ||
    "(unknown — check your credentials)";
  const emulator = process.env.FIRESTORE_EMULATOR_HOST;
  console.log(
      `${dryRun ? "[dry-run] " : ""}target: ${target}` +
      `${emulator ? ` via emulator ${emulator}` : " (LIVE)"}\n`);

  const snap = await db.collection("clients").get();

  let patched = 0;
  let skippedRecent = 0;
  let skippedNoPhone = 0;
  let skippedAlreadyDone = 0;
  const sample = [];
  const multiNumber = [];
  let unlinked = 0;

  let batch = db.batch();
  let pending = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const patch = patchFor(data, sinceMs);

    if (!patch) {
      // Re-derived only to report WHY, so the operator can sanity-check the
      // scope from the dry run instead of trusting one number.
      const created = createdAtMs(data.createdAt);
      const hasNumber = Boolean(String(data.phone || "").trim() ||
        String(data.mobile || "").trim());
      if (created !== null && created >= sinceMs) skippedRecent += 1;
      else if (!hasNumber) skippedNoPhone += 1;
      else skippedAlreadyDone += 1;
      continue;
    }

    patched += 1;
    if (sample.length < SAMPLE_SIZE) {
      sample.push({id: doc.id, from: data.name || "", to: patch.name});
    }
    // Reported in FULL, not sampled — see otherNumbersIn.
    const appended = String(data.phone || "").trim() ||
      String(data.mobile || "").trim();
    if (otherNumbersIn(patch.name, appended).length > 0) {
      multiNumber.push({id: doc.id, to: patch.name});
    }
    // A client Wave has never seen is CREATED by the upsert this write
    // triggers, not patched. That is almost certainly wanted, but it is a
    // different action from renaming an existing customer and the operator
    // should know the count before it happens.
    if (!data.waveCustomerId) unlinked += 1;

    if (dryRun) continue;
    batch.update(doc.ref, patch);
    pending += 1;
    if (pending >= BATCH_SIZE) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (!dryRun && pending > 0) await batch.commit();

  const tag = dryRun ? "[dry-run] " : "";
  if (sample.length) {
    console.log(`${tag}sample (first ${sample.length}):`);
    for (const s of sample) {
      console.log(`  ${s.id}`);
      console.log(`    "${s.from}"`);
      console.log(`    -> "${s.to}"`);
    }
    console.log("");
  }
  console.log(
      `${tag}clients: ${snap.size} scanned, ${patched} renamed, ` +
      `${skippedRecent} skipped (created on/after ${
        new Date(sinceMs).toISOString().slice(0, 10)}), ` +
      `${skippedNoPhone} skipped (no phone), ` +
      `${skippedAlreadyDone} skipped (already correct)`);

  if (unlinked > 0) {
    console.log(
        `\n${tag}${unlinked} of those are not linked to a Wave customer yet, ` +
        "so the upsert will CREATE them in Wave rather than rename one.");
  }

  if (multiNumber.length > 0) {
    console.log(
        `\n${tag}${multiNumber.length} name(s) will end up holding MORE THAN ` +
        "ONE phone number — the name already carried a different number from " +
        "the one in `phone`, and only this client's own number is stripped. " +
        "Not data loss, but check whether the old number should go:");
    for (const m of multiNumber) console.log(`  ${m.id}  "${m.to}"`);
  }

  if (!dryRun && patched > 0) {
    console.log(
        `\n${patched} Wave customer pushes are now draining. Let them settle ` +
        "before running an import — see this file's header.");
  }
}

// Only run when invoked directly, so the rules here that can destroy data are
// requirable by jest without the script reaching for prod credentials.
if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = {
  assertKnownFlags,
  baseNameFor,
  createdAtMs,
  otherNumbersIn,
  parseSince,
  patchFor,
};
