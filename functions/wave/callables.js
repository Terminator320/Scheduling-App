const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

const {WAVE_FULL_ACCESS_TOKEN} = require("./auth");
const {graphql, whoami, listBusinesses} = require("./client");
const {importCustomers} = require("./customers");
const {
  enqueueCustomerUpsert,
  drainQueue,
  countQueuedJobs,
  countDeadJobs,
  requeueDeadJobs,
  listOutstandingClientIds,
  shouldEnqueueClientWrite,
} = require("./worker");
const {mappedFieldsHash} = require("./mappers");
const {classifyWaveError} = require("./errors");
const {
  isImportDue,
  SCHEDULE_VALUES,
  resolveImportWindow,
  watermarkPatch,
} = require("./import_schedule");
const {toMillis} = require("../time_utils");

const {
  assertPayloadShape,
  assertAdmin,
  enforceDurableRateLimit,
} = require("../security");

// Accepted automatic-import cadences (mirrors the app's WaveImportSchedule
// enum and the wave/connection field); "off" is the default when absent.
const IMPORT_SCHEDULE_SET = new Set(SCHEDULE_VALUES);

// waveImportCustomers is a heavy one-shot admin op (~650 customers across ~7
// Wave pages), so a modest cap keeps a stuck/retried admin from hammering Wave.
const WAVE_IMPORT_RATE_MAX = 5;
const WAVE_IMPORT_RATE_WINDOW_MS = 60 * 60 * 1000;

// Cadence is a single enum field, so the cap is looser than the import's —
// generous enough that an admin toggling the picker never trips it.
const WAVE_SCHEDULE_RATE_MAX = 20;
const WAVE_SCHEDULE_RATE_WINDOW_MS = 60 * 60 * 1000;
// Caps how many live Wave calls (whoami + listBusinesses) an admin can make.
// The already-connected short-circuit runs first and isn't rate-limited.
const WAVE_BOOTSTRAP_RATE_MAX = 10;

// The Wave business to connect, kept in Secret Manager so the name never
// ships in the app. waveBootstrap uses it whenever the client supplies no
// businessId/businessName.
const WAVE_BUSINESS_NAME = defineSecret("WAVE_BUSINESS_NAME");

// ----- Wave Accounting integration ------------------------------------------
//
// Wires the app's `clients` collection to Wave Accounting customers. The
// `wave/connection` doc holds the selected business id, `waveSyncQueue` is a
// durable outbox drained on a schedule, and these functions are just thin
// wrappers adding auth/admin/rate-limit guards around the `wave/*` modules.

/**
 * Reads the connected Wave `businessId` from the `wave/connection` doc.
 * @return {!Promise<string>} The business id, or "" if not connected.
 */
async function readWaveBusinessId() {
  const snap = await getFirestore().collection("wave").doc("connection").get();
  const data = snap.exists ? snap.data() : null;
  return data && typeof data.businessId === "string" ? data.businessId : "";
}

// Per-instance cache for the drain's connection gate. A found businessId
// caches for the instance's lifetime; a not-connected result only caches for a
// short TTL, so a fresh bootstrap still gets picked up within a few minutes.
const NOT_CONNECTED_CACHE_MS = 5 * 60 * 1000;
let cachedBusinessId = "";
let notConnectedUntilMs = 0;

/**
 * Cached wrapper around readWaveBusinessId for the two automatic drain sites
 * (the `clients` write trigger and the daily sweep). The cache is what keeps a
 * disconnected install from paying a Firestore read on every client edit.
 * @return {!Promise<string>} The business id, or "" if not connected.
 */
async function readWaveBusinessIdCached() {
  if (cachedBusinessId) return cachedBusinessId;
  if (Date.now() < notConnectedUntilMs) return "";
  const businessId = await readWaveBusinessId();
  if (businessId) {
    cachedBusinessId = businessId;
  } else {
    notConnectedUntilMs = Date.now() + NOT_CONNECTED_CACHE_MS;
  }
  return businessId;
}

/**
 * Selects the intended Wave business from the listed businesses — by name
 * when `wantName` is given, else the single business when exactly one exists,
 * never blindly taking the first of several.
 * @param {!Array<{id: string, name: string}>} businesses Listed businesses.
 * @param {string} wantName Configured business name ("" when not set).
 * @return {{id: string, name: string}} The selected business.
 * @throws {HttpsError} not-found when a given name has no match;
 *   failed-precondition when ambiguous (several businesses, no selector).
 */
