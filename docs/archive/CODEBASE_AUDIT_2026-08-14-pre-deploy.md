# Codebase Audit — 2026-08-14 (pre-deploy pass)

> **STATUS: all 27 findings CLOSED at `10545972`** (2026-08-14), and the three
> follow-ups it left were done 2026-08-15 — rules + indexes deployed and the
> legal pages republished, all verified live.
>
> **Restored from git history 2026-08-15.** This snapshot and its sibling
> `-first-pass` were overwritten in place by the next sweep instead of being
> archived, which is why neither appeared here until now; the content below is
> the file exactly as it stood at `669f2e31`.

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `docs/`, `.claude/`). Baseline: `2ca8013b` on
`redesgin`, working tree carrying the /doctor-pass docs changes.

**Context: this audit was run immediately before deploying the pending backend
and running the Wave client-name/phone backfill.** Findings are weighted toward
what breaks once deployed, and toward the client-name/phone path specifically.

## Summary

- Scanned: ~54k lines Dart (261 test files), ~29k lines `functions/` JS (45 jest
  suites), both rules files, 51 composite indexes, all `docs/` + `.claude/`.
- Auto-fixed (safe, in the diff): **7 files, documentation only** — no code was
  changed. Three of them were actively wrong in a way that misleads future work.
- Reported for your decision: **27** (⚠️ 0 pre-ship · 🔴 3 security · 🟠 8 bugs ·
  🔵 16 improvements)
- Verification: `flutter analyze` **No issues found!** (unchanged from baseline) ·
  `flutter test` **2071/2071 passing** · `functions` jest **1077/1077 across 45
  suites** · `npm run lint` clean · **`firestore.rules` and `storage.rules` both
  compile with zero errors**.

### Top 3 to look at first

1. **B1 — the Wave import can silently revert the backfill you are about to
   run.** `listOutstandingClientIds` protects `queued`/`inflight` jobs but not
   `dead` ones, and a bulk push against Wave's 60/min ceiling is exactly what
   produces dead jobs. One word fixes it.
2. **B2/B3 — two `ref.read`-in-`catch` crash sites**, one of them in the very
   file whose sibling method carries a seven-line comment about this same bug
   having shipped as a FATAL.
3. **D1 — the deploy is a 3-delete/3-add swap at an unchanged count of 25**, so
   a count check passes while three functions get deleted. Already correctly
   documented in `docs/DEPLOYMENT.md`; the risk is trusting the count.

---

## Deploy readiness — verified against live production

Checked against the real project, not the docs:

| Check | Result |
|---|---|
| Functions live in prod | **25** — matches `45302651` |
| Export set vs. local | **3 removed / 3 added**, count unchanged at 25 |
| `firestore.rules` compiles | ✅ zero errors (runbook expected 3 warnings — there are none) |
| `storage.rules` compiles | ✅ zero errors |
| Required composite indexes | ✅ all present, incl. new `(status, endTime DESC)` and `(archived, name, __name__)` |
| Client `name` rules cap | ✅ **225** = `personName` 200 + 1 + `phone` 24 |
| Scheduled functions | 6 live → 3 after deploy (back inside the free allowance) |

**D1 — the deletion abort.** `waveScheduledImport`, `waveSyncWorker` and
`sendOverdueJobPrompts` are all live and all scheduled. `firebase deploy` aborts
non-interactively on deletion, leaving prod on new-rules + old-functions.
`docs/DEPLOYMENT.md` §"Pending: a THREE-deletion deploy" already carries the
exact commands and the three orphaned Cloud Scheduler jobs to clean up
afterwards — **follow that section; do not trust the export count.**

Incidental: `validateUploadedImage` runs in **us-east1** while every other
function is us-central1. Expected for a Storage trigger bound to the bucket's
region, but `CLAUDE.md` states us-central1 globally — worth a word confirming
it's deliberate.

---

## Auto-applied cleanups (review the diff)

All seven are documentation. No behavior, no code.

