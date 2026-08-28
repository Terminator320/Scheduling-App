#!/usr/bin/env node
// One-off, READ-ONLY: counts appointments stored as a MULTI-DAY run — one
// document whose `startTime`/`endTime` describe a daily window spanning two or
// more work days.
//
// WHY this exists: a multi-day run is one document with ONE `status`, so
// marking day 1 complete closes the whole run. The proposed fix is to book each
// day as its own appointment (linked by `seriesId`, carrying a stored
// day index/count) so each day closes on its own. This count is what decides
// what happens to the runs ALREADY in the database:
//
//   backfill everything      — viable when the total is small
//   backfill only OPEN runs  — a finished run needs no per-day cards, so only
//                              pending/in_progress work has to be split
//   leave them alone         — viable when the total is ~zero, since then the
//                              day-slice machinery only has to survive for
//                              history
//
// The tally is therefore split OPEN vs CLOSED, which is the line those three
// options are drawn on. It also reports:
//
//   photos     — the `images` subcollection belongs to ONE document, so a run
//                split into N docs can only keep its photos on day 1. A run
//                carrying photos is the one shape a backfill degrades.
//   series     — a run already inside a repeating series would have to fan
//                each occurrence into its days, so the two mechanics compose;
//                a non-zero number here is a complexity signal, not a blocker.
//   time off   — `isPersonal && isDayOff`. A week of booked holiday is a
//                multi-day run that nothing wants split into 5 cards, so it is
//                counted apart from real work rather than folded into the
//                total that drives the decision.
//   over cap   — a raw day count above MAX_APPOINTMENT_SPAN_DAYS. Only the
//                console and the Admin SDK can write one (`firestore.rules`
//                bounds client writes), and a backfill must clamp it exactly
//                the way `sliceForDay` does rather than fanning out hundreds
//                of documents.
//
// The day count comes from `day_slice_utils.dayCountOf`, the same server-side
// mirror the widget, the Siri snapshot and the push text already use — so this
// script cannot disagree with them about how long a run is. In particular a
// NIGHT SHIFT (end time at or before start time) counts nights, so 22:00-06:00
// on a single date is ONE day here, not two.
//
// Usage:
//   For prod:
//     export GOOGLE_APPLICATION_CREDENTIALS=/path/to/prod-service-account.json
//     node functions/scripts/count-multi-day-appointments.js
//
//   For the local emulator:
//     export FIRESTORE_EMULATOR_HOST=localhost:8080
//     export GCLOUD_PROJECT=schedulingapp-88727
//     node functions/scripts/count-multi-day-appointments.js
//
//   --verbose  also lists every multi-day run it finds.

"use strict";

const {initializeApp, applicationDefault} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {assertKnownFlags: rejectUnknownFlags} = require("./_flags");
const {printTargetBanner} = require("./_project");
const {
  dayCountOf,
  MAX_APPOINTMENT_SPAN_DAYS,
} = require("../day_slice_utils");
// The one owner of the terminal set; a local copy here is the drift that
// decides an irreversible migration on the wrong open/closed tally.
const {TERMINAL_STATUSES} = require("../time_utils");

const EXACT_FLAGS = ["--verbose"];

/**
 * Rejects any argument this script does not recognize. The rule itself lives
 * in the shared `_flags.js` — this wrapper only supplies the flag list.
 * @param {!Array<string>} argv Arguments after the node + script paths.
 */
function assertKnownFlags(argv) {
  rejectUnknownFlags(argv, {exact: EXACT_FLAGS});
}

// Read-only, so this is purely a round-trip dial rather than a write bound.
const PAGE_SIZE = 500;


/**
 * Scans every appointment and tallies the multi-day runs.
 * @param {!Object} db The Firestore handle.
 * @param {boolean} verbose Whether to list each multi-day run.
 * @return {!Promise<!Object>} The tally.
 */