function selectBusiness(businesses, wantName) {
  const list = Array.isArray(businesses) ? businesses : [];
  if (wantName) {
    // Name match is case-insensitive and whitespace-trimmed, so "acme co"
    // and "  Acme Co  " both match. Id match stays exact since ids are
    // opaque tokens.
    const want = wantName.trim().toLowerCase();
    // We guard `b.name` too — a business with no name would otherwise throw
    // a raw TypeError, which classifyWaveError would turn into a misleading
    // generic Wave failure instead of the intended wave/business-not-found.
    const match = list.find((b) => b && typeof b.name === "string" &&
        b.name.trim().toLowerCase() === want);
    if (!match) throw new HttpsError("not-found", "wave/business-not-found");
    return match;
  }
  if (list.length === 1) return list[0];
  throw new HttpsError("failed-precondition", "wave/business-ambiguous");
}

// waveBootstrap — admin-only, idempotent get-or-create of wave/connection.
const waveBootstrap = onCall(
    {
      secrets: [WAVE_FULL_ACCESS_TOKEN, WAVE_BUSINESS_NAME],
      enforceAppCheck: true,
    },
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      await assertAdmin(req.auth.uid);
      assertPayloadShape(req.data, new Set());

      const db = getFirestore();
      const ref = db.collection("wave").doc("connection");

      // Already-connected doc gets returned unchanged, so this call is safe
      // to make more than once.
      const existing = await ref.get();
      if (existing.exists && existing.data() &&
          typeof existing.data().businessId === "string" &&
          existing.data().businessId) {
        const d = existing.data();
        logger.info("WAVE-BOOT already connected", {
          uid: req.auth.uid,
          businessId: d.businessId,
        });
        return {businessId: d.businessId, businessName: d.businessName || ""};
      }

      // The target business is chosen server-side from the Secret Manager
      // value — the app never names it. The `|| ""` guards against an
      // unset/empty secret throwing on `.trim()`.
      const wantName = (WAVE_BUSINESS_NAME.value() || "").trim();

      // Only the not-yet-connected path (live Wave calls) is rate-limited.
      await enforceDurableRateLimit(
          "wave-bootstrap",
          req.auth.uid,
          WAVE_BOOTSTRAP_RATE_MAX,
          WAVE_IMPORT_RATE_WINDOW_MS,
      );

      // Network calls run outside the transaction — transactions retry, and
      // a Wave mutation must never run twice. whoami() fast-fails a bad
      // token before we bother listing businesses.
      let selected;
      try {
        await whoami();
        const businesses = await listBusinesses();
        selected = selectBusiness(businesses, wantName);
      } catch (e) {
        if (e instanceof HttpsError) throw e;
        const {code, message} = classifyWaveError(e);
        logger.warn("WAVE-BOOT failed", {uid: req.auth.uid, code, message});
        throw new HttpsError(code, message);
      }

      // Transaction set-if-absent so concurrent first calls converge on one
      // connection — the first writer wins, and later writers just return
      // its value.
      const result = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(ref);
        const fd = fresh.exists ? fresh.data() : null;
        if (fd && typeof fd.businessId === "string" && fd.businessId) {
          return {businessId: fd.businessId, businessName: fd.businessName ||
            ""};
        }
        tx.set(ref, {
          businessId: selected.id,
          businessName: selected.name || "",
          bootstrappedAt: FieldValue.serverTimestamp(),
        });
        return {businessId: selected.id, businessName: selected.name || ""};
      });

      logger.info("WAVE-BOOT connected", {
        uid: req.auth.uid,
        businessId: result.businessId,
      });
      return result;
    },
);

const waveGetConnection = onCall(
    {enforceAppCheck: true},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      await assertAdmin(req.auth.uid);
      assertPayloadShape(req.data, new Set());

      const snap = await getFirestore()
          .collection("wave").doc("connection").get();
      const data = snap.exists ? snap.data() : null;
      const businessId = data && typeof data.businessId === "string" ?
        data.businessId : "";
      const businessName = data && typeof data.businessName === "string" ?
        data.businessName : "";
      const rawSchedule = data && typeof data.importSchedule === "string" ?
        data.importSchedule : "off";
      const importSchedule =
        IMPORT_SCHEDULE_SET.has(rawSchedule) ? rawSchedule : "off";

      // Outbox depth, so Settings can say what is still waiting instead of
      // offering a Sync button over an invisible queue. Two `count()`
      // aggregates — billed per 1000 index entries, not per job.
      //
      // ADDITIVE fields: an older build parses this response by name and
      // ignores the rest, so adding to it is safe (the same contract the
      // two-way sync's five `pushed*` fields rely on).
      //
      // Best-effort and reported as `null`, never 0, when the read fails.
      // Zero means "the queue is empty", which is the one thing an admin
      // would act on by NOT pressing Sync — a failed read must not be able to
      // say that. Skipped entirely while disconnected: there is no queue to
      // describe and no reason to pay for two reads.
      let pendingCount = null;
      let failedCount = null;
      if (businessId) {
        try {
          [pendingCount, failedCount] = await Promise.all([
            countQueuedJobs(),
            countDeadJobs(),
          ]);
        } catch (e) {
          logger.warn("WAVE-CONN outbox count failed", {error: String(e)});
        }
      }

      return {
        connected: Boolean(businessId),
        businessId,
        businessName,
        importSchedule,
        pendingCount,
        failedCount,
      };
    },
);

