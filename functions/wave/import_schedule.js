"use strict";

/**
 * @fileoverview Pure cadence helper for the scheduled Wave import, kept in a
 * plain module (no Storage/Firestore load at require time) so jest can
 * require it directly, unlike the onSchedule module that uses it.
 * @module wave/import_schedule
 */

const DAY_MS = 24 * 60 * 60 * 1000;
const WEEK_MS = 7 * DAY_MS;
const MONTH_MS = 30 * DAY_MS;

/** The only accepted `importSchedule` wire values. */
const SCHEDULE_VALUES = ["off", "weekly", "monthly"];

/**
 * Decides whether a scheduled Wave import should run now.
 * @param {string} schedule One of `off` | `weekly` | `monthly`. Anything
 *   else (including undefined/"") is treated as `off`.
 * @param {?number} lastAutoImportMs Epoch ms of the last successful
 *   auto-import, or null/undefined when it has never run.
 * @param {number} nowMs Current epoch ms.
 * @return {boolean} True when the import is due.
 */
function isImportDue(schedule, lastAutoImportMs, nowMs) {
  let intervalMs;
  if (schedule === "weekly") {
    intervalMs = WEEK_MS;
  } else if (schedule === "monthly") {
    intervalMs = MONTH_MS;
  } else {
    return false; // off / unknown → never
  }
  if (typeof lastAutoImportMs !== "number") return true; // never run yet
  return nowMs - lastAutoImportMs > intervalMs;
}

// ---------------------------------------------------------------------------
// Delta-import window
// ---------------------------------------------------------------------------
//
// Wave filters `customers(modifiedAtAfter:)` server-side, so an import can ask
// for only what changed. `wave/connection.customerDeltaSince` is that
// watermark and `lastFullImportAt` is when the last unfiltered pass ran.
//
// This lives beside `isImportDue` deliberately: both decide "should this
// import run, and over what", off the same doc, and they INTERACT — see the
// note on FULL_RESYNC_INTERVAL_MS.

// How far behind the run's start the watermark is set. Absorbs clock skew
// against Wave and anything edited in the same second the query went out.
const DELTA_OVERLAP_MS = 5 * 60 * 1000;

// How stale the last full pass may get before one is forced.
//
// NOT about deletes — the import has never deleted a local client, so a
// customer removed in Wave keeps its doc either way. It is the backstop for
// `modifiedAt` itself: we trust Wave to bump it for every field we map and
// cannot verify that, so a mapped change it misses would otherwise stay stale
// forever.
//
// CONSEQUENCE, accepted: this is SHORTER than both cadences in this file, and
// `isImportDue` only fires once the cadence has elapsed — so when the
// scheduled import is the only thing running, `lastFullImportAt` is always
// older than this interval by the time it starts, and it resolves to a full
// pass every time. The delta then only ever fires on the interactive sync.
// (Not an invariant: `lastFullImportAt` is shared, so an interactive full pass
// shortly before a scheduled run does let that run go delta. Both outcomes are
// correct — the point is that the scheduled path gets little benefit.)
// Deliberate: a weekly or monthly job paying 7 Wave pages costs nothing, and
// lengthening this past MONTH_MS to "fix" it would trade a real staleness
// guarantee for that non-saving.
const FULL_RESYNC_INTERVAL_MS = 7 * DAY_MS;

/**
 * Decides whether an import runs as a delta, and from when.
 *
 * @param {{deltaSinceMs: ?number, lastFullMs: ?number, nowMs: number}} state
 *   The two `wave/connection` stamps as epoch ms (read them through
 *   `toMillis`), plus the run's start instant.
 * @return {{since: string, reason: string}} `since` is an ISO-8601 instant for
 *   a delta run, or "" for a full one.
 */
function resolveImportWindow({deltaSinceMs, lastFullMs, nowMs}) {
  if (!deltaSinceMs) return {since: "", reason: "no-watermark"};
  if (!lastFullMs || nowMs - lastFullMs >= FULL_RESYNC_INTERVAL_MS) {
    return {since: "", reason: "periodic-full-resync"};
  }
  // A watermark in the future is a clock or data fault, not a valid window —
  // honouring it would silently import nothing, forever.
  if (deltaSinceMs > nowMs) return {since: "", reason: "watermark-ahead"};
  return {since: new Date(deltaSinceMs).toISOString(), reason: "delta"};
}

/**
 * Builds the `wave/connection` patch that advances the watermark after a run.
 *
 * Only ever called after a FULLY SUCCESSFUL import: advancing past a window
 * that was never imported skips every customer changed inside it, permanently
 * and silently, whereas redoing a window is free (the import is idempotent).
 *
 * @param {{startedAtMs: number, wasFull: boolean}} run The run's START instant
 *   — not its end, which would drop anything edited while it was in flight.
 * @return {!Object} Firestore patch.
 */
function watermarkPatch({startedAtMs, wasFull}) {
  const patch = {
    customerDeltaSince: new Date(startedAtMs - DELTA_OVERLAP_MS),
  };
  if (wasFull) patch.lastFullImportAt = new Date(startedAtMs);
  return patch;
}

module.exports = {
  isImportDue,
  SCHEDULE_VALUES,
  resolveImportWindow,
  watermarkPatch,
  FULL_RESYNC_INTERVAL_MS,
  WEEK_MS,
  MONTH_MS,
};