async function countMultiDay(db, verbose) {
  const tally = {
    scanned: 0,
    multiDay: 0,
    open: 0,
    closed: 0,
    openWorkDays: 0,
    timeOff: 0,
    openTimeOff: 0,
    withPhotos: 0,
    inSeries: 0,
    overCap: 0,
    longest: 0,
    // day count -> how many runs, for the runs that would actually be split.
    openHistogram: new Map(),
  };
  let cursor = null;

  for (;;) {
    let query = db.collection("appointments")
        .orderBy("__name__")
        .limit(PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);

    const snap = await query.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      tally.scanned += 1;
      const data = doc.data() || {};

      // Unclamped on purpose: the raw count is what says whether a document
      // exceeds the cap at all, and `overCap` is one of the things a backfill
      // has to be told about up front.
      const rawDays = dayCountOf(data);
      if (rawDays < 2) continue;

      tally.multiDay += 1;
      if (rawDays > tally.longest) tally.longest = rawDays;
      if (rawDays > MAX_APPOINTMENT_SPAN_DAYS) tally.overCap += 1;

      const status = String(data.status || "").trim().toLowerCase();
      const isClosed = TERMINAL_STATUSES.has(status);
      // The derived `isTimeOff`, never the raw `isDayOff` flag — a client
      // visit carrying a stray flag from a console edit is still real work.
      const isTimeOff = data.isPersonal === true && data.isDayOff === true;
      const photos = Number(data.pictureCount) || 0;
      const seriesId = String(data.seriesId || "").trim();

      if (isTimeOff) tally.timeOff += 1;
      if (isClosed) {
        tally.closed += 1;
      } else {
        tally.open += 1;
        if (isTimeOff) {
          tally.openTimeOff += 1;
        } else {
          const days = Math.min(rawDays, MAX_APPOINTMENT_SPAN_DAYS);
          tally.openWorkDays += days;
          tally.openHistogram.set(
              days, (tally.openHistogram.get(days) || 0) + 1);
          if (photos > 0) tally.withPhotos += 1;
          if (seriesId !== "") tally.inSeries += 1;
        }
      }

      if (verbose) {
        const marks = [
          isClosed ? "closed" : "OPEN",
          isTimeOff ? "time off" : "work",
          photos > 0 ? `${photos} photo(s)` : null,
          seriesId !== "" ? `series ${seriesId}` : null,
          rawDays > MAX_APPOINTMENT_SPAN_DAYS ? "OVER CAP" : null,
        ].filter(Boolean);
        console.log(
            `  ${rawDays}d  appointments/${doc.id}  [${marks.join(", ")}]`);
      }
    }

    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < PAGE_SIZE) break;
  }

  return tally;
}

/**
 * Entry point.
 * @return {!Promise<void>} Resolves when the count has been printed.
 */
async function main() {
  assertKnownFlags(process.argv.slice(2));
  const verbose = process.argv.includes("--verbose");

  const app = initializeApp({credential: applicationDefault()});
  // Read-only, but the banner still prints: knowing which project a number
  // describes is the whole point of reporting one to act on.
  printTargetBanner(app, {dryRun: false});

  const db = getFirestore();
  const t = await countMultiDay(db, verbose);

  console.log(`\nscanned ${t.scanned} appointments`);
  console.log(`multi-day runs (2+ work days): ${t.multiDay}`);
  console.log(`  open (pending/in_progress):  ${t.open}`);
  console.log(`  closed (done/cancelled):     ${t.closed}`);
  console.log(
      `  booked time off (any status): ${t.timeOff}` +
      `${t.openTimeOff > 0 ? `, ${t.openTimeOff} of them open` : ""}`);
  if (t.overCap > 0) {
    console.log(
        `  OVER the ${MAX_APPOINTMENT_SPAN_DAYS}-day cap: ${t.overCap} ` +
        "(console/Admin-SDK writes; a backfill must clamp these)");
  }
  console.log(`  longest run seen: ${t.longest} day(s)`);

  if (t.openHistogram.size > 0) {
    console.log("\nopen WORK runs by length (what a backfill would split):");
    for (const days of [...t.openHistogram.keys()].sort((a, b) => a - b)) {
      console.log(`  ${days} days x ${t.openHistogram.get(days)} run(s)`);
    }
    console.log(
        `  => ${t.openWorkDays} per-day documents would replace ` +
        `${sumCounts(t.openHistogram)} run(s)`);
    if (t.withPhotos > 0) {
      console.log(
          `  ${t.withPhotos} of them carry photos — those can only stay on ` +
          "day 1, since `images` is a per-document subcollection");
    }
    if (t.inSeries > 0) {
      console.log(
          `  ${t.inSeries} of them are already inside a repeating series`);
    }
  }

  if (t.multiDay === 0) {
    console.log(
        "\nZERO multi-day runs: nothing to migrate. The per-day split can " +
        "ship as a create-path change alone, and the day-slice machinery " +
        "only has to survive for documents written before it.");
  } else if (t.open === 0) {
    console.log(
        "\nNo OPEN multi-day runs: every existing one is already closed, so " +
        "splitting history buys nothing. Change the create path and leave " +
        "the closed runs rendering through the day-slice machinery.");
  } else {
    console.log(
        `\n${t.open} open multi-day run(s) still have the all-or-nothing ` +
        "completion problem. Splitting just those is the smallest migration " +
        "that fixes what is actually broken today.");
  }
}

/**
 * Total runs across a histogram.
 * @param {!Map<number, number>} histogram
 * @return {number}
 */
function sumCounts(histogram) {
  let total = 0;
  for (const count of histogram.values()) total += count;
  return total;
}

// Only run when invoked directly. Without this the module ran a PRODUCTION
// scan the moment anything required it, which is why its pure helpers could
// not be tested — and this script's verdict is what authorizes irreversible
// follow-up work.
if (require.main === module) {
  main().then(() => process.exit(0)).catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = {assertKnownFlags};
