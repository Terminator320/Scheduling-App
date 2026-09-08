# Codebase Audit — 2026-09-01

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`) **plus production telemetry** (Crashlytics,
Cloud Functions logs, Firestore). Baseline: `5a22338e` (working tree clean).

This audit deliberately looked past the static layer, because the 2026-08-31
pass had already closed everything there and its real findings all came from
production. Six reviewers ran in parallel (security, bugs, dead code,
performance, maintainability + test coverage, UX/product).

## Summary

- Scanned: 405 `lib/` Dart files · 143 `functions/` JS files · 327 test files ·
  rules + indexes · 2 weeks of prod telemetry
- **Auto-fixed: 0.** The static layer is pristine for the third consecutive
  audit — `flutter analyze` clean, `dart fix` "Nothing to fix!", functions
  ESLint clean, no orphaned l10n keys, no unused providers/routes/files/deps,
  all 14 named single-owners intact. Nothing safe was left to apply, and the
  invocation asked for report-only.
- Reported for your decision: **31**
  (⚠️ 0 pre-ship · 🔴 6 security · 🟠 7 bugs · 🔵 18 improvements)
- Verification: `flutter analyze` clean · `flutter test` **3058 passed** ·
  `functions npm test` **1636 passed** · functions lint clean

**Top 3 to look at first**

1. **B1** — `workingDays` is the one non-lenient cast in `EmployeeRecord.fromMap`,
   and the comment twelve lines below it states the leniency rule it breaks. One
   console-edited `users` doc errors the roster stream app-wide, or locks that
   person out of signing in.
2. **I4/F1** — three `assertAdmin` gates can be deleted with all 1636 tests
   green (mutation-proven), on the callables that mint and delete real Firebase
   Auth accounts.
3. **I1** — the technician can only read jobs and tap "Mark as complete". The
   entire photo pipeline already exists and is wired admin-only. Largest
   product gap in the app.

---

## Production telemetry (new this pass)

**Crashlytics is quiet** — two open issues in two weeks, and both trace to one
root cause you fixed on 2026-08-31.

| Issue | Volume | Status |
|---|---|---|
| `deadline-exceeded` from `placesReverseGeocode` (grouped under a stale `permission-denied` title) | 22 events / 3 users | Fixed by `8a448e0f`, ships in 1.55.0+84 |
| `MapsFailureRateLimit` in `getPlaceDetails` on suggestion tap | 4 events / 2 users, new in 1.54.0 | Same root cause |

The breadcrumbs show **15 failed reverse-geocode callables in 10 ms**, twice.
All three Places callables share `fetchPlacesJson` (`functions/places.js:104`),
which had no timeout before `8a448e0f` — so requests the client abandoned at
10 s kept running server-side and still consumed their rate-limit slot. That
explains the `getPlaceDetails` 40-per-15-min exhaustion too.

> **Action:** confirm both are gone once 1.55.0 has real fleet time. Absence
> today proves nothing — it shipped hours ago.

**Functions error log** — 31 of 40 ERROR entries are `Invalid request, unable to
process` spread evenly across 14 different callables. These are **external
scanners**: the stack never leaves the CORS middleware, so App Check and the
callable protocol reject them before any handler runs. Not a defect — the
defense is working — but they are logged at ERROR and bury real errors. See I17.

**Wave dead-letters** — all stopped 2026-08-30 18:15 UTC; your fixes
(`4dc086e5`, `ca40c40a`) landed 19:27 UTC. Nothing since. One loose end: memory
records that an admin must press "Retry failed" once to drain the parked
`customerUpsert__o0KcOnJSgjvMHYpmcZ44` job. I could not verify the queue state —
the Firestore MCP query returns `read_time cannot be in the future` (a tool
quirk; local and Google clocks agree). **Check the Wave settings screen.**

---

## ⚠️ Pre-ship checklist

**None.** Zero `TODO`/`FIXME`/`HACK`/`XXX`/`TEMP`/`REMOVEME` markers anywhere in
`lib/`, `test/` or `functions/`. Verified, not assumed.

---

## 🔴 Security findings

### S1 — `updatedAt` is the last client-writable field with no bound · medium-low · high
- **Where:** `firestore.rules:297-301` (`isAvailabilityOnlyChange`), validator at `:203-256`
- **Risk:** `updatedAt` sits inside the `hasOnly` allowlist, but `isValidUserData`
  never mentions it and has no `hasOnly` — so an unlisted key is unchecked. Any
  active employee can write an arbitrary type/size there on their own `users`
  doc. `watchEmployees()` holds a live `snapshots()` over active docs on every
  signed-in device, so one inflated doc is re-delivered to every peer on every
  snapshot. This is the same class the file already closed for appointments at
  `:686-694`, with the pin missing here.
- **Fix:** add `&& request.resource.data.updatedAt == request.time` to the
  **self** branch only. `updateSelfDetails`
  (`firebase_employees_repository.dart:307`) already sends
  `FieldValue.serverTimestamp()` unconditionally, so nothing breaks. Keep it off
  the admin branch or a legacy doc with a bad value becomes un-updatable.

### S2 — `email` can still be written to `/users` without the matching Auth change · medium · high
- **Where:** `firestore.rules:328`
- **Risk:** the update denylist is `['uid','termsAcceptedAt','locationConsentAt']`
  — `email` is absent, so an admin can desync Firestore from Firebase Auth by
  writing it directly. `docs/DEPLOYMENT.md` documents this as **still open** and
  notes the reason it waited (breaking 1.37.1's employee edit) is gone.
- **Fix:** add `'email'` to the denylist. Every shipped path already routes
  through `changeEmployeeEmail`. Rules deploy; do it as its own reviewed change.

### S3 — No spend ceiling on Google Maps Platform, and the risk is no longer theoretical · medium · high
- **Where:** `docs/audits/AUDIT_FOLLOWUPS.md` §2 (open); `functions/places.js:30-40`
- **Risk:** the in-code limiters bound per-user abuse, not total spend. The
  file's own comment names a GCP billing alert as "the only thing between a
  stolen admin session and an unbounded bill" — and an alert only emails you.
  This pass found a **real production storm** firing 15 billed Places calls in
  10 ms where the server kept running after the client gave up.
- **Fix:** the runbook in §2 is complete (budget + Pub/Sub + cap-disable
  function). Needs `roles/billing.admin`, so you must run it. Elevated from
  "cost hygiene" to "do this soon".

### S4 — `images.storagePath` isn't constrained to its own appointment · low · high
- **Where:** `firestore.rules:752-760`
- **Risk:** create/update caps the string at 500 chars but never requires it to
  sit under `appointments/{appointmentId}/images/`. A compromised admin session
  could plant a row pointing at another appointment's object, making that photo
  readable by the second appointment's assignees. Admin-gated and an admin can
  already read everything, so the delta is narrow.
- **Fix:** `request.resource.data.storagePath.matches('appointments/' + appointmentId + '/images/.*')`

### S5 — `assertPayloadShape` measures UTF-16 code units, not bytes · low · high
- **Where:** `functions/security.js:48`
- **Risk:** `serialized.length > 4096` where the constant and the error code
  (`payload-too-large`) both say bytes. 4096 emoji/CJK characters serialize to
  ~12–16 KB and pass. `requireString`'s per-field caps still bound what is
  *used*, so this widens a DoS/log-volume surface, not a data hole.
  `notification_utils.js` gets this right with `Buffer.byteLength`.
- **Fix:** `Buffer.byteLength(serialized, "utf8") > MAX_PAYLOAD_BYTES`

### S6 — Two `req.data` dereferences that skip the optional-reader · low · high
- **Where:** `functions/employee_accounts.js:722-723`
- **Risk:** `req.data.termsAccepted` / `req.data.locationConsent` where every
  sibling uses `optionalString(req.data, …)`. A callable invoked with no data
  throws `TypeError` → opaque `internal` instead of a shaped `invalid-argument`.
  Not exploitable: sits above the rate limiter, changes no state, leaks nothing.
- **Fix:** `req.data?.termsAccepted === true`

**Verified clean:** all 14 callables set `enforceAppCheck`, validate payloads,
and hold guard order (auth → assertAdmin → payload → re-auth → limiter → work);
no fail-open `if (req.auth.token && …)` shape anywhere; `assertFreshReauth`
fails closed on a missing/non-numeric `auth_time`; every `resource.data` rule
clause has a matching query constraint; `liveActivityTokens.expiresAt` is the
only client-written TTL and is capped at +31 d against a 30 d client write; all
five credential fields pass `kCredentialImePersonalizedLearning`; no secrets in
tracked files; no PII in any log call; role is never cached.

> **Note on the automated "missing assertAdmin" alerts.** A background scanner
> flagged `employee_accounts.js` ×2 and `places.js` as CRITICAL/HIGH missing
> admin checks, citing `// MUTANT` markers. These were **false positives** — it
> observed the test-coverage reviewer's temporary mutations. Verified: zero
> `MUTANT` markers in the tree, `assertAdmin` present at
> `employee_accounts.js:276`/`:792` and `places.js:212`/`:265`/`:324`, and
> `git diff HEAD -- functions/` is empty. The other two callables in that file
> (`changeEmployeeEmail`, `completeEmployeeSetup`) are self-service by design.
> **But see I4 — the mutation itself proved a real test gap.**