// waveRetryFailedJobs — admin-only recovery for dead-lettered outbox jobs.
//
// A `dead` job is terminal: no drain picks it up again, so that client's data
// diverges from Wave permanently. Before this callable the only way back was
// editing the client again to mint a fresh job, which an admin would have to
// know to do — and would only think to do if they noticed the error badge.
//
// Deliberately a separate, explicit action rather than an automatic requeue:
// a job that died on a `WaveValidationError` will die again, so retrying on a
// timer would spin forever and re-report the same failure. The admin presses
// this once they have fixed the data or the outage has passed.
//
// Rate-limited like every other admin write callable. It drains afterwards so
// the press has a visible effect, best-effort — the requeue is the durable
// part and must be reported even if the push behind it fails.
const WAVE_RETRY_RATE_MAX = 10;
const WAVE_RETRY_RATE_WINDOW_MS = 60 * 60 * 1000;

const waveRetryFailedJobs = onCall(
    {enforceAppCheck: true, secrets: [WAVE_FULL_ACCESS_TOKEN]},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      await assertAdmin(req.auth.uid);
      assertPayloadShape(req.data, new Set());
      await enforceDurableRateLimit(
          "wave-retry", req.auth.uid,
          WAVE_RETRY_RATE_MAX, WAVE_RETRY_RATE_WINDOW_MS);

      const businessId = await readWaveBusinessId();
      if (!businessId) {
        throw new HttpsError("failed-precondition", "wave/not-connected");
      }

      const {requeued, scanned} = await requeueDeadJobs();
      logger.info("WAVE-RETRY requeued dead jobs",
          {uid: req.auth.uid, requeued, scanned});

      // Push them now so the admin sees the result of the press rather than
      // waiting for their next client edit or the daily sweep. Best-effort:
      // the requeue already committed, and reporting it as a failure would be
      // wrong.
      let pushed = null;
      if (requeued > 0) {
        try {
          const drained = await drainQueue({
            businessId,
            batchLimit: SYNC_PUSH_BATCH_LIMIT,
            deadlineMs: Date.now() + SYNC_PUSH_BUDGET_MS,
          });
          pushed = drained.done;
        } catch (e) {
          logger.warn("WAVE-RETRY drain after requeue failed",
              {uid: req.auth.uid, error: String(e)});
        }
      }

      return {requeued, scanned, pushed};
    },
);

// waveSetImportSchedule — admin-only setter for the auto-import cadence on
// the wave/connection doc. No secret, but rate-limited like every other admin
// write callable: defense-in-depth so a compromised admin session can't spin
// the doc. The limit sits AFTER the payload validation, so a burst of
// malformed submissions can't burn a legitimate caller's window.
const waveSetImportSchedule = onCall(
    {enforceAppCheck: true},
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      await assertAdmin(req.auth.uid);
      assertPayloadShape(req.data, new Set(["schedule"]));

      const schedule = req.data && req.data.schedule;
      if (typeof schedule !== "string" || !IMPORT_SCHEDULE_SET.has(schedule)) {
        throw new HttpsError("invalid-argument", "wave/invalid-schedule");
      }
      await enforceDurableRateLimit(
          "wave-schedule",
          req.auth.uid,
          WAVE_SCHEDULE_RATE_MAX,
          WAVE_SCHEDULE_RATE_WINDOW_MS,
      );

      const ref = getFirestore().collection("wave").doc("connection");
      const snap = await ref.get();
      const data = snap.exists ? snap.data() : null;
      if (!data || typeof data.businessId !== "string" || !data.businessId) {
        throw new HttpsError("failed-precondition", "wave/not-bootstrapped");
      }

      await ref.update({importSchedule: schedule});
      logger.info("WAVE-SCHED set", {uid: req.auth.uid, schedule});
      return {schedule};
    },
);

/**
 * Runs an import against the delta watermark and advances it on success.
 *
 * ONE owner for the whole four-step dance — read the stamps, resolve the
 * window, import, advance — because both callers previously hand-copied it and
 * each omission fails silently in its own direction: forget `since` and every
 * run is a full import; forget the patch and the watermark never moves;
 * advance on the failure path and every customer changed inside that window is
 * skipped for good. The unattended `waveScheduledImport` carried the untested
 * copy, which is the one where a mistake is invisible.
 *
 * Does NOT catch — the caller owns error classification and logging, and each
 * has its own (an HttpsError vs. a logged skip). Throwing leaves both stamps
 * untouched, which is the correct failure behaviour.
 *
 * @param {{connectionRef: !Object, connection: !Object, businessId: string,
 *   skipClientIds: !Set<string>, nowMs: number,
 *   extraPatch: (Object|undefined)}}
 *   params `connection` is the already-read doc data; `extraPatch` merges into
 *   the same post-run write so a caller needing its own stamp costs no
 *   second round trip.
 * @return {!Promise<{summary: !Object, window: !Object}>}
 */
