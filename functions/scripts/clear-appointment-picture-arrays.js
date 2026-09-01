#!/usr/bin/env node
// One-off: DELETES each appointment's legacy `pictures` array, once its photos
// are provably in the `appointments/{id}/images` subcollection.
//
// This is the CONTRACT step's cleanup — the "separate script" the copy-only
// `backfill-appointment-images.js` header points at. Photos moved off the
// parent document because every appointment read carried its whole photo array
// (a stored download url alone was ~215 of a ~290-byte entry) while the
// calendar reads up to 1000 appointments at a time and only the detail sheet
// ever shows a photo. Until now the array was kept in step so builds that read
// it kept working; nothing reads it any more, and this reclaims the space.
//
// **THIS IS THE ONLY DESTRUCTIVE SCRIPT IN THIS DIRECTORY THAT TARGETS DATA
// THE APP CANNOT REBUILD**, so it is written to refuse rather than to cope:
//
//   - It CLEARS NOTHING it has not verified. Every entry of an appointment's
//     array must already exist in that appointment's subcollection, matched by
//     `appointmentImageDocId` — the same derivation both stores key on. One
//     missing photo and the whole appointment is left alone and reported.
//   - It never copies. Copying is `backfill-appointment-images.js`'s job, and
//     a script that both copies and deletes cannot be dry-run meaningfully:
//     the dry run would report a coverage it is itself about to create.
//   - An entry with no identity (no `storagePath` AND no url) is unrenderable
//     and uncopyable, so it can never be covered. Those appointments are
//     reported and skipped too — clearing would destroy the only record that
//     the entry ever existed, which is a decision for a person.
//
// RUN ORDER, and it matters:
//   1. `backfill-appointment-images.js` (copy) — including a re-run, because
//      any build still writing the array will have added to it since the last
//      pass.
//   2. Ship the app build that reads the subcollection only.
//   3. This script, once no build writes the array either.
//
// Running it early is the one genuinely unsafe move: the array is what an
// older build renders from, so clearing it blanks every photo on every phone
// that has not updated.
//
// IDEMPOTENT: `pictureCount` is re-stamped from what the subcollection actually
// holds, absolutely, never as a delta, so a second run agrees with the first
// and writes nothing.
//
// IT DOES NOT SKIP AN APPOINTMENT THAT CARRIES NO ARRAY. Those are the ones
// whose counter can be wrong with nothing left to notice it — an appointment
// whose array was emptied while its `pictureCount` write failed reads as
// having no photos on every card, forever. The completeness of that counter is
// this script's second job, and the prose elsewhere that leans on "stamped on
// every document that predates the change" only became true when this stopped
// `continue`ing past them.
//
// Usage:
//   For prod:
//     export GOOGLE_APPLICATION_CREDENTIALS=/path/to/prod-service-account.json
//     node functions/scripts/clear-appointment-picture-arrays.js --dry-run
//     node functions/scripts/clear-appointment-picture-arrays.js
//
//   For the local emulator:
//     export FIRESTORE_EMULATOR_HOST=localhost:8080
//     export GCLOUD_PROJECT=schedulingapp-88727
//     node functions/scripts/clear-appointment-picture-arrays.js
//
// AN UNKNOWN ARGUMENT IS A HARD ERROR — see `_flags.js`. `--dryrun` or
// `--dry_run` would otherwise silently read as false and take this LIVE
// against `/appointments`.

const {FieldValue} = require("firebase-admin/firestore");
const {appointmentImageDocId} = require("../appointment_image_ids");
const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");
const {bootstrapScript} = require("./_project");

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

/** Appointments read per page. Each costs one subcollection read on top. */
const PAGE_SIZE = 200;

/**
 * Decides what to do with one appointment, given what its subcollection holds.
 *
 * Pure, so the refusal rule — the whole point of the script — is testable
 * without Firestore. `storedIds` is the set of document ids the subcollection
 * actually contains.
 *
 * @param {!Array<!Object>} pictures The legacy `pictures` array.
 * @param {!Set<string>} storedIds Document ids present in the subcollection.
 * @return {{clear: boolean, missing: !Array<string>, identityless: number}}
 *   `clear` is true only when every entry is accounted for.
 */
function planClear(pictures, storedIds) {
  const missing = [];
  let identityless = 0;
  for (const picture of pictures) {
    const id = appointmentImageDocId(picture);
    if (id === "") {
      // Neither a storage path nor a url: nothing can render it and nothing
      // could have copied it. Refusing keeps the evidence.
      identityless += 1;
      continue;
    }
    if (!storedIds.has(id)) missing.push(id);
  }
  return {
    clear: missing.length === 0 && identityless === 0,
    missing,
    identityless,
  };
}

/**
 * Whether an appointment carrying NO array needs its `pictureCount` re-stamped.
 *
 * Pure, because it is the second half of this script's completeness claim and
 * the half that is easy to get wrong. Two shapes have to be told apart: a
 * field that is ABSENT is the normal state of an appointment that never had a
 * photo, reads as 0 on the client, and must not generate a write for every
 * document in the collection; a field that is PRESENT but not an integer is a
 * console edit or a legacy write that no reader can use, and it gets replaced
 * whatever the subcollection holds.
 *
 * @param {!Object} data The stored appointment document.
 * @param {number} storedCount How many documents its subcollection holds.
 * @return {boolean} True when a write would change something.
 */
