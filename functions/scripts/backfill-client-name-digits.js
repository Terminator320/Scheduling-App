#!/usr/bin/env node
// One-off: takes the punctuation out of a client `name` that is already
// nothing but that client's own phone number, so the Wave customer reads
// "5145551234" instead of "(514) 555-1234". Owner call 2026-08-16.
//
// WHY: `name` is synced VERBATIM as the Wave CUSTOMER name
// (`toWaveCustomerInput`, `wave/mappers.js`) and the invoicing workflow there
// identifies people by number — bare. The `phone` FIELD is untouched and stays
// formatted; `PhoneInputFormatter` still masks it as it is typed. The rule
// lives in `ClientNamePolicy.composeStored`, hand-mirrored as
// `client_name_utils.js`; this is the data half of it, catching the docs
// `backfill-client-name-with-phone.js` renamed under the previous formatting.
//
// THIS SCRIPT CANNOT RENAME ANYBODY, and that is the whole design. It patches
// a doc only when `stripPhone(name)` comes back EMPTY — i.e. the stored name
// reduces to nothing once this client's own number is taken off it, so the
// name IS the number and there is no human name anywhere in it to lose. A
// business, a legacy "Marc Tremblay 514-555-1234", or a person still carrying
// a typed name all leave a non-empty remainder and are skipped untouched. That
// makes it strictly narrower than re-running the rename backfill, which is the
// point: this is a reformat, not a rename, and it must not become one.
//
// THE RULE, per doc:
//   1. Skip any client with no phone AND no mobile — nothing to be named
//      after, and nothing about the doc is wrong.
//   2. Skip any client whose name is not already exactly its own number
//      (see above).
//   3. Skip any BUSINESS. Its name is its identity in Wave even in the odd
//      case where that name happens to be a number, and `composeStored`
//      answers `""` for it — which this script must never write.
//   4. Otherwise set `name` to `composeStored(...)`, which is the bare number.
//      IDEMPOTENT: a second run recomputes the same string, finds it already
//      stored, and writes nothing.
//
// There is deliberately NO `--since`. The previous backfill had one because it
// REPLACED names and the owner did not want freshly-added clients rewritten;
// here the only thing that changes is a number's punctuation, so age is not a
// reason to leave a doc inconsistent with every other one.
//
// TWO TRIGGERS FIRE ON EVERY PATCHED DOC, both wanted, neither free:
//   - `propagateClientEdits` fans the name onto that client's FUTURE
//     appointments. Harmless: it writes the DISPLAY name
//     (`clientDisplayName` strips the number back off), so those copies are
//     unchanged in practice.
//   - `waveUpsertCustomer` enqueues an outbox job AND DRAINS IT IN THE SAME
//     INVOCATION (the 5-minute `waveSyncWorker` was deleted 2026-08-13). That
//     is the point of this script — but it means a few hundred Wave GraphQL
//     mutations fire within seconds of the last batch, against Wave's
//     60-calls/min ceiling. RUN THIS WHEN THE QUEUE IS QUIET and let it settle
//     before the next import; rejected jobs back off and are picked up by the
//     daily `runWaveDaily` drain, so nothing is lost, but a run in the middle
//     of a sync will be slow and noisy.
//
// Usage:
//   For prod:
//     export GOOGLE_APPLICATION_CREDENTIALS=/path/to/prod-service-account.json
//     node functions/scripts/backfill-client-name-digits.js --dry-run
//     node functions/scripts/backfill-client-name-digits.js
//
//   For the local emulator:
//     export FIRESTORE_EMULATOR_HOST=localhost:8080
//     export GCLOUD_PROJECT=schedulingapp-88727
//     node functions/scripts/backfill-client-name-digits.js
//
//   Options:
//     --dry-run   report what would change, write nothing
//
// AN UNKNOWN ARGUMENT IS A HARD ERROR, and that is about `--dry-run`
// specifically: it is matched exactly, so `--dryrun` or `--dry_run` would
// otherwise read as false and take the run LIVE.
//
// It prints the TARGET PROJECT before reading anything — running this against
// the wrong project is the other mistake worth guarding, and that banner is
// the only thing standing in the way.
//
// A crash mid-run leaves the earlier batches committed. That is safe: the
// reformat is idempotent, so re-running finishes the job and re-writes nothing
// it already did.

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const {
  composeStored,
  isBusiness,
  stripPhone,
} = require("../client_name_utils");
const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");
const {printTargetBanner} = require("./_project");
// The batched-write loop, shared so `--dry-run` cannot be forgotten at a
// call site — see `_batch.js`.
const {commitInBatches} = require("./_batch");