async function importWithWatermark({
  connectionRef, connection, businessId, skipClientIds, nowMs, extraPatch,
}) {
  let window = resolveImportWindow({
    deltaSinceMs: toMillis(connection.customerDeltaSince),
    lastFullMs: toMillis(connection.lastFullImportAt),
    nowMs,
  });

  let summary;
  try {
    summary = await importCustomers({
      businessId, graphql, skipClientIds, since: window.since,
    });
  } catch (e) {
    // A delta-only failure is STICKY without this: the watermark stays put,
    // so every retry rebuilds the same delta query and fails the same way
    // until the 7-day resync ages it out — and only the admin-facing sync
    // breaks, since the scheduled run is normally full anyway. One retry as
    // a full import both self-heals that and covers `modifiedAtAfter` itself
    // being wrong, which is not a hypothetical: the query shape was already
    // wrong once against this API.
    if (!window.since) throw e;
    logger.warn("WAVE-CUST delta import failed — retrying as full", {
      error: String(e),
    });
    window = {since: "", reason: "delta-failed-fell-back-to-full"};
    summary = await importCustomers({
      businessId, graphql, skipClientIds, since: "",
    });
  }

  // A run that PROTECTED clients (skipClientIds) did not import them, so the
  // window it just covered is incomplete — advancing past it would hide any
  // Wave-side change to those customers until the next full pass. Holding the
  // watermark makes the next run re-query the same span; that is idempotent
  // and free, and it self-heals as soon as the outbox drains (a dead-lettered
  // job leaves `queued`/`inflight`, so it stops being protected).
  // Unknown counts as NOT covered on purpose: holding the watermark is free
  // (the next run redoes an idempotent window), advancing it wrongly loses
  // changes.
  const covered = summary.skippedPending === 0;

  // `wasFull` comes from the window we just built, not from the summary —
  // routing our own input back out through importCustomers would give the
  // decision two sources and the further-travelled one would win.
  const patch = {
    ...(extraPatch || {}),
    ...(covered ?
      watermarkPatch({startedAtMs: nowMs, wasFull: !window.since}) : {}),
  };
  if (!covered) {
    logger.info("WAVE-CUST watermark held — run protected pending clients", {
      skippedPending: summary.skippedPending,
    });
  }

  // The import already committed. A failure to record the watermark means the
  // next run redoes this window — wasteful, not wrong — so it must not turn a
  // successful sync into an error the admin sees, discarding the push counts
  // with it.
  if (Object.keys(patch).length > 0) {
    try {
      await connectionRef.update(patch);
    } catch (e) {
      logger.error("WAVE-CUST watermark write failed — next run will redo " +
        "this window", {error: String(e)});
    }
  }

  return {summary, window};
}

// The interactive sync drains the outbox itself so it can report what reached
// Wave. Unlike the other two drain sites, the bound here is the ADMIN'S
// PATIENCE, not the function timeout: the client gives up at
// `kWaveSyncTimeoutSeconds` (120, `wave_service.dart` — hand-mirrored, each
// carries a pointer to the other) and a callable cannot be cancelled,
// so anything past that is work the admin has already been told failed — and
// will re-trigger by tapping again. Push therefore gets a small slice and the
// import keeps the rest; the `waveUpsertCustomer` trigger and the daily sweep
// mop up the backlog either way.
//
// The batch limit is sized to what the budget can actually chew: dispatch is
// sequential (claim txn → Wave round trip → outcome txn, ~1s/job), and the
// query fetches batchLimit docs up front, so a limit the deadline can't reach
// just bills reads for jobs it discards. It is also one of three consumers of
// Wave's 60/min ceiling (see DEFAULT_BATCH_LIMIT's sizing note in worker.js) —
// 20/min leaves room.
const SYNC_PUSH_BATCH_LIMIT = 20;
const SYNC_PUSH_BUDGET_MS = 20 * 1000;

