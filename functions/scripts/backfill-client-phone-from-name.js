#!/usr/bin/env node
// !! SUPERSEDED 2026-08-14 — DO NOT RUN THIS SCRIPT AGAIN. !!
// It already ran against prod (see the "ALREADY RAN AGAINST PROD" note
// below) and its effect was deliberately REVERSED the same cycle. Stripping
// the phone out of `name` and renaming clients to "First Last" is correct
// for the app, but `name` is synced VERBATIM as the Wave customer name
// (`toWaveCustomerInput`, `wave/mappers.js`) — so this also renamed every one
// of those clients IN WAVE, on real invoices, losing the number the
// invoicing workflow identifies customers by. Owner call 2026-08-14: put the
// number back on the end of `name` and let the APP show the first/last
// halves instead (`ClientNamePolicy`, hand-mirrored as `client_name_utils.js`).
// Re-running THIS script now would redo that damage against every client it
// already touched. The replacement is `backfill-client-name-with-phone.js` —
// read that one, not this one. Full story: the
// `clients/{id}.name` IS WAVE'S FIELD bullet in the root `CLAUDE.md`.
// This file is kept only as history; do not "fix" or resurrect it.
//
// One-off: lifts a phone number out of a client's `name`/`businessName` and
// into the `phone` field, then rebuilds `name` from the first/last halves.
//
// WHY this exists: hundreds of legacy clients were entered as
// "Marc Tremblay 514-555-1234" with `phone` left empty. Nothing can dial that
// — not the detail view's Call button, not the `clientPhone` denormalized onto
// each appointment, not the Wave payload. There are too many to fix by hand.
//
// THE RULE, per doc:
//   1. Look for a phone number in `name` and in `businessName` — SEPARATELY,
//      never in the two concatenated. Which field it came from decides step 3.
//   2. No number in either -> skip the doc entirely. Nothing else changes.
//   3. Number found:
//        - set `phone` if it is empty (a typed phone always wins). Either
//          field may supply it — an unreachable client is the whole problem.
//        - set `name` to whichever of the first/last halves exist — but ONLY
//          when the number was in `name`. That is what cleans the number out
//          of the display name, and it is also the only case where the name
//          is known to be junk.
//        - never touch `businessName`. It is a read-only legacy field the app
//          never emits, and `ClientRecord.fromMap`'s name-falls-back-to-
//          businessName half depends on it staying put.
//
// Step 2 is what keeps the blast radius small. A Wave-imported business client
// carries the business in `name` and a contact person in first/last — renaming
// those would replace the business with a person. Only the polluted docs get
// renamed.
//
// The rename takes ONE half when that is all there is (owner call 2026-08-08,
// after the prod dry-run). Requiring both left 39 of 347 docs holding a phone
// number as their display name. It is safe precisely because of step 2: in the
// patched set `name` is only ever the bare number, so there is nothing in it to
// lose. A doc with neither half keeps its name and still gets its phone.
//
// Idempotent: a second run finds no number left in a renamed doc, and a doc
// that already had a phone is not re-patched.
//
// TWO TRIGGERS FIRE ON EVERY PATCHED DOC, both wanted, neither free:
//   - `propagateClientEdits` fans the corrected name/phone onto that client's
//     FUTURE appointments. That is the point — it repairs the denormalized
//     copies too.
//   - `waveUpsertCustomer` enqueues an outbox job AND drains it in the same
//     invocation. The mappedFieldsHash gate means only genuinely-changed docs
//     enqueue, but that can still be a few hundred jobs, each drained by its
//     own trigger against Wave's 60-calls/min ceiling. Run this when the queue
//     is quiet and let it settle before the next scheduled import.
//
// Usage:
//   For prod:
//     $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\prod-service-account.json"
//     node functions/scripts/backfill-client-phone-from-name.js --dry-run
//     node functions/scripts/backfill-client-phone-from-name.js
//
//   For the local emulator:
//     $env:FIRESTORE_EMULATOR_HOST = "localhost:8080"
//     $env:GCLOUD_PROJECT = "schedulingapp-88727"
//     node functions/scripts/backfill-client-phone-from-name.js
//
// Pass --dry-run to report what it would do, with a sample of the before/after
// names, without writing. ALWAYS dry-run against prod first and read the
// sample — a rename is not reversible from here.
//
// !! THIS ALREADY RAN AGAINST PROD ON 2026-08-08, ON THE BUGGY VERSION. !!
// Step 1 was split per field later the same day (code review). The version
// that ran searched `name` and `businessName` JOINED and then renamed `name`
// whichever field the number came from — so a clean business name beside a
// polluted legacy `businessName` was renamed to its CONTACT PERSON, in place,
// unrecoverably from the doc itself.
//   -> AUDITED 2026-08-08 with `audit-client-phone-backfill-damage.js`
//      (read-only): NO client matched the damaged shape, so that run cost
//      nothing. Every polluted client had its number in `name`, the case this
//      script handles correctly. Re-run that audit after any future live run.
// The earlier prod dry-run counts (347 docs / 39 renamable) describe the buggy
// rule and are stale. Re-run --dry-run and re-read the sample before ever
// invoking this again.

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const DRY_RUN = process.argv.includes("--dry-run");
const BATCH_SIZE = 400;
const SAMPLE_SIZE = 25;

// A run of digits and the separators a person types between them. The `\d` at
// each end keeps a trailing "(" or "-" out of the match.
const CANDIDATE = /\+?\d[\d\s().\-]{7,}\d/g;

