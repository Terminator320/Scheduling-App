# Codebase Audit — 2026-09-05

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`, `.claude/rules/`, `docs/`).
Baseline: `f884e120` (branch `redesgin`), working tree clean.

The previous rolling audit was archived to
`docs/archive/CODEBASE_AUDIT_2026-09-03-rolling.md` — its still-open items
(Maps billing cap, the Crashlytics re-check that needs a shipped build, the
Wave "Retry failed" press, the Xcode `InfoPlist.strings` confirmation) are
**not** repeated here and are still open.

## Status — ALL 33 IMPLEMENTED, 2026-09-05

Every S/B/I finding above is closed in the working tree, plus the three
code-quality suggestions. Verification after the pass:
`flutter analyze` **No issues found!** · `flutter test` **3386 passed** ·
`functions` jest **1785 passed / 84 suites** · `functions` ESLint clean.
(Baselines were 3370 / 1758 / 82.)

The deploy-gate section is deliberately NOT done — it is prod work, not a code
change, and still gates the next app build.

Four findings were closed differently from the suggestion, and the difference
matters:

- **B1 secondary** — `looksLikeBusinessName` could not be consulted: it returns
  true for ANY digit, so a pure-number name always reads as a business and the
  whole lift would stop working. The gate is a NANP-shape test instead
  (7, or 10 through 15 digits — 8 and 9 are neither a local nor a full number),
  which rejects `3101-5696` while keeping all six worked examples `b7c888a8`
  pinned, including the 11-digit typo.
- **I8** — only `debouncer_test.dart` was a margin race, and it is on
  `fake_async` now. The other three named files are NOT the same shape and were
  left alone: the disk-cache delays exist to force distinct filesystem mtimes
  (waiting longer is always fine), and the upload-service and live-map ones are
  bounded poll loops, not fixed margins. `live_map_screen_test.dart` explicitly
  needs `runAsync` for real `dart:ui` encoding, which `fake_async` cannot drive.
- **I10** — the dead PROVIDER, the interface method and the impl are deleted,
  but the six tests were REWRITTEN onto `fetchBuildings` /
  `fetchClientsByBuilding` rather than deleted: they were the only coverage of
  `_patchWindow`'s derived-map behaviour, which is live code.
- **I17 does NOT reproduce.** Two full `npx jest` runs and one
  `--detectOpenHandles` run at HEAD emit no "worker process has failed to exit
  gracefully" warning and detect no open handles. Nothing was changed for it.

I16 also went further than the finding: the two duplicated pairs were merged
into the mirrored location, and the other ten root test files were moved to
mirror `lib/` as well. Only `test/widget_test.dart` remains at the root.

## Summary

- Scanned: 423 non-generated Dart files, 161 `functions/` JS files, both rules
  files, 973 tracked files for BOM, 865 ARB keys.
- **Auto-fixed: 0.** Nothing safe was available to fix — see below. The tree is
  unchanged apart from the archive copy.
- Reported for your decision: **33**
  (⚠️ 1 deploy gate · 🔴 4 security · 🟠 10 bugs · 🔵 18 improvements)
- Verification: `flutter analyze` → **No issues found!** ·
  `flutter test` → **3370 passed** (run 2; run 1 hit one flaky test, see I8) ·
  `functions` jest → **1758 passed / 82 suites** ·
  `functions` ESLint → clean · `dart fix --dry-run` → **Nothing to fix!**

### Why there are zero auto-fixes

The safe-fix categories were all already empty at HEAD: the analyzer reports no
errors or warnings, `dart fix` has nothing to apply, ESLint is clean, there are
no unused imports, no orphaned files, no unused dependencies and no BOMs. The
remaining candidates are all explicitly report-only under
`references/safe-vs-risky.md`: ARB keys are reference-by-generated-getter, and
the off-scale spacing values have no unambiguous token to map to. A clean static
layer is the normal state for this repo, not a sign the sweep missed something.

### Top 3 to look at first

1. **B1** — the `liftPhoneFromName` Dart↔JS hand-mirror drifted in today's
   `b7c888a8`. A Wave customer named by a 7-digit or 11–15-digit number imports
   with an empty `phone`, and nothing in the app can dial them.
2. **B2 / I-perf** — attaching a client to a job now reads that client's entire
   appointment history (up to 1000 docs, up to 2 sequential round trips) to
   render two lines, and re-fires on every local write while the sheet is open.
   Regression from `04ee8f61`; this is the app's core booking flow.
3. **I1 / I3** — two docs describe live Firestore indexes as deleted or
   unnecessary. This repo has already suffered a 2-day invisible outage from
   exactly this (`3eebcc93`, "restore the endTime composite the last audit
   deleted"). These are instructions to delete working infrastructure.

### Verified clean (so the next pass doesn't re-walk them)

Unused files (0) · unused deps (0) · unused route constants (0) · dead JS (0) ·
`TODO(pre-ship)`/`FIXME`/`HACK`/`XXX` (0) · BOMs (0/973) · EN-FR ARB drift (0,
865=865) · `throw Exception(...)` in `lib/` (0) · `FirebaseFirestore.instance`
in UI (0) · hand-spelled email normalization (0) · raw `Timer` used as a
debounce (0) · `ref.read` inside a `catch` (0) · raw `Stream.listen` without
`onError` (0) · `ScaffoldMessenger` outside the three sanctioned sites (0) ·
App Check on all 18 callables · guard order on every callable · no fail-open
`req.auth.token &&` guards · no secrets in tracked source · `searchIndexTokens`
/ `_foldAccent` / `appointment_day_slice` hand-mirrors all agree · every
`StreamSubscription`/controller/`Debouncer` disposed · every production query
shape has a matching index.

## ⚠️ Deploy gate (act before the next app build)

There is **no** `TODO(pre-ship)` scaffolding in the tree — verified zero, so the
usual pre-ship section is genuinely empty. What is outstanding is the deploy
ordering already recorded in your notes, restated because it gates the build:

- [ ] The backend is still **undeployed**. `functions/index.js` exports **29**
  functions; the four added 2026-09-04 (`searchClients`, `searchHistory`,
  `findAppointmentConflicts`, `restoreAppointmentStatus`) plus the two new
  `clients` sort composites (`archived+jobCount`, `archived+createdAt`) must be
  deployed and **READY** before the app build that calls them ships.
- [ ] `functions/scripts/backfill-search-tokens.js` and
  `backfill-client-sort-fields.js` are **release prerequisites, not follow-ups**.
  Without them, search returns nothing for every pre-2026-09-04 client and
  closed job, and the new sort order has no field to sort on.
- [ ] Both of those scripts are the only two in `functions/scripts/` with no
  test of their own (see I13) — they are also the two that must run against
  production. Worth a dry run first.

## 🔴 Security findings (review required)

### S1 — The server-owned job time record is writable by an admin client · severity: low · confidence: high
- **Where:** `firestore.rules:391-392` (type checks), `:424-432` (create),
  `:435-441` (admin update)
- **Risk:** `.claude/rules/appointments.md` states the job time record has ONE
  owner, the server, and that no client may write one. The rules only
  *type-check* `startedAt`/`completedAt`. A compromised admin session or a
  modified admin build can forge or backdate the crew's on-site time record —
  the billable field artifact — and silently overwrite what `lifecycleStamps`
  wrote, with no server trace.
- **Why the in-file comment's reasoning doesn't close it:** the comment at
  `:386-390` argues they can't be banned because an admin edit's
  `request.resource.data` is the *merged* document. True for a
  `keys().hasAny()` ban — but not for a `diff().affectedKeys().hasAny()` ban,
  which is the technique already used two lines above for `pictureCount`
  (`:436-437`). I verified the ban is safe: `AppointmentRecord.toMap` omits both
  fields, and every repository write path is a merging `update()` or a `set()`
  on a new doc, so neither field would appear in `affectedKeys()` on a
  legitimate save.
- **Fix:** admin update — add
  `&& !request.resource.data.diff(resource.data).affectedKeys().hasAny(['startedAt','completedAt'])`;
  create — add `&& !request.resource.data.keys().hasAny(['startedAt','completedAt'])`.
  Needs a rules deploy. Test coverage gap: `appointment_crew_actions_rules_test.dart:43`
  pins only the employee branches; the admin branch is untested.

### S2 — `searchHistory` scopes a non-admin by a client-written field and never re-verifies `employeeIds` · severity: low · confidence: high (absent) / low (exploitable today)
- **Where:** `functions/indexed_search.js:145-175`, `historyScope` at `:128-140`
- **Risk:** for an employee the only narrowing is
  `historySearchScopes array-contains-any [...]`, and that field is a
  denormalized mirror of `employeeIds` written by the **client app**. The
  callable then returns the full document (`clientName`, `clientPhone`,
  `address`, `notes`). Any doc whose scopes drift from `employeeIds` is readable
  by a technician `firestore.rules` would refuse.
- **Honest scoping:** I traced every current write path and none can drift —
  `_toFirestoreMap` rebuilds scopes on create and update, and
  `client_propagation.js:154` rebuilds from stored `employeeIds`. This is
  defense-in-depth, **not a live exploit**. It is listed because the module's own
  principle ("a token hit is a PREFILTER, never the answer") is applied to the
  query but not to the scope.
- **Fix:** in the filter at `:170-172`, for a non-admin also require
  `(doc.data().employeeIds || []).map(String).includes(profile.docId)` — the
  shape `mayRestore` already uses in `appointment_actions.js:35-43`.

### S3 — `assertActiveCall` lets the bridge row shadow the authenticated uid · severity: low (latent) · confidence: high
- **Where:** `functions/security.js:277` — `return {uid: req.auth.uid, ...data};`
- **Risk:** the spread comes after the literal, so a `uid` field on the
  `usersByUid` row would override the token-derived uid. `profile.uid` is the
  durable rate-limit key and the log key in `indexed_search.js:153,246` and
  `appointment_actions.js:62`. Latent only — `bridgeBody` writes exactly
  `role`/`docId`/`status` and `/usersByUid` is `allow write: if false`. A future
  field addition silently breaks per-caller rate limiting.
- **Fix:** `return {...data, uid: req.auth.uid};`

### S4 — Raw Auth uid in eight log sites where the convention is `shortHash` · severity: informational · confidence: high
- **Where:** `functions/places.js:93`; `functions/wave/callables.js:124,155,177,289,318,359,408`
- **Risk:** not PII in the strict sense and all are admin-only paths, but it
  makes Cloud Logging a directly-correlatable identity store. `security.js`
  defines `shortHash(uid)` for exactly this, and `clients.js:65`,
  `indexed_search.js`, `appointment_actions.js:89` and `employee_accounts.js`
  all follow it.
- **Fix:** route these eight through `shortHash`.

## 🟠 Bug findings (review required)

### B1 — `liftPhoneFromName` hand-mirror has drifted; Wave imports land undialable · severity: high · confidence: high (verified)
- **Where:** `lib/features/clients/domain/policies/client_name_policy.dart:250-266`
  vs `functions/client_name_utils.js:387-402` (whose JSDoc at `:417` explicitly
  reads `HAND-MIRROR of ClientNamePolicy.liftPhoneFromName`)
- **Problem:** today's `b7c888a8` added a whole-field branch to Dart
  `_matchPhone` — if the trimmed name has no character outside `[\d\s().\-]` and
  7–15 digits, it is lifted into the phone field. The JS twin was not changed
  and still only matches via `PHONE_CANDIDATE` requiring **exactly 10** digits.
- **Failing scenario:** a Wave customer named `"5628332"` (7-digit local number,
  phone box empty in Wave — the exact shape `importedPhone` exists to catch).
  JS returns `null`, the client doc gets `phone: ''` while `name` stays
  `"5628332"`. Nothing can dial it: not the Call button, not the `clientPhone`
  denormalized onto every appointment. The same customer typed into
  `AddClientSheet` *is* lifted. Same divergence for any 11–15 digit run that
  isn't `1` + 10 NANP digits.
- **Fix:** port the whole-field branch into `matchPhoneInName` and copy the six
  new Dart worked examples into `functions/__tests__/client_name_utils.test.js`
  in the same commit — the two suites are supposed to share examples
  value-for-value, and the Dart suite gained 6 while jest gained 0.
- **Secondary (low, Dart side):** the whole-field test has no NANP sanity check,
  so a *business* named only by digits and separators (`"3101-5696"`) now
  populates `phone` with a nonsense `formatPhoneNumber` result.
  `looksLikeBusinessName` already treats any digit as a business signal but
  `liftPhoneFromName` never consults it.

### B2 — Attaching a client reads that client's entire job history · severity: high · confidence: high (verified)
- **Where:** `lib/features/calendar/utils/client_booking_context_scope.dart:29`
  → `lib/features/clients/application/appointment_history_providers.dart:57-68`
  → `firebase_appointments_repository.dart:465-488`
  (`pageSize: 500`, `cap: _clientHistoryScanLimit` = 1000).
  Call sites: `add_appointment_sheet.dart:288`, `details_edit_body.dart:156`.
- **Problem:** `watchClientBookingContext` watches `clientJobHistoryProvider` —
  whose own doc comment says it is *"for the Job history section"* — to produce
  exactly two things: a de-duplicated address list and one "last visit" label.
  It costs N document reads where N is the client's whole archive (capped 1000),
  in ⌈N/500⌉ sequential round trips. Before `04ee8f61` this path cost **zero**
  extra reads. It fires on attaching a client, changing to a different one, and
  opening the edit body of any client job.
- **Amplifier:** the provider calls `ref.invalidateSelf()` on **every**
  `onLocalWrite` emission (`:61-66`), so while the form is open with a client
  attached, any local appointment write re-runs the full read — including the
  background photo-upload queue draining.
- **Downstream:** `previousAddresses` is passed through uncapped;
  `_PreviousAddresses` builds every row in a non-lazy `Column`. A
  property-management client with 30 units renders 30 eagerly-built rows inside
  a form sheet. `ClientJobHistorySection` bounds itself at 50 for this reason;
  this surface has no equivalent.
- **Fix:** give the booking form its own bounded read — a
  `clientRecentAddressesProvider` calling `fetchClientHistory(clientId:, limit: 20)`
  with a matching small cap (the query is already `startTime` DESC on the
  `(clientId, startTime DESC)` composite, so the newest 20 is the right slice).
  Memoize the derived values on the history list's identity, and cap the
  rendered rows.

### B3 — Picking a previous job address produces no visible change · severity: medium · confidence: med-high
- **Where:** `lib/features/calendar/widgets/sections/job_address_section.dart:43-68`
  with `add_appointment_sheet.dart:138-141`
- **Problem:** `_PreviousAddresses` is shown only when
  `useCustomAddress && client != null && previousAddresses.isNotEmpty && !_searching`.
  Tapping a row sets `_controllers.address.text` and calls
  `setUseCustomAddress(value: true)` — but `useCustomAddress` was already true
  (it is a precondition of showing the list), `_searching` stays false, and
  `previousAddresses` is unchanged. The rebuilt widget is identical to the
  pre-tap one. `SelectedClientCard` doesn't help — it renders the *client's*
  address, not the job address.
- **Failing scenario:** admin taps "1250 boul. LaSalle", sees nothing happen,
  taps another to check, saves — the job silently takes the second address.
- **Fix:** flip to the field after a pick (set `_searching = true`), or mark the
  chosen row selected. The four existing widget tests only assert the callback
  fires; none pumps a post-pick frame.

### B4 — Dart and JS disagree about the client/employee name seam · severity: medium · confidence: high (verified)
- **Where:** `lib/features/calendar/domain/policies/history_search_policy.dart:35-47`
  vs `functions/search_tokens.js:184-206`
- **Problem:** the server joins `clientName` + every `employeeNames` entry into
  ONE string and does a single `includes`. The Dart twin tests `clientText` and
  each `employeeText` **separately**.
- **Failing scenario:** appointment with `clientName: "Marie Tremblay"`,
  `employeeNames: ["Marc Dubois"]`, query `tremblay marc`. The loaded-page filter
  says "No results"; 250 ms later the callable settles and the row appears. That
  is exactly the "same search at two layers, results change visibly when the
  debounce settles, nothing logged" failure the convention exists to prevent.
- **Fix:** make the JS side match per-field
  (`[clientName, ...employeeNames].some(f => normalize(f).includes(q))`), and add
  the seam example to both suites.

### B5 — `rawMatches` concatenates phone numbers across the seam · severity: medium · confidence: high (verified)
- **Where:** `lib/features/clients/domain/policies/client_search_policy.dart:174-175`
- **Problem:** `digitsOnly(rawPhones(data).join(' ')).contains(queryDigits)`
  joins every number into one blob. A client with `phone: 5145551234` and
  `mobile: 9876543210` yields `"51455512349876543210"`, so a query of `1234987`
  matches a number nobody has. The JS side does it correctly
  (`.map(digitsOnly).some(...)`), and `index()`/`entryMatches()` honour the
  split; only `rawMatches` does not — while being the declared single owner of
  the raw-map matcher.
- **Reachability:** this is the injected-`FirebaseFunctions`-absent fallback, so
  production always takes the callable path — tests-only today.
- **Fix:** `return queryDigits.isNotEmpty && rawPhones(data).map(digitsOnly).any((n) => n.contains(queryDigits));`

### B6 — `save()` sets `isSaving` before an await that sits outside its `try` · severity: low-medium · confidence: med
- **Where:** `lib/features/calendar/application/event_details_controller.dart:515`,
  `:528`, `:715`
- **Problem:** `isSaving: true` is set at `:515` before
  `await _settleAndValidate(...)` at `:528`, which awaits `_seedFuture` at
  `:715` — and neither is inside the `try` starting at `:562`. `_seedFuture` is a
  `Future.microtask` whose `ref.read(loggerProvider)` throws a `StateError` if
  the notifier was disposed before it ran. Then `save()` rethrows with
  `isSaving` stuck true — the Save button is permanently disabled for the life
  of the sheet, plus an unhandled zone error. This is the exact "un-caught
  pre-check throw with the flag already set leaves the button stuck" shape the
  reentrancy convention names. Every other controller checked was correct.
- **Fix:** move `_settleAndValidate` inside the `try`, or wrap it so a throw
  resets `isSaving` and returns `EventDetailsFailed`.

### B7 — "last visit" can be a FUTURE booking · severity: low · confidence: high (verified)
- **Where:** `lib/features/calendar/utils/client_booking_context_scope.dart:38-41`
- **Problem:** `history.first.startTime` is the newest by `startTime` DESC and
  `fetchClientHistory` applies **no** time filter, so it includes future
  appointments. `clients_jobsAndLastVisit` can read "last 12 Oct 2026" for a job
  that hasn't happened.
- **Fix:** pick the newest visit with `startTime.isBefore(now)` (via
  `currentDayProvider`, not `DateTime.now()`), or reword the key.

### B8 — Selecting a "recent" client attaches a synthetic record with no address · severity: low · confidence: high
- **Where:** `lib/features/clients/widgets/fields/client_picker.dart:130-137`
- **Problem:** the row builds `ClientRecord(id:, name:, phone:)` from
  appointment-denormalized recents. `AppointmentFormFields._selectClient:242`
  then writes the empty `client.fullAddress` into the address controller and
  `selectClient:238-239` forces `useCustomAddress: true`. Picking the same client
  from *search* pre-fills their address and offers the switch; from *recents* it
  does neither. Two paths to the same client produce different drafts.
- **Fix:** resolve the real `ClientRecord` on tap, or carry the address on
  `RecentClient`.

### B9 — Results header reads "Exact match" for substring results · severity: low · confidence: high
- **Where:** `lib/features/clients/widgets/fields/client_picker.dart:153-155`,
  `client_search_status.dart:32-33`
- **Problem:** `isFallback` is only true for `PhoneRung.firstSeven`/`lastSeven`.
  A text search always takes the canonical rung, which is a substring test
  server-side. Typing `mar` renders "Exact match" above "12 matches" —
  self-contradictory, and on the booking path it invites attaching the wrong
  client.
- **Fix:** branch the header on `status.mode` and `results.length > 1`, not on
  `isFallback` alone.

### B10 — `searchHistory` sits exactly on Firestore's 30-disjunction ceiling · severity: low (fragility) · confidence: med-high
- **Where:** `functions/indexed_search.js:157-163`
- **Problem:** `array-contains-any` with up to `TOKEN_QUERY_LIMIT` (10) tokens ×
  `in` with 3 statuses = exactly 30 disjunctions. At the maximum, so it works —
  but adding a fourth terminal status alias, or raising the token limit, fails
  with `INVALID_ARGUMENT` for long queries only.
- **Fix:** no code change needed; add a one-line note at the `in` clause naming
  the 10 × 3 arithmetic so a future edit sees the ceiling.

## 🔵 Areas to improve (review required)

### I1 — A rule describes a LIVE index as deleted, with the reasoning that caused an outage · impact: high · confidence: high (verified)
- **Where:** `.claude/rules/appointments.md:547-556`
- **Opportunity:** it states the `(employeeIds CONTAINS, endTime ASC)` composite
  "was DELETED 2026-08-28" as a redundant prefix. That index is **live** in
  `firestore.indexes.json` today, and commit `3eebcc93` is literally *"restore
  the endTime composite the last audit deleted"* — the deletion broke the travel
  sweep for two days, invisibly. The rule still carries the prefix-redundancy
  reasoning that caused it, and only conditionally suggests restoring. Your own
  memory already records this as a lesson; the rule file does not.
- **Suggested improvement:** rewrite to "Deleted 2026-08-28 and **restored
  2026-08-31** (`3eebcc93`) after it broke the travel sweep for two days. It is
  live — do not delete it as a prefix again."

### I2 — `functions/CLAUDE.md` says 25 exports; there are 29, and three modules are undocumented · impact: high · confidence: high (verified)
- **Where:** `functions/CLAUDE.md:6`
- **Opportunity:** `index.js` exports **29**. Worse, `indexed_search.js`,
  `appointment_actions.js` and `search_tokens.js` appear **zero times** in that
  file — four exports and both hand-mirrors are undocumented in the module map.
  `docs/DEPLOYMENT.md` uses the export count as a deploy abort check, so a wrong
  number there is operational, not cosmetic.
- **Suggested improvement:** correct to 29 and add the three modules to the map,
  noting `search_tokens.js` is a hand-mirror of `core/search/search_tokens.dart`.

### I3 — A doc says "no composite index needed" for a query a live composite serves · impact: high · confidence: high (verified)
- **Where:** `docs/CLOUD_FUNCTIONS.md:1082`
- **Opportunity:** it says `recountClientJobs` uses the automatic single-field
  index on `clientId` — "no composite index needed". But
  `(clientId ASC, dayIndex ASC)` **is** deployed in `firestore.indexes.json`,
  and the function's own comment says it is served by it. Given I1's precedent,
  this reads as licence to delete a live index.
- **Suggested improvement:** correct it to name the composite.

### I4 — The documented overdue window is 12× the real one · impact: high · confidence: high (verified)
- **Where:** `docs/CLOUD_FUNCTIONS.md:955,958,964` vs
  `functions/notification_policy.js:30`
- **Opportunity:** the doc describes the window as `(now−24 h, now]`.
  `OVERDUE_LOOKBACK_MS = 2 * 60 * 60 * 1000` — two hours, as the code's own
  comment at `:216` says. The doc also derives a scan width from the wrong
  number.
- **Suggested improvement:** correct to 2 h and re-derive the stated scan width.

### I5 — The TTL-policy list omits a collection that has one · impact: high · confidence: high (verified)
- **Where:** `.claude/rules/firestore-indexes.md:50-53`
- **Opportunity:** eight `"ttl": true` overrides exist; the list names seven and
  omits `clientRecountClaims`. This is the list used to reason about which
  policies a deploy could drop — and `--force` once removed all five live
  policies.
- **Suggested improvement:** add `clientRecountClaims`.

### I6 — `searchClients` read cap documented as 50, actually 200 · impact: med-high · confidence: high (verified)
- **Where:** `docs/CLOUD_FUNCTIONS.md:661` vs `functions/indexed_search.js:39`
- **Opportunity:** `SEARCH_READ_LIMIT = 200`. The root `CLAUDE.md` already says
  200, so the two docs disagree with each other. The cap is a known,
  deliberately-warned truncation bound, so its value matters.

### I7 — The log-tag registry is not exhaustive, and one auth tag is invisible to a tag search · impact: high · confidence: high (verified)
- **Where:** `.claude/rules/error-handling.md` (registry) vs four code sites
- **Opportunity:** the registry declares itself EXHAUSTIVE and is now the *only*
  place a tag lives (notices dropped support codes 2026-08-04). Four gaps:
  1. `CLI-RECENT` (`recent_clients_provider.dart:27`) is in code, absent from
     `.claude/` entirely.
  2. `auth.forgot_password` (`forgot_password_screen.dart:92`) is a surviving
     dotted-lowercase tag — the 2026-08-25 sweep replaced six `login.*` tags for
     being "invisible to a Crashlytics search by tag" and **missed this one**,
     while the rule names `forgot_password_screen` as a covered site.
  3. Four `auth_service.dart` labels carry **no tag at all** (`:78`, `:98`,
     `:122`, `:132`) — all `completeAccountSetup:` prefixed. `:132` is the
     breadcrumb for `AuthFailureStartingPasswordReused`, the load-bearing guard.
     The same file correctly uses `ACCT-SIGNOUT` at `:192`/`:198`, so this is
     drift, not a decision.
  4. The `ME-SAVE` row lists three intro keys but
     `error_introSaveLocationSharing` exists in both ARBs with 9 references.
- **Suggested improvement:** add `CLI-RECENT`; rename `auth.forgot_password` to
  `AUTH-RESET` (or `AUTH-SIGNIN`); prefix the four `auth_service` labels with
  `AUTH-SETUP `; add the fourth `ME-SAVE` key. Registry and code in one commit.

### I8 — A flaky test hides a real green/red signal · impact: high · confidence: high (verified)
- **Where:** `test/core/utils/debouncer_test.dart` (all 10 tests)
- **Opportunity:** the full suite failed on run 1
  (`forwards async action failures to onError`) and passed on run 2 (3370). The
  file passes 10/10 in isolation. Every test uses real wall-clock timing — a
  40 ms debounce with an 80 ms wait, a 40 ms margin that full-suite CPU
  contention on Windows exceeds. Three other files share the pattern:
  `appointment_image_disk_cache_test.dart`,
  `appointment_image_upload_service_test.dart`, `live_map_screen_test.dart`.
  Your own notes record that "a recorded green test count is a CLAIM" — a flaky
  suite is how a real failure gets waved through as "just the flaky one".
- **Suggested improvement:** drive these through `fake_async` rather than
  widening the sleeps (wider sleeps trade flakiness for wall-clock time and
  still race).

### I9 — Five orphaned ARB keys · impact: medium · confidence: high (verified)
- **Where:** `lib/l10n/app_en.arb:605, 609, 1520, 1528, 3183` (+ their FR twins
  at `128, 129, 329, 331, 689`)
- **Opportunity:** `clients_filterAllAddresses`, `clients_buildingUnits`,
  `clients_searchByNameBusinessPhoneEmailAddress`, `clients_addNamedClient`,
  `clients_filterByType` have zero member-access and zero string-literal
  references across `lib/` and `test/`. Orphaned by `d84cae53` (clients rebuild)
  and `eb200e68` (ClientPicker replaced ClientSearchField).
  `docs/plans/2026-08-29-clients-address-filter.md` still describes
  `clients_buildingUnits` as live.
- **Suggested improvement:** a deliberate l10n pass — delete from **both** ARBs
  plus the EN `@` block in one commit, then `flutter gen-l10n`. Not part of a
  code sweep. EN/FR are otherwise perfectly in step (865 = 865, zero drift,
  `untranslated.json` empty).

### I10 — A dead provider keeps a dead repository method alive, with tests · impact: medium · confidence: high
- **Where:** `lib/features/clients/application/clients_providers.dart:110`
  (`clientBuildingKeysProvider`), `clients_repository.dart:90`,
  `firebase_clients_repository.dart:267` (`fetchBuildingKeys`)
- **Opportunity:** the provider has zero `ref.watch/read/listen/invalidate` and
  zero overrides across `lib/` and `test/`. Orphaned by `d84cae53`, which moved
  `ClientsFilterSheet` onto `clientBuildingsProvider`. Its repository method's
  only non-test caller is the dead provider, but it has 6 test references
  (`firebase_clients_repository_test.dart:670-805`) — so it *reads* as live, and
  a future caller could re-add the ~700-doc scan `d84cae53` just moved off the
  tab-open path. `clients_providers.dart:79` and `.claude/rules/clients.md:102-109`
  both still describe `ClientsListView` watching it.
- **Must survive:** the private `_CachedClientScanWindow.buildingKeys` getter
  (`:516`) — used by `buildings`, `fetchClientsByBuilding` and `patched`. Only
  the *public repository method* is unreachable.
- **Suggested improvement:** delete provider + interface method + impl + tests
  together, or keep it and document why it has no caller. Update the two docs
  either way.

### I11 — Photo uploads are serial while downloads are bounded-concurrent · impact: medium · confidence: med
- **Where:** `lib/features/calendar/data/appointment_image_upload_service.dart:144-146`
- **Opportunity:** `_uploadFiles` awaits one Storage PUT at a time. The mirror
  read path `AppointmentImageLoader.loadAll` deliberately chunks at 4. Nothing
  in `.claude/rules/images.md` justifies serialising the upload, so the asymmetry
  looks unintentional. N ≤ 10 files at ~200-500 KB each: on field LTE a 10-photo
  batch is ~10× a single upload, and it runs as a background drain where iOS
  caps execution — a slow serial batch is likelier to be suspended mid-pass and
  re-queued.
- **Suggested improvement:** chunk at the same bound the loader uses (4), keeping
  the per-file try/catch inside the mapped function so the
  survivors/permanentFailures/tooLargeNames classification is unchanged, and
  collect per chunk with `Future.wait` so `uploaded` keeps list order.

### I12 — Callable search results are re-scored inside the sort comparator · impact: low · confidence: high
- **Where:** `lib/features/clients/data/firebase_clients_repository.dart:314-328`
- **Opportunity:** the comparator calls `ClientSearchPolicy.scoreRecord` on both
  operands per comparison, re-normalizing name and phone digits each time.
  N = 25, so ~235 calls instead of 25 — tens of microseconds, below the
  measurable bar. Reported only because it is a fresh regression against a
  decorate-sort-undecorate convention this repo applies everywhere else,
  including `_byDisplayName` two methods above it.
- **Suggested improvement:** build a `(score, sortKey, record)` list once, then
  sort on precomputed keys.

### I13 — The two release-prerequisite backfills are the only untested scripts · impact: medium · confidence: high
- **Where:** `functions/scripts/backfill-search-tokens.js`,
  `backfill-client-sort-fields.js`
- **Opportunity:** every other script in `functions/scripts/` has a `__tests__`
  sibling or a tested `*_policy.js`. These two have neither
  (`backfill-client-sort-fields` does have `client_sort_backfill_policy.js`;
  `backfill-search-tokens.js` has nothing) — and they are exactly the two that
  must run against production before the next build. Your own notes record a
  backfill whose `--dry-run` wrote everything then threw.
- **Suggested improvement:** a policy sibling + jest test for
  `backfill-search-tokens.js` at minimum, and a dry run against prod before the
  real one.

### I14 — The `security.js` helper list omits the two composed guards · impact: high · confidence: high
- **Where:** `functions/CLAUDE.md:8-25`
- **Opportunity:** the list asserts completeness but omits `assertAdminCall` and
  `assertActiveCall` (`security.js:242,262`) — the guards every new callable is
  *required* to open with, and whose whole reason for existing is that a
  hand-written gate silently loses a clause.
- **Suggested improvement:** add both, with their guard order.

### I15 — Four more documentation claims that would be acted on · impact: medium · confidence: high
- `docs/ARCHITECTURE.md:1465` — "THIRTEEN … every callable is durably limited";
  there are **18** call sites, and it omits `placesAutocomplete`,
  `restoreAppointmentStatus` and all three `indexed_search` routes.
- `docs/ARCHITECTURE.md:1197` — says `role` is "set at creation from the invite
  sheet's Admin toggle"; `employee_accounts.js:152` is `const role = "employee";`
  hard-coded and never read from payload. The doc contradicts itself at `:67`
  and `:1028`. This is a **security-relevant** inaccuracy.
- `.claude/rules/testing.md:30-32` — account-exit tests "must override THREE
  providers"; `accountExitStubOverrides` returns **four**, and its own docstring
  says a fourth "getting it subtly wrong is a hang". Following the count still
  hangs — the exact failure the bullet exists to prevent.
- `docs/ARCHITECTURE.md:40` — client phone "numbers are STORED formatted"; false
  since 2026-09-04, `firebase_clients_repository.dart:370-376` normalizes through
  `normalizePhoneForStorage`. Acting on this writes masked numbers and breaks the
  `clients.name` IS-the-phone rule.
- Also: `.claude/rules/employees.md:655` quotes the `/users` `allow update` shape
  **missing the `emailMovesThroughAuth()` conjunct** — a reader reconstructing the
  rule from the doc drops the guard that forces email changes through
  `changeEmployeeEmail`.
- Also: the per-STEP tour migration left three docs describing the old per-scope
  store (`lib/core/navigation/CLAUDE.md:12`,
  `lib/features/feature_tour/CLAUDE.md:23`, `docs/ARCHITECTURE.md:68`).

### I16 — 12 test files sit at `test/` root instead of mirroring `lib/`, two duplicating coverage · impact: low · confidence: high
- **Where:** `test/client_tile_test.dart` (62 lines) vs
  `test/features/clients/widgets/cards/client_tile_test.dart` (158);
  `test/status_chip_test.dart` (78) vs
  `test/shared/widgets/feedback/status_chip_test.dart` (88); plus 10 others at
  root.
- **Opportunity:** the two duplicated pairs overlap, and the root copies use a
  bare `MaterialApp` with no theme/l10n while the mirrored ones use the real
  harness — so the weaker copy can pass while the real one fails.
- **Suggested improvement:** merge the two duplicated pairs into the mirrored
  location; the other 10 are a location convention call.

### I17 — Jest leaks a worker · impact: low · confidence: high (observed)
- **Where:** `functions/` suite
- **Opportunity:** the run ends with *"A worker process has failed to exit
  gracefully… Try running with --detectOpenHandles"*. Green today, but it masks
  real handle leaks and slows CI.
- **Suggested improvement:** run `--detectOpenHandles` once and `.unref()` the
  offending timer.

### I18 — 28 off-scale `EdgeInsets` values · impact: low · confidence: high
- **Where:** 28 sites using 5, 9, 10, 11, 13, 14, 15, 18, 20, 25, 48 —
  `AppSpacing` is 4/8/12/16/24/32. Several are *mixed*
  (`inline_month_calendar.dart:18` `fromLTRB(10, 4, 10, 12)`,
  `calendar_month_grid.dart:19`, `app_nav_drawer.dart:67`), pairing token values
  with off-scale ones.
- **Opportunity:** these look like deliberate optical values and there is **no
  unambiguous token to map them to**, which is why they were not auto-fixed.
- **Suggested improvement:** owner call — either add the missing steps to
  `AppSpacing`, or record the exemption somewhere greppable so every future audit
  stops re-finding them.

## 🟡 Code-quality suggestions (optional)

- `lib/features/calendar/data/appointment_image_upload_service.dart:318,321` —
  throws `StateError('signed out')` / `StateError('no users doc for uid')` from a
  service where the feature has a typed `ImageUploadFailure` family. These are
  internal preconditions on a background drain never surfaced to UI, so it may be
  intentional — worth a decision either way.
- `lib/features/employees/widgets/fields/employee_color_grid.dart:200-206` — the
  only raw-hex site outside `lib/core/theme/`: a 7-stop `SweepGradient` hue ring
  that deliberately ignores the theme (comment at `:198`). Either leave it and
  accept the recurring flag, or move the stops into `AppColors` as a named
  decorative constant.
- `.claude/rules/error-handling.md` — says "All six sites use it" of
  `Debouncer.tagged`; there are now **five**, since `DebouncedPagedSearch`
  merged two. It also attributes the `tag:` parameter to the three device
  controllers when it actually lives on the shared
  `resolveUserDocId` helper (`lib/core/app/device_deregistration.dart:104-121`) —
  a seventh tag-hiding shape the documented grep procedure doesn't list.

## Notes / uncertainties

- **A reported finding I rejected on verification.** One reviewer claimed
  `.claude/rules/code-quality.md` is factually wrong to say the `firestore.rules`
  rationale comments "were deleted", on the basis that 160 comment lines remain
  and the count only moved 168 → 160. That reasoning only looked at the last two
  commits. The real history is `546 → 168` in one commit
  (`73d37147` → `6c1e3dd5`) — roughly 378 comment lines genuinely were removed,
  exactly as the rule says. **The rule is accurate and needs no change**, and the
  absence of those blocks is correctly not a finding. Recording this so a future
  audit doesn't re-raise it.
- Auto-fix count is genuinely zero, not "not attempted" — `dart fix --dry-run`
  reported "Nothing to fix!" and the analyzer and ESLint were both clean at HEAD.
- The full suite was run twice (3369+1 failure, then 3370 green) specifically to
  characterize I8 rather than record a green number I hadn't observed twice.
- `.worktrees/p7b-wave-invoices/` is a second full checkout of the repo, properly
  gitignored with zero tracked files. It is excluded from all counts here; note
  that a naive repo-wide grep will double-hit it.
- S2's exploitability is bounded by my tracing of current write paths; I could
  not rule out a console or Admin-SDK edit having already produced drift in
  production, which is unreadable from here.
- Prod-state items from the archived rolling audit (Maps billing cap, Crashlytics
  re-check, Wave "Retry failed", the Xcode `InfoPlist.strings` confirmation)
  remain open and were not re-verified — several need console or Mac access.

---

Say **"do everything but the pre-ship"** and I'll implement every finding above
except the deploy-gate section, then re-verify against the recorded baselines
(3370 flutter / 1758 jest / analyze clean).