/**
 * Pushes pending outbox jobs to Wave for the interactive sync, then counts
 * what is still queued.
 *
 * Best-effort by design: this half is a courtesy — the `waveUpsertCustomer`
 * trigger already pushed each edit as it was made, and the daily sweep retries
 * whatever is left — so a drain failure must not fail the sync the admin asked
 * for. The import that follows is the part allowed to throw. The
 * two steps are caught separately on purpose: the pending count matters MORE
 * when the drain failed, since it is the only thing that then tells the admin
 * work is still outstanding.
 *
 * @param {{businessId: string, uid: string}} params Connected business id and
 *   the calling admin's uid (for the failure log only).
 * @return {!Promise<{created: number, updated: number, pending: number,
 *   failed: number, incomplete: boolean}>} What landed in Wave, what is still
 *   queued, what dead-lettered, and whether the drain itself threw.
 */
async function drainForSync({businessId, uid}) {
  const result =
    {created: 0, updated: 0, pending: 0, failed: 0, incomplete: false};
  try {
    // No `graphql`/`upsertCustomer` — drainQueue defaults to the real Wave
    // client and WAVE_FULL_ACCESS_TOKEN is in scope via the callable's
    // `secrets` binding, same as the other two drain sites below.
    const drained = await drainQueue({
      businessId,
      batchLimit: SYNC_PUSH_BATCH_LIMIT,
      deadlineMs: Date.now() + SYNC_PUSH_BUDGET_MS,
    });
    result.created = drained.created;
    result.updated = drained.updated;
    // Dead-lettered jobs are NOT queued and will never retry, so without
    // this the admin is told "already up to date" about clients that can
    // now only reach Wave by hand.
    result.failed = drained.dead;
  } catch (e) {
    // `incomplete` is what stops the notice reporting an all-zero drain as
    // "everything was already up to date" — a broken push and a quiet queue
    // produce identical counters, and only one of them is good news.
    result.incomplete = true;
    logger.warn("WAVE-CUST sync push failed", {uid, error: String(e)});
  }

  // Counted AFTER the drain, so the number is what the admin still has to
  // wait for. Without it a 3-of-200 drain would report "3 added to Wave" and
  // read as a finished sync.
  try {
    result.pending = await countQueuedJobs();
  } catch (e) {
    result.incomplete = true;
    logger.warn("WAVE-CUST sync pending count failed", {uid, error: String(e)});
  }
  return result;
}

// waveImportCustomers — admin-only two-way sync: push the outbox to Wave,
// then pull Wave customers back into `clients`.
//
// The name is inaccurate and stays anyway. It was first tagged #compat-1.37.1,
// but that tag was wrong about WHY: renaming a deployed callable deletes the
// old name, and EVERY shipped build calls this one — not just the 1.37.1 the
// shim was about. So retiring that shim (2026-08-08) did not unblock a rename,
// and a future one still needs the two-step: deploy the new name alongside,
// ship a build that calls it, then drop the old name once no build calls it.
// Same for wave_service.dart's caller.
const waveImportCustomers = onCall(
    {
      secrets: [WAVE_FULL_ACCESS_TOKEN],
      enforceAppCheck: true,
      timeoutSeconds: 300,
    },
    async (req) => {
      if (!req.auth || !req.auth.uid) {
        throw new HttpsError("unauthenticated", "auth-required");
      }
      await assertAdmin(req.auth.uid);
      assertPayloadShape(req.data, new Set());
      await enforceDurableRateLimit(
          "wave-import",
          req.auth.uid,
          WAVE_IMPORT_RATE_MAX,
          WAVE_IMPORT_RATE_WINDOW_MS,
      );

      const connectionRef =
        getFirestore().collection("wave").doc("connection");
      const connectionSnap = await connectionRef.get();
      const connection =
        (connectionSnap.exists && connectionSnap.data()) || {};
      const businessId = typeof connection.businessId === "string" ?
        connection.businessId : "";
      if (!businessId) {
        throw new HttpsError("failed-precondition", "wave/not-bootstrapped");
      }

      // Captured BEFORE any work: the watermark must cover everything edited
      // while this run was in flight, so it has to come from the start.
      const startedAtMs = Date.now();

      logger.info("WAVE-CUST sync starting", {uid: req.auth.uid, businessId});

      // Push BEFORE pulling. Local edits are the newer truth here — the
      // outbox holds writes the app already accepted — so importing first
      // would overwrite them with the Wave rows they are about to replace.
      const pushed = await drainForSync({businessId, uid: req.auth.uid});

      // Ordering is NOT sufficient on its own. The drain is bounded and only
      // takes jobs already due, so anything it left behind is still a live
      // local edit — and the import would overwrite it AND mark it synced.
      // Resolved after the drain so a job it completed isn't protected for
      // nothing. Best-effort: an empty set on failure means the import
      // behaves as it always did, which is the pre-existing risk, not a new
      // one — but it must be logged, since the cost is silent data loss.
      let skipClientIds = new Set();
      try {
        skipClientIds = await listOutstandingClientIds();
      } catch (e) {
        logger.error("WAVE-CUST outstanding-job read failed — import may " +
          "overwrite un-pushed client edits", {uid: req.auth.uid,
          error: String(e)});
      }

      let summary;
      let window;
      try {
        // Throwing leaves the watermark untouched, so the next run redoes
        // this window. Redoing is free (the import is idempotent); skipping
        // would drop every customer changed inside it, permanently.
        ({summary, window} = await importWithWatermark({
          connectionRef, connection, businessId, skipClientIds,
          nowMs: startedAtMs,
        }));
      } catch (e) {
        const {code, message} = classifyWaveError(e);
        logger.warn("WAVE-CUST import failed", {
          uid: req.auth.uid,
          code,
          message,
        });
        throw new HttpsError(code, message);
      }

      logger.info("WAVE-CUST sync done", {
        window: window.reason,
        uid: req.auth.uid,
        totalCount: summary.totalCount,
        imported: summary.imported,
        updated: summary.updated,
        skippedArchived: summary.skippedArchived,
        skippedPending: summary.skippedPending,
        skippedUnchanged: summary.skippedUnchanged,
        pages: summary.pages,
        delta: summary.delta,
        pushedCreated: pushed.created,
        pushedUpdated: pushed.updated,
        pushedPending: pushed.pending,
        pushedFailed: pushed.failed,
        pushIncomplete: pushed.incomplete,
      });
      // Additive fields only — the 1.37.1 build parses the import half of
      // this response by name and ignores the rest.
      return {
        ...summary,
        pushedCreated: pushed.created,
        pushedUpdated: pushed.updated,
        pushedPending: pushed.pending,
        pushedFailed: pushed.failed,
        pushIncomplete: pushed.incomplete,
      };
    },
);