const BATCH_SIZE = 400;
const SAMPLE_SIZE = 25;

/** Bare switches, matched EXACTLY — the same way the code reading them does. */
const EXACT_FLAGS = ["--dry-run"];

/**
 * Rejects any argument that is not a flag this script knows.
 *
 * THE POINT IS `--dry-run` ITSELF: it is matched exactly, so `--dryrun`,
 * `--dry_run` or `-dry-run` silently evaluate to FALSE and the run goes LIVE.
 * The rejection rule lives in the shared `_flags.js`; this wrapper only
 * supplies THIS script's flag list.
 *
 * @param {!Array<string>} argv Arguments after the node + script paths.
 */
function assertKnownFlags(argv) {
  rejectUnknownFlags(argv, {exact: EXACT_FLAGS});
}

/**
 * The patch for one client doc, or null when it needs no change.
 *
 * The `stripPhone(...) !== ""` guard is what makes this script incapable of
 * losing a name: the only docs it touches are the ones whose stored `name`
 * reduces to nothing once their own number comes off it, so there is no human
 * name in there to overwrite. Everything else — a business, a legacy
 * "<name> <number>", a person still called by their name — is skipped.
 *
 * @param {!Object} data The stored client document.
 * @return {?{name: string}} A field patch, or null to skip the doc.
 */
function patchFor(data) {
  const phone = String(data.phone || "").trim();
  const mobile = String(data.mobile || "").trim();
  if (!phone && !mobile) return null;

  const name = String(data.name || "").trim();
  if (!name) return null;
  if (stripPhone(name, {phone, mobile}) !== "") return null;
  // `composeStored` answers "" for a business, which must never be written.
  if (isBusiness(data)) return null;

  const composed = composeStored({
    baseName: name,
    phone,
    mobile,
    type: data.type,
    businessName: data.businessName,
  });
  if (!composed || composed === name) return null;
  return {name: composed};
}

/**
 * Rewrites every number-named client's `name` in its bare form.
 * @return {!Promise<void>}
 */
async function main() {
  const argv = process.argv.slice(2);
  assertKnownFlags(argv);
  const dryRun = argv.includes("--dry-run");

  const app = initializeApp({credential: applicationDefault()});
  const db = getFirestore();

  // Printed BEFORE anything is read: running a bulk write against the wrong
  // project is the mistake the operator has to be able to see coming.
  printTargetBanner(app, {dryRun});

  const snap = await db.collection("clients").get();

  let patched = 0;
  let unlinked = 0;
  const sample = [];

  const writer = commitInBatches(db, {dryRun, batchSize: BATCH_SIZE});

  for (const doc of snap.docs) {
    const data = doc.data();
    const patch = patchFor(data);
    if (!patch) continue;

    patched += 1;
    if (sample.length < SAMPLE_SIZE) {
      sample.push({id: doc.id, from: String(data.name || ""), to: patch.name});
    }
    // A client Wave has never seen is CREATED by the upsert this write
    // triggers, not patched — a different action from renaming an existing
    // customer, and the operator should know the count before it happens.
    if (!data.waveCustomerId) unlinked += 1;

    await writer.stage(doc.ref, patch);
  }
  await writer.flush();

  const tag = dryRun ? "[dry-run] " : "";
  if (sample.length) {
    console.log(`${tag}sample (first ${sample.length}):`);
    for (const s of sample) console.log(`  ${s.id}  "${s.from}" -> "${s.to}"`);
    console.log("");
  }
  console.log(
      `${tag}clients: ${snap.size} scanned, ${patched} reformatted, ` +
      `${snap.size - patched} left alone`);

  if (unlinked > 0) {
    console.log(
        `\n${tag}${unlinked} of those are not linked to a Wave customer yet, ` +
        "so the upsert will CREATE them in Wave rather than rename one.");
  }

  if (!dryRun && patched > 0) {
    console.log(
        `\n${patched} Wave customer pushes are now draining. Let them settle ` +
        "before running an import — see this file's header.");
  }
}

// Only run when invoked directly, so the rule here is requirable by jest
// without the script reaching for prod credentials.
if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = {assertKnownFlags, patchFor};
