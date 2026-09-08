#!/usr/bin/env node
// One-off: DELETES each appointment's legacy `pictures` array, once its photos
// are provably in the `appointments/{id}/images` subcollection.

const {FieldValue} = require("firebase-admin/firestore");
const {appointmentImageDocId} = require("../appointment_image_ids");
const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");
const {scanByName} = require("./_scan");
const {bootstrapScript} = require("./_project");

/** Bare switches, matched EXACTLY — see `_flags.js`. */
const EXACT_FLAGS = ["--dry-run"];

/**
 * Rejects any argument that is not a flag this script knows.
 * @param {!Array<string>} argv Arguments after the node + script paths.
 */
function assertKnownFlags(argv) {
  rejectUnknownFlags(argv, {exact: EXACT_FLAGS});
}

/** Appointments read per page. Each costs one subcollection read on top. */
const PAGE_SIZE = 200;

/**
 * Decides what to do with one appointment, given what its subcollection holds.
 * @param {!Array<!Object>} pictures The legacy `pictures` array.
 * @param {!Set<string>} storedIds Document ids present in the subcollection.
 * @return {{clear: boolean, missing: !Array<string>, identityless: number}}
 * `clear` is true only when every entry is accounted for.
 */
function planClear(pictures, storedIds) {
  const missing = [];
  let identityless = 0;
  for (const picture of pictures) {
    const id = appointmentImageDocId(picture);
    if (id === "") {
      // Neither a storage path nor a url: nothing can render it and nothing
      // could have copied it.
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
 * @param {!Object} doc An appointments QueryDocumentSnapshot.
 * @return {!Promise<!Set<string>>}
 */
async function storedImageIds(doc) {
  const snap = await doc.ref.collection("images").select().get();
  return new Set(snap.docs.map((d) => d.id));
}

/**
 * The sweep itself, with every side effect injected.
 * @param {{db: !Object, dryRun: boolean,
 * log: (function(string):void|undefined),
 * warn: (function(string):void|undefined)}} opts
 * @return {!Promise<{appointments: number, withArray: number, cleared: number,
 * entriesCleared: number, recounted: number, refused: !Array<!Object>}>}
 */
async function runClear({db, dryRun, log = console.log, warn = console.warn}) {
  let appointments = 0;
  let withArray = 0;
  let cleared = 0;
  let entriesCleared = 0;
  let recounted = 0;
  const refused = [];

  for await (const doc of scanByName(
      db.collection("appointments"),
      {pageSize: PAGE_SIZE},
  )) {
    appointments += 1;
    const data = doc.data() || {};
    const pictures = Array.isArray(data.pictures) ? data.pictures : [];
    // Read for every appointment, array or not — the subcollection is the
    // store, so it is the only thing that can say whether `pictureCount` is
    // right.
    const storedIds = await storedImageIds(doc);

    if (pictures.length === 0) {
      // No array to clear, so the only question left is whether the counter
      // agrees with the subcollection.
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
    // actually holds rather than from the array's length — they agree here by
    // construction, but the subcollection is the store, so it is what the
    // number should come from.
    await doc.ref.update({
      pictures: FieldValue.delete(),
      pictureCount: storedIds.size,
    });
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
