"use strict";

/**
 * Decide what a client doc is missing for the sort queries to see it.
 *
 * Firestore `orderBy` returns only documents that HAVE the ordered field, so a
 * client with no `jobCount` (recount trigger never ran) or no `createdAt`
 * (pre-2026 import) disappears from the Most jobs / Recently added sorts while
 * still appearing under Name.
 *
 * @param {!Object} data The client document data.
 * @param {*} fallbackCreatedAt Value to stamp when `createdAt` is absent.
 * @return {?Object} The patch to merge, or null when nothing is missing.
 */
function planClientSortPatch(data, fallbackCreatedAt) {
  const patch = {};
  if (data.jobCount === undefined || data.jobCount === null) {
    patch.jobCount = 0;
  }
  if (data.createdAt === undefined || data.createdAt === null) {
    patch.createdAt = fallbackCreatedAt;
  }
  return Object.keys(patch).length === 0 ? null : patch;
}

module.exports = {planClientSortPatch};
