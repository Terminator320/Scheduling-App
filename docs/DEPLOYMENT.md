# Deploying a release (backend + app)

Project `schedulingapp-88727`, region `us-central1`.

This is the **release** runbook: what order to do things in, and how to check a
backend change won't break the app builds already on people's phones. For the
mechanics of the deploy command itself — prompts, expected warnings, secret
errors — use the `/deploy` skill, which this doc deliberately does not repeat.

---

## The one rule

> **Deploy the backend BEFORE you cut or ship the app build. Never the reverse.**

Every callable runs `assertPayloadShape(req.data, allowedKeys)`, which throws
`invalid-argument / unexpected-field` on the **first key it doesn't recognise**.
So:

| Direction | What happens |
|---|---|
| **New app build → old functions** | Every affected callable **fails outright.** P4c's build calls `createEmployeeAccount` / `completeEmployeeSetup` / `deleteEmployeeAccount`, which do not exist until it deploys → *no employee can be created or set up at all.* |
| **Old app build → new functions** | Fine **if** each new allowlist is a superset and each new field is optional. That is the contract to preserve — see the check below. |

The asymmetry is the whole point: the backend must always be able to serve the
build behind it *and* the build ahead of it. Ship backend first and you always
have that.

---

## 1. Pre-flight

```bash
flutter analyze                       # 0 issues is the baseline
flutter test                          # full suite
cd functions && npm run lint && npx jest
```

Then validate the rules without deploying (Firebase MCP
`firebase_validate_security_rules`, `source_file: firestore.rules`).