| File | Change | Why |
|---|---|---|
| `.claude/rules/testing.md:4` | `functions/test/**` → `functions/__tests__/**` | That directory **does not exist** — the testing rules never loaded for any Cloud Functions test work. Answers the open "is `paths:` frontmatter working?" question: for this file, it wasn't. |
| `.claude/skills/codebase-audit/references/project-map.md:48` | Removed `confirmed` from the status allowlist; noted `overdue` is display-only | The audit skill's own "do not touch" reference taught a **retired** status as live. A future pass could have "restored" it into the rules. |
| `project-map.md:4` | Feature list: added the 8 missing dirs | Omitted `dashboard`, `feature_tour`, `home_widget`, `live_activity`, `navigation`, `notifications`, `presence`, `siri`. |
| `project-map.md:36` | Corrected the `analysis_options.yaml` exclude list | Claimed `*.g.dart` and `lib/l10n/generated/**`; actual are `**/*.freezed.dart`, `lib/l10n/.gen/**`, `lib/firebase_options.dart`, `build/**`, `.dart_tool/**`. |
| `project-map.md:80` | Noted there are currently **zero** `TODO(pre-ship)` markers | The bullet pointed at nothing, making an empty Pre-ship section look like an oversight. |
| `.claude/rules/security.md:29` | App Check module list: dropped deleted `invites.js`, added `clients.js` + `employee_accounts.js` | The two most sensitive callable modules were missing from the list a reviewer checks against. |
| `.claude/skills/.../security-checklist.md` | `/users` read rule: four clauses → **three**; `resolveMyInvite` → the real rate-limited routes | An auditor would have hunted a clause deleted 2026-08-08 and skipped the routes that actually carry the limit. |
| `CLAUDE.md:458` | Siri schema v2 → noted current value is **3** | Code is 3 in both `schedule_snapshot.dart:10` and `ScheduleSnapshot.swift:21`; line 605 already said v3, so the file contradicted itself. |
| `docs/ARCHITECTURE.md:1101` | Test counts → 2071 Flutter / 1077 jest (45 suites) | Measured from actual runner output this session. |
| `docs/plans/README.md:143` | Rewrote the client-phone-backfill ops entry | **The dangerous one.** It said the backfill "has not been run for real" while referencing "the earlier botched run" four lines later. It *did* run against prod 2026-08-08, renamed real Wave customers, and was reversed 2026-08-14. Acting on the old text re-inflicts damage the damage-audit script calls unrecoverable from the doc. |

> Full detail is in `git diff`. Nothing below this line was auto-changed.

---

## ⚠️ Pre-ship checklist

**None.** Verified zero `TODO(pre-ship)` markers repo-wide, zero
`enforceAppCheck: false`, and `lib/core/testing_flags.dart` is gone. This
section is genuinely empty, not skipped.

---

## 🔴 Security findings

### S1 — Wave import writes an uncapped `name`, making the client permanently un-editable · medium · high
- **Where:** `functions/wave/mappers.js:281` (`fromWaveCustomer`) vs
  `firestore.rules:667` (`data.name.size() <= 225`)
- **Risk:** `importCustomers` runs under the Admin SDK, which **bypasses rules**,
  and neither `fromWaveCustomer` nor `importCustomers` caps `name` length. A Wave
  customer with a name over 225 chars imports fine, then every subsequent app
  save of that client fails with an opaque `permission-denied` — taking the
  address, contacts and billing edits in the same save with it. The edit sheet
  seeds its name field from `baseNameFor` with no truncation, and
  `LengthLimitingTextInputFormatter` only limits *subsequent* edits, so the admin
  cannot obviously repair it. **This matters more after your change**, because
  the stored name now deliberately carries the phone number — the value is longer
  by the width of a phone number than it used to be.
- **Fix:** clamp `name` in `fromWaveCustomer` to 200 before the number is
  appended, or add a `clientFieldNotWidened('name')` branch to `allow update`
  mirroring the existing `appointmentSpanNotWidened` / `emergencyFieldNotSet`
  asymmetry — both exist precisely so an over-cap doc stays updatable.

### S2 — Composed client values can exceed their rules cap · low · high (arithmetic) / low (reachability)
- **Where:** `edit_client_sheet.dart:220` (name 200 + 1 + **mobile 32** = 233 >
  225); `edit_client_sheet.dart:158` (street 500 + apt 32 vs `address` cap 500);
  appointment `clientName` = `firstName` 200 + 1 + `lastName` 200 = 401 vs
  `firestore.rules:531` cap of 200
- **Risk:** each surfaces as an opaque `permission-denied` on an ordinary save.
  All three need unrealistic field lengths, so this is robustness rather than a
  blocker — but `text_limits_test.dart` currently pins only the
  `personName + 1 + phone` sum, so none of these three is covered by the very
  mechanism the repo relies on to catch this class of bug.
