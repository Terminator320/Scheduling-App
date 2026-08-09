const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
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

// Per-instance cache for the scheduled worker's connection gate. A found
// businessId caches for the instance's lifetime; a not-connected result only
// caches for a short TTL, so a fresh bootstrap still gets picked up within a
// few minutes.
const NOT_CONNECTED_CACHE_MS = 5 * 60 * 1000;
let cachedBusinessId = "";
let notConnectedUntilMs = 0;

/**
 * Cached wrapper around readWaveBusinessId for the every-5-minutes scheduler.
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
      return {
        connected: Boolean(businessId),
        businessId,
        businessName,
        importSchedule,
      };
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
// Wave. Unlike waveSyncWorker, the bound here is the ADMIN'S PATIENCE, not the
// function timeout: the client gives up at `kWaveSyncTimeoutSeconds` (120,
// `wave_service.dart` — hand-mirrored, each carries a pointer to the other)
// and a callable cannot be cancelled,
// so anything past that is work the admin has already been told failed — and
// will re-trigger by tapping again. Push therefore gets a small slice and the
// import keeps the rest; waveSyncWorker mops up the backlog either way.
//
// The batch limit is sized to what the budget can actually chew: dispatch is
// sequential (claim txn → Wave round trip → outcome txn, ~1s/job), and the
// query fetches batchLimit docs up front, so a limit the deadline can't reach
// just bills reads for jobs it discards. It is also a second consumer of
// Wave's 60/min ceiling alongside the every-5-minute worker (see
// DEFAULT_BATCH_LIMIT's sizing note in worker.js) — 20/min leaves room.
const SYNC_PUSH_BATCH_LIMIT = 20;
const SYNC_PUSH_BUDGET_MS = 20 * 1000;

/**
 * Pushes pending outbox jobs to Wave for the interactive sync, then counts
 * what is still queued.
 *
 * Best-effort by design: this half is a courtesy — `waveSyncWorker` drains the
 * same queue every 5 minutes — so a drain failure must not fail the sync the
 * admin asked for. The import that follows is the part allowed to throw. The
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
    // `secrets` binding, same as waveSyncWorker below.
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
// fields change. `retry: true` is safe here since the handler is idempotent
// and hash-guarded.
const waveUpsertCustomer = onDocumentWritten(
    {document: "clients/{clientId}", retry: true},
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
    },
);

// waveSyncWorker — drains the Wave outbox on a schedule. It's single-instance
// for simple pacing; the lease reaper and transactional claim are what
// actually handle robustness.
// timeoutSeconds is raised to 540 because a worst-case 30-job drain (with
// Retry-After sleeps) would blow past the default 60s. drainQueue gets a
// deadline at ~70% of the timeout, so it stops claiming new jobs in time to
// finish writing outcomes cleanly.
const WORKER_TIMEOUT_SECONDS = 540;
const WORKER_DEADLINE_FRACTION = 0.7;

const waveSyncWorker = onSchedule(
    {
      schedule: "every 5 minutes",
      secrets: [WAVE_FULL_ACCESS_TOKEN],
      maxInstances: 1,
      timeoutSeconds: WORKER_TIMEOUT_SECONDS,
    },
    async () => {
      // Cheap gate that skips the run entirely while Wave isn't connected.
      // The cached read avoids a Firestore read on every run for idle
      // installs.
      const businessId = await readWaveBusinessIdCached();
      if (!businessId) {
        logger.debug("waveSyncWorker: not bootstrapped — nothing to do");
        return;
      }
      // We intentionally don't pass `graphql`/`upsertCustomer` here —
      // drainQueue defaults to the real Wave client, and
      // WAVE_FULL_ACCESS_TOKEN is already in scope via this function's
      // `secrets` binding.
      const deadlineMs = Date.now() +
        WORKER_TIMEOUT_SECONDS * 1000 * WORKER_DEADLINE_FRACTION;
      const summary = await drainQueue({businessId, deadlineMs});
      logger.info("waveSyncWorker: drain done", {
        processed: summary.processed,
        done: summary.done,
        retried: summary.retried,
        dead: summary.dead,
        skipped: summary.skipped,
        reclaimed: summary.reclaimed,
      });
    },
);

// waveScheduledImport — daily Wave → App auto-import, only runs
// importCustomers() when the configured cadence is due. A per-run failure
// just logs and retries the next day.
const waveScheduledImport = onSchedule(
    {
      schedule: "every 24 hours",
      secrets: [WAVE_FULL_ACCESS_TOKEN],
      maxInstances: 1,
      timeoutSeconds: 300,
    },
    async () => {
      const ref = getFirestore().collection("wave").doc("connection");
      const snap = await ref.get();
      const data = snap.exists ? snap.data() : null;
      const businessId = data && typeof data.businessId === "string" ?
        data.businessId : "";
      if (!businessId) {
        logger.debug("waveScheduledImport: not connected — nothing to do");
        return;
      }
      const schedule = data && typeof data.importSchedule === "string" ?
        data.importSchedule : "off";
      // One clock instant for the due check AND the watermark — two Date.now()
      // calls would let them disagree about when this run started.
      const startedAtMs = Date.now();
      if (!isImportDue(schedule, toMillis(data.lastAutoImportAt),
          startedAtMs)) {
        logger.debug("waveScheduledImport: not due", {schedule});
        return;
      }

      logger.info("WAVE-SCHED import starting", {businessId, schedule});
      let summary;
      let window;
      try {
        // Same protect-list as the interactive sync, and it matters more
        // here: this runs unattended, so a client edit clobbered by it is
        // lost with nobody watching. There is no push first — waveSyncWorker
        // owns that — so the set is simply whatever is still outstanding.
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
    },
);

module.exports = {
  selectBusiness,
  waveBootstrap,
  waveGetConnection,
  waveSetImportSchedule,
  waveImportCustomers,
  waveUpsertCustomer,
  waveScheduledImport,
  waveSyncWorker,
};