// waveUpsertCustomer — enqueues a Wave write-back when a client doc's mapped
// fields change, AND pushes it (see the inline drain at the bottom).
// `retry: true` is safe here since the handler is idempotent and hash-guarded:
// `enqueueCustomerUpsert` writes a deterministic `customerUpsert__<clientId>`
// job id with `merge: true`, so a re-run rewrites the same doc.
//
// This is the PRIMARY push path as of 2026-08-13, replacing the deleted
// `waveSyncWorker` scheduler. Draining here rather than on a 5-minute poll is
// both cheaper and faster: an idle day costs nothing instead of 288
// invocations, and an edit reaches Wave in seconds instead of up to five
// minutes. `waveScheduledImport` is the daily safety net for what an
// event-driven push structurally cannot catch — a job that failed and backed
// off, and a lease left stale by a dead instance — since neither produces a
// new client write to ride on.
//
// `timeoutSeconds` is raised off the 60 s default because the drain can sleep
// on Wave's Retry-After; the drain's own budget is a fraction of it so the
// handler always has room to return cleanly.
const TRIGGER_TIMEOUT_SECONDS = 300;
const TRIGGER_DRAIN_BUDGET_MS = 180 * 1000;

// WAVE'S 60-CALLS/MIN CEILING IS PACED BY THESE TWO NUMBERS, and they are the
// only thing pacing it. `dispatchQueuedJobs` dispatches SEQUENTIALLY (claim txn
// → Wave round trip → outcome txn, ~1 s/job), so a single invocation is
// self-limiting at roughly 60 calls/min — which is exactly how the deleted
// `waveSyncWorker` stayed inside the ceiling: `maxInstances: 1` meant one drain
// in flight, ever. A trigger inherits `setGlobalOptions({maxInstances: 10})`
// instead, so without the cap below, ten concurrent client writes each running
// a 20-job drain would burst to ~600 calls/min. That is not hypothetical — a
// bulk backfill (`scripts/backfill-client-phone-from-name.js` warns about a few
// hundred jobs) is precisely the shape that produces it.
//
// Two instances is the compromise: it bounds a burst near Wave's ceiling while
// keeping the ENQUEUE responsive, which `maxInstances: 1` would not — that
// serializes every client write behind whatever drain is in flight, and the
// enqueue is inside the same invocation, so a slow drain would delay the
// durability of the next edit rather than just its push.
//
// This only bounds concurrency because an EVENT-DRIVEN v2 function processes
// one event per instance (`concurrency` is left at the platform default, which
// is 1 for Eventarc triggers). Setting `concurrency` above 1 here would let a
// single instance run several drains at once and silently void the cap.
const TRIGGER_MAX_INSTANCES = 2;
// Small on purpose. This drain runs per client edit; its job is "push THIS
// edit now, and help a little with the backlog", not "clear the queue" — the
// old worker's 30 was sized for a 5-minute cadence, not for one drain per
// write. A backlog is finished by the next edit, the Sync button, or the daily
// sweep, none of which are on a deadline.
const TRIGGER_DRAIN_BATCH_LIMIT = 5;