function needsRecount(data, storedCount) {
  const raw = data.pictureCount;
  if (raw === undefined || raw === null) return storedCount !== 0;
  if (!Number.isInteger(raw)) return true;
  return raw !== storedCount;
}

/**
 * Reads the ids one appointment's subcollection holds.
 *
 * Ids only (`select()` with no fields) — the bodies are irrelevant here. It
 * runs for EVERY appointment, array or not: the subcollection is the store,
 * so it is the only thing that can say whether `pictureCount` is right.
 * @param {!Object} doc An appointments QueryDocumentSnapshot.
 * @return {!Promise<!Set<string>>}
 */
async function storedImageIds(doc) {
  const snap = await doc.ref.collection("images").select().get();
  return new Set(snap.docs.map((d) => d.id));
}

/**
 * The sweep itself, with every side effect injected.
 *
 * Split out of `main()` so the paging loop, BOTH `--dry-run` gates and the
 * `doc.ref.update` that deletes `pictures[]` can be exercised by jest. This is
 * the only unattended, irreversible deletion in `scripts/`, and this repo has
 * already shipped a backfill whose `--dry-run` wrote everything and then threw
 * — the gates are exactly the part that cannot be reviewed into correctness.
 *
 * @param {{db: !Object, dryRun: boolean,
 *   log: (function(string):void|undefined),
 *   warn: (function(string):void|undefined)}} opts
 * @return {!Promise<{appointments: number, withArray: number, cleared: number,
 *   entriesCleared: number, recounted: number, refused: !Array<!Object>}>}
 */
async function runClear({db, dryRun, log = console.log, warn = console.warn}) {
  let cursor = null;
  let appointments = 0;
  let withArray = 0;
  let cleared = 0;
  let entriesCleared = 0;
  let recounted = 0;
  const refused = [];

  for (;;) {
    // Ordered by document id — the only field every appointment is guaranteed
    // to have. Ordering by a data field would silently exclude any document
    // missing it, which is exactly how a sweep misses the rows that most need
    // it.
    let query = db.collection("appointments")
        .orderBy("__name__")
        .limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const snap = await query.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      appointments += 1;
      const data = doc.data() || {};
      const pictures = Array.isArray(data.pictures) ? data.pictures : [];
      // Read for every appointment, array or not — the subcollection is the
      // store, so it is the only thing that can say whether `pictureCount` is
      // right. Ids only, so this is the cheapest read Firestore offers.
      const storedIds = await storedImageIds(doc);

      if (pictures.length === 0) {
        // No array to clear, so the only question left is whether the counter
        // agrees with the subcollection. `undefined` parses as 0 on the client
        // side, so treat it as 0 here too and write only on a real difference.
        if (!needsRecount(data, storedIds.size)) continue;
        recounted += 1;
        if (dryRun) continue;
        await doc.ref.update({pictureCount: storedIds.size});
        continue;
      }
      withArray += 1;

      const plan = planClear(pictures, storedIds);
      if (!plan.clear) {
        refused.push({
          id: doc.id,
          missing: plan.missing.length,
          identityless: plan.identityless,
        });
        continue;
      }

      cleared += 1;
      entriesCleared += pictures.length;
      if (dryRun) continue;
      // One write, not a batch: the array delete and the count must land
      // together, and `pictureCount` is re-stamped from what the subcollection
      // actually holds rather than from the array's length — they agree here
      // by construction, but the subcollection is the store, so it is what the
      // number should come from.
      await doc.ref.update({
        pictures: FieldValue.delete(),
        pictureCount: storedIds.size,
      });
    }

    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break;
  }

  const prefix = dryRun ? "[dry run] would clear" : "cleared";
  log(
      `${prefix} ${entriesCleared} array entries across ${cleared} ` +
      `appointments (${withArray} still carried an array, ` +
      `${appointments} scanned)`);

  if (recounted > 0) {
    const verb = dryRun ? "[dry run] would re-stamp" : "re-stamped";
    log(
        `${verb} pictureCount on ${recounted} appointment(s) that carried no ` +
        "array but disagreed with their subcollection");
  }

  if (refused.length > 0) {
    warn(
        `REFUSED ${refused.length} appointment(s) whose subcollection does ` +
        "not cover the array — run backfill-appointment-images.js and try " +
        "again. An `identityless` entry cannot be covered by any backfill " +
        "and needs a human:");
    for (const row of refused) {
      warn(
          `  ${row.id}: ${row.missing} not copied, ` +
          `${row.identityless} unrenderable`);
    }
  }
  if (dryRun) {
    log("no writes were made; re-run without --dry-run to apply");
  }

  return {appointments, withArray, cleared, entriesCleared, recounted, refused};
}

/**
 * Reads the flags, resolves credentials, prints the banner, runs the sweep.
 * @return {!Promise<void>}
 */
async function main() {
  const argv = process.argv.slice(2);
  const {db, dryRun} = bootstrapScript(argv, {assertFlags: assertKnownFlags});

  await runClear({db, dryRun});
}

// Guarded so `planClear` can be required by jest without `main()` reaching for
// application-default credentials at load.
if (require.main === module) {
  main().then(() => process.exit(0)).catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = {
  planClear,
  needsRecount,
  storedImageIds,
  runClear,
};