**Expect a clean `OK: No errors detected.`** This used to warn 3× on
`isAvailabilityOnlyChange` (one "Unused function", two "Invalid variable
name"); those were artifacts of it being uncalled and **are gone as of
2026-08-15**, since P5 wired it up. A warning here is now worth reading, not
ignoring.

## 2. Find out what is ACTUALLY live

Do not trust this repo's docs for this — they have been wrong. On 2026-08-02
`docs/CLOUD_FUNCTIONS.md` claimed 21 deployed and `recountClientJobs` missing;
production actually had 22 and `recountClientJobs` was live.

Firebase MCP `functions_list_functions`, or:

```bash
firebase functions:list
```

Diff that against the export list in `functions/index.js` — that list is the
source of truth for what *should* exist.

## 3. Diff the backend since the last deploy

Find the last deployed commit in the **Deploy log** at the bottom of this file,
then:

```bash
git --no-pager diff --stat <last-deploy-commit> -- functions/ firestore.rules firestore.indexes.json
```

## 4. Compatibility check — the step people skip

For **every callable whose payload handling changed**, answer two questions.

**(a) Is the new allowlist a superset of the deployed one?**

```bash
# deployed
git show <last-deploy-commit>:functions/employee_accounts.js | grep -n "assertPayloadShape" -A 4
# local
grep -n "assertPayloadShape" -A 4 functions/employee_accounts.js
```

If a key was **removed** from an allowlist, the currently-installed build breaks
the moment you deploy. Keep the key (ignore it server-side) until no build in
the wild still sends it.

**(b) Is every newly-added field optional?**

New fields must read through `optionalString(...)` or `x === true`, never
`requireString(...)`. A new *required* field breaks every older build.

**(c) Rules: is any cap tighter than what a shipped write path can produce?**

This is the most common way a rules deploy breaks the app, and it fails with an
opaque `permission-denied` that names no field. For each new/changed cap in
`isValidUserData` / `isValidClientData` / `isValidAppointmentData`, find the
widest value the **client** and the **callables** can actually write — check
`lib/core/validators/text_limits.dart` and the server's `requireString` limits.
A cap below either one makes matching docs **permanently un-updatable**,
including by `deactivateEmployee`.

Two real examples from this repo:

- `phone` is capped at **40** in rules, not `TextLimits.phone`, because
  `createEmployeeAccount` accepts 40.
- `employeeIds` was briefly capped at **30** (reasoning from
  `whereArrayContainsAny`) — wrong: that is a *query* chunk size, not an
  assignment limit, and nothing bounds the picker client-side. It is **500**,
  tied to `_userStreamLimit`.

Also check the converse: a **client** cap must not exceed the callable's, or the
field accepts input the server rejects as `invalid-argument`, which surfaces to
the user as an unexplained "Something went wrong".

## 5. Deploy

```bash
cd functions && npm run lint
firebase deploy --only functions,firestore:rules
```

- Add `,storage` when `storage.rules` changed. The target is **`storage`** —
  `storage:rules` is not a valid target.
- Add `,firestore:indexes` **only when `firestore.indexes.json` changed.** A new
  query whose index is missing fails `FAILED_PRECONDITION`, which the
  best-effort callers swallow into a silent no-op — so if you changed a query,
  you must deploy indexes.
  **An index deploy returns before the index is `READY`.** The deploy only
  *starts* the build, so a function or app build that needs a new index races
  it: check the Firestore console's Indexes tab before shipping the app, and
  expect a scheduled sweep to fail `FAILED_PRECONDITION` (and self-heal on its
  next run) in the gap. **Index EXEMPTIONS deploy the same way and are the
  slower direction to undo** — re-adding an override you removed rebuilds the
  index over the whole collection, so treat "which fields are exempt" as a
  decision, not a toggle. See the `fieldOverrides` note in `functions/CLAUDE.md`
  for what is exempt and why.
- **Never pass `--force`.** It treats any prod field override missing from
  `firestore.indexes.json` as drift and DELETES it — this removed all 5 live TTL
  policies once (2026-07-21).
- Single function: `--only functions:<name>`.

## 6. Verify

1. `functions_list_functions` — count matches `functions/index.js` exports, no
   orphans.
2. Spot-check logs for anything you changed (MCP `functions_get_logs`) — look
   for startup errors and for `unexpected-field`, which means an older build is
   hitting a narrowed allowlist.
3. **Smoke-test with the OLD build** if one is installed. This is the check that
   proves step 4 was right.
4. Only now cut / upload the new app build.

## 7. Rollback

Functions are versioned by deploy, not by tag, so rollback = redeploy the
previous source:

```bash
git stash                                   # or branch off
git checkout <last-deploy-commit> -- functions/ firestore.rules
firebase deploy --only functions,firestore:rules
git checkout HEAD -- functions/ firestore.rules
```

Rules roll back instantly and cleanly. Functions take a minute per function.
**Anything already written under the new rules stays written** — a rollback does
not un-write data, so a widened cap that let bad data in is not undone by
reverting the cap.

---

## Repo-specific traps

- **TTL policies live in `firestore.indexes.json`** as `fieldOverrides` with
  `"ttl": true`. They are not console-only state. See the `--force` warning above.
- **TTL expiration offset must be `0`.** Every `expiresAt` in this app stores the
  *absolute* deletion instant; a non-zero offset silently multiplies retention.
  The offset is immutable once set — fixing one means delete → wait for it to
  disappear → recreate.
- **Deploying functions (re)activates App Check** (`enforceAppCheck: true`) on
  the callables. Expected and correct.
- **Secrets must already exist** in Secret Manager or binding fails at deploy:
  `GOOGLE_MAP_API_KEY`, `APNS_AUTH_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`,
  `WAVE_FULL_ACCESS_TOKEN`, `WAVE_BUSINESS_NAME`. Only the two functions that
  *bind* `APNS_SECRETS` may read them — otherwise every invocation logs a "No
  value found for secret parameter" warning.
- **Emulator only:** clearing app data regenerates the App Check debug token;
  re-register it in the console or every write fails `permission-denied` while
  cached reads still succeed (making it look collection-specific).
- **A deploy that REMOVES an export prompts for deletion — read the list before
  confirming.** Every deploy through 2026-08-04 was additive or flat, so each
  log row below says "no deletion prompt"; the `#compat-1.37.1` retirement
  (27 → 25, dropping `createEmployeeInvite` and `redeemSignupCode`) is the first
  that is not. Confirm the CLI names **exactly** the functions you intended and
  nothing else — an orphan the docs forgot about is deleted just as silently as
  an intended one. Deleting a callable is **not** reversible for a client build
  that still calls it: the call fails `not-found` immediately, everywhere, with
  no rollout window. Redeploying restores it, so the recovery is fast, but the
  outage starts the instant the delete lands. This is still never a reason to
  pass `--force`.

---

## Pending (steps 2–3 of 3): the photo subcollection migration (phase 1)

> **Step 1 (backend + rules + indexes) DEPLOYED 2026-08-14 at `d3e22377`.**
> `cascadeDeleteAppointmentImages` is live, so the subcollection is now safe to
> write to. **Steps 2 (backfill) and 3 (app build) are still outstanding**, and
> the app build additionally waits on the `(clientId, startTime DESC)` index
> reaching `READY`.

Photos are moving from the `pictures` array on each appointment into
`appointments/{id}/images`. **Phase 1 is written; its backend half (step 1
above) deployed 2026-08-14.** It writes BOTH stores; the array stays
authoritative and is what the shipped build reads.

The ordering below is the whole safety property — it is an expand/contract
migration and the steps are not interchangeable:

1. **Deploy backend + rules + indexes.** This adds two exports
   (`cascadeDeleteAppointmentImages`, `recountAppointmentPictures`), so the
   count moves **24 → 26** and this is *also* the deletion deploy below — see
   that section for the non-interactive abort.
   **The cascade trigger MUST be live before any photo reaches the
   subcollection.** Firestore does not delete a subcollection with its parent,
   so an appointment deleted while the trigger is absent orphans its photo
   documents permanently and invisibly. Deploying the app build first is the
   one ordering that creates unrecoverable litter.
2. **Run the backfill**, `--dry-run` first:
   ```bash
   node functions/scripts/backfill-appointment-images.js --dry-run
   node functions/scripts/backfill-appointment-images.js
   ```
   Copy-only — it never touches the `pictures` array, and must not be changed
   to. Idempotent (ids are derived from each photo) and atomic per appointment.
3. **Ship the app build.** It prefers the subcollection and falls back to the
   array, so it is correct whether or not step 2 has run — but the card's photo
   indicator reads the `pictureCount` the backfill stamps.

**Do NOT delete the `pictures` array as part of this.** That is the CONTRACT
step, a separate release gated on the same condition the `#compat-1.37.1` shim
waited on: no device still *runs* a build that reads the array. 1.45.0+72 does.

**Rules validation is a REQUIRED pre-flight for this deploy and could not be
done locally** — the Firestore emulator needs Java, which is not installed on
this machine. Validate `firestore.rules` before deploying (Firebase MCP
`firebase_validate_security_rules`, or the emulator on a machine with a JRE).
The new `match /images/{imageId}` block declares a nested `function` and calls
`get()` on the parent appointment; a syntax error there fails the whole rules
release, and a rules release that fails leaves the deploy half-applied.

Note the cost this block adds, since it is the argument against reaching for a
subcollection casually: `parentAppointment()` is a document `get()` on top of
the `usersByUid` one every rule already pays, so an employee listing a job's
photos evaluates **two** rules reads. It is one per query, cached per request,
and it buys the far larger saving on the range queries — but it is real.

---

## DONE 2026-08-14: a THREE-deletion deploy (25 → 22 → 25)

> **Deployed at `d3e22377`** — see the log row. Kept as the worked record of how
> a deletion deploy is checked. **Step 2 below (the 3 orphaned Cloud Scheduler
> jobs) was NOT done** and is still outstanding: `gcloud` is not installed on
> the Windows box. The abort this section predicts did not fire — a *different*
> one did, on the new `retry: true` functions; both are now in the log row.

**Verified against `78d89478` (what prod runs) on 2026-08-13, not from this
doc's own history — an earlier draft of this section said "25 → 24,
`waveSyncWorker` and nothing else" and was wrong on both counts.** Reproduce
the check before deploying:

```bash
git show 78d89478:functions/index.js | grep '^exports\.' \
  | sed 's/exports\.\([a-zA-Z]*\).*/\1/' | sort > /tmp/prod.txt
grep '^exports\.' functions/index.js \
  | sed 's/exports\.\([a-zA-Z]*\).*/\1/' | sort > /tmp/local.txt
comm -23 /tmp/prod.txt /tmp/local.txt   # deletions
comm -13 /tmp/prod.txt /tmp/local.txt   # additions
```

**Deletions (3) — the prompt must name exactly these:**

| Function | Why it can go |
|---|---|
| `waveSyncWorker` | The Wave push is event-driven now: `waveUpsertCustomer` enqueues *and* drains. |
| `waveScheduledImport` | Folded into `sendDailyJobDigest`, which calls `runWaveDaily()` (`wave/callables.js`). Not lost — still the drain safety net for backed-off and stale-`inflight` jobs. |
| `sendOverdueJobPrompts` | Merged into `sendUpcomingJobReminders`; its per-recipient ledger, not the cadence, is what guaranteed at-most-once. |

**Additions (3):** `waveRetryFailedJobs`, plus the photo migration's
`cascadeDeleteAppointmentImages` and `recountAppointmentPictures`.

Net 25 → 25, so **the export COUNT tells you nothing here** — read the two
lists, not the total.

### 1. The deletion abort

Expect the **non-interactive abort** the 2026-08-08 row documents: the CLI
releases rules/indexes, uploads the source, then stops with "Aborting because
deletion cannot proceed in non-interactive mode", leaving prod on
new-rules + old-functions. Close it:

```bash
firebase functions:delete waveSyncWorker waveScheduledImport \
  sendOverdueJobPrompts --region us-central1
firebase deploy --only functions,firestore:rules,firestore:indexes  # never --force
```

`functions:delete --force` is **not** `deploy --force` — it only skips the y/n
prompt for the named functions and touches no index or TTL policy.

### 2. Delete THREE orphaned Cloud Scheduler jobs

Removing a scheduled function does not reliably remove its scheduler entry, and
**only 3 jobs are free** — leaving these behind bills for three jobs forever and
silently undoes the consolidation that created them.

Scheduled functions go from **6 to 3** in this deploy (`purgeExpiredHistory`,
`sendUpcomingJobReminders`, `sendDailyJobDigest` survive):

```bash
gcloud scheduler jobs list --location us-central1
# delete any that survive:
gcloud scheduler jobs delete firebase-schedule-waveSyncWorker-us-central1 \
  --location us-central1
gcloud scheduler jobs delete firebase-schedule-waveScheduledImport-us-central1 \
  --location us-central1
gcloud scheduler jobs delete firebase-schedule-sendOverdueJobPrompts-us-central1 \
  --location us-central1
```

Landing on exactly 3 is the point of the change. Verify the count afterwards.

### 3. `firestore:indexes` and `firestore:rules` are BOTH required

`firestore.indexes.json` carries the new `(status, endTime DESC)` and
`(clientId, startTime DESC)` composites, the 23 single-field exemptions, and
the `images` subcollection exemptions. The overdue sweep (now inside
`sendUpcomingJobReminders`) fails `FAILED_PRECONDITION` until
`(status, endTime DESC)` reads **Ready**, and the app build must not ship until
the client-history composite does.

`firestore.rules` carries the photo subcollection's `match /images/{imageId}`
block and the `pictureCount` guards. **Validate the rules before deploying** —
they could not be compiled locally (the Firestore emulator needs Java, absent on
the dev machine), and the new block declares a nested function and calls `get()`
on the parent. A failed rules release leaves the deploy half-applied.

The CLI will report the `signupCodes` TTL override as unmatched drift and
correctly refuse to delete it without `--force`; that is expected and must stay
refused.

### 4. Then the photo migration's own ordering

See "Pending (steps 2–3 of 3): the photo subcollection migration" above —
backend+rules first, then the backfill, then the app build. The cascade
trigger must be live before any photo reaches the subcollection.

---

## Per-release checklist

Copy this into the release PR / notes:

```
[ ] flutter analyze 0 · flutter test green · functions lint + jest green
[ ] rules validate (only the 3 isAvailabilityOnlyChange warnings)
[ ] recorded what is ACTUALLY live (functions:list), not what the docs claim
[ ] diffed functions/ + rules since the last deploy commit
[ ] every changed allowlist is a SUPERSET; every new field is optional
[ ] no rules cap is tighter than a shipped client OR callable write path
[ ] indexes: unchanged → omit target · changed → include it
[ ] if any export was REMOVED: deletion prompt lists exactly those, nothing else
[ ] deployed backend  (no --force)
[ ] verified function count + logs
[ ] smoke-tested with the OLD build
[ ] THEN cut the app build
[ ] appended a row to the Deploy log below
```

---

## Deploy log

Keep this current — step 3 depends on it, and it is the only reliable record of
what production is running.

| Date | Commit | Targets | Fns live | Notes |
|---|---|---|---|---|
| 2026-07-18 | — | functions, rules | 21 | `placesReverseGeocode`, travel-aware reminder rebuild |
| 2026-08-01 | `d916b16` | functions, rules | 22 | P3 clients; added `recountClientJobs` |
| 2026-08-03 | `95259db` | functions, rules | 25 | P4 + P4b + **P4c**: added `createEmployeeAccount`, `completeEmployeeSetup`, `deleteEmployeeAccount`; `private/emergency` rule; `isValidAppointmentData`. **Deleted nothing** — `revokeInvite`/`previewInvite` were never deployed (prod had 22, not the 24 an earlier draft of this row assumed), and `createEmployeeInvite`/`redeemSignupCode` were **kept as the `#compat-1.37.1` shim** for the 1.37.1+64 build on the App Store. No deletion prompt; 22 → 25. `firestore:indexes` omitted (file already in sync with prod). Verified post-deploy: 25 functions live, all three shim rules present, zero `unexpected-field` in logs. See the shim note above. |
| 2026-08-04 | `56cfb5e` | functions | 27 | Employee email → Auth sync: adds `changeEmployeeEmail` (26 → 27), which moves the sign-in email in Firebase Auth AND on the `users` doc together and is what re-enables the read-only email field in `edit_person_sheet`. It also pushes the employee a `kind:"emailChanged"` notice naming the new address (best-effort, after the commit). **Deploy BEFORE the app build ships** — the client calls it from inside `updateEmployee` whenever the email changed on a doc carrying a `uid`, so an un-deployed function turns every such save into a `not-found` and the admin cannot save the person at all. No rules change (`email` was already admin-writable on `/users`, and this write is Admin SDK anyway) and no index change, so `firestore:rules`/`firestore:indexes` are optional here. 1.37.1 is unaffected: it never calls this, and its Firestore-only email edit keeps working exactly as before (desynced, as it always was). Verified post-deploy: 27 functions live and an exact match against `index.js`'s 27 exports (no orphans), `changeEmployeeEmail` ACTIVE with its startup TCP probe passing on the first attempt. No deletion or secret prompts. Deployed without `--force`. A second run the same day added `firestore:rules,storage` for completeness — both were already byte-identical to prod (unchanged since the `1c6a949` rules deploy), so the CLI skipped both uploads and merely re-released them, and every function reported "Skipped (No changes detected)". Rules compiled with only the 3 known `isAvailabilityOnlyChange` warnings. `firestore:indexes` still deliberately omitted (file in sync with prod). Both runs went out from an uncommitted tree; that tree was committed as `56cfb5e` immediately after, which is the hash above. |
| 2026-08-03 | `1c6a949` | functions, rules, **indexes** | 26 | Client archive + delete: adds `deleteClient` (25 → 26), gated on a live `count()` of the client's appointments; `isValidClientData` accepts `archived` (optional, so 1.37.1 writes still pass). **`allow delete` on `/clients` is KEPT** as a second `#compat-1.37.1` shim entry (owner call 2026-08-03) — 1.37.1+64 ships an ungated Delete button doing a direct `doc.delete()`, and withdrawing the grant would fail it with an opaque `permission-denied`. Nothing in the new build uses it. **`firestore:indexes` IS required** — new `(archived, name, __name__)` composite for the list's server-side `where('archived','==',false)`. Backfill ran BEFORE the deploy, as required (Firestore excludes docs missing a filtered field, so an un-backfilled client vanishes from the list the moment the app build ships): **674 patched, 0 already had the field**; the confirming dry-run then reported `0 patched, 674 already had the field`. Verified post-deploy: 26 functions live, `deleteClient` ACTIVE with a clean startup probe, zero `unexpected-field` in logs, rules compiled with only the 3 known `isAvailabilityOnlyChange` warnings. **The `(archived, name, __name__)` index was still `CREATING` when the deploy finished — the app build must NOT ship until it reads `READY`,** or the list query fails `FAILED_PRECONDITION`. Deployed without `--force`. (The first `firebase deploy` invocation exited 9 at the tail; an immediate re-run reported every function "Skipped (No changes detected)" and exited 0, so the first run had in fact converged.) |

| 2026-08-04 | (audit pass, uncommitted at deploy time) | functions, rules, storage | 27 | **Codebase-audit fixes. No export change** — 27 → 27, so no deletion prompt. Backend halves of the multi-day gaps: the push diff now gates on the run's END (`hasWorkLeft`) so a job cancelled mid-run still reaches its crew; the overdue floor widens to 24h + 14d; the digest queries and buckets on OVERLAP with tomorrow and orders by clock time. Hardening: `toIdList` rejects slash/over-long ids (one poisoned `employeeIds` element could reject the whole `Promise.all` digest batch and silence it nightly), `runDailyDigest` is wrapped like the reminder sweep, `waveSetImportSchedule` gains a 20/hr durable limit, and the travel context query warns at its 50-doc cap. `maintenance_policy.js` added as an internal module (NOT an export) so `purgeExpiredHistory` — the only unattended irreversible deletion — is testable. **Rules: additive caps only** — `pictures` ≤ 100 and `isValidDocIdField(seriesOpId)` on `isValidAppointmentData`; both pass anything either build writes. **Two fixes were REVERTED before deploying**, each after review showed it traded a known gap for a worse one: an `email_verified` gate on `redeemSignupCode` (1.37.1 redeems on an unverified token and would have deleted the account it just created — every invite on the App Store build), and widening `MAX_BOOKING_MS` to 14d (`decideOrigin` tests raw instants, so a long run becomes a wrong origin at any hour). Verified post-deploy: 27 live matching `index.js`, zero ERROR log entries. Deployed without `--force`. |

| 2026-08-04 | `5ac67343` | functions, **rules** | 27 | **Second codebase-audit pass. No export change** — 27 → 27, verified identical to `functions/index.js` before deploying, so no deletion prompt. Functions: `propagateClientEdits` now floors its query at `now − MAX_APPOINTMENT_SPAN_MS` and filters on `endTime` (a client edit was skipping any job already under way); `countFutureAssignments` same fix client-side; `runTravelAwareReminderSweep` flattened to `Promise.all`; `deleteAccount`'s orchestration extracted to the new `account_policy.js` (behaviour unchanged, response still `{deleted:true}`). **Rules: `emergencyFieldNotSet` added to `/users` `allow update`** — the emergency pair may now be REMOVED but never WRITTEN, closing the peer-readable-PII hole. Deliberately NOT the flat denylist the audit first proposed: that form rejects the `FieldValue.delete()` scrub and would brick any doc still carrying the pair. **No backfill needed or run** — owner confirmed no emergency contact has ever been entered, and the guard is safe either way; `scripts/backfill-emergency.js` deleted. **Old-build check:** `emergencyContact` does not exist anywhere in `lib/` at `v1.37.0+62`, so the 1.37.1+64 App Store build never writes those fields and cannot be broken by this rule. No `assertPayloadShape` allowlist or `requireString` cap changed. `firestore.indexes.json` and `storage.rules` unchanged → both targets omitted; every changed query kept its existing index shape. Deployed without `--force`. Rules deployed twice (a stale comment on `allow create` was corrected in the second pass). Verified post-deploy: 27 functions live, rules released, clean `STARTUP TCP probe` on all changed functions, zero `unexpected-field`. |

| 2026-08-04 | `108b410b` | functions, rules, storage | 27 | **Two-way Wave sync (1.43.0+68). No export change** — 27 → 27, diffed against `functions/index.js` before deploying, so no deletion prompt. `waveImportCustomers` now drains the outbox to Wave (`drainForSync`, bounded 20 jobs / 20 s) BEFORE importing, and returns five additive fields (`pushedCreated`/`pushedUpdated`/`pushedPending`/`pushedFailed`/`pushIncomplete`). **Additive only — 1.37.1 parses the import half by name and ignores the rest**, and its Import button simply also pushes now, which the 5-minute `waveSyncWorker` does anyway. No `assertPayloadShape` allowlist changed (still `new Set()`), no `requireString` cap changed, no rules or index change → `firestore:rules,storage` were re-released byte-identical for completeness. **Two data-loss fixes ride along, both pre-existing:** `importCustomers` now takes a `skipClientIds` protect-list from `listOutstandingClientIds` (an import was overwriting a client whose edit was still queued AND re-stamping `wave.lastSyncedHash`, so the pending push then no-opped and the edit vanished with the row reading "synced"); and the import is hash-gated, skipping any client whose stored hash already matches, which cuts a steady-state run from ~650 writes + ~650 `waveUpsertCustomer` invocations to ~0 and stops the app reporting "650 clients updated" after a sync that changed nothing. **`waveScheduledImport` gets the same protect-list** and needed it more — it runs unattended. Deployed without `--force`. Verified post-deploy: 27 live, exact match against the 27 exports (no orphans, no extras), rules + storage released, and zero ERROR entries on any changed function — the only two errors in the window were `redeemSignupCode` rejecting a non-POST rollout probe (correct behaviour, untouched by this change). The "request was not authenticated" warnings on the scheduled/trigger functions are the usual rollout-probe noise, matching the identical cluster at every prior deploy. **App build 1.43.0+68 can ship now** — this had to land first, since against the old backend the "Sync with Wave" button would have been a pure clobbering import. |
| 2026-08-08 | (release 1.44.0+70, uncommitted at deploy time) | functions, rules, **indexes** | **25** | **The `#compat-1.37.1` retirement — the repo's FIRST deletion deploy** (27 → 25), plus the 2026-08-08 codebase audit and the 1.43.1 Wave heal. **Deleted: `createEmployeeInvite`, `redeemSignupCode`** — the deletion list named exactly those two and nothing else. Gate was owner confirmation that every device is on 1.40+. `redeemSignupCode` was the last unauthenticated callable in the codebase. **The CLI ABORTS on deletion in non-interactive mode** — it released rules and indexes, uploaded the function source, then stopped with "Aborting because deletion cannot proceed in non-interactive mode", leaving prod on new-rules + old-functions. That half-state is safe (the removed grants are unused by any shipped build) but must be closed. Fix is the CLI's own suggestion, `firebase functions:delete <name> --region us-central1`, then re-run the deploy; **`functions:delete --force` is NOT `deploy --force`** — it only skips the y/n prompt for the named functions and touches no index or TTL policy. Record this: any future deploy that removes an export will hit the same abort. **Rules: removals only** — `allow delete` withdrawn from `/users` and `/clients`, the `/signupCodes` block and the 4th `/users` read clause deleted. No cap changed, nothing added, so no shipped write path can be broken. **`firestore:indexes` included** (the `signupCodes` TTL `fieldOverride` was dropped from the file). The CLI reported "1 field override defined in your project that is not present in your indexes file" and **correctly refused to delete it without `--force`** — so the live `signupCodes` TTL policy REMAINS. Left deliberately: the collection was verified empty in prod before the deploy and rules now deny all access, so it reaps nothing and costs nothing. Never `--force` this away (it deleted all 5 live TTL policies in 2026-07-21). **Compatibility check:** every `assertPayloadShape` allowlist and every `requireString`/`optionalString` cap byte-identical to `108b410b` — no narrowing, no new required field. **`completeEmployeeSetup` gained an `email_verified` identity guard** (above the rate limiter). Prod was queried first: **zero `invited` users**, so nobody could be stranded mid-onboarding. It is still a real forward constraint — **do not create an employee account until app build 1.44.0+70 ships**, because the shipped 1.43.x setup screen has no way to send or confirm a verification email. `storage.rules` unchanged since `108b410b` → target omitted. Deployed without `--force`. **Verified post-deploy:** 25 live, exact match against `index.js`'s 25 exports (no orphans, no extras); a confirming `--only functions` re-run reported all 25 "Skipped (No changes detected)", proving prod's source matches local; clean `STARTUP TCP probe succeeded after 1 attempt` on all 25; zero `unexpected-field` and zero `email-not-verified`. The only ERROR entries are 12 `Invalid request, unable to process.` at 21:14:38-53 — two per callable, the Cloud Run rollout probe hitting `onCall` with a non-callable request, the same benign cluster as every prior deploy. **Zero errors after the deploy window.** |
| 2026-08-11 | `70579d22` | functions, rules, storage | 25 | **Release 1.45.0+72 — closes the 2026-08-08 → 2026-08-11 gap.** No export change (25 → 25, diffed against `functions/index.js` first), so **no deletion prompt and no abort** — the 2026-08-08 row's warning did not apply. What moved is the code behind the existing 25: `changeEmployeeEmail`'s self branch, its non-admin re-auth freshness gate and its 20/hr → 5/hr budget; `travelAlertsEnabled` read BEFORE the Routes call so an opted-out tech costs no estimate and gets the fixed 30-min lead; the multi-day Live Activity skip and the crew-colour parse in `travel_utils.js`; the new internal `day_slice_utils.js` day-scoping behind the widget payload and push text; the single `TERMINAL_STATUSES` owner in `time_utils.js`; and `notifyAdminsOfSelfEmailChange` on the shared active-admins fan-out. **Rules: two additions** — P5's `isAvailabilityOnlyChange` self-service clause on `/users` `allow update`, and `isValidAppointmentSpan` on appointment create/admin-update. The span bound carries a deliberate **+2h DST allowance**: the app counts calendar days against local wall-clock instants while CEL's `duration.value` is absolute, so a flat 14d would have refused the widest booking the form can save for about two weeks each autumn, as an opaque `permission-denied`. `firestore.indexes.json` unchanged since `1c6a949` → **`firestore:indexes` deliberately omitted**, which also keeps the surviving `signupCodes` TTL policy untouched. `storage.rules` unchanged → the CLI skipped its upload and merely re-released it. Deployed without `--force`. Pre-flight: `npm run lint` clean, **902/902 jest** passing. **Verified post-deploy:** all 25 reported "Successful update operation", `functions_list_functions` returns exactly the 25 exports (no orphans, no extras), rules + storage released. Log check found **zero real errors** — the only ERROR/WARNING entries in the window are the recurring `Request has invalid method. GET` / `Invalid request, unable to process.` pairs, the Cloud Run rollout probe hitting `onCall` endpoints, identical to the benign cluster at every prior deploy; a severity≥ERROR query excluding that one class returned an empty set. |
| 2026-08-11 | `78d89478` | functions, rules, storage | 25 | **Closes the second 2026-08-11 audit — the only backend change since `70579d22` is `maintenance.js`.** No export change (25 → 25, diffed against `functions/index.js` first), so no deletion prompt. The I6 refactor moves `purgeExpiredHistory`'s image-validation decisions into the pure `maintenance_policy.js` sibling, which is what makes them testable at all — `maintenance.js` resolves a Storage bucket at load and throws on `require()` outside the emulator. Behaviour is unchanged: the status gate (only `done`/`cancelled` are ever purged), the images-before-doc ordering, and the no-progress loop termination are the three rules that destroy data if they regress, and all three are now pinned by the new `image_validation_policy.test.js` (212 lines). **No rules change** — both `firestore.rules` and `storage.rules` were already byte-identical to prod, so the CLI reported "already up to date, skipping upload" and merely re-released them. `firestore:indexes` deliberately omitted again (file unchanged since `1c6a949`), which keeps the surviving `signupCodes` TTL policy untouched. Deployed without `--force`. Pre-flight: `npm run lint` clean, **921/921 jest across 41 suites** passing (up from 902 — the new suite). **Verified post-deploy:** all 25 reported "Successful update operation" and `functions_list_functions` returns exactly the 25 exports (no orphans, no extras). Log check found **zero real errors**: `purgeExpiredHistory` itself logged nothing new — a module-load throw would have failed the deploy outright, not merely logged — and every ERROR entry in the deploy window is the same `Invalid request, unable to process.` CORS/https-layer shape as the benign clusters at the 2026-08-04 and 2026-08-08 deploys, i.e. the Cloud Run rollout probe hitting `onCall` endpoints unauthenticated. |
| 2026-08-14 | `d3e22377` | functions, rules, **indexes** | 25 | **The three-deletion swap + the photo subcollection migration's phase 1.** Deleted `waveSyncWorker`, `waveScheduledImport`, `sendOverdueJobPrompts`; added `waveRetryFailedJobs`, `cascadeDeleteAppointmentImages`, `recountAppointmentPictures` — net 25 → 25, so the count proves nothing and the two lists were diffed against **live prod** (which matched `78d89478`'s exports exactly) before touching anything. **A NEW failure mode, not in this runbook until now: `firebase deploy` ABORTS with `Error: Pass the --force option to deploy functions with a failure policy`.** The two new photo triggers are the first `retry: true` functions to be *newly created* here, and the CLI wants confirmation of the failure policy non-interactively; the 2026-08-08 deletion abort is a *different* abort and this one fires earlier — nothing at all was released on that first attempt. Resolved by **splitting the deploy** rather than reaching for a whole-target `--force`: `firebase deploy --only firestore:rules,firestore:indexes` (no `--force`, so the surviving `signupCodes` TTL override was reported as drift and **correctly refused** — it remains live), then `firebase functions:delete waveSyncWorker waveScheduledImport sendOverdueJobPrompts --region us-central1 --force` to keep the removal explicit and auditable rather than silently absorbed, then `firebase deploy --only functions --force`. **With no firestore target in scope, `--force` cannot reach an index or TTL policy** — the same scoping that makes `functions:delete --force` safe. Record this: any future deploy that ADDS a `retry: true` function hits the same abort. **Compatibility check:** every `assertPayloadShape` allowlist and every `requireString`/`optionalString` cap byte-identical to `78d89478` — no narrowing, no new required field; the one added allowlist belongs to the new `waveRetryFailedJobs`. All three deleted functions are scheduled/server-only with **zero references in `lib/` or `ios/`**, so no shipped build can hit a `not-found`. **Rules: additive** — the photo subcollection's `match /images/{imageId}` block and the `pictureCount` guards; validated clean via the Firebase MCP `firebase_validate_security_rules` *before* deploying (the emulator needs Java, absent on this box — the MCP tool works without it and closes the gap this doc previously flagged as unverifiable locally). **`firestore:indexes` required** — the file gained 166 lines. Pre-flight: `npm run lint` clean, **1100/1100 jest across 46 suites**. **Verified post-deploy:** 3 creates + 22 updates all "Successful", `functions_list_functions` returns exactly the 25 exports (no orphans, no extras). Log check found **zero real errors** — every ERROR entry in the whole retained window (40, back to 2026-08-04) is the same `Invalid request, unable to process.` CORS-layer shape, the Cloud Run rollout probe hitting `onCall`; today's 8 all sit inside the deploy window. **Two indexes were still `CREATING` at completion — `(status, endTime DESC)` and `(clientId, startTime DESC)`, exactly the two this doc names as gating.** The overdue sweep inside `sendUpcomingJobReminders` fails `FAILED_PRECONDITION` and self-heals on its next run until the first is `READY`; **the app build must not ship until the second is.** **NOT DONE in this deploy, both still outstanding:** the 3 orphaned Cloud Scheduler jobs (`gcloud` is not installed on this Windows box — scheduled functions must land on exactly 3, and only 3 are free), and the appointment-images backfill. The client-name and phone-formatting backfills had already been run against prod earlier the same day (504 renamed, 142 reformatted) and must NOT be re-run. |
| 2026-08-15 | `6d41dd3c` | functions, rules, **indexes** | 25 | **Closes the 2026-08-15 codebase audit (41 findings).** No export change (25 → 25), diffed against **live prod** before touching anything, so **neither known abort fired** — no deletion prompt and no failure-policy abort. `waveUpsertCustomer` moved module (`wave/callables.js` → the new `wave/triggers.js`) but keeps its export name, so it is an UPDATE, not a create; the `retry: true` abort only fires on newly-created ones. **Compatibility check:** every `assertPayloadShape` allowlist byte-identical to `d3e22377`, no new required field, no narrowed cap. The new `requireDocId` helper in `security.js` replaces three restated call sites (`clients.js`, `employee_accounts.js` ×2) at the SAME 128 cap, adding only a `/` reject — no legitimate document id can contain one. **Rules: two WIDENINGS that fix live rejections, one tightening no shipped build can reach, one new cap.** `clientName` on appointments **200 → 401** (it is the DENORMALIZED display name, composed by `ClientRecord.displayName` from two 200-char halves; sized to `personName` it was rejecting whole appointment saves with an opaque `permission-denied`) and client `address` **500 → 533** (`AddressParser.canonicalFrom` joins the 500-char street with the 32-char apt). The tightening adds `resource.data.status != 'cancelled'` to the employee mark-done branch, closing a hole where an assignee could put `done` over `cancelled` and resurrect a cancelled visit as a completed one — verified safe against the shipped build: **1.45.0+72's `DetailsActionBar` already gates on `hasStarted && !isDone && !isCancelled`**, so it never sends that write. **THE ONE ACCEPTED RISK: a new 500-char cap on `clients.addressLine2`.** The DEPLOYED `d3e22377` import wrote that field **uncapped** (`IMPORT_FIELD_CAPS` had no entry for it; this commit adds one), so any prod client doc over 500 chars is now permanently un-updatable from the app. **Prod could not be inspected to confirm none exists** — every Firebase MCP Firestore read fails `The requested 'read_time' cannot be in the future`, because this Windows box's clock runs ahead of Google's (`firebase deploy` sends no `read_time` and is unaffected). Owner accepted the risk on the reasoning that Wave models `addressLine2` as a short peer street line and that rules roll back instantly and cleanly. **If an opaque `permission-denied` ever appears on an ordinary client save, check this field FIRST.** Also added: a declarative `match /appointmentRecountClaims/{appointmentId}` block (`allow read, write: if false`) — there is no `match /{document=**}` catch-all in this file, so the collection was already default-denied and this changes no behaviour. **`firestore:indexes` required** — it adds the `appointmentRecountClaims.expiresAt` TTL policy and a `presence.updatedAt` override. The surviving `signupCodes` TTL override was again reported as drift and **correctly refused** without `--force`; it remains live. `storage.rules` unchanged since `108b410b` → target omitted. Deployed without `--force`. **Pre-flight:** `npm run lint` clean, **1160/1160 jest across 47 suites**; `firestore.rules` validated clean via the Firebase MCP — note the **3 `isAvailabilityOnlyChange` warnings this doc lists as "expected, ignore" are now GONE**, exactly as predicted once P5 wired the function up. **Verified post-deploy:** all 25 reported "Successful update operation" (0 creates, 0 deletions), `functions_list_functions` returns exactly the 25 exports (no orphans, no extras), rules released. Log scan: **zero `unexpected-field`, zero `permission-denied`**, no `Cannot find module`/`SyntaxError`/startup failures. The only ERROR entries in the deploy window are 2 `Invalid request, unable to process.` on `waveRetryFailedJobs` — the same benign Cloud Run rollout probe hitting `onCall` as at every prior deploy (38 of the 40 retained ERROR entries are that one shape). **TWO REAL FAILURES SURFACED THAT PREDATE THIS DEPLOY BY ~8h AND ARE UNRELATED TO IT:** `WAVE-WORKER dead-lettering job` for clients `GAQJI0Ctadf8ppVHbSOE` (02:29:30Z) and `6GKdxhkzWH8HWYjwrolZ` (04:07:42Z), both `WaveApiError` / `errorKind: graphql` / `retryable: false`, so both customer upserts are sitting dead-lettered and will NOT self-heal — run `waveRetryFailedJobs` or investigate the GraphQL rejection. **Still outstanding, unchanged by this deploy:** the 3 orphaned Cloud Scheduler jobs (`gcloud` is not installed on this box) and the appointment-images backfill. |
| 2026-08-15 | `e84a66fd` | functions, rules, storage | 25 | **The root-cause fix for the two dead-lettered Wave upserts the previous row flagged as open — `functions/wave/` only.** No export change (25 → 25, diffed against `functions/index.js` and against live prod before touching anything), so **neither known abort fired**: no deletion prompt and no failure-policy abort. `retry_policy.js` is a NEW file but an internal module, not an export, so it creates no function. **What was actually wrong: `toCountryCode`/`toProvinceCode` could emit values outside Wave's GraphQL ENUM vocabulary, and that is a permanent kill, not a dropped field.** An unrecognised enum value fails variable coercion, so Wave answers with a *top-level* GraphQL error rather than a per-field `inputErrors` entry — the worker classifies that non-retryable and dead-letters the job, and a `dead` job never retries on its own. Two ways in, both reachable from one typo in one address: `toCountryCode` accepted any `/^[A-Z]{2}$/`, so a province typed into the country box ("ON", "QC") was sent as a country code; and a plain 2-letter province was prefixed `CA-` **unconditionally**, so a US client in "NY" went as the non-existent `CA-NY`. Both are now membership tests against real ISO-3166-1 / ISO-3166-2 sets, the country is resolved FIRST so it decides which country's subdivisions a bare "QC"/"NY" is read against, and a value that isn't a real subdivision is **omitted** — one missing address line beats a client that can never sync again. Also in: `graphql` errors that look transient (internal/timeout/unavailable, which Wave returns on HTTP 200) are now retryable; a rate-limited job gets a 20-attempt budget instead of the ordinary 5, because a rate-limit says nothing about whether the payload can ever succeed and a bulk backfill enqueues hundreds at once; the dead-letter log gains `errorDetail` (PII-free) because `sanitized` flattens every transport failure to "WaveApiError(graphql)" and without it a dead job is undiagnosable. **`waveRetryFailedJobs`' RESPONSE gains a `failed` key** — same null-is-unknown contract as `pushed` — since the drain behind a requeue usually dead-letters the same job again inside the same call, leaving the queue's dead count unchanged while the app, seeing only `requeued`, announced success. **No request-side change anywhere:** every `assertPayloadShape` allowlist and every `requireString` cap is byte-identical to `6d41dd3c`, so no shipped build can be broken by this; the added response key is ignored by any build that doesn't read it, and backend-first ordering is preserved for the build that will. **No rules and no index change** — `firestore.rules` and `storage.rules` were already byte-identical to prod (`"already up to date, skipping upload"`, merely re-released) and `firestore.indexes.json` is untouched, so `firestore:indexes` was deliberately omitted and the surviving `signupCodes` TTL override was never at risk. Deployed without `--force`; no secret prompt (`WAVE_FULL_ACCESS_TOKEN` v1 still the only binding). **Pre-flight:** `npm run lint` clean, **1209/1209 jest across 48 suites** (up from 1160 — the new `wave_retry_policy.test.js` plus mapper and callable cases). **Verified post-deploy:** all 25 reported "Successful update operation" (0 creates, 0 deletions), `firebase functions:list` returns exactly 25 matching the exports, rules + storage released; the two changed surfaces rolled to `waveupsertcustomer-00044-ciq` and `waveretryfailedjobs-00003-kuj`, both `ACTIVE` with startup TCP probes passing on the first attempt, no `Cannot find module`/`SyntaxError`/startup failure. **ACTION LEFT: the two dead-lettered jobs are still dead and will NOT self-heal** — clients `6GKdxhkzWH8HWYjwrolZ` and `GAQJI0Ctadf8ppVHbSOE`, last re-dead-lettered 16:05Z today, before this deploy. They now stand a real chance of succeeding because the payload changed, which was not true at the previous row: press **Settings › Retry failed** (or invoke `waveRetryFailedJobs`) and read the new `failed` count rather than `requeued` to know whether it worked. If they dead-letter a third time, the new `errorDetail` in the `WAVE-WORKER dead-lettering job` log line names the actual GraphQL refusal. **Still outstanding, unchanged by this deploy:** the 3 orphaned Cloud Scheduler jobs, the appointment-images backfill, and the accepted `clients.addressLine2` cap risk from the previous row. |
| 2026-08-15 | `be56f118` | functions, rules, storage | 25 | **The SECOND Wave fix of the day, and the one that actually unblocks the two dead-lettered upserts — `functions/wave/customers.js` only.** No export change (25 → 25, `functions/index.js` untouched), so neither known abort fired. **Found because the previous row's deploy made it visible:** `errorDetail` on the dead-letter log line turned "WaveApiError(graphql)" into `codes=[NOT_FOUND] fields=[customerPatch]`, i.e. a `waveCustomerId` pointing at a customer that had been **deleted in Wave**. Note what that means for the previous row's diagnosis — the enum-coercion bug was real and worth fixing, but it was NOT what these two jobs were dying of. **Why this class of dead-letter was unrecoverable in a way ordinary ones are not: the offending value is STORED on the doc.** Wave reports a missing patch target as a top-level GraphQL error (so it arrives as the correctly-non-retryable `WaveApiError('graphql')`) or, equivalently, as a `NOT_FOUND` inputError; either way every later push and every "Retry failed" press re-sent the same missing id and failed identically, so the Settings row read "2 clients failed to sync" with no way to clear it. `upsertCustomer` now routes both shapes (`isStaleCustomerLink` / `hasNotFoundInputError`) into the create path **with the identity search FORCED on** — the same route a crashed create takes, and what stops a spurious `NOT_FOUND` minting a duplicate customer instead of relinking. `writeSyncSuccess` needed the matching exception: it sets `waveCustomerId` only on a doc that is still *unlinked* (that is what keeps it idempotent), so the healed link would never have persisted — `replacesLink` is that carve-out, conditioned on the stale id still being the one on the doc, so a link established concurrently is newer, unproven-dead, and wins. Predicates are deliberately narrow (a structured `NOT_FOUND` code, never a text match on Wave's message): this is the one path that REWRITES a client's Wave identity. **No rules, index, payload or secret change** — both rules files were byte-identical to prod and merely re-released, `firestore:indexes` omitted, every `assertPayloadShape` allowlist and `requireString` cap identical to `e84a66fd`. Deployed without `--force`. **Pre-flight:** `npm run lint` clean, **1215/1215 jest across 48 suites** (up 6 — the stale-link cases). **Verified post-deploy:** all 25 "Successful update operation" (0 creates, 0 deletions), `firebase functions:list` returns 25 matching the exports, rules + storage released, `waveUpsertCustomer` rolled to a new revision at 01:05:20Z with its startup TCP probe passing first attempt. **The log scan mattered more than usual here** — this change adds a **module-scope `require("./client")` to `customers.js`**, and a require cycle would surface exactly as a startup failure; the scan for `Cannot find module` / `SyntaxError` / circular-require / any ERROR in the window came back **empty**. (The cycle is genuinely absent: `client.js` requires only `./auth`, lazily.) **DEPLOYED FROM AN UNCOMMITTED TREE**, as the `56cfb5e` row once was; committed immediately after as `be56f118`, which is the hash above. **ACTION LEFT, now with a real recovery path:** press **Settings › Retry failed** once for clients `6GKdxhkzWH8HWYjwrolZ` and `GAQJI0Ctadf8ppVHbSOE` — they relink or recreate instead of failing, where before this deploy the press was guaranteed to fail. Read the `failed` count, not `requeued`. **Still outstanding:** the 3 orphaned Cloud Scheduler jobs, the appointment-images backfill, and the accepted `clients.addressLine2` cap risk. |

### The `#compat-1.37.1` shim — RETIRED 2026-08-08

**Gone.** No shipping code or rule is gated on it any more. Kept here as the
record of what was removed and why, so none of it is re-added by accident.
`grep -rn "#compat-1.37.1"` still hits this file, the two CLAUDE.mds,
`docs/ARCHITECTURE.md`, `docs/CLOUD_FUNCTIONS.md`, `docs/cost-breakdown.html`
and the dated `docs/audits/` + `docs/plans/` snapshots — all of those are
history now, not instructions. It also hits `functions/wave/callables.js` and
`lib/features/wave/data/wave_service.dart`, which were **never** deletion sites
(see the `waveImportCustomers` note at the end of this section).

The shim existed for 1.37.1+64 (`2b1ace5`, head of `origin/notification`), which
was the App Store build from P4c until 1.40.0+65 replaced it. The owner
confirmed 2026-08-08 that **every device in the fleet is on 1.40+**, which is
the gate this always waited on — note the gate is "no device still RUNS it", not
"it is no longer downloadable". Retired in one sweep:

| What | Why it could go |
|---|---|
| `createEmployeeInvite`, `redeemSignupCode`, `invites.js`, `signup_code_utils.js` (+ both jest suites), the `/signupCodes` rules block and its `firestore.indexes.json` TTL entry | Only 1.37.1 called them (`firebase_employees_repository.dart:82`, `:109`). 1.40.0+ has no reference anywhere in `lib/`. The `signupCodes` collection was verified **empty in prod** before the TTL policy was dropped, so nothing is stranded. |
| `allow delete` on `/users`, and the fourth `/users` read clause (`email_verified` + `invited` + email match) | 1.40.0+ has no users-doc delete path, and an invited person reads their own doc through clause 3 (`uid` is set at creation by `createEmployeeAccount`). |
| `allow delete` on `/clients` | 1.40.0's Delete button is behind `kShowTestingDeleteClient = kDebugMode`, so it is unreachable in any release build; 1.41+ removed it outright. `deleteClient` is now the only delete path in rules as well as in code. |

**Two real holes closed with it** — while the grants were live, an admin on the
old build could delete a client with job history (orphaning those appointments,
exactly what `deleteClient`'s live `count()` gate prevents) or delete a `users`
doc (permanently orphaning every past appointment's `employeeIds` crew link).

**One related hole is still OPEN and is NOT part of this sweep:** `allow update`
on `/users` denylists only `uid`/`termsAcceptedAt`/`locationConsentAt`, so
`email` can still be written directly to Firestore without the matching Auth
change. The current build never does — every email edit routes through
`changeEmployeeEmail` — so tightening the rule now costs nothing, and the reason
it waited (breaking 1.37.1's employee edit) is gone. The suggested clause is in
`docs/audits/CODEBASE_AUDIT.md`. Do it as its own reviewed change; it is a rules
*tightening*, not a removal.

Also unblocked by this retirement, and likewise not done here: **disabling open
sign-up in the Firebase Auth console** (F1 in
`docs/audits/SECURITY_ASSESSMENT_2026-08-04.md`), which shared this gate because
1.37.1's invite acceptance called client-side `register()`.

Note `waveImportCustomers` was tagged `#compat-1.37.1` but is **not** a deletion
site and keeps its (inaccurate, two-way) name: renaming a deployed callable
breaks every shipped build, not just the old one.