---

## 🟠 Bug findings

### B1 — `workingDays` is the one non-lenient cast, and it can lock a user out · high · high
- **Where:** `lib/features/employees/domain/models/employee_record.dart:57`
- **Problem:** `(data['workingDays'] as List?)` — every other field in the same
  factory uses `(data['x'] ?? '').toString()`, and the comment at `:71-75`
  states the rule and the reason: this factory runs inside `users` snapshot
  streams **and** on the sign-in path, so one console-edited doc "would throw
  app-wide". A doc holding a string or map for `workingDays` throws a
  `TypeError` inside the factory, erroring the roster stream (Team tab, crew
  picker, day route, live-map roster, calendar dots at once) — and if it is the
  signing-in user's own doc, that person cannot sign in.
  `normalizeWorkingDays` already tolerates a wrong-length list.
- **Fix:** `final raw = data['workingDays']; final storedDays = raw is List ? raw.map((v) => v == true).toList() : null;`

### B2 — Swipe-to-archive removes the row even when nothing was written · medium · high
- **Where:** `lib/features/clients/widgets/views/clients_list_view.dart:197`
- **Problem:** `DismissiblePane(onDismissed: () => archiveClient(client))` with
  no `confirmDismiss`. `flutter_slidable` collapses the row to zero extent
  *before* running `onDismissed`, and `archiveClient`
  (`client_actions_host.dart:28-63`) has three paths that write nothing: the
  `guardedOffline` early return, `ClientArchiveBusy` (silent by design), and
  `ClientArchiveFailed`. Only success calls `onClientArchived` →
  `_pagingController.refresh()`. Full-swipe on cellular in a basement: offline
  notice shown, nothing written, row gone. The `Slidable` is keyed, so it stays
  collapsed across rebuilds — an unarchived client is invisible until
  pull-to-refresh. The `Busy` variant vanishes with no notice at all.
