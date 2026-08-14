#!/usr/bin/env node
// READ-ONLY audit. Writes nothing, ever. There is no --apply.
//
// !! RUN THIS BEFORE `backfill-client-name-with-phone.js`, NOT AFTER. !!
// This audit works by comparing a client's current `name` against the names
// its PAST appointments still carry. That backfill sets a person's `name` to
// their phone number, at which point every past name differs from the current
// one and the comparison stops discriminating — a damaged client and an intact
// one look identical. Docs already in that state are detected and reported in
// their own bucket rather than being counted as confirmed damage, but the
// evidence is weaker there: only `businessName` and the history values remain.
//
// WHY this exists: `backfill-client-phone-from-name.js` was run against prod on
// 2026-08-08 while it still searched `name` and `businessName` CONCATENATED and
// then renamed `name` from first+last whichever field the number came from. A
// client holding a clean business in `name` and a polluted legacy
// `businessName` was therefore renamed to its CONTACT PERSON:
//
//   before  name: "Plomberie ABC"   businessName: "Plomberie ABC 514-555-1234"
//           firstName: "Luc"        lastName: "Gagnon"
//   after   name: "Luc Gagnon"      businessName: unchanged
//
// The business name is not recoverable from the doc — it was overwritten in
// place and Firestore keeps no history. This script finds the docs that fit
// that shape and proposes what to restore them to, from two independent
// sources, so a human can decide per doc.
//
// RECOVERY SOURCE 1 (strong): a PAST appointment's denormalized `clientName`.
// `propagateClientEdits` only rewrites appointments with work left
// (`hasWorkLeft`, i.e. endTime >= now), so every completed visit still carries
// the name the client had BEFORE the backfill. A past name that differs from
// the current one is near-proof this doc was renamed, and is the exact string
// to restore.
//
// RECOVERY SOURCE 2 (weaker): `businessName` with the phone number stripped.
// Only a guess at the original formatting, but `businessName` was never
// written by the backfill, so its text is intact.
//
// A doc whose past appointments agree with its current name was NOT damaged —
// it legitimately had a person's name all along. Those are reported
// separately so the count you act on is not inflated.
//
// Usage:
//   $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\prod-service.json"
//   node docs/audits/audit-client-phone-backfill-damage.js
//
// Repair is deliberately manual: there are few enough docs to edit by hand in
// the app or the console, and a second bulk rewrite over data a first bulk
// rewrite already damaged is how one bad row becomes two.

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

// This file lives in docs/audits/; the rule it reuses lives with the scripts.
// A bare "./" here threw MODULE_NOT_FOUND on the only tool for assessing the
// 2026-08-08 rename, so it had never actually run from this location.
const {
  extractPhone,
} = require("../../functions/scripts/backfill-client-phone-from-name");
const {digitsOf} = require("../../functions/client_name_utils");

/** Past appointments to sample per suspect client. */
const HISTORY_SAMPLE = 20;

/**
 * `text` with the first clean 10-digit number removed, whitespace tidied.
 *
 * Only used to PROPOSE a restore value for a human to read — never written.
 *
 * @param {string} text Free text that may contain a phone number.
 * @return {string} The text without its number, or the text unchanged.
 */
function withoutPhone(text) {
  const raw = String(text || "");
  const stripped = raw
      .replace(/\+?\d[\d\s().-]{7,}\d/, " ")
      .replace(/\s{2,}/g, " ")
      .replace(/^[\s,;:—-]+|[\s,;:—-]+$/g, "")
      .trim();
  return stripped || raw.trim();
}

/**
 * Whether `name` is nothing but this client's OWN stored number — the shape
 * `backfill-client-name-with-phone.js` leaves behind.
 *
 * Once a doc is in that state this audit can no longer tell a damaged client
 * from an intact one: every past appointment name differs from the current
 * one, so the "CONFIRMED renamed" list would swallow the whole collection.
 *
 * @param {!Object} data The stored client document.
 * @param {string} name The doc's current trimmed name.
 * @return {boolean}
 */
function isOwnNumber(data, name) {
  const digits = digitsOf(name);
  if (!digits) return false;
  return digits === digitsOf(data.phone) || digits === digitsOf(data.mobile);
}

/**
 * The composed first+last name, or "" when neither half is present.
 *
 * @param {!Object} data The stored client document.
 * @return {string} The composed name.
 */
function composedName(data) {
  return [
    String(data.firstName || "").trim(),
    String(data.lastName || "").trim(),
  ].filter(Boolean).join(" ");
}

/**
 * Whether this doc fits the shape the buggy rename left behind.
 *
 * The rename fired when a number was found in the JOINED text and the composed
 * halves differed from `name`. Post-run that leaves: `name` equal to the
 * composed halves, a number still sitting in `businessName` (never written),
 * and no number left in `name`.
 *
 * @param {!Object} data The stored client document.
 * @return {boolean} True when the doc is a candidate for inspection.
 */
