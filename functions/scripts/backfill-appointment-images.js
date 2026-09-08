#!/usr/bin/env node
// One-off: COPIES each appointment's `pictures` array into its
// `appointments/{id}/images` subcollection, and stamps `pictureCount`.

const {Timestamp} = require("firebase-admin/firestore");
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

// Each appointment costs (photos + 1) writes in one batch.
const PAGE_SIZE = 200;

/**
 * The subcollection document for one stored photo map.
 * @param {!Object} picture A stored `pictures[]` entry.
 * @return {!Object} The subcollection document body.
 */
function imageDoc(picture) {
  const storagePath = String(picture.storagePath || "").trim();
  const doc = {storagePath};
  if (picture.fileName != null) doc.fileName = String(picture.fileName);
  // Round-trip whatever shape the array held.
  const uploadedAt = picture.uploadedAt;
  if (uploadedAt instanceof Timestamp) {
    doc.uploadedAt = uploadedAt;
  } else if (uploadedAt instanceof Date) {
    doc.uploadedAt = Timestamp.fromDate(uploadedAt);
  } else if (typeof uploadedAt === "string" && uploadedAt !== "") {
    const parsed = new Date(uploadedAt);
    doc.uploadedAt = isNaN(parsed.getTime()) ?
      null : Timestamp.fromDate(parsed);
  } else {
    doc.uploadedAt = null;
  }
  return doc;
}

/**
 * Copies one appointment's photo array into its subcollection.
 * @param {!Object} db
 * @param {!Object} doc An appointments QueryDocumentSnapshot.
 * @param {boolean=} dryRun Report what would happen without writing.
 * @return {!Promise<{copied: number, skipped: number}>}
 */
async function backfillOne(db, doc, dryRun = false) {
  const data = doc.data() || {};
  const pictures = Array.isArray(data.pictures) ? data.pictures : [];

  const writes = [];
  let skipped = 0;
  for (const picture of pictures) {
    const id = appointmentImageDocId(picture);
    const storagePath = String(picture.storagePath || "").trim();
    if (id === "" || storagePath === "") {
      // Nothing this script can write a renderable document for.
      skipped += 1;
      continue;
    }
    writes.push({id, body: imageDoc(picture)});
  }

  // `pictureCount` counts what the subcollection actually holds, not what the
  // array claimed — an identity-less entry is not a photo anyone can see, and
  // the card's indicator must not promise one.
  const count = writes.length;
  if (dryRun) return {copied: count, skipped};

  const batch = db.batch();
  const images = doc.ref.collection("images");
  for (const write of writes) {
    batch.set(images.doc(write.id), write.body, {merge: true});
  }
  // Written even at zero, so an array holding nothing but identity-less entries
  // reads as no photos rather than promising one.
  batch.update(doc.ref, {pictureCount: count});
  await batch.commit();
  return {copied: count, skipped};
}

/**
 * Pages every appointment and backfills the ones carrying photos.
 * @return {!Promise<void>}
 */
async function main() {
  const argv = process.argv.slice(2);
  const {db, dryRun} = bootstrapScript(argv, {assertFlags: assertKnownFlags});

  let appointments = 0;
  let withPhotos = 0;
  let copied = 0;
  let unrenderable = 0;

  for await (const doc of scanByName(
      db.collection("appointments"),
      {pageSize: PAGE_SIZE},
  )) {
    appointments += 1;
    const data = doc.data() || {};
    const pictures = Array.isArray(data.pictures) ? data.pictures : [];
    if (pictures.length === 0) continue;
    withPhotos += 1;
    const result = await backfillOne(db, doc, dryRun);
    copied += result.copied;
    unrenderable += result.skipped;
  }

  const prefix = dryRun ? "[dry run] would copy" : "copied";
  console.log(
      `${prefix} ${copied} photos across ${withPhotos} appointments ` +
      `(${appointments} scanned)`);
  if (unrenderable > 0) {
    console.log(
        `skipped ${unrenderable} array entries with no storagePath and no ` +
        `url — these were already unrenderable`);
  }
  if (dryRun) {
    console.log("no writes were made; re-run without --dry-run to apply");
  } else {
    console.log(
        "the `pictures` array was NOT modified — clearing it is " +
        "clear-appointment-picture-arrays.js");
  }
}

// Guarded like `backfill-client-name-with-phone.js`, so `imageDoc` and
// `backfillOne` can be required by jest without `main()` reaching for
// application-default credentials at load.
if (require.main === module) {
  main().then(() => process.exit(0)).catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = {
  imageDoc,
  backfillOne,
};
