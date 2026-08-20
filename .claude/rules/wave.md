---
paths:
  - "functions/wave/**"
  - "functions/scripts/*wave*"
  - "lib/features/settings/**"
  - "test/features/settings/**"
---

# Wave Accounting integration

Loaded when working on the Wave sync. Root context: `../../CLAUDE.md`;
functions overview: `../../functions/CLAUDE.md`. Client-side client rules —
the sync badge, `clients/{id}.name` as Wave's customer name — are in
`clients.md`.

- **Wave Accounting** (`functions/wave/*`): admin callables (`waveBootstrap`,
  `waveImportCustomers` — App Check + `assertAdmin` + `enforceDurableRateLimit`).
  **`waveImportCustomers` is a TWO-WAY sync despite its name** (2026-08-04): it
  drains the outbox to Wave via `drainForSync` and only then imports. The name
  is historical and **stays** — renaming a deployed callable deletes the one
  every shipped build calls, so the cost of the accurate name is a broken
  "Sync with Wave" button on every phone until it updates. This outlived the
  `#compat-1.37.1` shim it was first tagged with: the constraint was never
  specific to 1.37.1.
  **The two halves of customer sync are SEPARATE FILES.** `wave/customers.js`
  keeps the App → Wave push (`upsertCustomer`, `writeSyncSuccess`, the
  `LIST_CUSTOMERS`/`LIST_CUSTOMERS_SINCE` documents, `readBusinessId`);
  `wave/customers_import.js` owns the Wave → App pull (`importCustomers`,
  `importOneCustomer`, `buildWaveIdIndex`, `BATCH_LIMIT`). `customers.js`
  re-exports `importCustomers`, so **no call site changed** — `sync_run.js`,
  `callables.js` and the jest suite all still `require("./customers")`. The
  require direction is what keeps the pair loadable: customers.js →
  customers_import.js is EAGER (module scope), and the back-reference is LAZY
  (`pushHalf()`, called at run time). So a new import-side helper must never
  eagerly require the push half — that closes a real cycle and whichever file
  loaded second sees a half-built `exports`.
  **AN IMPORT MUST NEVER TOUCH A CLIENT WITH AN UN-PUSHED OUTBOX JOB.** This is
  the invariant, and push-before-pull is only half of it. `importCustomers`
  overwrites every mapped field of a linked client with Wave's values AND
  stamps `wave.lastSyncedHash` from them — so a queued edit isn't merely
  overwritten, it is marked *synced*: the pending job then hashes the clobbered
  doc, matches, returns `noop`, and the edit is gone with the row reading
  "synced" and nothing logged. Ordering alone does not prevent it, because the
  drain is bounded AND its query only takes jobs already due — a job backed off
  after a transient Wave error is invisible to the drain and still live
  milliseconds later. Every caller of `importCustomers` therefore passes
  `skipClientIds` from **`listOutstandingClientIds`** (`worker.js`, covers
  `queued` AND `inflight`); the param is injected rather than read inside
  `customers_import.js` because `worker.js` already requires that module and
  reaching back would close a cycle. Both callers need it — the daily
  the daily `runWaveDaily` most of all, since it runs unattended.
  **The import is hash-gated, and `updated` counts REAL changes only.** It
  skips any linked client whose stored `wave.lastSyncedHash` already equals
  `mappedFieldsHash(fromWaveCustomer(node))` (counted as `skippedUnchanged`).
  That equality is exact, not a heuristic — both sides hash the same
  `toWaveCustomerInput` projection, which is the identity
  `shouldEnqueueClientWrite`'s Rule 2 already depends on to stop an import
  feeding every client back into the outbox. Without the gate the import
  re-wrote all ~650 clients every run: ~650 writes AND ~650
  `waveUpsertCustomer` invocations per press that all conclude "nothing to
  do", and the app reported "650 clients updated in the app" after a sync that
  changed nothing. **The `hasCreatedAt` half of the condition is
  load-bearing** — the update branch is the only thing that backfills a missing
  `createdAt`, and the clients list orders by it, so skipping a doc without one
  hides it from the list forever.
  **The import is also a DELTA when `since` is supplied** (2026-08-04): Wave
  filters `modifiedAtAfter` server-side, so it returns only changed customers.
  `LIST_CUSTOMERS_SINCE` is a **separate document** from `LIST_CUSTOMERS`, not
  one query with a nullable variable — a server reading an omitted variable as
  `modifiedAtAfter: null` would give a full import that imports nothing and
  reports success. **`importCustomers` stays stateless about the watermark; the
  whole read → decide → import → advance sequence has ONE owner,
  `importWithWatermark` (`wave/sync_run.js`)**, called by both the interactive
  sync and the unattended daily import. It was hand-copied in both before, and
  each omission fails silently in its own direction; the unattended copy — the
  one where a mistake is invisible — was the untested one. The decisions
  themselves are the pure `resolveImportWindow` / `watermarkPatch`, in
  `wave/import_schedule.js` beside `isImportDue` because the two cadences
  interact.
  **THE WATERMARK ADVANCES ONLY OVER A WINDOW THAT WAS FULLY COVERED.** Three
  things break it, all silent, all handled: a throw (leaves both stamps, next
  run redoes the window), a run with `skippedPending > 0` (those clients were
  deliberately protected from the clobber, so their Wave-side change would be
  invisible to every later delta — the watermark is HELD), and an unknown
  `skippedPending` (treated as not-covered, since holding is free and advancing
  wrongly loses data). It is the run's START minus an overlap, never its end.
  **A delta-only failure retries once as a FULL import** — without that, a bad
  `modifiedAtAfter` makes every interactive sync fail identically until the
  7-day resync ages the window out, and only the admin-facing path breaks. **A
  failed watermark WRITE is logged, not thrown**: the import already committed,
  and failing there would report a successful sync as an error and discard the
  push counts with it.
  A periodic full pass runs every 7 days: not for deletes
  (the import never deletes a local client) but as the backstop for `modifiedAt`
  itself, which we trust Wave to bump and cannot verify. That interval is
  shorter than both cadences, so the SCHEDULED import normally goes full every
  time and the delta mostly benefits the interactive sync — accepted, since a
  weekly job paying 7 Wave pages costs nothing. `buildWaveIdIndex`
  (`wave/customers_import.js`) is built lazily so a no-op delta costs zero
  Firestore reads. Full detail:
  `docs/CLOUD_FUNCTIONS.md`.
  **Wave rejects INLINE STRING ARGUMENTS — every string must travel as a
  GraphQL variable** (`GRAPHQL_VALIDATION_FAILED: Inline argument of type
  String is not allowed`). Confirmed against the live API 2026-08-04. Inline
  `Int`/`Boolean` are accepted; only `String` is refused. Every query in
  `wave/customers.js` already parameterises, so this only bites a query
  written by hand — write the variable in from the start rather than
  discovering it as a 400.
  The push is best-effort (bounded by `SYNC_PUSH_BATCH_LIMIT` /
  `SYNC_PUSH_BUDGET_MS`, with the `waveUpsertCustomer` trigger having already
  pushed each edit as it was made and the daily sweep retrying the rest) and its
  failure must never fail the import. Those two bounds are sized against
  `kWaveSyncTimeoutSeconds` (`wave_service.dart`, hand-mirrored) and NOT
  against the 300 s function timeout: a callable cannot be cancelled, so past
  the client's deadline the admin has already been told the sync failed and
  will tap again.
  **A zero counter must never be reported as success.** The response carries
  `pushedPending` (a `count()` taken AFTER the drain), `pushedFailed`
  (`drained.dead` — dead-lettered jobs are not `queued`, so the pending count
  misses them and they never retry) and `pushIncomplete` (the drain or the
  count threw). Without all three, a broken push, a bounded push and an empty
  queue produce identical zeros, and the app says "everything was already up to
  date" while edits sit undelivered. Response fields are additive only.
  `drainQueue`'s `created`/`updated`
  counters come from `tallyUpsert`, folded from each `upsertCustomer` status
  and incremented only where `done` is (a committed outcome), so a superseded
  job can't be counted in two drains; `linked` counts as an **update**, since
  that path patches a customer a crashed attempt already created.
  the read-only `waveGetConnection` (admin + App Check; no secret, but
  durably rate-limited — `wave-connection`, 60/hour, added once it stopped
  being a single-document read: it also runs two `count()` aggregates on
  `waveSyncQueue` so Settings can show the outbox depth), `waveSetImportSchedule`
  (admin + App Check; no secret, but durably rate-limited like every other
  admin write callable — `wave-schedule`, 20/hour — writes the `importSchedule`
  field on `wave/connection`), `waveRetryFailedJobs` (admin + App Check + the
  `WAVE_FULL_ACCESS_TOKEN` secret + durable rate limit — `wave-retry`,
  10/hour — admin-only recovery for dead-lettered outbox jobs: `requeueDeadJobs`
  puts them back in the queue, then a best-effort drain pushes them so the
  admin sees the result of the press rather than waiting for the next client
  edit or the daily sweep. **The requeue runs its per-job transactions in
  `REQUEUE_CHUNK`-sized concurrent batches, not one at a time** — the shape
  that produces dead jobs is a bulk backfill, a few hundred of them, and a
  serial round trip each spent 12-20 s of the callable's budget before the
  drain behind it had run at all. The transactions touch distinct documents,
  so there is nothing to serialize for, and the per-job catch still keeps one
  stubborn job from aborting the recovery.
  **The response carries `failed` (`drained.dead`) beside `pushed`, and it is
  not optional** (2026-08-15): the very reason this action is manual — a job
  that died on a `WaveValidationError` dies again — means the drain behind the
  requeue routinely dead-letters it a SECOND time inside the same call, leaving
  the outbox's dead count exactly where it was. Reporting only `requeued` made
  the app announce "1 client queued for Wave again" as a success over a
  Settings row still reading "1 client failed to sync", which is the same
  silence `pushedFailed` was added to the sync response to end. Null-is-unknown
  like `pushed` — the drain threw, or never ran — and the app must never render
  that as "nothing failed"), the `waveUpsertCustomer`
  `clients` trigger, and the daily `runWaveDaily` — which is NOT its own
  export: `waveScheduledImport` was deleted 2026-08-13 and this now rides
  `sendDailyJobDigest` as an isolated rider (server-triggered, so no App
  Check/rate limit).
  **THE PUSH IS EVENT-DRIVEN, NOT POLLED** (2026-08-13, owner call). The
  `waveSyncWorker` scheduler — `every 5 minutes`, drain the `waveSyncQueue`
  outbox — is **DELETED**. `waveUpsertCustomer` now enqueues the job AND
  drains it in the same invocation, so an edit reaches Wave in seconds rather
  than up to five minutes, an idle day costs zero invocations instead of 288,
  and one of the six Cloud Scheduler jobs (only 3 are free per billing account)
  goes away. Two properties there are load-bearing and must not be
  "simplified": the drain is wrapped so it **cannot throw** — the job is
  already durably queued, so a failure is a delay, not a loss, and a throw
  would re-run the whole handler under `retry: true` for something a retry
  cannot fix — and it sits **below** the `shouldEnqueueClientWrite` gate, which
  is what stops `upsertCustomer`'s own `wave.*` write-back from re-entering the
  drain in a cycle (the hash is unchanged by that write, so the re-fire returns
  at the top).
  **`runWaveDaily` therefore drains BEFORE its due check, unconditionally.**
  That is the safety net for the two states an event-driven push structurally
  cannot catch: a job sitting on its `nextAttemptAt` backoff, and a job left
  `inflight` by a dead instance (reclaimed by `drainQueue`'s lease pass) —
  neither produces a client write to ride on. It must run even when
  `importSchedule` is `off`, which is the DEFAULT and governs the PULL only;
  gating the push on it would mean a default install never pushes
  automatically at all. It also re-establishes push-before-pull on the
  unattended path, and reads `skipClientIds` AFTER the drain. Pinned by
  `wave_callables.test.js` ("pushes without a poll" / "is the drain safety
  net"). Don't reintroduce a polling worker to "fix" a sync latency
  complaint — check the trigger's drain and the daily sweep first.
  `importCustomers` still only re-runs when the configured cadence is due.
  **Auto-import cadence:** `importSchedule` on `wave/connection` is one of
  `off`/`weekly`/`monthly` (`WaveImportSchedule` enum client-side; `SCHEDULE_VALUES`
  server-side). The `isImportDue` helper (`wave/import_schedule.js`, pure/jest-testable)
  treats **off or any unknown value as never-run**; a due import stamps
  `lastAutoImportAt` and a failed one leaves it unchanged (retried next day). The full-access
  Wave token lives in Secret Manager (`WAVE_FULL_ACCESS_TOKEN`) only — **no
  OAuth**. The Connect target is chosen **server-side**: `waveBootstrap` resolves
  the business from the `WAVE_BUSINESS_NAME` secret when the client sends no
  `businessId`/`businessName`, so the business name never ships in the app and
  `_connect()` passes no selector. (Business resolution is fully server-side via
  the internal `listBusinesses` helper — there is no `waveListBusinesses`
  callable; the in-app business picker was removed.) The app
  cannot read the rules-locked `wave` collection directly, so the Settings Wave
  section calls `waveGetConnection` on mount to show persistent "Connected to X"
  status — this is the **only** Wave read path; never read the collection
  client-side. **Import invariant:** `importCustomers`
  (`wave/customers_import.js`) MUST write
  `createdAt`/`updatedAt` on every client doc (new docs get both; re-runs backfill
  `createdAt` only when missing) — the clients list/search order by `createdAt`
  and Firestore **excludes any doc missing the orderBy field**, so a timestampless
  import is silently invisible in-app. **Outbox invariant:** the job claim AND the
  outcome write are both transactional — `commitOutcome` writes
  `done`/`queued`/`dead` only while the job is still `inflight` with the same
  `claimedAt`, so a client edit that re-enqueues mid-dispatch isn't clobbered.
  The reclaim pass enforces the same rule with a single read+write transaction
  (it has no Wave call to span), so neither path may ever do an unconditional
  `update`.
  **A `waveCustomerId` pointing at a customer that no longer exists in Wave
  must RELINK, never dead-letter** (2026-08-15, found in prod). Wave reports a
  missing `customerPatch` target as a top-level GraphQL error — so it arrives
  as `WaveApiError('graphql')`, which the retry taxonomy correctly calls
  non-retryable — or, equivalently, as a `NOT_FOUND` **inputError**. Both
  dead-lettered, and both were unrecoverable in a way ordinary dead-lettering
  is not: **the offending value is STORED on the doc**, so every later push and
  every "Retry failed" press re-sent the same missing id and failed
  identically. Two clients sat like that with the Settings row reading
  "2 clients failed to sync" and no way to clear it. `upsertCustomer` now
  routes both shapes (`isStaleCustomerLink` / `hasNotFoundInputError`,
  `wave/customers.js`) into the create path with the identity search FORCED on
  — the same route a crashed create takes, and the reason a spurious NOT_FOUND
  relinks rather than minting a duplicate customer. **`writeSyncSuccess` needed
  the matching exception**: it sets `waveCustomerId` only on a doc that is
  still unlinked, which is what keeps it idempotent, so the healed link would
  never have persisted. `replacesLink` is that exception and is conditioned on
  the stale id still being the one on the doc — a link established concurrently
  is newer and unproven-dead, so it wins. Keep the predicates narrow
  (a structured `NOT_FOUND`, never a text match on Wave's message): this is the
  one path here that REWRITES a client's Wave identity.
  **Import invariant: the customer's number lands in the app's ONE `phone`
  field** (2026-08-19). `importedPhone` (`wave/mappers.js`) resolves it the way
  the app does — Wave's `phone`, else Wave's `mobile`, else a number lifted out
  of the customer NAME — renders it "(514) 555-1234" when it is NANP, and
  always writes `mobile: ''`. Full reasoning, and why only the phone half of
  the name lift is taken, in `clients.md`.
  **Mapper invariant: NEVER send a value outside a Wave ENUM's vocabulary —
  omit the field instead** (2026-08-15). `provinceCode` and `countryCode` are
  GraphQL enums, so a value they don't know is NOT an `inputErrors` entry the
  worker can report against that one field: GraphQL refuses to coerce the whole
  `$input` variable and answers with a **top-level** error, which arrives as
  `WaveApiError(graphql)`, is non-retryable by design, and dead-letters the job.
  Nothing recovers it — "Retry failed" re-sends the identical payload into the
  identical refusal — so one stray address field costs that client every future
  sync, permanently and silently. `toProvinceCode`/`toCountryCode`
  (`wave/mappers.js`) therefore test MEMBERSHIP against `ISO_COUNTRY_CODES` and
  `SUBDIVISION_CODES` rather than shape: both doc blocks always claimed they
  "omit rather than guess", but `/^[A-Z]{2}$/` accepts any two letters, so a
  province typed into the country box ("ON", "QC") shipped as a country code.
  The province prefix follows the client's **resolved country** too — it was an
  unconditional `CA-`, so a New York client was sent as `CA-NY`, a subdivision
  of nowhere. Resolve country BEFORE province in `toWaveCustomerInput`; the
  province reads against it. Apply the same rule to any new enum-typed field.
  **And `sanitizeError` is not a diagnostic** — it flattens every transport
  failure to `WaveApiError(graphql)`, which is correct for the job's
  `lastError` and the client's `wave.syncError` (the app reads those), but it
  left the REASON recorded nowhere in the system. `describeWaveError`
  (`wave/retry_policy.js`) is the log-only companion the dead-letter
  `logger.error` carries as `errorDetail`: GraphQL `extensions.code`, the error
  `path` and the `at "input.address.countryCode"` field fragment, plus
  `Expected type`. It takes **only** the quoted run following `at` — the same
  message quotes the offending VALUE immediately before it, and that is
  customer data. Keep new detail extraction on that side of the line.