const waveUpsertCustomer = onDocumentWritten(
    {
      document: "clients/{clientId}",
      retry: true,
      secrets: [WAVE_FULL_ACCESS_TOKEN],
      timeoutSeconds: TRIGGER_TIMEOUT_SECONDS,
      maxInstances: TRIGGER_MAX_INSTANCES,
    },
    async (event) => {
      const beforeSnap = event.data?.before;
      const afterSnap = event.data?.after;
      const after = afterSnap?.exists ? afterSnap.data() : null;

      // On delete, the local doc is just dropped and Wave is left intact —
      // nothing to enqueue.
      if (!after) return;

      const before = beforeSnap?.exists ? beforeSnap.data() : null;
      if (!shouldEnqueueClientWrite(before, after)) return;

      // The mark-pending write below only touches wave.* fields, so when
      // the trigger re-fires on it, mappedFieldsHash is unchanged and
      // shouldEnqueueClientWrite returns false — no second pending-write,
      // no loop.
      const clientId = event.params.clientId;
      const db = getFirestore();

      // We compute the hash once here. shouldEnqueueClientWrite also hashes
      // internally but doesn't expose its result, so this is the one
      // explicit hash computed at the enqueue site.
      const hash = mappedFieldsHash(after);

      // Mark-pending + enqueue land in ONE WriteBatch so a crash between the
      // two can't leave the doc stuck at 'pending' with no queued job (or a
      // queued job with no visible pending state).
      const batch = db.batch();
      batch.update(db.doc("clients/" + clientId), {
        "wave.syncState": "pending",
        "wave.syncError": null,
      });
      // payloadHash is diagnostic only — the worker re-reads the live doc
      // and recomputes the hash before writing, since the doc is the real
      // source of truth.
      await enqueueCustomerUpsert(clientId, {batch, payloadHash: hash});
      try {
        await batch.commit();
      } catch (e) {
        // The batch fails atomically when the doc was deleted before
        // commit, so we fall back to enqueue-only. The worker treats a
        // missing doc as a clean skip, and any other failure just retries
        // via retry:true's idempotent re-run.
        logger.warn("waveUpsertCustomer: batched mark-pending failed; " +
            "enqueueing without it", {clientId, err: e.message});
        await enqueueCustomerUpsert(clientId, {payloadHash: hash});
      }
      logger.debug("waveUpsertCustomer: enqueued", {clientId});

      // Push it now. Everything below is best-effort and MUST NOT throw: the
      // job is already durably queued, so a drain failure is a delay, not a
      // loss — and throwing would re-run the whole handler under `retry: true`
      // for something the retry cannot fix.
      //
      // This cannot loop. `upsertCustomer` writes `wave.*` back onto the
      // client doc, which re-fires this trigger, but `mappedFieldsHash` is
      // unchanged by that write so `shouldEnqueueClientWrite` returns false at
      // the top and the re-fire never reaches here.
      try {
        const businessId = await readWaveBusinessIdCached();
        if (!businessId) {
          logger.debug("waveUpsertCustomer: not connected — queued only",
              {clientId});
          return;
        }
        const summary = await drainQueue({
          businessId,
          batchLimit: TRIGGER_DRAIN_BATCH_LIMIT,
          deadlineMs: Date.now() + TRIGGER_DRAIN_BUDGET_MS,
        });
        logger.info("waveUpsertCustomer: drain done", {
          clientId,
          processed: summary.processed,
          done: summary.done,
          retried: summary.retried,
          dead: summary.dead,
          skipped: summary.skipped,
          reclaimed: summary.reclaimed,
        });
      } catch (e) {
        // Logged at warn, not error: the daily sweep and the Sync button both
        // pick this job up, so the outcome is a late push rather than a lost
        // one.
        logger.warn("waveUpsertCustomer: inline drain failed — job stays " +
            "queued for the daily sweep", {clientId, err: String(e)});
      }
    },
);