- **Fix:** move the work into `confirmDismiss` and gate dismissal on the
  outcome; `archiveClient` returns `Future<bool>` (true only on
  `ClientArchived`). The tap action at `:210` is unaffected.

### B3 — `contacts` unchecked `as List?` on a live client stream · medium-high · high
- **Where:** `lib/features/clients/domain/models/client_record.dart:80`
- **Problem:** same shape as B1, same file-local contradiction — the comment 25
  lines down explains that `== true` is used rather than a cast precisely
  because "one console-written `"false"` would throw for the whole page". The
  `.whereType<...>()` on the next line already tolerates junk *elements*; only
  the container type is unguarded. One bad doc blanks a Clients page.
- **Fix:** `final raw = data['contacts']; final rawContacts = raw is List ? raw : const [];`

### B4 — The same cast inside the search isolate, twice · medium · high
- **Where:** `lib/features/clients/domain/policies/client_search_policy.dart:145`
  and `lib/features/clients/data/firebase_clients_repository.dart:375`
- **Problem:** two spellings of one bug. Both run over the ~5000-doc scan window
  inside a `compute` isolate; a throw kills the isolate, so the **entire** search
  returns nothing for every query because of one malformed doc, with nothing
  logged. `client_search_policy.dart`'s own docstring says this matcher must not
  read *less* than the record — here it reads less *safely*.
- **Fix:** same `is List` guard, both sites together.

### B5 — Cache generation read on the wrong side of an await · low · med-high
- **Where:** `lib/core/images/appointment_image_loader.dart:66-70`
- **Problem:** `final generation = _disk.generation` is captured *after*
  `await _disk.read(key)`. `deregisterThisDevice` calls `loader.clear()` before
  `signOut()`, while the credential is still live. A load whose disk read is in
  flight resumes, reads the already-bumped generation, fetches successfully, and
  `write` sees `startedAt == _generation` — so one user's job photo lands in the
  on-disk cache after sign-out, outliving the process on a shared handset. That
  is the leak the generation guard exists to prevent.
- **Fix:** hoist the read to the first line of `_resolve`.

### B6 — `firebase_employees_repository.dart:201/202/276` cast deviation · low · high
- **Problem:** `stored?['email'] as String?` where the convention 60 lines away
  is `(x ?? '').toString()`. Admin `updateEmployee` only, inside a typed-failure
  path, so it degrades to an error notice rather than a crash.

### B7 — Comment/code drift on the assignee mark-done rule · low (docs) · high
- **Where:** `firestore.rules:657`
- **Problem:** the justification comment says `DetailsActionBar` hides the button
  on `hasStarted && !isDone && !isCancelled`. That clock gate was removed
  2026-08-17 — `details_action_bar.dart:39` is `if (!isDone && !isCancelled)`.
  The branch really is the only gate, which is correct; the comment mis-sizes it
  for the next reader. This repo's own recorded lesson is "a long comment is a
  spec".
- **Fix:** drop `hasStarted &&` from the comment.

**Verified clean:** every `Stream.listen` passes `onError`; no `ref.read` in a
`catch` or on an unguarded post-await path; all submit/save controllers set the
in-flight flag before the first await and reset on every exit; all
`employeeIds`/`employeeNames` pairings route through `assigneeNameAt`; the
Dart↔JS DST/day-slice mirrors agree; every query has an index; all three
2026-08-31 fatal *fixes* are still in place.