- **Fix:** extend `text_limits_test.dart` with the three composed cases, then
  raise whichever rules cap the arithmetic demands.

### S3 — `changeEmployeeEmail`'s admin branch is not re-auth gated · low · high — **documented residual, not a regression**
- **Where:** `functions/employee_accounts.js:445` — `if (!isAdmin) assertFreshReauth(...)`
- **Risk:** an unattended, already-authenticated admin session can rewrite any
  employee's sign-in email with no re-authentication, bounded only by
  `assertAdmin` and 5/hour.
- **Why it stays:** keying the gate on `isSelf` instead broke every admin roster
  save with an opaque `stale-auth`, because `updateEmployee` has no re-auth step
  to satisfy. `CLAUDE.md` states this residue accurately. **Listed only so it is
  not mistaken for a new finding.** Closing it needs a re-auth prompt on the
  admin save path first.

**Verified clean (deploy-critical):** the `/users` two-branch update and its
load-bearing outer parentheses · `isAvailabilityOnlyChange` ↔
`kSelfServiceUserFields` exact 7-key match · every function-owned denylist
(`uid`/`termsAcceptedAt`/`locationConsentAt`, `waveCustomerId`/`wave`/`jobCount`,
`pictureCount`) on both create and update · `isValidAppointmentSpan` incl. the
`+2h` DST allowance · `storage.rules`' `status == 'active'` gate on both branches
· guard order on all 12 callables, with `completeEmployeeSetup` failing **closed**
on a missing token · no hardcoded secrets; no PII in any `functions/` log · all
four credential fields set `enableIMEPersonalizedLearning: false` ·
`android/local.properties` absent from this branch and `/android/` still ignored.

---

## 🟠 Bug findings

### B1 — The Wave import can clobber a **dead-lettered** client's un-pushed edit · medium-high · high
- **Where:** `functions/wave/worker.js:1046` (`listOutstandingClientIds`), consumed
  at `functions/wave/customers.js:628`
- **Problem:** `functions/CLAUDE.md` states the invariant as *"AN IMPORT MUST
  NEVER TOUCH A CLIENT WITH AN UN-PUSHED OUTBOX JOB"*, but the protect list is
  `.where("status", "in", ["queued", "inflight"])`. **`dead` is a fourth status**
  (set at `worker.js:531` and `:770`) and a dead job is un-pushed too — that is
  the entire reason `waveRetryFailedJobs` exists. The docstring justifies
  including `inflight` and never considers `dead`.
- **Why it matters right now:** dead-lettering fires on *"not retryable OR
  attempts cap reached"*. The backfill's own header warns it fires "a few hundred
  Wave GraphQL mutations within seconds… against Wave's 60-calls/min ceiling" —
  which is precisely how jobs exhaust their attempts and dead-letter. The next
  unattended import then overwrites `name` with Wave's **pre-backfill** value and
  stamps `lastSyncedHash` from it; a later `waveRetryFailedJobs` requeue
  short-circuits as `noop` on the matching hash, and `healSyncState` clears the
  badge. **The rename is silently undone and the row reads "Synced with Wave".**
- **Honest scoping:** the `hasCreatedAt && lastSyncedHash === hash` gate at
  `customers.js:643` *incidentally* protects the common case, because Wave still
  holds the pre-edit state so the hashes match. It fails to protect when (a) the
  doc has no `createdAt` — legacy import docs, which is why `hasCreatedAt` is in
  the condition at all — or (b) the round-trip hash differs for an unrelated
  reason, notably `mobile`, which the import reads back from Wave while
  `EditClientSheet._save` clears it locally.
- **Fix:** add `"dead"` to the status filter, and update the docstring. A dead
  job's edit is the one *most* at risk, because it will not self-heal.

### B2 — `ref.read` inside a `catch` after an await — `_selectSuggestion` · medium · high
- **Where:** `lib/shared/widgets/fields/address_autocomplete_field.dart:193`
- **Problem:** `ref.read(loggerProvider)` sits inside the `catch`, **above** the
  `if (!mounted) return;` at :197, after awaiting `getPlaceDetails`. Under
  Riverpod 3 `ref.read` on an unmounted consumer throws a `StateError`
  unconditionally. This is the **exact** failure `CLAUDE.md` documents as having
  escaped to the zone handler as a **FATAL** — and the fix *was* applied to the
  sibling method in the same file (`:114`, under a seven-line comment naming it),
  and missed here. Invoked fire-and-forget from `onTap`, so the sheet being
  dismissed before Places responds is routine.