function isSuspect(data) {
  const name = String(data.name || "").trim();
  const businessName = String(data.businessName || "").trim();
  const composed = composedName(data);

  if (!name || !composed || name !== composed) return false;
  if (!businessName) return false;
  // The number that triggered the rename has to still be in businessName...
  if (!extractPhone(businessName)) return false;
  // ...and `name` must be clean, or it was never renamed at all.
  if (extractPhone(name)) return false;
  // A business whose name genuinely IS the contact person lost nothing.
  return withoutPhone(businessName) !== name;
}

/**
 * The distinct `clientName` values on this client's PAST appointments.
 *
 * @param {!Object} db Firestore instance.
 * @param {string} clientId The client doc id.
 * @return {!Promise<!Array<string>>} Distinct historical names, newest first.
 */
async function historicalNames(db, clientId) {
  // clientId-only query so the automatic single-field index serves it (the
  // same reason fetchClientHistory has no orderBy).
  const snap = await db.collection("appointments")
      .where("clientId", "==", clientId)
      .limit(200)
      .get();

  const now = Date.now();
  const seen = new Map();
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const end = d.endTime && d.endTime.toMillis ?
      d.endTime.toMillis() :
      (d.startTime && d.startTime.toMillis ? d.startTime.toMillis() : 0);
    // Only settled visits: anything still live was rewritten by
    // propagateClientEdits when the backfill saved, so it echoes the new name.
    if (!end || end >= now) continue;
    const clientName = String(d.clientName || "").trim();
    if (!clientName) continue;
    if (!seen.has(clientName)) seen.set(clientName, end);
  }
  return [...seen.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, HISTORY_SAMPLE)
      .map(([n]) => n);
}

/**
 * Reports every client whose display name the backfill may have overwritten.
 * @return {!Promise<void>}
 */
async function main() {
  initializeApp({credential: applicationDefault()});
  const db = getFirestore();
  const snap = await db.collection("clients").get();

  const suspects = [];
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    if (isSuspect(data)) suspects.push({id: doc.id, data});
  }

  console.log(`Scanned ${snap.size} client(s).`);
  if (suspects.length === 0) {
    console.log("No client matches the damaged shape. Nothing to repair.");
    return;
  }

  const damaged = [];
  const unchanged = [];
  const renamed = [];
  for (const s of suspects) {
    const past = await historicalNames(db, s.id);
    const current = String(s.data.name || "").trim();
    // Its `name` is already just its own number, so this audit's whole
    // discriminator is gone — see the ordering banner at the top of the file.
    if (isOwnNumber(s.data, current)) {
      renamed.push({...s, past});
      continue;
    }
    const differing = past.filter((n) => n !== current);
    (differing.length > 0 ? damaged : unchanged).push({...s, past, differing});
  }

  console.log(
      `\n${damaged.length} client(s) CONFIRMED renamed — a past appointment ` +
      "still carries a different name:");
  for (const d of damaged) {
    console.log(`\n  ${d.id}`);
    console.log(`    now            "${d.data.name}"`);
    const wasList = d.differing.map((n) => `"${n}"`).join(", ");
    console.log(`    was (history)  ${wasList}`);
    console.log(`    businessName   "${d.data.businessName}"`);
    console.log(`    → restore to   "${withoutPhone(d.data.businessName)}"  ` +
      "(or the history value above, if they disagree)");
  }

  if (renamed.length > 0) {
    console.log(
        `\n!! ${renamed.length} client(s) fit the shape but their \`name\` is ` +
        "ALREADY just their phone number, so this audit cannot tell whether " +
        "they were damaged: every past appointment name differs from a bare " +
        "number. `backfill-client-name-with-phone.js` has run over these. " +
        "Recover them from `businessName` and the history values below, by " +
        "hand:");
    for (const r of renamed) {
      const wasList = r.past.map((n) => `"${n}"`).join(", ");
      console.log(`  ${r.id}  now "${r.data.name}"  ` +
        `businessName "${r.data.businessName}"  was ${wasList || "(none)"}`);
    }
  }

  if (unchanged.length > 0) {
    console.log(
        `\n${unchanged.length} client(s) fit the shape but have NO past ` +
        "appointment disagreeing with the current name. Either they were " +
        "always named for the contact person, or they have no settled " +
        "history to check against — read these before touching them:");
    for (const u of unchanged) {
      console.log(`  ${u.id}  name "${u.data.name}"  ` +
        `businessName "${u.data.businessName}"  ` +
        `(${u.past.length} past name(s) seen)`);
    }
  }

  console.log(
      "\nRepair by hand, in the app or the console. Editing a client fires " +
      "propagateClientEdits and waveUpsertCustomer, so do it while the Wave " +
      "queue is quiet.");
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = {isSuspect, withoutPhone, composedName};
