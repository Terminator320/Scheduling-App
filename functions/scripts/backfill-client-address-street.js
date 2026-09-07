#!/usr/bin/env node
// One-off: reduces `clients/{id}.address` to the STREET LINE, dropping the
// trailing city/province/postal/country that the doc already carries in its
// own fields. Owner call 2026-08-28.
//
// WHY: those four are their own fields, so an `address` that also carries them
// stores each one twice and lets the two copies drift — edit the city in one
// place and the other silently disagrees. The Wave import has always written a
// street line here while the app wrote the whole picked string, so the field
// already means two different things depending on where a client came from.
// The app stopped writing the full string on 2026-08-28
// (`address_field_filler.dart`); this is the data half, for everything already
// stored.
//
// THIS IS HYGIENE, NOT A FIX. Nothing user-visible changes: every read
// composes through `AddressParser.composeFull` / `composeFullAddress`, which
// reduce before they rejoin, so a legacy doc already renders correctly. What
// this buys is that the field means ONE thing, for the next script or feature
// that reads it raw.
//
// THIS SCRIPT CANNOT LOSE INFORMATION, and that is the design. It only removes
// trailing segments that MATCH fields still on the same document, so the old
// string can be rebuilt from the doc exactly, at any time. That is what makes
// it categorically unlike `backfill-client-name-with-phone.js`, which replaced
// a name that existed nowhere else and destroyed 504 of them.
//
// THE RULE, per doc:
//   1. Skip a client with no `address`.
//   2. Skip a client with no locality fields at all — there is nothing to
//      identify a tail with, and `streetFromAddress` would fall back to the
//      first segment, which on a legacy doc is a GUESS. Guessing is what this
//      script must not do; those docs keep rendering fine through the
//      composer.
//   3. Otherwise set `address` to `streetFromAddress(...)`, but ONLY when that
//      actually removed a segment — not merely when the string differs. The
//      reducer rejoins with ", ", so an address whose own commas are spaced
//      differently comes back changed while nothing was stripped, and
//      re-spelling stored data is not this script's job. IDEMPOTENT: a reduced
//      value passes straight back through, so a second run writes nothing.
//
// IT MUST NEVER BE POINTED AT `appointments`. An appointment carries ONE
// address string and NO city/province/postal of its own — the same reduction
// there would destroy the locality on every live job, unrecoverably, because
// there is nothing left to rebuild it from.
//
// TRIGGERS ON EVERY PATCHED DOC — both verified to be no-ops, which is the
// whole reason this is safe to run at any time:
//   - `propagateClientEdits` compares the COMPOSED address
//     (`composeFullAddress`), and both shapes compose to the same string, so
//     `relevantClientChange` returns null and nothing is fanned onto a live
//     appointment. Pinned by "normalizing `address` to the street line
//     propagates NOTHING" in `client_propagation.test.js`. If that ever
//     regresses to comparing the raw field, THIS SCRIPT BECOMES DESTRUCTIVE.
//   - `waveUpsertCustomer` enqueues nothing. `mappedFieldsHash` hashes the
//     OUTPUT of `toWaveCustomerInput`, which already ran `streetFromAddress`,
//     so both shapes produce the same `addressLine1` and the same hash;
//     `shouldEnqueueClientWrite` Rule 1 refuses the write. Unlike the name
//     backfills, this one costs Wave nothing and needs no quiet window.
//
// Usage:
//   For prod:
//     export GOOGLE_APPLICATION_CREDENTIALS=/path/to/prod-service-account.json
//     node functions/scripts/backfill-client-address-street.js --dry-run
//     node functions/scripts/backfill-client-address-street.js
//
//   For the local emulator:
//     export FIRESTORE_EMULATOR_HOST=localhost:8080
//     export GCLOUD_PROJECT=schedulingapp-88727
//     node functions/scripts/backfill-client-address-street.js
//
//   Options:
//     --dry-run   report what would change, write nothing
//
// AN UNKNOWN ARGUMENT IS A HARD ERROR, and that is about `--dry-run`
// specifically: it is matched exactly, so `--dryrun` or `--dry_run` would
// otherwise read as false and take the run LIVE.
//
// The dry run prints EVERY change, not a sample — the list is the review
// artifact, and at ~700 clients it is readable. A live run prints a short
// sample instead, as confirmation rather than a document.
//
// It prints the TARGET PROJECT before reading anything — running this against
// the wrong project is the other mistake worth guarding, and that banner is
// the only thing standing in the way.
//
// A crash mid-run leaves the earlier batches committed. That is safe: the
// reduction is idempotent, so re-running finishes the job and re-writes
// nothing it already did.


const {streetFromAddress} = require("../client_address_utils");
const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");
const {bootstrapScript} = require("./_project");
// The batched-write loop, shared so `--dry-run` cannot be forgotten at a
// call site — see `_batch.js`.
const {commitInBatches} = require("./_batch");
// The document-id paging loop, shared so a bulk run cannot read the whole
// collection in one `.get()` — see `_scan.js`.
const {scanByName} = require("./_scan");

const BATCH_SIZE = 400;
const PAGE_SIZE = 500;
const SAMPLE_SIZE = 25;