- **Fix:** hoist `final logger = ref.read(loggerProvider);` above the `await`.

### B3 — Same pattern — `EventDetailsController._loadStoredPictures` · medium · high
- **Where:** `lib/features/calendar/application/event_details_controller.dart:139`
- **Problem:** same shape on a `NotifierProvider.autoDispose.family`, fired
  from `build()` via `Future.microtask`. `repo` is correctly hoisted at :135; the
  logger is not. The author checks `ref.mounted` at :145, which proves disposal
  here is known to be real — so a failed subcollection read throws a `StateError`
  *over* the real failure and loses the `APPT-IMG` breadcrumb.
- **Fix:** same hoist.

### B4 — Eleven more `ref.read`-after-await sites · medium → low · high
- **Where:** `my_details_screen.dart:128,203,266,272,315` ·
  `account_setup_screen.dart:213,256,325` · `settings_screen.dart:250` ·
  `contact_export_launcher.dart:56` · `appointment_history_view.dart:134`
- **Problem:** same class, smaller blast radius. Several already hoist `notices`
  or `repository` in the same method and missed only the logger;
  `appointment_history_view.dart:134` directly contradicts its own twin
  `clients_list_view.dart:83`, which *was* fixed.
- **Fix:** same hoist. **Note for any CI check:** a single-line grep for
  `ref.read(` finds **none** of these — they are all multi-line `ref\n  .read(...)`
  chains. That is why they survived previous passes.

### B5 — Hard casts on every employees stream · medium-high · high
- **Where:** `lib/features/employees/domain/models/employee_record.dart:69,72,74,76`
- **Problem:** `data['jobTitle'] as String?` and `(data['workStartMinutes'] as num?)`
  ×3, while **every other field in the same factory is lenient** — `(data['name']
  ?? '').toString()`, `int.tryParse` for `colorValue`, `firestoreDateTime` four
  rows below. This factory runs inside three `snapshots().map(...)` chains plus
  `splash_controller.dart:69` and `sign_in_controller.dart:135`. One
  console-edited user doc with a numeric `jobTitle` or a string `"480"` kills the
  crew picker, day route, live-map roster and calendar dots app-wide — and
  becomes a **sign-in failure**.
- **Fix:** `JobTitle.fromRaw(data['jobTitle']?.toString())` and
  `int.tryParse(data['workStartMinutes']?.toString() ?? '')` — matching the
  `colorValue` line already in the file.

### B6 — Cast defeats the function's own documented contract · medium · high
- **Where:** `lib/features/presence/data/presence_repository.dart:100`
- **Problem:** `_toFixes`'s docstring at :83 says *"One malformed doc must not
  drop the whole map — skip it and keep going"*, and it type-tests `lat`/`lng`
  with `is! num` at :92 — then hard-casts `(data['updatedAt'] as Timestamp?)`.
  A string instant throws inside `snapshots().map`, blanking the **whole** admin
  live map. This is the last raw `as Timestamp?` in `lib/`;
  `firebase_appointments_repository.dart:729` documents removing this exact cast
  as a bug.
- **Fix:** `firestoreDateTime(data['updatedAt'])` — the lenient primitive exists.

### B7 — The superseded backfill is guarded by a comment only · low severity / **high blast radius** · high
- **Where:** `functions/scripts/backfill-client-phone-from-name.js:264`
- **Problem:** the header is an emphatic *"DO NOT RUN THIS SCRIPT AGAIN"*, but
  `main()` has no refusal — the shebang, the executable bit and
  `if (require.main === module) main()` are all live. Re-running it redoes the
  Wave rename against every client the reversal just repaired. It sits one
  tab-completion away from the script you *do* want
  (`backfill-client-phone-from-name` vs `backfill-client-name-with-phone`), and
  its replacement already applies this repo's "turn the comment into a failure"
  discipline via `assertKnownFlags`.
- **Fix:** first line of `main()`:
  `throw new Error("SUPERSEDED — see backfill-client-name-with-phone.js")`. The
  `require.main` split keeps `extractPhone`/`patchFor` requirable by jest.

### B8 — The damage-audit script is broken · low · high
- **Where:** `docs/audits/audit-client-phone-backfill-damage.js:45`
- **Problem:** `require("./backfill-client-phone-from-name")` — the file lives in
  `functions/scripts/`. Throws `MODULE_NOT_FOUND` immediately. This is the *only*
  tool for assessing the 2026-08-08 rename damage.
