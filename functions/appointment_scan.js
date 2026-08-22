"use strict";

// One bounded appointment-window query, shared by the three scheduled sweeps.
//
// Each of them wants the same thing — open jobs whose `startTime`/`endTime`
// falls in a window, newest or oldest first, capped, with a warn when the cap
// truncates — and each had its own ~15-line copy. The copies had already
// drifted: two mapped their snapshot with the shared `recordOf` while
// `travel_utils.js` re-spelled the mapper body inline, twice.
//
// The caller keeps everything that legitimately differs — its own status set
// (`PENDING_STATUSES` is deliberately narrower than `OPEN_STATUSES`), its own
// cap, its own ordering direction and, most importantly, its own CONSEQUENCE
// sentence, because "oldest jobs deferred to a later run" and "some crews may
// not receive a digest" are different operational facts. Only the query and
// the warn-at-cap mechanism are shared. Same split as `pageToCap` on the Dart
// side.
//
// Pure with respect to Firestore setup: `db` is injected, nothing is resolved
// at load, so this module is safe to `require` from a test.

const {recordOf} = require("./notification_policy");

/**
 * Reads one capped window of appointments and warns when the cap truncates it.
 *
 * The ORDERING is not cosmetic at any call site. Firestore orders by the
 * inequality field ascending unless told otherwise, so a descending window
 * spends its cap on the newest jobs and an ascending one on the oldest — and
 * which of those is right differs per sweep. Get it wrong and the cap silently
 * discards exactly the jobs the sweep exists for.
 *
 * @param {!Object} db Firestore handle.
 * @param {{statuses: !Array<string>, field: string, lo: !Date,
 *   loOp: (string|undefined), hi: !Date, hiOp: (string|undefined),
 *   descending: (boolean|undefined), cap: number, logger: ?Object,
 *   label: string, consequence: string}} options
 * @return {!Promise<!Array<!Object>>} Plain appointment records.
 */
async function scanAppointmentWindow(db, options) {
  const {
    statuses,
    field,
    lo,
    loOp = ">",
    hi,
    hiOp = "<=",
    descending = false,
    cap,
    logger,
    label,
    consequence,
  } = options;

  const snap = await db
      .collection("appointments")
      .where("status", "in", statuses)
      .where(field, loOp, lo)
      .where(field, hiOp, hi)
      .orderBy(field, descending ? "desc" : "asc")
      .limit(cap)
      .get();

  if (snap && snap.size === cap && logger) {
    logger.warn(`${label}: candidate cap hit; ${consequence}`, {cap});
  }

  return ((snap && snap.docs) || []).map(recordOf);
}

module.exports = {
  scanAppointmentWindow,
};
