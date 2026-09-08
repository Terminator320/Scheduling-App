#!/usr/bin/env node
// One-off, READ-ONLY: counts `appointments/{id}/images` documents that carry a
// `url` and no `storagePath`.

"use strict";

const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");
const {scanByName} = require("./_scan");
const {bootstrapScript} = require("./_project");

const EXACT_FLAGS = ["--verbose"];

/**
 * Rejects any argument this script does not recognize.
 * @param {!Array<string>} argv Arguments after the node + script paths.
 */
function assertKnownFlags(argv) {
  rejectUnknownFlags(argv, {exact: EXACT_FLAGS});
}

// Read-only, so this is purely a round-trip dial rather than a write bound.
const PAGE_SIZE = 500;

/**
 * Counts the legacy documents across every appointment.
 * @param {!Object} db The Firestore handle.
 * @param {boolean} verbose Whether to list each affected appointment id.
 * @return {!Promise<{scanned: number, legacy: number, orphans: number}>} The
 * tally. `orphans` are documents with NEITHER a storagePath nor a url —
 * they can never be rendered and the clear script refuses them, so they are
 * worth surfacing here rather than leaving for that run to discover.
 */
async function countLegacyUrls(db, verbose) {
  let scanned = 0;
  let legacy = 0;
  let orphans = 0;

  for await (const doc of scanByName(
      db.collectionGroup("images"),
      {pageSize: PAGE_SIZE},
  )) {
    scanned += 1;
    const data = doc.data() || {};
    const storagePath = String(data.storagePath || "").trim();
    const url = String(data.url || "").trim();
    // Both branches below name the document, so `doc.ref.parent.parent` — the
    // appointment, which is what an operator needs to act on one of these — is
    // resolved once for the pair.
    const appointmentId =
        doc.ref.parent.parent ? doc.ref.parent.parent.id : "(unknown)";
    const path = `appointments/${appointmentId}/images/${doc.id}`;

    // The two halves of ONE classification of a document with no storagePath,
    // spelled side by side so neither can drift from the other: a url makes it
    // a legacy permanent link, no url makes it unrenderable, and the clear
    // script refuses an appointment on the second.
    if (storagePath !== "") continue;
    if (url !== "") {
      legacy += 1;
      if (verbose) console.log(`  legacy url: ${path}`);
    } else {
      orphans += 1;
      console.log(`  NO IDENTITY (neither storagePath nor url): ${path}`);
    }
  }

  return {scanned, legacy, orphans};
}

/**
 * Counts the `url` strings still sitting in parent `pictures[]` arrays.
 * @param {!Object} db The Firestore handle.
 * @param {boolean} verbose Whether to list each affected appointment id.
 * @return {!Promise<{appointments: number, withArray: number, urls: number}>}
 * The tally.
 */
async function countArrayUrls(db, verbose) {
  let appointments = 0;
  let withArray = 0;
  let urls = 0;

  for await (const doc of scanByName(
      db.collection("appointments"),
      {pageSize: PAGE_SIZE},
  )) {
    appointments += 1;
    const data = doc.data() || {};
    const pictures = Array.isArray(data.pictures) ? data.pictures : [];
    if (pictures.length === 0) continue;
    withArray += 1;

    const carried = pictures.filter(
        (p) => String((p && p.url) || "").trim() !== "").length;
    urls += carried;
    if (carried > 0 && verbose) {
      console.log(`  ${carried} array url(s): appointments/${doc.id}`);
    }
  }

  return {appointments, withArray, urls};
}

/**
 * Entry point.
 * @return {!Promise<void>} Resolves when the count has been printed.
 */
async function main() {
  const argv = process.argv.slice(2);
  // Read-only: `--dry-run` is not in this script's flag allowlist, so `dryRun`
  // comes back false and the banner carries no misleading "[dry-run]" prefix —
  // see `bootstrapScript`.
  const {db} = bootstrapScript(argv, {assertFlags: assertKnownFlags});
  const verbose = argv.includes("--verbose");
  const {scanned, legacy, orphans} = await countLegacyUrls(db, verbose);
  const array = await countArrayUrls(db, verbose);

  console.log(`\nscanned ${scanned} image documents`);
  console.log(`legacy url-only (url set, no storagePath): ${legacy}`);
  if (orphans > 0) {
    console.log(`no identity at all (neither field): ${orphans}`);
  }
  console.log(
      `\nscanned ${array.appointments} appointments; ` +
      `${array.withArray} still carry a pictures[] array, ` +
      `holding ${array.urls} url(s)`);

  if (legacy === 0) {
    console.log(
        "\nZERO url-only image documents: dropping `url` from the images " +
        "rules allowlist strands no bytes, which is what S1 asked.");
  } else {
    console.log(
        `\n${legacy} url-only image document(s) remain: those bytes have NO ` +
        "other handle, so re-home them to a storagePath before the field " +
        "goes. Re-run with --verbose to list them.");
  }

  // Deliberately a SECOND sentence.
  if (array.urls === 0) {
    console.log(
        "ZERO array urls: no permanent rules-free link remains in the " +
        "database at all.");
  } else {
    console.log(
        `${array.urls} permanent rules-free link(s) STILL READABLE off the ` +
        "appointment documents, with no revocation path since " +
        "rotateAssignedImageTokens was deleted. Until " +
        "clear-appointment-picture-arrays.js has run, any claim that none " +
        "remains is about the SUBCOLLECTION only.");
  }
}

// Only run when invoked directly.
if (require.main === module) {
  main().then(() => process.exit(0)).catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = {assertKnownFlags, countLegacyUrls, countArrayUrls};