- **Fix:** correct the path; the usage header at :36 is stale too.

**Verified clean:** `ClientNamePolicy` ↔ `client_name_utils.js` agree on
`stripPhone`, `composeStored`, `isBusiness` and `displayFor` branch order, and
`composeStored`/`stripPhone` are inverses and both idempotent · every other
hand-mirrored pair in lockstep (`appointment_day_slice` ↔ `day_slice_utils`,
`appointment_image_doc_id` ↔ `appointment_image_ids`, `maxAppointmentSpanDays` ↔
`MAX_APPOINTMENT_SPAN_DAYS` ↔ the rules bound, `kSelfServiceUserFields` ↔
`isAvailabilityOnlyChange`, `image_magic` both sides) · photo migration: single
`WriteBatch`, cascade rethrows and covers all three delete paths, `_resolvedFor`
gating and the viewer offset correct · every `appointmentsInRangeProvider`
consumer re-scopes through `runsOn` · `Stream.listen` always passes `onError` ·
zero `throw Exception(` in `lib/` · exactly the 3 sanctioned SnackBar sites · no
`FirebaseFirestore.instance` in UI · **l10n: 720 keys, 0 orphans, 0 EN/FR drift,
0 missing `@key` blocks** · zero unused dependencies (all 5 heuristic hits are
legitimate codegen/lint/config/SPM entries).

---

## 🔵 Areas to improve

### I1 — `displayName`'s branch is untested *and* its arguments default fail-open · high · high
- **Where:** `client_record.dart:155` → `client_name_policy.dart:202`
- **Opportunity:** `displayFor` declares `businessName = ''` and
  `type = ClientType.unset` **as defaults**, so dropping either argument at the
  call site still compiles and silently takes the *person* branch. The only test
  (`client_record_test.dart:43`) never sets `type:` or `businessName:` — its
  "Vogas Plumbing" case passes through the **no-halves fallback**, not the
  business branch. Net: you could drop the `type:` argument, keep the whole suite
  green, and render every commercial client as its contact person on every card,
  tile and appointment. The `fromMap` test at :130 doesn't discriminate either.
- **Suggested improvement:** add
  `ClientRecord(type: ClientType.commercial, name: 'Vogas Plumbing (514) 555-1234', firstName: 'Marc', lastName: 'Tremblay').displayName == 'Vogas Plumbing'`
  plus the legacy-`businessName`-with-no-`type` twin. Consider making `type`
  required.

### I2 — `ClientNamePolicy.baseNameFor` has zero Dart tests · high · high
- **Where:** `client_name_policy.dart:146`
- **Opportunity:** grepped across `lib/`, `test/` and `functions/`: the only
  references are the policy, `edit_client_sheet.dart:93`, and the **JS** side —
  which has 4 worked examples in
  `functions/__tests__/backfill_client_name_with_phone.test.js:147`. The mirror
  discipline is **one-sided on the one function whose own docstring says getting
  it wrong renames real Wave customers**, and the Dart copy seeds the edit
  sheet's name field on every client edit.
- **Suggested improvement:** port the four JS cases verbatim.

### I3 — Nothing asserts the phone stays in the Wave customer name · high · high
- **Where:** `functions/wave/mappers.js:164` (`toWaveCustomerInput`)
- **Opportunity:** every fixture in `wave_mappers.test.js` uses bare names
  ("Acme Corp", "Solo", "T"). The entire owner change rests on `name` reaching
  Wave **verbatim, with the number**; a future "cleanup" applying
  `clientDisplayName` there would break invoice identification with nothing
  failing.
- **Suggested improvement:** one assertion —
  `toWaveCustomerInput({name: 'Marc Tremblay (514) 555-1234', …}).name` is
  unchanged.

### I4 — Client-name round-trip untested at the sheet level · medium-high · high
- **Where:** `add_client_sheet_test.dart`, `edit_client_sheet_test.dart`
- **Opportunity:** grepped `saved.name` in both: **zero hits**. They assert
  `saved.phone` heavily but never that the persisted `name` came back as
  `"<base> <phone>"`, nor that a re-save doesn't stack a second number — which is
  the whole point of `composeStored`'s idempotence.
- **Suggested improvement:** one assertion per sheet, plus a save-twice case.

