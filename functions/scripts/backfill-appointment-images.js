#!/usr/bin/env node
// One-off: COPIES each appointment's `pictures` array into its
// `appointments/{id}/images` subcollection, and stamps `pictureCount`.
//
// WHY this exists: photos are moving off the parent document. Every appointment
// read carried its whole photo array, and the calendar reads up to 1000
// appointments at a time while only the detail sheet ever shows a photo.
//
// COPY, NEVER MOVE. This script does not touch the `pictures` array, and it
// must not be changed to. Clearing it is `clear-appointment-picture-arrays.js`,
// and keeping the two apart is what makes either one safe to dry-run: a script
// that copied and deleted in one pass would report a coverage it was itself
// about to create. That script REFUSES any appointment this one has not
// covered, so run this first — including a re-run before the clear, since any
// build still writing the array will have added to it since the last pass.
//
// RUN THIS BEFORE the app build that reads the subcollection ships. There is
// no array fallback left in the app, so an appointment this has not reached
// shows no photos at all — and the counts it stamps are what the card's photo
// indicator reads.
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
//
// AN UNKNOWN ARGUMENT IS A HARD ERROR — see `_flags.js`. `--dryrun` or
// `--dry_run` would otherwise silently read as false and take this LIVE
// against `/appointments`.

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore, Timestamp} = require("firebase-admin/firestore");
const {appointmentImageDocId} = require("../appointment_image_ids");
const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");
const {printTargetBanner} = require("./_project");

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

// Each appointment costs (photos + 1) writes in one batch. Firestore's limit is
// 500 operations, and the rules cap photos at 100 per appointment, so a page of
// 200 appointments is committed per-appointment rather than merged.
const PAGE_SIZE = 200;

/**
 * The subcollection document for one stored photo map.
 *
 * **`url` is never carried.** Photos render from bytes fetched off
 * `storagePath`, so a persisted download URL is a permanent rules-free token
 * with no reader. A LEGACY entry holding only a url used to keep it, since
 * that string was the sole handle on its bytes — but a prod count on
 * 2026-08-22 found zero such rows, `firestore.rules` stopped accepting the
 * field, and the caller now SKIPS such an entry rather than writing a document
 * that could never render.
 * @param {!Object} picture A stored `pictures[]` entry.
 * @return {!Object} The subcollection document body.
 */
function imageDoc(picture) {
  const storagePath = String(picture.storagePath || "").trim();
  const doc = {storagePath};
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
      // Nothing this script can write a renderable document for. Two shapes
      // land here: an entry with no storagePath AND no url (no legal document
      // id either), and — since 2026-08-22 — an entry with only a url. The
      // second used to be copied WITH its url, because that string was the
      // sole handle on its bytes; `firestore.rules` no longer accepts the
      // field and the loader no longer resolves one, so copying it now would
      // write a document that can never render, and the Admin SDK bypasses
      // rules so nothing would report it. A prod count on the day the field
      // went found ZERO such rows, so this is a guard against reintroduction
      // rather than a case that fires. Counted, never silently dropped: a
      // non-zero total here needs a person, because clearing that array entry
      // afterwards destroys the only record the photo existed.
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
  // Written even at zero, so an array holding nothing but identity-less
  // entries reads as no photos rather than promising one. A photoless
  // appointment never reaches here and keeps no count — absent parses as 0,
  // which is the right answer for a job that has none.
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
  assertKnownFlags(argv);
  const dryRun = argv.includes("--dry-run");

  const app = initializeApp({credential: applicationDefault()});
  const db = getFirestore();

  // Printed BEFORE the first read — `applicationDefault()` resolves whatever
  // credentials are in the environment, and nothing on the command line says
  // which project that is.
  printTargetBanner(app, {dryRun});

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
      const result = await backfillOne(db, doc, dryRun);
      copied += result.copied;
      unrenderable += result.skipped;
    }

    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break;
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