---

## 🔵 Areas to improve

### I1 — The technician cannot record anything about the work · high
- **Where:** `firestore.rules:678-693` (`hasOnly(['status','updatedAt'])`);
  images subcollection is read-only for employees; `main_calendar_screen.dart:455`
  returns no FAB when `!isAdmin`
- **Opportunity:** a plumber's whole app is: read today's jobs, tap
  Call/Directions, tap Mark as complete. They cannot photograph what they found,
  note "customer also wants the water heater quoted", or record materials. For a
  trades business the field record *is* the billable artifact and the upsell
  pipeline — today it travels by phone call. **The photo pipeline, offline upload
  queue, magic-byte validation and per-appointment `images` subcollection are all
  already built**; they are wired to the admin-only edit form.
- **Suggested:** widen the employee rules branch to allow the images
  subcollection write plus a notes field for assignees, and surface the existing
  photo picker on the technician's job view. Pairs with I7.

### I2 — Every appointment write discards the whole History scan window · high
- **Where:** `lib/features/calendar/data/firebase_appointments_repository.dart:87-91`,
  consumed at `:489-516`
- **Opportunity:** `_invalidateSearchCache()` sets `_scanWindow = null` — the
  full paged terminal-status window, capped at 5000 — and is called by **nine**
  write paths. It also pokes `_localWrites`, and `historySearchProvider`
  invalidates on that, so if a search is on screen the window is not just
  dropped but immediately re-fetched. Realistic path: admin searches History,
  taps a result, marks it complete → the screen behind the sheet re-pages the
  entire archive. At ~2000 settled jobs that is 2000 billed reads and 4
  sequential round trips for a one-field write, then `compute` marshals all
  2000 raw maps across the isolate boundary again. It grows with the archive.
  **The clients repository already solved exactly this** with `_patchWindow`
  (`firebase_clients_repository.dart:69-86`), which merges the changed doc
  instead of dropping the window. Appointments has no equivalent.
- **Suggested:** give `_scanWindow` the same patch treatment — the status/photo/
  delete paths all know which ids changed. Cheapest partial win: skip
  invalidation entirely on `appendAppointmentPictures`/`removeAppointmentPictures`,
  which cannot change any field `matchHistoryDocs` reads.

### I3 — The device locale is ignored on first launch · high
- **Where:** `shared_prefs_settings_repository.dart:23,32`; `app_language.dart:26`
- **Opportunity:** `serverLocaleOf(null)` returns `'en'` and nothing reads
  `PlatformDispatcher.instance.locale`. A francophone plumber whose iPhone is in
  French installs the app and gets **English**. It compounds:
  `currentServerLocale` registers the FCM token locale
  (`push_registration_controller.dart:70`), the widget payload
  (`widget_sync_service.dart:268`) and the Live Activity locale
  (`live_activity_registration_controller.dart:97`) — so their pushes, Lock
  Screen cards and home-screen widget are English too, until they find the
  Settings toggle. For a Québec business this is close to a first-run defect.
- **Suggested:** seed from `PlatformDispatcher.instance.locale` when no stored
  preference exists. ~10 lines.

### I4 — Three `assertAdmin` gates are deletable with a green suite · high
- **Where:** `functions/employee_accounts.js:276` (`createEmployeeAccount`),
  `:792` (`deleteEmployeeAccount`), `functions/places.js:324` (`placesReverseGeocode`)
- **Opportunity:** mutation-proven — the guard was removed, all 1636 tests still
  passed, tree restored. `assert_admin.test.js` covers 8 of 14 callables;
  `places_admin_gate.test.js` has blocks for `placesAutocomplete` and
  `placesGetDetails` only; `employee_accounts_callables.test.js:33` stubs
  `assertAdmin` with `jest.fn()` and never asserts it. These are not read
  paths — they mint and delete real Firebase Auth accounts, bypassing
  `firestore.rules` via the Admin SDK. `deleteEmployeeAccount`'s entire callable
  wrapper (`:789-824`) is untested. **A mocked-and-never-asserted dependency
  reads as covered and is not** — the inverse of "coverage lives under the
  caller's name", and name-grepping cannot tell them apart.
- **Suggested:** copy `delete_client_callable.test.js`'s harness — it already has
  the right shape twice, including "a non-admin is refused and burns NO
  rate-limit slot". Three tests. Better: **M3** below fixes it structurally.

### I5 — `usersByUid` teardown is deletable with a green suite · high
- **Where:** `functions/bridge.js:189-191`, `:203-205`
- **Opportunity:** `bridge.test.js` makes 14 `makeEvent(...)` calls and none
  passes `after` as null, so the doc-deleted branch never runs. `usersByUid` is
  `assertAdmin`'s **only** data source (`security.js:243`) and the collection
  every rules role gate resolves through. Break the teardown and a deleted
  user's bridge row survives with `role: "admin", status: "active"` — a live
  admin credential for an account that no longer exists.