### I5 — `relevantClientChange` fixtures don't cover the strip · medium-high · high
- **Where:** `functions/client_propagation.js:76`
- **Opportunity:** fixtures are `{name:"Ada", phone:"555"}`. Nothing proves a
  phone-only edit produces **no** `clientName` patch, nor that a name edit
  propagates the *stripped* form — which is what keeps appointment cards from
  showing the number.
- **Suggested improvement:** two cases.

### I6 — `_allowedStatuses` isn't pinned to the rules · medium · high
- **Where:** `firebase_appointments_repository.dart:426` vs
  `firestore.rules:431`
- **Opportunity:** this repo has an established mechanism for exactly this —
  `text_limits_test.dart`, `self_service_fields_test.dart` and
  `appointment_span_rules_test.dart` all read `firestore.rules` back and fail the
  build on drift. The status allowlist, one of the most load-bearing duplications
  in the codebase, has no such pin. (This audit found the *documentation* copy of
  that allowlist had already drifted — see the auto-fix table.)
- **Suggested improvement:** a fourth rules-reading test.

### I7 — `_patchWindow`'s merge semantics untested · medium · high
- **Where:** `firebase_clients_repository.dart`
- **Opportunity:** nothing asserts that function-owned `jobCount`/`createdAt`
  survive a patch — which is the documented reason it merges rather than
  substitutes.

### I8 — Remaining hard casts on Firestore reads · medium → low · high
- **Where:** `firebase_appointments_repository.dart:746`
  (`data['employeeIds'] as List<dynamic>?`, on the double-booking path, 12 lines
  below a comment explaining a raw `startTime` cast was removed for this reason —
  and `AppointmentRecord._parseStringList` already handles `employeeIds` arriving
  as a bare String, so the codebase asserts that shape exists) ·
  `client_record.dart:108,109,114,115` (`as bool?` ×3 and `as num?` for the
  function-owned `jobCount`, beside a lenient `ClientType.fromRaw` at :110) ·
  `google_places_repository.dart:97,155`

### I9 — Unawaited async UI callback with no `try` · medium · high
- **Where:** `lib/core/app/photo_upload_failure_listener.dart:70`
- **Opportunity:** the SnackBar's Open action awaits `getAppointmentById`, which
  rethrows. Offline or `permission-denied` escapes an unawaited async callback
  into the zone handler as a **fatal**, and the user gets no feedback. Secondary:
  the SnackBar is hosted by `ScaffoldMessenger` and can outlive this `State`, so
  the `ref.read` itself can throw (same class as B2/B4).
- **Suggested improvement:** hoist `repo`/`logger`/`notices`, wrap in try/catch
  with `logger.warn` + `composeErrorNotice`.

### I10 — God files, ranked by size × churn · medium · high
| File | Lines | Commits (3mo) | Concrete extraction |
|---|---|---|---|
| `firebase_appointments_repository.dart` | 831 | 29 | Lift the search-cache cluster (`_searchCache`, `_scanWindow`, `_cacheSearch`, `_invalidateSearchCache`, `matchHistoryDocs`, the two `_Cached*` classes) into an `AppointmentHistorySearchCache` collaborator — ~150 lines, and it turns "every write path must invalidate" from a convention into an explicit dependency. |
| `main_calendar_screen.dart` | 775 | 44 | `_CollapseHandle` (655-716) and `_TodayPill` (717-775) are self-contained private widgets → `calendar/widgets/`. −120 lines, zero risk. |
| `settings_screen.dart` | 592 | 45 | The delete-account flow (`_confirmDeleteAccount`, `_runDeletion`, `_BlockingProgressOverlay`) is a cohesive ~130-line security-adjacent concern. |
| `functions/wave/callables.js` | 962 | — | `waveImportCustomers`' handler body is **157 lines inline** (567-724), `waveUpsertCustomer` ~133. Extract each to a named function beside `importWithWatermark`/`drainForSync`, which already follow that shape in the same file. |
| `functions/wave/worker.js` | 1081 | — | Lines 825-1072 (`countQueuedJobs`, `countDeadJobs`, `requeueDeadJobs`, `listOutstandingClientIds`) are admin/ops queries, not the queue engine — a clean `worker_admin.js` split at an existing section banner. |

### I11 — `build()` length is systemically over the project's own limit · low · high
- **68 of 311 `build()` methods (22%) exceed 60 lines.** Worst:
  `weekly_bar_chart.dart:38` (124), `client_search_field.dart:40` (123),
  `employee_details_view.dart:43` (120), `calendar_month_grid.dart:179` (119),
  `employee_picker.dart:28` (107).
