#!/usr/bin/env node
// One-off: renders every client's stored `phone`/`mobile` as
// "(514) 555-1234", and re-states `name` for the clients whose name IS their
// number.
//
// WHY: `PhoneInputFormatter` masks a number as it is typed, so anything
// entered in the app is already formatted — but Wave-imported and legacy docs
// hold bare digits ("4506220931"). That was invisible until 2026-08-14, when
// `backfill-client-name-with-phone.js` made a person's `name` their phone
// number VERBATIM: Wave's customer list now mixes "(514) 234-0818" with
// "4506220931" for the same kind of customer.
//
// Fixing `phone` rather than only `name` is deliberate — it is one write
// either way, and the raw digits were also rendering on the client detail
// screen and in the `clientPhone` denormalized onto every appointment.
//
// THE RULE, per doc:
//   1. Format `phone` and `mobile` INDEPENDENTLY, and only when the stored
//      value is a NANP number: ten digits with no "+", or eleven beginning
//      with 1 (that leading 1 is the `+1` country code and is dropped).
//      Everything else is left untouched — see `formatNanpNumber` in
//      `../client_name_utils` for why that bound is the whole safety of
//      this script. It moved there when the Wave import started resolving
//      an imported number the same way, and is re-exported below so this
//      script's own tests still read it off here.
//   2. If `name` is nothing but this client's own number, re-state it from the
//      formatted value. That is the only case where `name` is touched, so a
//      BUSINESS — whose name is its own — can never be renamed here.
//   3. No change on any field -> skip the doc entirely.
//
// Idempotent: formatting an already-formatted number reproduces it exactly, so
// a second run writes nothing.
//
// Usage:
//   For prod:
//     export GOOGLE_APPLICATION_CREDENTIALS=/path/to/prod-service-account.json
//     node functions/scripts/backfill-client-phone-formatting.js --dry-run
//     node functions/scripts/backfill-client-phone-formatting.js
//
//   Options:
//     --dry-run   report what would change, write nothing
//
// AN UNKNOWN ARGUMENT IS A HARD ERROR, for the same reason as its sibling
// script: `--dryrun` would otherwise read as false and take the run LIVE.
//
// Every patched doc fires `waveUpsertCustomer`, which enqueues AND drains in
// the same invocation — so this pushes to Wave at up to a few hundred
// mutations against a 60-calls/min ceiling. RUN IT WHEN THE QUEUE IS QUIET.

const {readFileSync} = require("fs");

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");

const {digitsOf, formatNanpNumber} = require("../client_name_utils");
const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");
// The batched-write loop, shared so `--dry-run` cannot be forgotten at a
// call site — see `_batch.js`.
const {commitInBatches} = require("./_batch");

const BATCH_SIZE = 400;
const SAMPLE_SIZE = 25;

/** Bare switches, matched EXACTLY — see the header. */
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

/**
 * The project this run will write to, for the banner.
 *
 * THE SERVICE-ACCOUNT FILE IS THE CASE THAT MATTERS. `applicationDefault()`
 * reads the project out of that JSON internally and never puts it on
 * `app.options`, so a run authenticated the recommended way printed
 * "(unknown)" — the one line standing between a bulk rewrite and the wrong
 * project, blank precisely when credentials were supplied properly.
 *
 * @param {!Object} app The initialized admin app.
 * @return {string} A project id, or a marker saying it could not be resolved.
 */
function resolveProjectId(app) {
  const fromApp = app.options && app.options.projectId;
  if (fromApp) return fromApp;

  const fromEnv =
    process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT;
  if (fromEnv) return fromEnv;

  const keyFile = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (keyFile) {
    try {
      const parsed = JSON.parse(readFileSync(keyFile, "utf8"));
      if (parsed && parsed.project_id) return parsed.project_id;
    } catch (err) {
      // Reported, not swallowed: an unreadable key file is worth seeing before
      // the run rather than inferring from a blank banner.
      console.error(
          `could not read the project id out of ${keyFile}: ${err.message}`);
    }
  }
  return "(unknown — check your credentials)";
}

/**
 * The patch for one client doc, or null when it needs no change.
 *
 * @param {!Object} data The stored client document.
 * @return {?{phone: (string|undefined), mobile: (string|undefined),
 *   name: (string|undefined)}} A field patch, or null to skip the doc.
 */
