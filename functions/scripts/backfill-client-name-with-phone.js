#!/usr/bin/env node
// One-off: makes each PERSON's `name` their phone number and nothing else, so
// the Wave customer reads "(514) 555-1234". A BUSINESS is left alone.
//
// WHY: `name` is synced VERBATIM as the Wave CUSTOMER name
// (`toWaveCustomerInput`, `wave/mappers.js`), and the invoicing workflow there
// identifies people by number. Owner call 2026-08-14. This supersedes both the
// "<name> <number>" shape this script wrote before and
// `backfill-client-phone-from-name.js`, which ran against prod on 2026-08-08.
// The rule lives in `ClientNamePolicy`, hand-mirrored as
// `client_name_utils.js`; this is the data half of it.
//
// THE RULE, per doc:
//   1. Skip any client created ON OR AFTER --since (default 2026-08-08, the
//      day the first rename ran). "Don't touch the ones that were just added" —
//      owner call. A doc with NO `createdAt` is treated as OLD and patched:
//      the field is backfilled lazily, so its absence means legacy, not new.
//   2. Skip any client with no phone AND no mobile. There is no number to be
//      named after, and nothing about the doc is wrong.
//   3. SKIP ANY BUSINESS — its name IS its identity in Wave ("3101-5696 qc
//      inc.", "1505 Village de Bergerac"), a number in its place is
//      unrecognisable on an invoice, and unlike a person there is usually no
//      first/last for the app to fall back on.
//   4. Otherwise set `name` to the phone (or the mobile). Trivially IDEMPOTENT:
//      a second run computes the same number, finds it already stored, and
//      writes nothing.
//
// RULE 3 IS A HEURISTIC AND THE DRY RUN LISTS EVERY DOC IT MATCHED. The Wave
// import sets no `type`, so an imported business can only be recognised by its
// NAME — a leading digit, or a company token like "inc"/"ltée"/"enr". Read
// that list before going live: a PERSON wrongly matched keeps their name (no
// harm), but a BUSINESS wrongly missed is renamed on live invoices.
//
// The clients it DOES rename with no first/last on file are listed too — those
// end up called by their phone number in the app as well as in Wave.
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
//     up by the daily `runWaveDaily` drain, so nothing is lost, but a run in
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

const {
  composeStored,
  isBusiness,
  looksLikeBusinessName,
  stripPhone,
} = require("../client_name_utils");
// `toMillis` rather than a local parser: it finite-checks, so a NaN/Infinity
// `createdAt` reads as "no usable date" and the doc is SKIPPED by --since
// rather than renamed. This script rewrites live Wave customers.
const {toMillis} = require("../time_utils");

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
 * Whether this client is left alone because it is an ORGANIZATION.
 *
 * A business's NAME is its identity in Wave — "3101-5696 qc inc.", "1505
 * Village de Bergerac" — so replacing it with a phone number makes the
 * customer unrecognisable on a real invoice, and unlike a person there is
 * usually no first/last for the app to fall back on. `looksLikeBusinessName`
 * is what catches the imported ones, which carry no `type` at all.
 *
 * @param {!Object} data Client document fields.
 * @param {{phone: string, mobile: string}} numbers The doc's stored numbers.
 * @return {boolean}
 */
function isBusinessClient(data, numbers) {
  return isBusiness(data) ||
    looksLikeBusinessName(stripPhone(data.name, numbers));
}

/**
 * The patch for one client doc, or null when it needs no change.
 *
 * @param {!Object} data The stored client document.
 * @param {number} sinceMs Docs created at or after this are skipped.
 * @return {?{name: string}} A field patch, or null to skip the doc.
 */
function patchFor(data, sinceMs) {
  const created = toMillis(data.createdAt);
  // A doc with no createdAt is legacy, not new — `createdAt` is backfilled
  // lazily by the Wave import, so plenty of real old docs lack it.
  if (created !== null && created >= sinceMs) return null;

  const phone = String(data.phone || "").trim();
  const mobile = String(data.mobile || "").trim();
  if (!phone && !mobile) return null;

  const name = composeStored({
    baseName: data.name,
    phone,
    mobile,
    type: data.type,
    businessName: data.businessName,
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
  const nameless = [];
  const businesses = [];
  let unlinked = 0;

  let batch = db.batch();
  let pending = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const patch = patchFor(data, sinceMs);

    if (!patch) {
      // Re-derived only to report WHY, so the operator can sanity-check the
      // scope from the dry run instead of trusting one number.
      const created = toMillis(data.createdAt);
      const phone = String(data.phone || "").trim();
      const mobile = String(data.mobile || "").trim();
      if (created !== null && created >= sinceMs) {
        skippedRecent += 1;
      } else if (!phone && !mobile) {
        skippedNoPhone += 1;
      } else if (isBusinessClient(data, {phone, mobile})) {
        // Reported in FULL: this is a HEURISTIC on every doc that carries no
        // `type`, and the operator is the only one who can tell a real company
        // from a person the pattern happened to match.
        businesses.push({id: doc.id, name: String(data.name || "").trim()});
      } else {
        skippedAlreadyDone += 1;
      }
      continue;
    }

    patched += 1;
    if (sample.length < SAMPLE_SIZE) {
      sample.push({id: doc.id, from: data.name || "", to: patch.name});
    }
    // Reported in FULL, not sampled: this doc is about to be called by its
    // phone number IN THE APP as well as in Wave, because it has no first or
    // last name to fall back on. Nothing is lost that was not already missing,
    // but it is the one outcome the operator has to see in full.
    const hasOtherName = Boolean(
        String(data.firstName || "").trim() ||
        String(data.lastName || "").trim());
    if (!hasOtherName) nameless.push({id: doc.id, to: patch.name});
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
      `${businesses.length} skipped (business), ` +
      `${skippedRecent} skipped (created on/after ${
        new Date(sinceMs).toISOString().slice(0, 10)}), ` +
      `${skippedNoPhone} skipped (no phone), ` +
      `${skippedAlreadyDone} skipped (already correct)`);

  if (businesses.length > 0) {
    console.log(
        `\n${tag}${businesses.length} client(s) kept their name because they ` +
        "read as a BUSINESS — its name is what identifies it in Wave. This " +
        "is a heuristic on any doc with no `type`, so check the list for a " +
        "PERSON that should have been renamed:");
    for (const b of businesses) console.log(`  ${b.id}  "${b.name}"`);
  }

  if (unlinked > 0) {
    console.log(
        `\n${tag}${unlinked} of those are not linked to a Wave customer yet, ` +
        "so the upsert will CREATE them in Wave rather than rename one.");
  }

  if (nameless.length > 0) {
    console.log(
        `\n${tag}${nameless.length} client(s) have NO name anywhere else — no ` +
        "business name, no first/last — so they will be called by their phone " +
        "number in the app as well as in Wave. Nothing is lost that was not " +
        "already missing, but give these a name if any matter:");
    for (const n of nameless) console.log(`  ${n.id}  "${n.to}"`);
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
  parseSince,
  patchFor,
};
