#!/usr/bin/env node
// READ-ONLY audit. Writes nothing, ever. There is no --apply.
//
// WHY this exists: `backfill-client-name-with-phone.js` ran against prod on
// 2026-08-14 and renamed 504 clients' `name` to their phone number. It skips
// anything `looksLikeBusinessName` recognises, but that is a HEURISTIC over a
// collection where the Wave import sets no `type`, so a business whose name
// carries no digit and no company token — "Yokohama" was the one we caught —
// is renamed like a person. On live Wave invoices.
//
// The run printed only the FIRST 25 of the 504 as a sample. This lists all of
// them, so the check is over the whole set rather than whichever few sorted to
// the top by document id.
//
// THE OLD NAME IS RECOVERABLE, FOR NOW. `propagateClientEdits` only rewrites
// appointments that still have work left (`hasWorkLeft`, endTime >= now), so
// every SETTLED visit still carries the `clientName` the client had before the
// rename. That is the only copy left — `name` was overwritten in place and
// Firestore keeps no history. A client with no past appointment has no
// evidence at all and is reported separately.
//
// It ranks the ones most likely to be wrong first, so the top of the list is
// where the reading effort goes:
//   1. LIKELY BUSINESS — the remembered name has no first/last behind it and
//      does not look like a person's name. These are the Yokohamas.
//   2. NO EVIDENCE — renamed, but no settled visit to remember anything.
//   3. LOOKS FINE — the remembered name matches the first/last halves on the
//      doc, which is what a person looks like.
//
// Usage:
//   $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\prod-service.json"
//   node docs/audits/audit-renamed-client-names.js
//
// Repair is deliberately manual, in the Firebase console: set `name` back and
// set `type` to `commercial`, which is what stops any future save renaming it
// again. The write fires `waveUpsertCustomer`, so Wave gets the name back
// within seconds. Do NOT bulk-rewrite data a bulk rewrite already touched.

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

// This file lives in docs/audits/; the rule it reuses lives with the functions.
const {
  digitsOf,
  looksLikeBusinessName,
} = require("../../functions/client_name_utils");
const {toMillis} = require("../../functions/time_utils");

/**
 * Past appointments to read per candidate client.
 *
 * Small because the scan is ORDERED newest-first — it takes the latest settled
 * visits rather than an arbitrary slice. Matches
 * `functions/scripts/restore-client-name-halves.js`.
 */
const HISTORY_SCAN = 25;

/**
 * Whether `name` is nothing but this client's OWN stored number — the shape
 * the rename leaves behind.
 *
 * Compared as DIGITS so the stored formatting does not matter: the backfill
 * wrote `phone` verbatim, and that field holds both "(514) 555-1234" and bare
 * "5145551234" across the collection.
 *
 * @param {!Object} data The stored client document.
 * @return {boolean}
 */
function isRenamed(data) {
  const digits = digitsOf(String(data.name || "").trim());
  if (!digits) return false;
  return digits === digitsOf(data.phone) || digits === digitsOf(data.mobile);
}

/**
 * The composed first+last name, or "" when neither half is present.
 *
 * @param {!Object} data The stored client document.
 * @return {string}
 */
function composedName(data) {
  return [
    String(data.firstName || "").trim(),
    String(data.lastName || "").trim(),
  ].filter(Boolean).join(" ");
}

/**
 * The distinct `clientName` values on this client's SETTLED appointments,
 * newest first.
 *
 * @param {!Object} db Firestore instance.
 * @param {string} clientId The client doc id.
 * @return {!Promise<!Array<string>>} Distinct historical names.
 */
async function historicalNames(db, clientId) {
  // ORDERED, and the orderBy is what makes the limit mean anything: without it
  // Firestore falls back to __name__ order, so a busy client's slice can be
  // entirely future visits and the report claims a recoverable name is gone.
  // The (clientId ASC, startTime DESC) composite already exists.
  const now = Date.now();
  const snap = await db.collection("appointments")
      .where("clientId", "==", clientId)
      .where("startTime", "<", new Date(now))
      .orderBy("startTime", "desc")
      .limit(HISTORY_SCAN)
      .get();

  // A Set, not a Map: the query already returns newest-first, so insertion
  // order IS the answer and there is no timestamp left to sort by.
  const seen = new Set();
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const end = toMillis(d.endTime) || toMillis(d.startTime) || 0;
    // Only settled visits: anything still live was rewritten by
    // propagateClientEdits when the rename saved, so it echoes the NEW name.
    if (!end || end >= now) continue;
    const clientName = String(d.clientName || "").trim();
    if (!clientName) continue;
    // A remembered value with no letters in it is another phone number and
    // remembers nothing usable. Kept deliberately identical to
    // restore-client-name-halves.js: this file REPORTS what that one WRITES,
    // and the two rules disagreeing is how an operator reads one set and
    // repairs another.
    if (!/[a-z]/i.test(clientName)) continue;
    // Newest first already, so the first sighting of a name IS its latest.
    seen.add(clientName);
  }

  return [...seen];
}