- **The pattern to copy already exists in the repo:** `edit_person_sheet.dart`
  and `appointment_form_fields.dart` are 607/631-line files whose `build()`s are
  only 22 and 15 lines, because they delegate to `_detailsSection()` /
  `_whoSection()` list-builders. Apply that to the five above rather than
  inventing anything.

### I12 — Untested shared helpers · medium → low · high
- `assignee_resolver.dart:11` (`assigneeNameAt`) — owns the positional bounds
  check at 6 call sites, and the edit-sheet caller's result is **written back to
  Firestore**. Zero direct tests.
- `appointment_form_validator.dart:151` (`runLengthDays`) — zero tests, though
  its neighbours `allDaySpan`/`appointmentSpan` are well covered. It was
  extracted precisely because both form bodies had copied it.
- `guardedOffline` (`core/errors/error_cause.dart:80`) — zero tests despite 9
  call sites; `composeErrorNotice` beside it is tested.
- `functions/scripts/backfill-appointment-images.js` — no jest spec, unlike both
  client backfills. Its stated guarantee (atomic per appointment) is exactly a
  testable claim.

### I13 — `allPresenceStreamProvider` re-opens a collection-group listener on every drawer open · medium · high
- **Where:** `lib/features/presence/application/live_map_providers.dart:8`, consumed
  via `_onTheClockCount` at `navigation/widgets/app_nav_drawer.dart:324`
- **Opportunity:** it is `autoDispose` with **no `keepWarmWithGrace`** — the only
  collection/range provider in the app without it (`appointmentsInRangeProvider`,
  `dashboardHistoryProvider` and `newClientsProvider` all have it). Flutter's
  `DrawerController` doesn't build its child while dismissed, so the
  `collectionGroup('presence')` listener is established fresh on every admin
  drawer open and torn down on close — purely to render the Live Map row's badge
  number. Roughly one read per staff member with location enabled, per drawer
  open (~600 reads/day at 20 staff × 30 opens).
- **Suggested improvement:** add `keepWarmWithGrace(ref)` — the same 3-minute
  grace the appointment providers already use. One line, and it makes the
  provider consistent with every other listener in the app.

### I14 — Three small query/cache guardrails · low · high
- `firebase_employees_repository.dart:183` — `where('email', isEqualTo: …).get()`
  is the **only Firestore query in any repository with no upper bound at all**;
  every other one names a ceiling. Result set is 0–1 in practice, so this is a
  missing guardrail rather than a live cost. Fix: `.limit(2)` — enough to detect
  a collision.
- `presence_repository.dart:76` — `collectionGroup('presence').limit(500)` with
  **no `orderBy`**, the same shape that bit `fetchClientHistory`. Unreachable
  today (presence is one doc per user and the users streams cap at 500), but if
  it ever truncates the live map silently shows an arbitrary `__name__` slice.
  Fix: `.orderBy('updatedAt', descending: true)` so the cap keeps the freshest
  fixes.
- `firebase_clients_repository.dart:85` — `_pageBoundaryNames` is the one
  unbounded cache in the data layer: a `Map` on a session-long singleton that is
  only ever written, never cleared — not by `_patchWindow` or pull-to-refresh,
  both of which clear every other cache in the file. Fix: clear it alongside the
  others, or cap it like `_searchCache`.

### I15 — `displayName` computed twice per row in the clients list · low · high
- **Where:** `lib/features/clients/widgets/cards/client_tile.dart:56`
- **Opportunity:** each call runs `displayFor`, which runs `stripPhone` twice —
  roughly 4 regex passes per visible row per frame while scrolling. The
  repository already treats this getter as expensive and hoists it into a
  precomputed `sortKey` in both `matchClientDocs` and `fetchClientsByType`, with
  a comment saying why; this site didn't get the same treatment.
- **Suggested improvement:** `final name = client.displayName;` once at the top
  of `build`. (Same root cause as the `firebase_clients_repository.dart:374,426`
  note in I16.)

### I16 — Minor leaks and hygiene · low · high
- `main.dart:203,240` — two `StreamSubscription`s never stored or cancelled,
  while `dispose()` at :320 tears down two other resources. Harmless in prod
  (root widget) but stacks a listener per `pumpWidget`.
- `notice_listener.dart:81,90` — `OverlayEntry.remove()` without `dispose()`;
  trips leak-tracking in widget tests.