- **Suggested:** one test asserting `usersByUid/a1` is deleted.

### I6 — All three 2026-08-31 shipped fatals are fixed but unpinned · high
- **Where:** `wave_settings_section.dart:94`, `event_details_controller.dart:181`,
  `push_registration_controller.dart:88`
- **Opportunity:** three known production crashes, each fixed with a long
  explanatory comment, none regression-proofed. The Wave tests have 20 cases and
  two `thenThrow`, both `WaveFailure` — the new generic branch is never entered.
  `addError` appears nowhere in the event-details or push test files. The
  routine `simplify` passes this repo runs are exactly what would remove them.
- **Suggested:** three tests (throw a non-`WaveFailure`; `docs.addError(...)`;
  make the gate provider throw).

### I7 — The assignee picker renders empty on both loading and error · high
- **Where:** `add_appointment_sheet.dart:249-250`, `details_edit_body.dart:121`
- **Opportunity:** both use `.asData?.value ?? const []`. An assignee is
  *required* to save (`appointment_form_validator.dart:89-90`), so a slow first
  load or a transient permission error makes the booking form look like the
  business has no staff — no spinner, no message. This can block the only
  appointment-creation path.
- **Suggested:** distinguish loading (spinner) from error (retry) from genuinely
  empty.

### I8 — The offline write guard is tested on `save()` only · high
- **Where:** `event_details_controller.dart:370`, `:411`, `:718` untested; only
  `:467` covered
- **Opportunity:** drop the guard from `_setStatusOnRepo` and "Mark as complete"
  offline spins on an un-acked write until reconnect with the button disabled —
  exactly the failure the invariant exists for. Subtler: return a plain
  `SocketException` where a reentrancy skip should return `Busy`, and
  `_classifyError` renders "you appear to be offline" while online.
- **Suggested:** three asserts in the existing offline container.

### I9 — Dead-end error states on two primary screens · medium-high
- **Where:** `centered_error_text.dart:7` takes no retry parameter;
  `dashboard_screen.dart:118-120`; `my_details_screen.dart:382-384`, `:388-392`,
  `:418-420`, `:428-430`; `client_job_history_section.dart:73-79`;
  `live_map_screen.dart:179-182`
- **Opportunity:** any load error renders bare text and the screen is inert until
  you back out. My Details is the *only* self-service screen an employee has,
  and it has four such sites. Related silent failures: a refused photo renders
  as an invisible 1×1 slide in the read-only carousel
  (`image_viewer.dart:389-400`) while the editable strip correctly shows an
  error tile; `PeriodSummarySection` disappears entirely on error via
  `whenOrNull` (`dashboard_screen.dart:167-176`).
- **Suggested:** add an optional `onRetry` to `CenteredErrorText` and thread it
  through. History already does this well (`appointment_history_view.dart:351-354`).

### I10 — The Clients tab forces a full collection rescan per write · medium
- **Where:** `clients_list_view.dart:470-471`; `clients_providers.dart:98-112`;
  `firebase_clients_repository.dart:69-86`, `:292-319`
- **Opportunity:** `clientBuildingCountsProvider` and `clientBuildingKeysProvider`
  are watched unconditionally at the top of `build`, and the view lives in the
  hub's `IndexedStack` — so once visited they stay subscribed all session.
  `patched()` passes the original `fetchedAt` through (verified at `:496`,
  `:521`), so the window expires 2 minutes after the tab-open scan regardless of
  activity. The first client write after ~2 min idle re-pages all 714 prod docs
  plus 714 × `ClientRecord.fromMap` **and** 714 × `buildingKeyFor` on the UI
  isolate — unlike `searchClients`, which uses `compute`. It also fires from the
  inline add-client during booking, when the Clients list isn't even visible.
- **Suggested:** (1) refresh `fetchedAt` on a local patch — the window is
  provably current for the doc that just changed; (2) gate the two watches on the
  surfaces that consume a building count.

### I11 — The dispatcher gets no signal that work is happening · medium
- **Where:** `sendToActiveAdmins` has exactly one call site in the backend
  (`employee_accounts.js:655`, the email-change notice); the overdue sweep
  delivers only to `toIdList(c.employeeIds)` (`notification_utils.js:707-712`)
- **Opportunity:** nothing fires on completion, and an unassigned admin is never
  told a job ran over. `AttentionFlags.overdueOpen` exists
  (`dashboard_stats.dart:113-122`) but the Dashboard is a `PushedDestination`
  behind drawer → Business, while the admin's home is the calendar. The most
  valuable dispatcher signal is pull-only and two navigations deep.

