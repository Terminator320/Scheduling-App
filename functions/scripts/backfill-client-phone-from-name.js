#!/usr/bin/env node
// !! SUPERSEDED 2026-08-14 — DO NOT RUN THIS SCRIPT AGAIN. !!
// It already ran against prod (see the "ALREADY RAN AGAINST PROD" note
// below) and its effect was deliberately REVERSED the same cycle. Stripping
// the phone out of `name` and renaming clients to "First Last" is correct
// for the app, but `name` is synced VERBATIM as the Wave customer name
// (`toWaveCustomerInput`, `wave/mappers.js`) — so this also renamed every one
// of those clients IN WAVE, on real invoices, losing the number the
// invoicing workflow identifies customers by. Owner call 2026-08-14: a
// PERSON's `name` becomes their phone number and nothing else, a BUSINESS
// keeps its name, and the APP shows the first/last halves or the business
// name (`ClientNamePolicy`, hand-mirrored as `client_name_utils.js`).
// Re-running THIS script now would redo that damage against every client it
// already touched. The replacement is `backfill-client-name-with-phone.js` —
// read that one, not this one. Full story: the
// `clients/{id}.name` IS WAVE'S CUSTOMER NAME bullet in the root `CLAUDE.md`.
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
// Usage: NONE. `main()` throws and the write loop is gone (see below).
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

// The Firestore write loop was DELETED 2026-08-14, not merely commented out —
// a refusal at the top of a body that still exists is one edit away from being
// removed. `extractPhone` and `patchFor` stay because they are the two pure
// rules, they are jest-tested, and `docs/audits/audit-client-phone-backfill-
// damage.js` reads `extractPhone` to assess what the 2026-08-08 run did. Git
// has the loop if it is ever wanted again.
//
// `assertKnownFlags` stays too, even though `main()` refuses unconditionally
// below — every sibling script in this directory routes through the shared
// `_flags.js` rejection rule, and this one is one tab-completion away from
// being run instead of `backfill-client-name-with-phone.js`.

const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");

/** Bare switches, matched EXACTLY — see the sibling scripts' header. */
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

// A run of digits and the separators a person types between them. The `\d` at
// each end keeps a trailing "(" or "-" out of the match.
const CANDIDATE = /\+?\d[\d\s().-]{7,}\d/g;

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
    if (digits.length === 11 && digits.startsWith("1")) {
      digits = digits.slice(1);
    }
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
 *
 * REFUSES TO RUN. The header's "DO NOT RUN THIS SCRIPT AGAIN" is turned into a
 * failure here rather than left as a comment: this file sits one
 * tab-completion away from the script you actually want
 * (`backfill-client-name-with-phone.js`), and a run would redo the Wave
 * rename against every client the reversal just repaired — on real
 * invoices, unrecoverably from the doc.
 * @return {!Promise<void>}
 */
async function main() {
  // Validated even though every outcome below is a refusal: a caller who
  // passes a genuinely unknown flag should see THAT error, not the
  // superseded-script one, and it keeps this script's argv handling in the
  // same shape as every sibling that shares `_flags.js`.
  assertKnownFlags(process.argv.slice(2));
  throw new Error(
      "SUPERSEDED 2026-08-14 — this script already ran against prod and its " +
      "effect was deliberately reversed. Running it again renames real Wave " +
      "customers. Use functions/scripts/backfill-client-name-with-phone.js.");
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

module.exports = {assertKnownFlags, extractPhone, patchFor};