/**
 * How suspect one renamed client is.
 *
 * The signal for a BUSINESS is the absence of first/last halves: the Wave
 * import fills those from Wave's own first/last fields, which a company
 * customer does not have. A remembered name that matches the halves is the
 * signature of a person and needs no further reading.
 *
 * @param {!Object} data The stored client document.
 * @param {!Array<string>} past Remembered names, newest first.
 * @return {string} One of "business", "none", "fine".
 */
function verdictFor(data, past) {
  if (past.length === 0) return "none";
  const composed = composedName(data);
  if (composed && past.some((n) => n === composed)) return "fine";
  // No halves to be named after, so whatever it was called was not a person's
  // first and last name.
  if (!composed) return "business";
  return "business";
}

/**
 * Lists every client the rename touched, with the name its history remembers.
 * @return {!Promise<void>}
 */
async function main() {
  initializeApp({credential: applicationDefault()});
  const db = getFirestore();
  const snap = await db.collection("clients").get();

  const candidates = [];
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    if (isRenamed(data)) candidates.push({id: doc.id, data});
  }

  console.log(`Scanned ${snap.size} client(s).`);
  console.log(`${candidates.length} carry a phone number as their name.\n`);
  if (candidates.length === 0) return;

  const business = [];
  const none = [];
  const fine = [];
  for (const c of candidates) {
    const past = await historicalNames(db, c.id);
    const row = {...c, past, composed: composedName(c.data)};
    const verdict = verdictFor(c.data, past);
    if (verdict === "business") business.push(row);
    else if (verdict === "none") none.push(row);
    else fine.push(row);
  }

  // The heuristic that let these through in the first place, re-run on the
  // REMEMBERED name — a second opinion, not the same test twice.
  const flagged = business.filter((r) => looksLikeBusinessName(r.past[0]));
  const rest = business.filter((r) => !looksLikeBusinessName(r.past[0]));

  if (flagged.length > 0) {
    console.log(
        `!! ${flagged.length} client(s) whose REMEMBERED name reads as a ` +
        "business. These should not have been renamed — restore `name` and " +
        "set `type` to `commercial`:");
    for (const r of flagged) console.log(`  ${r.id}  "${r.past[0]}"`);
    console.log("");
  }

  console.log(
      `${rest.length} client(s) renamed with NO first/last name behind ` +
      "them. Read this list: a person here simply had no halves on file, but " +
      "a company here is a Yokohama — its name is gone from the doc and only " +
      "the remembered value below can restore it:");
  for (const r of rest) {
    const names = r.past.map((n) => `"${n}"`).join(", ");
    console.log(`  ${r.id}  now "${r.data.name}"  was ${names}` +
      `${r.composed ? `  (halves: "${r.composed}")` : ""}`);
  }

  if (none.length > 0) {
    console.log(
        `\n${none.length} client(s) have NO settled appointment, so nothing ` +
        "remembers what they were called. Their old name is unrecoverable " +
        "from Firestore — check Wave if one of these turns out to matter:");
    for (const r of none) {
      console.log(`  ${r.id}  now "${r.data.name}"` +
        `${r.composed ? `  (halves: "${r.composed}")` : ""}`);
    }
  }

  console.log(
      `\n${fine.length} client(s) look right — their history remembers the ` +
      "same first/last name the doc still carries. Not listed.");
}

main().catch((err) => {
  // `applicationDefault()` resolves CREDENTIALS and a PROJECT separately: a
  // service-account JSON carries its project id, a `gcloud auth
  // application-default login` does not, and a fresh shell loses any exported
  // GOOGLE_APPLICATION_CREDENTIALS. Otherwise this is a stack trace naming
  // neither cause nor cure.
  if (/Unable to detect a Project Id/i.test(String((err && err.message) || err))) {
    console.error(
        "No project id in this shell. Credentials were found, but not a " +
        "project.\n\n" +
        "  PowerShell:  $env:GOOGLE_CLOUD_PROJECT = \"schedulingapp-88727\"\n" +
        "  bash:        export GOOGLE_CLOUD_PROJECT=schedulingapp-88727");
    process.exit(1);
  }
  console.error(err);
  process.exit(1);
});