/** Bare switches, matched EXACTLY — the same way the code reading them does. */
const EXACT_FLAGS = ["--dry-run"];

/**
 * Rejects any argument that is not a flag this script knows.
 *
 * THE POINT IS `--dry-run` ITSELF: it is matched exactly, so `--dryrun`,
 * `--dry_run` or `-dry-run` silently evaluate to FALSE and the run goes LIVE.
 *
 * @param {!Array<string>} argv Arguments after the node + script paths.
 */
function assertKnownFlags(argv) {
  rejectUnknownFlags(argv, {exact: EXACT_FLAGS});
}

/**
 * Whether this doc carries any structured locality field.
 *
 * With none, `streetFromAddress` falls back to the FIRST segment, which is a
 * guess — right for the Wave push (it needs some `addressLine1`), wrong for a
 * write that replaces stored data. Those docs are skipped.
 *
 * @param {!Object} data The stored client document.
 * @return {boolean}
 */
function hasLocalityFields(data) {
  return ["city", "province", "postalCode", "country"].some(
      (key) => String(data[key] || "").trim() !== "");
}

/**
 * The comma-separated segments of an address, trimmed, empties dropped — the
 * same view `streetFromAddress` reduces.
 * @param {string} value An address string.
 * @return {!Array<string>}
 */
function segmentsOf(value) {
  return String(value).split(",").map((s) => s.trim()).filter(Boolean);
}

/**
 * The patch for one client doc, or null when it needs no change.
 *
 * THE TEST IS THAT A SEGMENT WAS REMOVED, not that the string changed.
 * `streetFromAddress` rejoins with ", ", so a stored value whose own commas
 * are spaced differently comes back textually different while nothing was
 * stripped — a prod dry run turned up "2304,2308,2312 Philippe dolbec" being
 * rewritten to "2304, 2308, 2312 Philippe dolbec" (three civic numbers, no
 * locality anywhere) and "203-3161 Blvd. De La Gare," losing its trailing
 * comma. Both are re-spelling, not de-duplication, and this script must only
 * ever remove a locality tail the doc still carries in its own fields.
 *
 * @param {!Object} data The stored client document.
 * @return {?{address: string}} A field patch, or null to skip the doc.
 */
function patchFor(data) {
  const stored = String((data || {}).address || "").trim();
  if (!stored) return null;
  if (!hasLocalityFields(data)) return null;

  const street = streetFromAddress(stored, data);
  // A write of "" would be destructive, so make it unreachable rather than
  // merely unlikely — the reducer never empties a non-empty address.
  if (!street) return null;
  // Fewer segments === a tail actually came off. Equal counts mean the only
  // difference is punctuation, which is not this script's business.
  if (segmentsOf(street).length >= segmentsOf(stored).length) return null;
  if (street === stored) return null;
  return {address: street};
}

/**
 * Reduces every client's stored address to its street line.
 * @return {!Promise<void>}
 */
async function main() {
  const argv = process.argv.slice(2);
  const {db, dryRun} = bootstrapScript(argv, {assertFlags: assertKnownFlags});

  let scanned = 0;
  let patched = 0;
  let noLocality = 0;
  const changes = [];

  const writer = commitInBatches(db, {dryRun, batchSize: BATCH_SIZE});

  // Paged, never one `.get()` of the whole collection: a run that dies
  // part-way leaves a HALF-patched collection, which from the app's side is
  // indistinguishable from one that was never backfilled at all.
  for await (const doc of scanByName(
      db.collection("clients"), {pageSize: PAGE_SIZE})) {
    scanned += 1;
    const data = doc.data();
    if (String(data.address || "").trim() && !hasLocalityFields(data)) {
      noLocality += 1;
    }

    const patch = patchFor(data);
    if (!patch) continue;

    patched += 1;
    if (dryRun || changes.length < SAMPLE_SIZE) {
      changes.push({
        id: doc.id,
        from: String(data.address || ""),
        to: patch.address,
      });
    }

    await writer.stage(doc.ref, patch);
  }
  await writer.flush();

  const tag = dryRun ? "[dry-run] " : "";
  if (changes.length) {
    const heading = dryRun ?
      `${tag}every change (${changes.length}):` :
      `${tag}sample (first ${changes.length}):`;
    console.log(heading);
    for (const c of changes) {
      console.log(`  ${c.id}  "${c.from}"`);
      console.log(`  ${" ".repeat(c.id.length)}  -> "${c.to}"`);
    }
    console.log("");
  }
  console.log(
      `${tag}clients: ${scanned} scanned, ${patched} reduced, ` +
      `${scanned - patched} left alone`);

  if (noLocality > 0) {
    console.log(
        `\n${tag}${noLocality} have an address but NO city/province/postal/` +
        "country, so there is nothing to identify a locality tail with and " +
        "they were skipped rather than guessed at. They still render " +
        "correctly — every read composes.");
  }

  if (!dryRun && patched > 0) {
    console.log(
        "\nNothing was pushed to Wave and nothing was fanned onto an " +
        "appointment — see this file's header for why both are no-ops.");
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

module.exports = {assertKnownFlags, hasLocalityFields, patchFor};
