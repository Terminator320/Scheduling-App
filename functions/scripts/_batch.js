/**
 * The batched-write loop every bulk backfill in this directory needs.
 *
 * Shared for the same reason `_flags.js` is: this is the code that performs
 * unattended, irreversible writes against prod, and it was hand-spelled — the
 * `let batch / pending / commit / reset / tail-commit / dryRun continue` body
 * byte-identical but for the constant — in four scripts at once. Four copies
 * means a fix has to be found four times, and a fifth script inherits
 * whichever copy gets pasted. Per-script config (`BATCH_SIZE`, what counts as
 * a change, what gets reported) deliberately stays with the script.
 *
 * **`dryRun` is enforced HERE, not at the call site.** That is the whole
 * safety argument: a script cannot forget the `if (dryRun) continue` that
 * guards its writes, because staging is what checks it. The failure this
 * prevents has happened in this directory before — a backfill whose
 * `--dry-run` wrote everything and then threw.
 */

// Firestore's hard cap on operations in one `WriteBatch`.
const MAX_BATCH_SIZE = 500;

/**
 * Opens a batched writer over `db`.
 *
 * @param {!Object} db Firestore instance (needs `.batch()`).
 * @param {{dryRun: (boolean|undefined), batchSize: (number|undefined)}=} opts
 *   `dryRun` makes every `stage` a no-op; `batchSize` defaults to Firestore's
 *   500-op cap and may not exceed it.
 * @return {{stage: function(!Object, !Object): !Promise<void>,
 *           flush: function(): !Promise<void>}}
 */
function commitInBatches(db, opts) {
  const {dryRun = false, batchSize = MAX_BATCH_SIZE} = opts || {};
  if (!Number.isInteger(batchSize) || batchSize < 1 ||
      batchSize > MAX_BATCH_SIZE) {
    throw new RangeError(
        `batchSize must be an integer in [1, ${MAX_BATCH_SIZE}]`);
  }

  let batch = null;
  let pending = 0;

  /**
   * Commits the open batch, if there is one, and starts a fresh one.
   * @return {!Promise<void>}
   */
  async function commit() {
    if (pending === 0) return;
    const open = batch;
    // Cleared BEFORE the await: a throw must not leave a half-committed batch
    // that a later `flush()` would resend.
    batch = null;
    pending = 0;
    await open.commit();
  }

  /**
   * Queues one operation against the open batch, committing at `batchSize`.
   *
   * The single place `dryRun` is honoured — every public `stage*` below is a
   * thin wrapper, so a new operation type cannot acquire its own copy of the
   * check and get it wrong.
   *
   * @param {function(!Object): void} apply Runs the op on the batch.
   * @return {!Promise<void>}
   */
  async function stageOp(apply) {
    if (dryRun) return;
    if (!batch) batch = db.batch();
    apply(batch);
    pending += 1;
    if (pending >= batchSize) await commit();
  }

  return {
    /**
     * Queues one `update`. A no-op under `dryRun`.
     * @param {!Object} ref Document reference.
     * @param {!Object} patch Fields to update.
     * @return {!Promise<void>}
     */
    stage(ref, patch) {
      return stageOp((b) => b.update(ref, patch));
    },

    /**
     * Queues one `set`. A no-op under `dryRun`.
     *
     * Separate from [stage] because `set` REPLACES the document where
     * `update` merges — `backfill.js` rewrites whole bridge rows, and routing
     * that through an `update` would leave a stale field behind on a row
     * whose shape changed.
     *
     * @param {!Object} ref Document reference.
     * @param {!Object} body The full document body.
     * @return {!Promise<void>}
     */
    stageSet(ref, body) {
      return stageOp((b) => b.set(ref, body));
    },

    /**
     * Queues one `delete`. A no-op under `dryRun`.
     *
     * This is the operation the module's safety argument is really about:
     * a field patch written by a forgotten `--dry-run` guard is re-runnable,
     * a delete is not. `backfill.js --prune-orphans` is its only caller and
     * was the one destructive write in this directory still guarding itself.
     *
     * @param {!Object} ref Document reference.
     * @return {!Promise<void>}
     */
    stageDelete(ref) {
      return stageOp((b) => b.delete(ref));
    },

    /**
     * Commits whatever is still queued. Every caller must await this after
     * its loop, or the tail of the run is silently dropped.
     * @return {!Promise<void>}
     */
    flush() {
      return commit();
    },
  };
}

module.exports = {commitInBatches, MAX_BATCH_SIZE};