### I12 — Duplication with a stated must-not-diverge contract · medium
Four cases, each where the code's own comment states a rule that has no owner:
- **The appointment search predicate is spelled twice** —
  `history_search_policy.dart:46-61` (raw Firestore map, debounced server scan)
  and `appointment_history_view.dart:249-256` (loaded-page filter). These are the
  *same search at two layers*; add a field to one and results visibly change when
  the debounce settles, with nothing logged. The client side already learned this
  and extracted `ClientSearchPolicy.entryMatches`. **Fix:** add
  `historyEntryMatches(...)` to `history_search_policy.dart`, route both through it.
- **`isAlreadyExists`** — `notification_policy.js:360` and `recount_claim.js:43`,
  functionally identical (one names the `6`, one inlines it). Both guard a
  `create()`-based at-most-once ledger: push delivery and the recount claim. Fix
  one and not the other → a duplicate push or a suppressed recount, invisibly.
  (The 2026-08-28 audit records B1 as closed for this file; it isn't.)
- **`_who(c, generic)`** — `live_activity_utils.js:73` and
  `notification_messages.js:83`, byte-identical, plus the `"Client"`/`"un client"`
  literals at 4 call sites. `live_activity_utils.js:66-68` states the contract in
  prose: "the card and the `leaveNow` push beside it must not call the same job
  two different things." A rule stated in two files has no owner.
- **Timestamp→ms, three spellings** — owner `time_utils.js:146` (`toMillis`,
  returns `null` on failure), `wave/worker.js:156` (returns **`NaN`**, also
  handles `.toDate()`), `recount_claim.js:94-97` (inline, no number branch).
  `NaN` compares false everywhere, so it silently degrades a lease comparison.

### I13 — The search-result LRU is implemented twice · medium
- **Where:** `firebase_appointments_repository.dart:51,52,76-85` and
  `firebase_clients_repository.dart:35,40,55-64`
- **Opportunity:** byte-identical `_isFresh`/`_cacheSearch` and identical dials
  (`_searchCacheMax = 50`, TTL 2 min). Same precedent as `kSearchDebounce` —
  "one cost dial, not a per-surface taste" — and as `pageToCap`, which exists
  because four hand-written paging loops were four chances to omit the cap.
- **Suggested:** one `SearchResultCache<T>` in `core/data/` beside
  `paged_scan.dart`. Keep `_invalidateSearchCache`/`clearCaches` per-repo — they
  legitimately differ on the `_localWrites` poke.

### I14 — Untested caps, clocks and seams that fail silently · medium
Grouped; each degrades gradually with no error:
- `_conflictScanLimit` (1000) cap warn untested
  (`firebase_appointments_repository.dart:640`) — every other ceiling in that file
  has a paired test. Truncate it and clashes past the cap go unreported, so the
  picker under-dims and the Save-time prompt under-fires.
- The search cache's TTL/LRU — `_clock`'s comment says it exists so tests can
  inject a fake clock, and **`clock:` appears in zero calendar test files**. Only
  invalidation is tested, never expiry or eviction.
- `isFirstAsyncError` (`error_cause.dart:56`) — zero tests, six call sites; its
  dartdoc says three sites previously spelled the distinction wrong.
- `assignee_availability_scope.dart:66-72` and `_whenLabel` — never reached; the
  picker test injects a literal `whenLabel`, so rendering is pinned but the
  production label (including its `isAllDay` branch) is not.
- `SecureStorageService._migrate`'s catch path (`:101-110`) — nothing drives a
  **throwing** migration, so `_migration = null` at `:109` is unpinned. Drop it
  and one pre-first-unlock `-25308` caches a "completed" future forever: keys
  stay on the old accessibility class and the biometric lock silently stops
  engaging.
- `AccountExitController`'s navigation (`:69-83`) — order and guards are pinned,
  the push-to-login is not. Drop it and a deleted user is signed out but left on
  the screen they had open, with `persistenceEnabled: true` still serving cached
  client names and addresses.
- `travel_utils.js:772-798` — `loadContextByEmployee`'s query shape, including
  the trailing `orderBy("endTime")` that requires the composite deleted on
  2026-08-29. **This is the exact site of the two-day invisible outage.** No test
  anywhere couples a sweep query to `firestore.indexes.json`, though the
  precedent exists (`notification_policy_ledger_body.test.js` reads the manifest).
- `wave/triggers.js:255-257` — the `runWaveDaily` guard you deployed yesterday;
  hoist the read back above the `try` and the bug returns, green.
- `wave/triggers.js:126-136` — the batch payload executes but is never asserted;
  deleting `...problemsPatch(after)` passes the whole suite and Phase 1 silently
  stops writing its only data source.

### I15 — Accessibility gaps · medium
Strong overall (all 13 `IconButton`s and 5 FABs have tooltips; colour is never
the sole cue; `liveRegion` on both banners). Verified gaps:
- `form_helpers.dart:49-75` — `formRemoveButton` is a **32×32** tap target,
  below Material's 48dp and iOS's 44pt, and its comment claiming it "meets
  Material minimum" is wrong.
- Three Settings switches never pass `SettingsTile.onTap`
  (`security_settings_card.dart:29-40`, `notifications_settings_card.dart:86-119`),
  so the row label is dead and only the ~31pt switch is tappable.
- `key_value_panel.dart:78,95-104` — the 70px key column holds a bare `Text` with
  no `maxLines`/`overflow`; `PHONE`→`TÉLÉPHONE` wraps in French where English
  never does.
- **Compliance:** `docs/legal/accessibility.html` publicly claims Bold Text and
  Increase Contrast support, but nothing in `lib/` reads `boldTextOf`/
  `highContrastOf` and Flutter does not honour these automatically. Correct the
  page or the code before the next Accessibility Nutrition Label review.

### I16 — Offline UX: the photo queue is invisible · medium
`PendingUploadStore` persists batches and `drainPending()` retries on reconnect,
but `PhotoUploadNotifier` exposes only `latestFailure` — there is no "pending"
state, and `PhotoUploadFailureListener` fires only on definitive failure. Someone
who photographs a job underground has no way to know the photos haven't left the
phone. Compounds I1. Also: neither `add_appointment_sheet.dart:180-243` nor
`add_client_sheet.dart:169-217` reads `isOfflineProvider` in the widget layer, so
you can fill out an entire appointment before being told it can't be saved.

### I17 — Operational hygiene · low-medium
- **External scanner noise** floods the Functions ERROR log (31 of 40 entries).
  Consider a log-based exclusion for the CORS-middleware rejection signature so
  real errors surface.
- **`functions/` has no jest config** — no `coverageThreshold`, no
  `collectCoverageFrom`. The 82.73% stmts / 76.97% branch baseline is not
  enforced, so coverage regresses silently. One-line ratchet at the current
  number.
- **`firebase.json`** ignores `build/**` but not `coverage/**`. One
  `jest --coverage` run writes hundreds of HTML files that would upload with the
  deploy, with no error and no diff to catch it.
- **`functions/scripts/` paging loop hand-written 6×** across 5 files
  (`audit-wave-contract.js:67`, `backfill-appointment-images.js:176`,
  `clear-appointment-picture-arrays.js:179`, `count-legacy-image-urls.js:88` and
  `:154`, `count-multi-day-appointments.js:107`). All correct today, but these
  scripts produce the migration and audit *numbers* this project makes decisions
  on, and the directory already has the shared-helper convention (`_batch.js`,
  `_flags.js`, `_project.js`). Also `stageDelete` (`_batch.js:113`) has zero test
  references, and its own docstring warns "a delete is not re-runnable" — the
  same shape as your recorded lesson about a backfill whose `--dry-run` wrote
  everything.

### I18 — Smaller product gaps · low-medium
- No week view and no per-technician calendar filter — three surfaces answer
  "what is Marc doing this week" and none is the calendar.
- Nothing supports "running late" / "on my way"; rescheduling needs
  open → Edit → date → Save. A reusable per-row crew-swap with Undo already
  exists in `personal_block_clash_dialog.dart`, reachable only after saving a
  day off.
- No duplicate / "book again" action, though repeat callbacks are common.
- The technician has no search at all (`drawer_catalog.dart:15-42`).
- No job time record — no `startedAt`/`completedAt` anywhere, so
  `JobTemplate.defaultDurationMinutes` stays a guess.
- No haptic on Mark as complete — the one button a gloved field worker presses
  while glancing away. Zero `onLongPress`/`CupertinoContextMenu` in all of
  `lib/`; swipe-to-complete on an agenda row is the cheapest polish win.
- `ios/Runner/Info.plist:57-70` has no `InfoPlist.strings` for any locale, so
  every OS permission prompt is English on a bilingual product.

---

## 🟡 Code-quality suggestions

- **`ClientSearchPolicy.matchesClient` has zero production callers**
  (`client_search_policy.dart:87`). CLAUDE.md calls it "the single client-side
  fallback matcher — route new client matching through it", but every production
  path uses `index()`+`entryMatches()` or `rawMatches()`. The split exists *for
  performance*: `index()` is hoisted to run once per data change, and
  `matchesClient` rebuilds the projection per candidate per keystroke. An author
  following CLAUDE.md literally would route new matching through exactly the
  function the hot paths were refactored to avoid. **Decide:** update the doc to
  name the real owners and demote this to a test shim, or delete it and re-point
  the test at `entryMatches`.
- **Admin callable guard prologue repeated at 11 sites** — `security.js` already
  owns `assertAdmin`/`assertPayloadShape`/`assertFreshReauth`/`APP_CHECK`, but
  the auth-check + gate prologue is re-decided per callable. An
  `assertAdminCall(req, allowedKeys)` would make **I4** structurally impossible
  rather than testing for it three times.
- Five byte-identical function pairs across `clients_list_view.dart` /
  `appointment_history_view.dart` (`_scheduleSearch`, `didUpdateWidget`,
  `_notifyFirstPageSettled`, `dispose`) — one coherent ~40-line "debounced search
  over a `PagingController`" block. Plus `_onAddClient` in both
  `clients_screen.dart:66` and `clients_list_view.dart:153`, which is worse in
  kind: the add-client → book-a-job flow lives in two places with no compile
  error if they drift.
- `setDayOff`/`setAllDay` twins across `add_event_controller.dart:206/239` and
  `event_details_controller.dart:276/260`; the extractable core is the error-key
  clearing re-spelled at **7 sites**.
- l10n prefix buckets: 188 keys sit in six buckets CLAUDE.md doesn't list
  (`applock_`, `onboarding_`, `wave_`, `dashboard_`, `liveMap_`, `tour_`).
  `liveMap_` is the lone lowerCamel prefix. Update the doc.
- `functions/client_address_utils.js:203,204` and `recount_claim.js:161` export
  internal-only helpers.
- `month_grid.dart:6` — `monthGridMaxRows` has no production caller and its
  comment ("Used to bound layout") is factually wrong; it's a test bound. Keep,
  fix the comment.
- Two raw colour literals outside the theme layer
  (`dashboard_hero.dart:63`, `image_viewer.dart:220`/`:313`) and six spacing
  calls mixing an on-scale value with an off-scale nudge. Arguably deliberate —
  worth a one-line comment rather than a change.

---

## Notes / uncertainties

- **`build()` length is effectively house style.** 58 of 333 exceed the ~60-line
  guideline, longest 98, and the top eight are flat trees with sub-widgets
  already extracted. Either relax the documented number to ~100 or leave it —
  reported as one aggregate, not 58 findings.
- **No god files, no nesting or boolean-parameter problems, `mounted`/`ref`
  handling genuinely clean.** Deepest control flow anywhere in `lib/` is 5.
- The `functions/` npm audit shows 8 moderate advisories, all transitive from
  `uuid <11.1.1` via `firebase-admin`. No code calls `uuid` with a `buf`, and the
  only fix is `firebase-admin@14`, recorded as incompatible with
  `firebase-functions@7.x`. Leave pinned.
- `isAlreadyExists` is at **two** instances — under the 3+ duplication bar — but
  listed in I12 because the 2026-08-28 audit records it as closed and it isn't.
  Don't let a third appear.
- I could not verify the Wave dead-letter queue state (MCP tool error, not a
  clock issue). Check the Wave settings screen for a parked job.
- I did not open `dev/.env`.

---

---

## Implementation status (2026-09-01)

Owner asked for everything, including the product work. **Not deployed** — the
rules and functions changes are landed in the tree only.

**Closed:** S1, S2, S4, S5, S6 · B1-B7 · I1-I17, plus most of the
code-quality section. Every mutation-proven finding was re-verified by
removing the guard and confirming the new test fails.

Notes on how three of them were implemented differently from the suggestion:

- **S2** is guarded on `uid`, not a flat denylist entry. `updateEmployee`
  writes `email` directly when the doc has no Auth account, and
  `changeEmployeeEmail` refuses such a doc outright — a flat denial would
  brick that doc's email with no path to repair it. The guarded form covers
  the whole live fleet, since every P4c doc carries its uid from creation.
- **I10** refreshes `fetchedAt` on a local patch *behind an absolute
  ceiling* (`_scanWindowMaxAge`, 10 min). Refreshing alone would let a
  steadily-edited window live forever and never see a REMOTE write, which is
  the only thing the TTL protects against.
- **I13**'s `SearchResultCache` made the LRU testable for the first time; the
  eviction is not observable through either repository, since a hit and a
  recompute return the same answer.

**Left, and why:**

- **S3** (Maps budget cap) needs `roles/billing.admin` — owner-only.
- **I17**'s log-based exclusion for the CORS-middleware scanner noise is a
  GCP console change. The other three I17 items are done (jest coverage
  ratchet, `coverage/**` deploy ignore, `scanByName` + `stageDelete` tests).
- **I18**: the mark-done haptic and the localized iOS permission prompts are
  done. The week view, the per-technician calendar filter, "running late" /
  "on my way", duplicate-a-job, technician search and a `startedAt`/
  `completedAt` job time record are NOT — each is a product decision plus a
  screen, not a cleanup.
- Three code-quality refactors remain: the duplicated debounced-search block
  across `clients_list_view` / `appointment_history_view`, `_onAddClient` in
  two places, and the error-key clearing spelled at 7 sites.
- The two new `ios/Runner/{en,fr}.lproj/InfoPlist.strings` must be added to
  the Runner target in Xcode before they ship. `project.pbxproj` was not
  hand-edited.

**Still owner-only from the telemetry section:** confirm the two Crashlytics
issues are gone once 1.55.0 has fleet time, and press "Retry failed" once on
the Wave settings screen.
