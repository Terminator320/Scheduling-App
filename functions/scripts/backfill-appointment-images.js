#!/usr/bin/env node
// One-off: COPIES each appointment's `pictures` array into its
// `appointments/{id}/images` subcollection, and stamps `pictureCount`.
//
// WHY this exists: photos are moving off the parent document. Every appointment
// read carried its whole photo array, and the calendar reads up to 1000
// appointments at a time while only the detail sheet ever shows a photo.
//
// COPY, NEVER MOVE. This script does not touch the `pictures` array, and it
// must not be changed to. The build in the field (1.45.0+72) reads photos from
// that array and knows nothing about the subcollection — clearing it here
// blanks every photo on every phone until it updates. The array is removed at
// the CONTRACT step, by a separate script, once no device still runs a build
// that reads it. That is the same gate the `#compat-1.37.1` shim waited on.
//
// RUN THIS BEFORE the app build that reads the subcollection ships. The client
// prefers the subcollection and falls back to the array, so running late is
// merely a missed optimisation rather than a visible failure — but the counts
// this stamps are what the card's photo indicator reads once the array goes.
//
// IDEMPOTENT twice over: the document ids are derived from each photo
// (`appointment_image_ids.js`, hand-mirrored from the Dart original), so a
// second run overwrites identical documents rather than duplicating them; and
// `pictureCount` is written as an absolute count, never an increment.
//
// ATOMIC PER APPOINTMENT: one appointment's photos and its count go in a single
// batch. That is deliberate, not incidental — the client treats an EMPTY
// subcollection as "not backfilled yet, use the array", so an appointment left
// half-copied would render a partial photo list with no error. All-or-nothing
// per appointment makes that state unreachable.
//
// Usage:
//   For prod:
//     export GOOGLE_APPLICATION_CREDENTIALS=/path/to/prod-service-account.json
//     node functions/scripts/backfill-appointment-images.js
//
//   For the local emulator:
//     export FIRESTORE_EMULATOR_HOST=localhost:8080
//     export GCLOUD_PROJECT=schedulingapp-88727
//     node functions/scripts/backfill-appointment-images.js
//
// Pass --dry-run to report what it would do without writing.

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {appointmentImageDocId} = require("../appointment_image_ids");

const DRY_RUN = process.argv.includes("--dry-run");
// Each appointment costs (photos + 1) writes in one batch. Firestore's limit is
// 500 operations, and the rules cap photos at 100 per appointment, so a page of
// 200 appointments is committed per-appointment rather than merged.
const PAGE_SIZE = 200;

/**
 * The subcollection document for one stored photo map.
 *
 * `url` is carried ONLY when there is no `storagePath`. Photos render from
 * `storagePath` (see `AppointmentImageUrlResolver`), and a persisted download
 * URL is a permanent rules-free token — so a modern entry's url is a credential
 * with no reader and is dropped. A LEGACY entry that has only a url still needs
 * it: dropping that one destroys the only thing that can render the photo.
 * @param {!Object} picture A stored `pictures[]` entry.
 * @return {!Object} The subcollection document body.
 */
function imageDoc(picture) {
  const storagePath = String(picture.storagePath || "").trim();
  const url = String(picture.url || "").trim();
  const doc = {storagePath};
  if (storagePath === "" && url !== "") doc.url = url;
  if (picture.fileName != null) doc.fileName = String(picture.fileName);
  // Round-trip whatever shape the array held. A Timestamp stays one; an
  // ISO string (written by the offline queue's carried-forward entries) is
  // parsed so the subcollection's orderBy('uploadedAt') sorts correctly.
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
 * @return {!Promise<{copied: number, skipped: number}>}
 */
async function backfillOne(db, doc) {
  const data = doc.data() || {};
  const pictures = Array.isArray(data.pictures) ? data.pictures : [];

  const writes = [];
  let skipped = 0;
  for (const picture of pictures) {
    const id = appointmentImageDocId(picture);
    if (id === "") {
      // No storagePath and no url — nothing to render and no legal document
      // id. Counted rather than silently dropped: a non-zero total here means
      // the array holds entries that were already unrenderable.
      skipped += 1;
      continue;
    }
    writes.push({id, body: imageDoc(picture)});
  }

  // `pictureCount` counts what the subcollection actually holds, not what the
  // array claimed — an identity-less entry is not a photo anyone can see, and
  // the card's indicator must not promise one.
  const count = writes.length;
  if (DRY_RUN) return {copied: count, skipped};

  const batch = db.batch();
  const images = doc.ref.collection("images");
  for (const write of writes) {
    batch.set(images.doc(write.id), write.body, {merge: true});
  }
  // Written even at zero, so an array holding nothing but identity-less
  // entries reads as no photos rather than promising one. A photoless
  // appointment never reaches here and keeps no count — absent already
  // parses as 0, and `hasPictures` tests both stores during the migration.
  batch.update(doc.ref, {pictureCount: count});
  await batch.commit();
  return {copied: count, skipped};
}

/**
 * Pages every appointment and backfills the ones carrying photos.
 * @return {!Promise<void>}
 */
async function main() {
  initializeApp({credential: applicationDefault()});
  const db = getFirestore();

  let cursor = null;
  let appointments = 0;
  let withPhotos = 0;
  let copied = 0;
  let unrenderable = 0;

  for (;;) {
    // Ordered by document id — the only field every appointment is guaranteed
    // to have. Ordering by a data field would silently exclude any document
    // missing it, which is exactly how a backfill misses the rows that most
    // need it.
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
      if (pictures.length === 0) continue;
      withPhotos += 1;
      const result = await backfillOne(db, doc);
      copied += result.copied;
      unrenderable += result.skipped;
    }

    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break;
  }

  const prefix = DRY_RUN ? "[dry run] would copy" : "copied";
  console.log(
      `${prefix} ${copied} photos across ${withPhotos} appointments ` +
      `(${appointments} scanned)`);
  if (unrenderable > 0) {
    console.log(
        `skipped ${unrenderable} array entries with no storagePath and no ` +
        `url — these were already unrenderable`);
  }
  if (DRY_RUN) {
    console.log("no writes were made; re-run without --dry-run to apply");
  } else {
    console.log(
        "the `pictures` array was NOT modified — it is still what the " +
        "shipped build reads");
  }
}

// Guarded like `backfill-client-name-with-phone.js`, so `imageDoc` and
// `backfillOne` can be required by jest without `main()` reaching for
// application-default credentials at load. The atomicity this script promises
// is a testable claim; it was the only backfill with no spec.
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
