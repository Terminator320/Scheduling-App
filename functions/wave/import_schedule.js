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

module.exports = {isImportDue, SCHEDULE_VALUES};
