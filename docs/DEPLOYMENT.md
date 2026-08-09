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

**Expected, ignore:** 3 warnings for `isAvailabilityOnlyChange` — one "Unused
function" and two "Invalid variable name". All three are artifacts of it being
uncalled and disappear when P5 wires it up.

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