// runWaveDaily — the daily Wave job. It does TWO things, and the first
// runs unconditionally:
//
//  1. Drains the outbox (app → Wave). This is the safety net under the
//     event-driven push in `waveUpsertCustomer`, and it exists because two
//     states cannot produce a client write to ride on: a job that failed and
//     is sitting on its `nextAttemptAt` backoff, and a job left `inflight` by
//     an instance that died mid-dispatch (reclaimed by `drainQueue`'s lease
//     pass). Without this they would wait for the next unrelated client edit
//     or for an admin to press Sync. It runs even when `importSchedule` is
//     `off` — that setting governs the PULL, and gating the push on it would
//     mean the default configuration never pushes automatically at all.
//
//  2. Pulls (Wave → app), but only when the configured cadence is due.
//
// The order is also the push-before-pull invariant: an import overwrites every
// mapped field of a linked client AND stamps `wave.lastSyncedHash` from Wave's
// values, so an un-pushed local edit underneath it is not merely overwritten
// but marked synced — silently lost. Draining first, and passing the
// `skipClientIds` protect-list for whatever the drain could not finish, is the
// same belt-and-braces the interactive sync uses. The old
// `waveSyncWorker` scheduler is what made the drain here look redundant;
// it was deleted 2026-08-13.
//
// **It is NOT its own scheduler.** It used to be `waveScheduledImport`, an
// `every 24 hours` `onSchedule`; it now rides `sendDailyJobDigest`
// (`notifications.js`), which was already a daily 18:00 timer carrying the
// Live Activity TTL prune as a rider. Cloud Scheduler bills per job past the
// first three, and this repo had six — this merge is one of the two that
// brought it to three, i.e. inside the free allowance. Exported as a plain
// async function so the digest can call it; keep it that way rather than
// re-promoting it to a timer, and note the caller isolates it in its own
// try/catch so a Wave failure cannot affect the push that already went out.
//
// The drain takes a bounded slice of the caller's budget and leaves the rest
// to the pull below it.
const SWEEP_DRAIN_BUDGET_MS = 180 * 1000;

/**
 * Runs the daily Wave maintenance: drain the outbox, then import if due.
 *
 * Never throws — every failure path inside is caught and logged, because the
 * caller is a user-facing push function whose own work has already completed
 * by the time this runs.
 *
 * @return {!Promise<void>}
 */
async function runWaveDaily() {
  const ref = getFirestore().collection("wave").doc("connection");
  const snap = await ref.get();
  const data = snap.exists ? snap.data() : null;
  const businessId = data && typeof data.businessId === "string" ?
    data.businessId : "";
  if (!businessId) {
    logger.debug("runWaveDaily: not connected — nothing to do");
    return;
  }
  const schedule = data && typeof data.importSchedule === "string" ?
    data.importSchedule : "off";
  // One clock instant for the due check AND the watermark — two Date.now()
  // calls would let them disagree about when this run started.
  const startedAtMs = Date.now();

  // Step 1: drain, ALWAYS — before the due check, so an `off` install
  // still gets its backed-off and stale-leased jobs retried. Isolated so a
  // drain failure cannot skip the import below it, exactly as the digest
  // isolates its TTL prune.
  try {
    const drained = await drainQueue({
      businessId,
      deadlineMs: startedAtMs + SWEEP_DRAIN_BUDGET_MS,
    });
    if (drained.processed > 0 || drained.reclaimed > 0) {
      logger.info("WAVE-SCHED drain done", {
        processed: drained.processed,
        done: drained.done,
        retried: drained.retried,
        dead: drained.dead,
        skipped: drained.skipped,
        reclaimed: drained.reclaimed,
      });
    }
  } catch (e) {
    // Warn, not throw: the import below is still worth running, and
    // `skipClientIds` protects whatever this failed to push.
    logger.warn("WAVE-SCHED drain failed", {error: String(e)});
  }

  if (!isImportDue(schedule, toMillis(data.lastAutoImportAt), startedAtMs)) {
    logger.debug("runWaveDaily: import not due", {schedule});
    return;
  }

  logger.info("WAVE-SCHED import starting", {businessId, schedule});
  let summary;
  let window;
  try {
    // Same protect-list as the interactive sync, and it matters more
    // here: this runs unattended, so a client edit clobbered by it is
    // lost with nobody watching. Read AFTER the drain above, so a job the
    // drain completed isn't protected for nothing — and so anything the
    // drain could not finish (backed off, dead-lettered, or past its
    // budget) is still shielded from the import.
    const skipClientIds = await listOutstandingClientIds();
    // Neither stamp advances on a throw — the cadence retries tomorrow
    // AND the delta window is redone, so nothing edited inside it is
    // skipped. `lastAutoImportAt` rides the same write as the watermark.
    ({summary, window} = await importWithWatermark({
      connectionRef: ref,
      connection: data,
      businessId,
      skipClientIds,
      nowMs: startedAtMs,
      extraPatch: {lastAutoImportAt: FieldValue.serverTimestamp()},
    }));
  } catch (e) {
    const {code, message} = classifyWaveError(e);
    logger.warn("WAVE-SCHED import failed", {code, message});
    return;
  }

  logger.info("WAVE-SCHED import done", {
    window: window.reason,
    imported: summary.imported,
    updated: summary.updated,
    skippedArchived: summary.skippedArchived,
    skippedPending: summary.skippedPending,
    skippedUnchanged: summary.skippedUnchanged,
    pages: summary.pages,
  });
}

module.exports = {
  selectBusiness,
  waveBootstrap,
  waveGetConnection,
  waveSetImportSchedule,
  waveImportCustomers,
  waveRetryFailedJobs,
  waveUpsertCustomer,
  runWaveDaily,
};
