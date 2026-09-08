"use strict";

/**
 * @fileoverview The one document-id paging loop the operator scripts share.
 * It was hand-written SIX times across five scripts — identical down to the
 * `if (snap.size < PAGE_SIZE) break` and, in three of them, down to the
 * comment. All six were correct, which is exactly why this needed an owner
 * rather than a fix: these scripts produce the migration and audit NUMBERS
 * this project makes decisions on, and repo history already holds a backfill
 * whose `--dry-run` wrote everything and then threw. A seventh copy is a
 * seventh chance to drop the cursor advance and silently re-scan page one
 * forever, or to drop the short-page break and re-read the last page.
 * The directory already has this convention (`_batch.js`, `_flags.js`,
 * `_project.js`); this is its scan half.
 * @module scripts/_scan
 */

/**
 * Yields every document of [source], paged by document id.
 * @param {!Object} source A CollectionReference or CollectionGroup.
 * @param {{pageSize: number}} options Page size, required — a default here
 * would let a new script inherit a number nobody chose for it.
 * @yields {!Object} Each QueryDocumentSnapshot, in id order.
 */
async function* scanByName(source, options) {
  const pageSize = options && options.pageSize;
  if (!Number.isInteger(pageSize) || pageSize <= 0) {
    throw new Error("scanByName: pageSize must be a positive integer");
  }

  let cursor = null;
  for (;;) {
    let query = source.orderBy("__name__").limit(pageSize);
    if (cursor) query = query.startAfter(cursor);
    const snap = await query.get();
    if (snap.empty) return;

    for (const doc of snap.docs) yield doc;

    // A short page means the collection ran out.
    if (snap.size < pageSize) return;
    cursor = snap.docs[snap.docs.length - 1];
  }
}

module.exports = {scanByName};