function patchFor(data) {
  const patch = {};

  const phone = formatNanpNumber(data.phone);
  if (phone) patch.phone = phone;
  const mobile = formatNanpNumber(data.mobile);
  if (mobile) patch.mobile = mobile;

  // The value each field ENDS this run with — the reformatted one where it
  // changed, otherwise whatever was already stored.
  //
  // COMPARING AGAINST THE FINAL VALUE, NOT THE PATCH, IS THE POINT. Gating the
  // name on `phone` having changed missed the doc whose phone was ALREADY
  // formatted while its name still held raw digits: `formatNanpNumber` returns
  // null there (that is its idempotence), so the name was never re-stated and
  // the two fields stayed disagreeing about the same number. Three docs
  // survived the first prod run that way.
  const finalPhone = phone || String(data.phone || "").trim();
  const finalMobile = mobile || String(data.mobile || "").trim();

  // `name` moves only when it IS this client's number, which is the shape the
  // 2026-08-14 rename leaves on a PERSON. A business's name is its own and is
  // never touched here.
  const name = String(data.name || "").trim();
  const nameDigits = digitsOf(name);
  if (nameDigits && !/[a-z]/i.test(name)) {
    let target = "";
    if (finalPhone && nameDigits === digitsOf(finalPhone)) {
      target = finalPhone;
    } else if (finalMobile && nameDigits === digitsOf(finalMobile)) {
      target = finalMobile;
    }
    if (target && target !== name) patch.name = target;
  }

  return Object.keys(patch).length > 0 ? patch : null;
}

/**
 * Formats every client's stored numbers.
 * @return {!Promise<void>}
 */
async function main() {
  const argv = process.argv.slice(2);
  assertKnownFlags(argv);
  const dryRun = argv.includes("--dry-run");

  const app = initializeApp({credential: applicationDefault()});
  const db = getFirestore();

  // Printed BEFORE anything is read — running a bulk rewrite against the wrong
  // project is the unrecoverable mistake, and this banner is the only defence.
  const target = resolveProjectId(app);
  const emulator = process.env.FIRESTORE_EMULATOR_HOST;
  console.log(
      `${dryRun ? "[dry-run] " : ""}target: ${target}` +
      `${emulator ? ` via emulator ${emulator}` : " (LIVE)"}\n`);

  const snap = await db.collection("clients").get();

  let patched = 0;
  let renamed = 0;
  let reformatted = 0;
  const sample = [];

  const writer = commitInBatches(db, {dryRun, batchSize: BATCH_SIZE});

  for (const doc of snap.docs) {
    const data = doc.data();
    const patch = patchFor(data);
    if (!patch) continue;

    patched += 1;
    if (patch.name) renamed += 1;
    if (patch.phone || patch.mobile) reformatted += 1;
    if (sample.length < SAMPLE_SIZE) {
      // REPORTED PER FIELD, because a patch is not always all three. A
      // name-only patch (the doc whose phone was already formatted) rendered
      // as `"(579) 640-1120" -> ""` under a single from/to line, which reads
      // like the phone is about to be blanked — the opposite of what it does.
      const lines = [];
      if (patch.phone) {
        lines.push(`phone   "${data.phone}" -> "${patch.phone}"`);
      }
      if (patch.mobile) {
        lines.push(`mobile  "${data.mobile}" -> "${patch.mobile}"`);
      }
      if (patch.name) {
        lines.push(`name    "${data.name}" -> "${patch.name}"`);
      }
      sample.push({id: doc.id, lines});
    }

    await writer.stage(doc.ref, patch);
  }
  await writer.flush();

  const tag = dryRun ? "[dry-run] " : "";
  if (sample.length) {
    console.log(`${tag}sample (first ${sample.length}):`);
    for (const s of sample) {
      console.log(`  ${s.id}`);
      for (const line of s.lines) console.log(`    ${line}`);
    }
    console.log("");
  }
  console.log(
      `${tag}clients: ${snap.size} scanned, ${patched} patched — ` +
      `${reformatted} had a number reformatted, ` +
      `${renamed} had their name re-stated`);

  if (!dryRun && patched > 0) {
    console.log(
        `\n${patched} Wave customer pushes are now draining. Let them settle ` +
        "before running an import — see this file's header.");
  }
}

/**
 * Turns the one setup failure that actually happens into an instruction.
 *
 * `applicationDefault()` resolves CREDENTIALS and a PROJECT separately: a
 * service-account JSON carries its project id, but a `gcloud auth
 * application-default login` does not — and a fresh shell loses any
 * `GOOGLE_APPLICATION_CREDENTIALS` that was exported for an earlier run. Both
 * surface as a google-auth stack trace naming neither cause nor cure.
 *
 * @param {*} err The thrown error.
 */
function explain(err) {
  const message = String((err && err.message) || err);
  if (/Unable to detect a Project Id/i.test(message)) {
    console.error(
        "No project id in this shell. Credentials were found, but not a " +
        "project.\n\n" +
        "  PowerShell:  $env:GOOGLE_CLOUD_PROJECT = \"schedulingapp-88727\"\n" +
        "  bash:        export GOOGLE_CLOUD_PROJECT=schedulingapp-88727\n\n" +
        "Or point GOOGLE_APPLICATION_CREDENTIALS at a service-account JSON, " +
        "which carries its own project id.");
    return;
  }
  console.error(err);
}

// Only run when invoked directly, so the rules here are requirable by jest
// without the script reaching for prod credentials.
if (require.main === module) {
  main().catch((err) => {
    explain(err);
    process.exit(1);
  });
}

module.exports = {
  assertKnownFlags,
  explain,
  formatNanpNumber,
  patchFor,
  resolveProjectId,
};