- `firebase_appointments_repository.dart:80` — `_localWrites` broadcast
  controller never closed; the provider has no `ref.onDispose`.
- `firebase_clients_repository.dart:374,426` — `client.displayName` computed
  twice per record across the 1000-doc scan window; it's an uncached getter that
  runs `stripPhone` each time. Hoist to one local.

---

## 🟡 Code-quality suggestions

- **Dead code (verify, then remove deliberately — the analyzer cannot see these):**
  `client_name_policy.dart:245` `extractPhone` (zero callers in `lib/` or `test/`;
  the same-named JS function belongs to the retired backfill and is unrelated) ·
  `design_tokens.dart:161` `AppRadius.rThumb` (zero refs; note `r24` at :152 is
  also unreferenced but **is** documented in `frontend.md`'s token scale, so keep
  it) · `month_grid.dart:6` `monthGridMaxRows` (referenced only by its own test) ·
  `consent_row.dart:35` `ConsentRowState` should be private.
- **Candidate dead index:** `firestore.indexes.json:28` `users (email, role,
  status)` — no query constrains all three, and no query pairs `email` with
  anything; likely the retired invite lookup. **Do not remove in this deploy** —
  defer and watch for `FAILED_PRECONDITION`.
- **Stale comments naming deleted exports:** `functions/wave/callables.js:684`
  states in the present tense that `waveScheduledImport` *is* the daily safety
  net — it is the only written explanation of how backed-off and stale-`inflight`
  Wave jobs get retried, so a reader greps for a function that no longer exists.
  `functions/notifications.js:163`'s `logger.error("sendOverdueJobPrompts failed")`
  label names a deleted export (arguably a deliberate stable search tag — your
  call). `history_screen.dart:87` references the deleted `NavigationRail`.
- **`functions/scripts/wave-introspect-customer-sort.js`** — one-off diagnostic
  whose question was answered and shipped; it instructs putting
  `WAVE_FULL_ACCESS_TOKEN` in a shell env var.
- **Published legal pages drifted:** `docs/legal/privacy-policy.html:191` says
  Camera is used "to take appointment **or profile photos**" — there is no
  profile-photo feature (the only Storage path written is
  `appointments/{id}/images/`; avatars are crew-colour + initials). Over-disclosure
  rather than under-, but it is cross-checked against the App Store privacy label.
  `docs/legal/accessibility.html:56` still says "version 1.37 · Last updated July
  31" against a shipping 1.45.0+72. **Remember these must be republished to the
  `es-pro-legal` Pages repo — editing `docs/legal/` alone changes nothing a user
  can read.**
- **`docs/CLOUD_FUNCTIONS.md`** — carries full present-tense sections for the
  deleted `sendOverdueJobPrompts` (:567) and `waveScheduledImport` (:901), the
  latter being the file's last section; and `waveRetryFailedJobs` is the only one
  of the 25 with **no** detail section, despite being new in this deploy and
  binding `WAVE_FULL_ACCESS_TOKEN`.
- **`.claude/workflows/wave-ultra-review.mjs:32-40`** — feeds six stale
  invariants to reviewer subagents as "must not break", including the four
  `/users` read clauses and `confirmed` in the allowlist.

---

## Notes / uncertainties

- **The performance pass needed a retry.** The first reviewer stalled and
  returned nothing; a re-scoped pass (I13–I16) completed and covered repository
  query bounds, provider `autoDispose` coverage, disposal leaks and item
  builders. Its honest headline: this codebase is **already heavily optimized**
  in all four areas — most of the patterns hunted for had already been fixed and
  documented in-code. Verified clean: every repository query has a `.limit` and
  every limit that needs one has a matching `orderBy`; no non-`autoDispose`
  stream provider is consumed only by a transient surface; **zero** confirmed
  disposal misses; **no** `DateFormat` construction inside any item builder and
  no O(n²) scans (all memoized or hoisted).
- Exhaustive per-site raw `EdgeInsets` spacing drift was sampled, not fully
  counted. Colors were counted: 122 of 138 raw `Color(0x…)` are in
  `lib/core/theme/`, and the 16 outside are legitimate palette catalogs.
- Test counts are runner output from this session, not estimates:
  **2071 Flutter, 1077 jest / 45 suites.**
- `git history` still contains the live `MAPS_API_KEY` committed by merge
  `33715f82`. The working tree is clean and `/android/` is ignored, but **the key
  still needs rotating** — carried forward from the 1.44.0 review, value not read
  or reproduced here.