/**
 * The first dialable 10-digit number in [text], formatted `(514) 555-1234`.
 *
 * Deliberately NARROWER than Dart's `formatPhoneNumber`
 * (lib/core/validators/phone_format.dart), which passes an international `+`
 * number through untouched and appends digits past the tenth verbatim. Those
 * are ambiguities the app tolerates from an admin typing into a field; a bulk
 * rewrite must not guess at them. Anything that is not a clean 10 digits is
 * left for manual handling and counted as `ambiguous`.
 *
 * The exactly-10 threshold is also what stops this matching a street number, a
 * postal code or a year.
 *
 * @param {string} text Free text that may contain a phone number.
 * @return {?string} The formatted number, or null when there is no clean one.
 */
function extractPhone(text) {
  const matches = String(text || "").match(CANDIDATE);
  if (!matches) return null;

  for (const candidate of matches) {
    // An international number has no fixed shape, so bracketing its first
    // three digits as an area code would be wrong. Leave it.
    if (candidate.includes("+")) continue;

    let digits = candidate.replace(/\D/g, "");
    if (digits.length === 11 && digits.startsWith("1")) digits = digits.slice(1);
    if (digits.length !== 10) continue;

    return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
  }
  return null;
}

/**
 * The patch for one client doc, or null when it needs no change.
 *
 * @param {!Object} data The stored client document.
 * @return {?Object} A field patch, or null to skip the doc.
 */
function patchFor(data) {
  const name = String(data.name || "").trim();
  const businessName = String(data.businessName || "").trim();

  // Extracted per FIELD, never from the two joined. Two reasons, both real:
  // the rename below is only safe when the number was in `name` itself, and a
  // space-join can synthesise a match across the boundary (digits ending
  // `name` + digits starting `businessName`) that exists in neither field.
  const inName = extractPhone(name);
  const found = inName || extractPhone(businessName);
  if (!found) return null;

  const patch = {};
  if (!String(data.phone || "").trim()) patch.phone = found;

  // Rename ONLY when the number was in `name`. A Wave-imported business client
  // can hold a clean business in `name` and a number in the legacy
  // `businessName` — renaming that one to its contact person replaces the
  // business with a person, which is the exact loss step 2 exists to prevent,
  // and it is not reversible from here. Lifting its number into an empty
  // `phone` above is still right; touching its display name is not.
  if (inName) {
    const composed = [
      String(data.firstName || "").trim(),
      String(data.lastName || "").trim(),
    ].filter(Boolean).join(" ");
    if (composed && composed !== name) patch.name = composed;
  }

  return Object.keys(patch).length ? patch : null;
}

/**
 * Patches every client doc carrying a phone number in its name.
 * @return {!Promise<void>}
 */
async function main() {
  initializeApp({credential: applicationDefault()});
  const db = getFirestore();
  const snap = await db.collection("clients").get();

  let patched = 0;
  let phoneSet = 0;
  let renamed = 0;
  let skipped = 0;
  const sample = [];
  const ambiguous = [];

  let batch = db.batch();
  let pending = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const patch = patchFor(data);

    if (!patch) {
      skipped += 1;
      // Worth surfacing BY NAME: a doc that clearly holds digits but produced
      // no clean 10-digit number needs a human, and a bare count would leave
      // nobody able to find them.
      // The !extractPhone half is load-bearing: a doc can also reach here
      // having ALREADY been fixed by an earlier run, and its businessName may
      // still legitimately hold the number. Without it, a second run reports
      // every one of those as needing a human.
      const raw = `${data.name || ""} ${data.businessName || ""}`.trim();
      if (!extractPhone(raw) && /\d{7,}/.test(raw.replace(/\D/g, ""))) {
        ambiguous.push({id: doc.id, raw});
      }
      continue;
    }

    patched += 1;
    if (patch.phone) phoneSet += 1;
    if (patch.name) renamed += 1;
    if (sample.length < SAMPLE_SIZE) {
      sample.push({
        id: doc.id,
        name: data.name || "",
        businessName: data.businessName || "",
        to: patch,
      });
    }

    if (DRY_RUN) continue;
    batch.update(doc.ref, patch);
    pending += 1;
    if (pending >= BATCH_SIZE) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (!DRY_RUN && pending > 0) await batch.commit();

  const tag = DRY_RUN ? "[dry-run] " : "";
  if (sample.length) {
    console.log(`${tag}sample (first ${sample.length}):`);
    for (const s of sample) {
      const business = s.businessName ? ` | business: "${s.businessName}"` : "";
      console.log(`  ${s.id}`);
      console.log(`    name: "${s.name}"${business}`);
      console.log(`    ->   ${JSON.stringify(s.to)}`);
    }
    console.log("");
  }
  console.log(
      `${tag}clients: ${snap.size} scanned, ${patched} patched ` +
      `(${phoneSet} phone set, ${renamed} renamed), ${skipped} skipped`);

  if (ambiguous.length > 0) {
    console.log(
        `\n${tag}${ambiguous.length} name(s) hold digits but no clean ` +
        "10-digit number — left alone, these need a human:");
    for (const a of ambiguous) console.log(`  ${a.id}  "${a.raw}"`);
  }
}

// Only run when invoked directly, so `extractPhone`/`patchFor` — the two rules
// here that can destroy data — are requirable by jest without the script
// reaching for prod credentials.
if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = {extractPhone, patchFor};
