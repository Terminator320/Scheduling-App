# Codebase Audit — 2026-07-21 (second pass)

> **Implementation status (same session).** All 3 security findings, all 6 bugs,
> all 4 minor bugs, and I1/I3/I12 + the full documentation-drift list were
> implemented on `notification`. Final state: `flutter analyze` 0 errors /
> 0 warnings / 3 info · `flutter test` **1008 passing** · `functions npm run
> lint` clean · `functions npm test` **654 passing**.
>
> **Three findings were deliberately NOT implemented as written**, each because
> acting on them would have made the codebase worse. Reasoning is recorded at
> the finding and in the code:
> - **I6 (`requireAdminCall`)** — implemented, then **reverted**. The callable
>   suites mock `assertAdmin` and keep `assertPayloadShape` real specifically to
>   pin the guard ORDER per callable. A helper in `security.js` closes over the
>   real `assertAdmin`, so the mock stops applying and the only way to keep those
>   18 tests green is to re-implement the order inside the test mock — which
>   destroys the property they exist to prove. Rationale is now a comment in
>   `functions/security.js` so this isn't re-attempted.
> - **I7 (derive `employeesStreamProvider` from `allUsersStreamProvider`)** — NOT
>   done. `watchEmployees()` is not a strict subset: `watchAllUsers()` adds
>   `orderBy('name')`, and Firestore EXCLUDES docs missing the orderBy field, plus
>   a 500 cap. Deriving one from the other would silently drop an unnamed active
>   employee from the picker — and unassigning staff changes who can see a visit.
>   The safe half (a `.limit(500)` for parity with its two siblings) was applied,
>   with the asymmetry documented in the query.
> - **S3 (lower the `contacts` cap 50 → 20)** — the cap was left at 50. The app
>   enforces no contact-count limit of its own, so lowering it would reject the
>   next save of any existing client already above the new value, for no real
>   security gain (Firestore's 1 MB doc ceiling bounds it either way). The
>   residual gap is now documented in the rule instead.
>
> **Still open (report-only, not implemented):** I2, I4, I5, I8, I9, I10, I11 —
> all structural refactors with no correctness impact — plus the two ambiguous
> spacing-literal call sites and the `dashboard_hero.dart:25` colour question.
>
> **Needs a deploy to take effect:** `firestore.rules` (S1 + S3 comment + the new
> `appointmentSeriesNotices` deny rule) and `functions` (S2, B2, B4).

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`). Baseline: working tree at `1192fc1`.

> This supersedes the earlier same-day audit (see `git log` for that revision),
> which covered the Crashlytics/secure-storage pass. This is an independent
> five-reviewer sweep run after that work landed.

## Summary
- Scanned: 261 non-generated `lib/` files (~37.6k lines), 29 `functions/`
  modules (~8.5k lines), 162 Dart test files + 27 jest suites, both rules files.
- Auto-fixed (safe, in the diff): **3** — 5 `unnecessary_lambdas` in one test
  file, 2 design-token spacing swaps.
- Reported for your decision: **22** (⚠️ 0 pre-ship · 🔴 3 security · 🟠 6 bugs +
  4 minor · 🔵 12 improvements)
- Verification: `flutter analyze` **3 info issues, 0 errors/warnings** (unchanged
  vs. baseline) · `flutter test` **1000/1000 pass** · `functions npm run lint`
  **clean** · `functions npm test` **644/644 pass**

**No S1 or S2 security findings. No pre-ship blockers.** The areas CLAUDE.md
flags as fragile — search-cache invalidation, `whereArrayContainsAny` chunking,
assignee retention, status normalization, the travel-sweep bounds, the
Dart↔JS↔Swift payload mirrors, controller disposal — were all checked and hold.

## Auto-applied cleanups (review the diff)
| File:line | Change | Why |
|---|---|---|
| `test/features/live_activity/live_activity_token_repository_test.dart` | 5 × `unnecessary_lambdas` | `dart fix` (tool-verified); file re-run, 12 tests pass |
| `lib/features/calendar/utils/cupertino_time_picker.dart:89-92` | `horizontal: 16, vertical: 8` → `AppSpacing.sp16/sp8` | design token; file already imported `design_tokens.dart` |
| `lib/shared/widgets/primitives/quick_action_button.dart:52-55` | `vertical: 12` → `AppSpacing.sp12` | design token; sibling `horizontal` was already tokenized |

> Full detail is in `git diff`. Nothing below this line was auto-changed.
> Note: `firestore.indexes.json` is also modified in this working tree, but that
> is from the earlier deploy session (TTL policy restoration), not this audit.

## ⚠️ Pre-ship checklist
**None.** No `TODO(pre-ship)` scaffolding, no destructive testing affordances,
and no App Check carve-outs remain — all 9 callables set `enforceAppCheck: true`.

## 🔴 Security findings (review required)

### S1 — `liveActivityTokens` rows written without `expiresAt` are never reaped · severity: medium · confidence: high
- **Where:** `firestore.rules:231-234` (rule); `functions/live_activity_registry.js:306-313` (sweep)
- **Risk:** The rule bounds `expiresAt` **only when the key is present**
  (`!('expiresAt' in ...keys()) || (...)`). The reaper filters
  `.where("expiresAt", "<=", now)`, and Firestore **excludes documents missing
  the filter field** — as does the Firestore TTL policy. So a row written
  without `expiresAt` is invisible to all three reapers, permanently. The client
  also picks the doc id (it is the ActivityKit activity id), so row count is
  unbounded. Every surviving `pushToStart` row is fanned out as its own direct
  APNs request on every `leaveNow` (`live_activity_dispatch.js:185-210`), so one
  legitimate reminder amplifies into N pushes forever.
- **Attack path:** an authenticated active employee on an instrumented device
  writes `users/{ownDocId}/liveActivityTokens/{randomId}` with a valid body and
  no `expiresAt`, in a loop. Every write passes the rule.
- **Fix:** make the field mandatory, not optional. **Not a breaking change** —
  verified `expiresAt` is a `required DateTime` parameter
  (`live_activity_token_repository.dart:49`) always supplied at
  `live_activity_registration_controller.dart:300`. The real client cannot omit
  it; only a modified one can. Needs a `firestore:rules` deploy.
- **Related, weaker:** `fcmTokens` (`firestore.rules:181-193`) has no TTL field
  at all and self-heals only for the two FCM codes in `isStaleTokenError`
  (`notification_utils.js:483-486`). A planted row producing any other code
  persists and is retried on every push. Lower impact (FCM batches; no per-row
  connection) but the same class.

### S2 — `createEmployeeInvite` bypasses the `colorValue` validation the rules enforce · severity: low · confidence: high
- **Where:** `functions/invites.js:132` (written at `:93` / `:105-110`)
- **Risk:** `firestore.rules:143-145,168-169` reject a `users` write whose
  `colorValue` isn't `^-?[0-9]+$`. The invite callable validates it only as a
  ≤40-char control-char-free string and writes via the Admin SDK, bypassing rules
  entirely. Impact is cosmetic (client falls back to blue) and admin-only —
  flagged as a rules-vs-server divergence on a field the rules explicitly guard.
- **Fix:** apply the same regex before the transaction.

### S3 — `isValidClientData` bounds the `contacts` array length but not its elements · severity: low · confidence: medium
- **Where:** `firestore.rules:327`
- **Risk:** `data.contacts is list && data.contacts.size() <= 50` has no
  per-element type or size cap, while every scalar sibling is capped.
  `ClientContact.toMap` emits three unbounded strings per element
  (`client_record.dart:24-28`), so an admin write can land ~1 MB of arbitrary
  data, which rides into `propagateClientEdits` and every denormalized
  appointment copy. Admin-only, bounded by Firestore's 1 MB ceiling —
  storage/perf abuse, not a confidentiality or integrity break.
- **Fix:** rules language can't loop, so use an aggregate cap — lower `contacts`
  to 20 and enforce per-field limits client-side via `TextLimits` (already the
  pattern), documenting the residual gap in the rule comment.

## 🟠 Bug findings (review required)

### B1 — Employees can never mark a job complete after its start day · severity: high · confidence: high
- **Where:** `lib/features/calendar/widgets/views/details_action_bar.dart:38`;
  data at `details_view_body.dart:209`
- **Problem:** the only employee-reachable "Mark as complete" button is gated on
  `isToday && !isDone && !isCancelled`, where `isToday` is
  `DateUtils.isSameDay(appointment.startTime, now)`. The only other status
  surface is the edit form's picker, gated by `showActions` = `isAdmin`.
  An employee who finishes at 23:50 and forgets to tap Complete gets the
  `sendOverdueJobPrompts` push at 00:15 — literally *"Is the job for X done yet?
  Open the app to update its status."* (`functions/notification_utils.js:287`) —
  opens the job, and **there is no button**. The job stays `pending` forever,
  shows as `overdue` on the dashboard, and stays in `todayJobs` and the Siri
  snapshot. Same dead end for day 2+ of any multi-day visit.
- **Fix:** gate on stored status, not the date — e.g.
  `!isDone && !isCancelled && !startTime.isAfter(now)`. **Verified rules-safe:**
  `firestore.rules:299-305` lets an assigned employee write `status:'done'` with
  no date restriction, so widening the button needs no rules change.

### B2 — Repeat-series delete/cancel/reschedule fans out one push per sibling · severity: high · confidence: high
- **Where:** `functions/notification_utils.js:157-158` (guard) vs `:162`, `:170`, `:175`
- **Problem:** the anchor dedup (`seriesId !== id → return []`) exists **only in
  the create branch**. Delete, cancel, and reschedule have no equivalent guard,
  so a series operation notifies per sibling doc. `event_details_controller.dart:634`
  and `appointment_series_editor.dart:110` write up to 15 docs in one batch, each
  firing `notifyAppointmentChanges` separately. Per invocation that is 1 card-marker
  read per assignee, 1 widget-window range query per employee (the `windows` Map
  is per-invocation, so nothing is reused across siblings), 1 users doc + 1
  `fcmTokens` read — **and one push per device**. Net: deleting or rescheduling
  one repeating job sends a tech ~15 notifications and ~15× the reads.
- **Fix:** extend the anchor dedup to the `cancelled`/`rescheduled` kinds via a
  short-lived `seriesId+kind+employeeDocId` claim doc, same shape as the existing
  reminder ledger, so only the first sibling of a batch notifies.

### B3 — Deep-linked appointment sheet opens in admin mode for employees · severity: medium · confidence: high
- **Where:** `lib/main.dart:314`
- **Problem:** `showEventDetails(navContext, record)` omits `showActions`, which
  defaults `true` (`lib/features/calendar/utils/sheet_helpers.dart:27`). Verified
  every other call site passes the role explicitly (`main_calendar_screen.dart:103`,
  `event_list.dart:109`, `appointment_history_view.dart:252`,
  `client_job_history_section.dart:96`) — the deep-link path is the sole outlier.
  An employee tapping a push or iOS widget row sees **Edit**, **Cancel
  appointment**, and inside edit **Delete appointment**. All three fail with
  `permission-denied`. No data leak (the `clients` read is role-gated at
  `event_details_controller.dart:153`), but three prominent always-failing controls.
- **Fix:** pass the resolved role, and make `showActions` **required** so no
  future call site can silently default to admin.

### B4 — Daily digest query omits `in_progress`, contradicting its own filter · severity: medium · confidence: high
- **Where:** `functions/notification_utils.js:975` (query) vs `:431` (pure filter)
- **Problem:** three sweeps use three different literal status arrays, none from
  a shared constant: overdue `["pending","in_progress","confirmed"]` (`:921`),
  digest `["pending","confirmed"]` (`:975`), travel `["pending","confirmed"]`
  (documented and correct — the visit already started). The digest's own pure
  filter `groupTomorrowsJobsByEmployee:431` skips **only** `cancelled`, i.e. it is
  written expecting every status and to filter in Dart. The query never delivers
  `in_progress`, so a job stored `in_progress` for tomorrow silently drops out of
  the 18:00 digest — **and the unit test passes on records production never sees.**
- **Fix:** add `"in_progress"` to `:975` and hoist to a shared `OPEN_STATUSES`.

### B5 — Unsafe list cast can kill the whole appointment stream · severity: medium · confidence: high
- **Where:** `lib/features/calendar/domain/models/appointment_record.dart:93`
- **Problem:** `List<String>.from(value)` throws `TypeError` on any non-String
  element. This parses `employeeIds`/`employeeNames` straight from Firestore, so
  one malformed element takes down the **entire stream**, not one record. The
  sibling six lines below (`_parseImageList:100`) uses `.whereType<...>()`, and
  `firebase_appointments_repository.dart:453` uses `.whereType<String>()` for the
  same field — this is the last unsafe spelling.
- **Fix:** `return value.whereType<String>().toList();` (Same class, lower stakes:
  `google_places_repository.dart:90` `.cast<String>()` is lazy and throws on
  iteration.)

### B6 — Photo-upload drain can double-upload a batch still being staged · severity: medium · confidence: medium
- **Where:** `lib/features/calendar/data/appointment_image_upload_service.dart:55-69` vs `:183-201`
- **Problem:** `drainPending()` is reentrancy-guarded by `_draining`, but
  `_stageAndRun` is not — it does `await _store.add(entry)` then `await
  _attempt(entry)` entirely outside that guard. If the offline→online or
  account-doc listener (`app_sync_listeners.dart:114-135`) fires `drainPending()`
  in that window, it loads the just-added entry and calls `_attempt` concurrently.
  Both passes see the staged file and both upload; `ImageStorageService` mints
  `fileName` from `DateTime.now().millisecondsSinceEpoch`, so the two get
  **different** `storagePath`s and `arrayUnion` cannot dedupe them. The photo
  appears twice in the carousel and twice in Storage.
- **Fix:** serialize staging behind the same guard as the drain.

### Minor bugs (low severity)
- `event_details_controller.dart:290` — `markAsDone`/`cancelAppointment` return
  `null` (their success sentinel) on the reentrancy path, so a status tap landing
  while `save()`/`deleteAppointment()`/`setSaving()` hold `isSaving` shows
  *"Appointment marked as complete"* and closes the pane **with no write**.
- `event_details_controller.dart:89` and `appointment_series_editor.dart:107` —
  `AppointmentStatus.fromRaw('overdue')` returns `overdue`, whose `.raw` throws by
  design. A doc with a stored `'overdue'` status (Admin-SDK/console only) makes
  the detail sheet fail to open and breaks mid-series save.
  `buildScheduleSnapshot` already defends via `_storedStatus`; route these two
  through the same mapper.
- `lib/core/launchers/address_map_launcher.dart:119` — `await launchUrl` with no
  try/catch and no `logger.warn`; a throw escapes to the zone handler as fatal.
  Its four sibling launchers all guard correctly.
- `lib/core/storage/secure_storage_service.dart:124-127` — `catch (_)` swallows
  every exception from the one-shot Keychain migration with zero logging. Not a
  sanctioned exception (this class has normal DI access), so a permanently
  failing migration retries silently forever with no Crashlytics signal.

## 🔵 Areas to improve (review required)

### I1 — `app_sync_listeners.dart` has zero tests · impact: high
- **Where:** `lib/core/app/app_sync_listeners.dart` (138 lines)
- **Opportunity:** its own docstring says it was *"extracted from `_PaulAppState`
  so this wiring can be exercised without building a `MaterialApp`"* — and then
  never was. It owns six listeners including two non-obvious transition
  predicates encoding invariants CLAUDE.md calls load-bearing: `:120`
  (`previous == true && !next && isSignedIn`, the offline→online photo drain) and
  `:130-132` (the first-account-doc drain, where *"a signed-out drain just
  re-queues"*). Best payoff-per-line in the repo.

### I2 — The three device-sync controllers duplicate a 5-part skeleton · impact: medium
- **Where:** `push_registration_controller.dart:61,79-88,110-123,134-144`;
  `presence_sync_controller.dart:95,110-121,136-151,153-165`;
  `live_activity_registration_controller.dart:91,113-121,150-156,174-181,125-134`
- **Opportunity:** identical `_busy`/`_pendingResync`, reentrancy guard, role
  gate, `findUserByUid` resolution, and `catch → warn` + `finally` coalescing,
  differing only by log tag. `_currentLocale()` is copied verbatim in three files.
  **Already drifting:** `active_user_identity_provider.dart:33`,
  `splash_controller.dart:38` and `sign_in_controller.dart:116` wrap
  `findUserByUid` in `retryAsync`; none of these three do. (Medium not high:
  they run off a *successful* `currentUserDocProvider` emission, so the token race
  is largely past — a maintainability signal, not a live bug.)

### I3 — `url_launcher` launch-and-notice body duplicated 4× (+1 divergent) · impact: medium
- **Where:** `phone_call_launcher.dart:16-33`, `web_url_launcher.dart:55-69`,
  `route_map_launcher.dart:15-29`, `email_compose_launcher.dart:118-130`;
  divergent: `address_map_launcher.dart:118-126`
- **Opportunity:** identical apart from l10n message and log tag — and the fifth
  copy dropped the try/catch entirely, exactly the drift a helper prevents.

### I4 — `AsyncValue` data→error listener block duplicated 4× · impact: medium
- **Where:** `day_route_screen.dart:79-98`, `main_calendar_screen.dart:182-203`,
  `dashboard_screen.dart:53-71`, `live_map_screen.dart:173-191`
- **Opportunity:** the transition guard is spelled **two different ways** —
  `if (next is! AsyncError || previous is AsyncError) return;` vs
  `if (!next.hasError || (previous?.hasError ?? false)) return;`.

### I5 — `functions/notification_utils.js` is the one genuine god file · impact: medium
- **Where:** 1034 lines, 22 exports
- **Opportunity:** mixes appointment diffing, EN/FR message tables, ledger ids,
  FCM delivery, widget-payload fetching, the write trigger, Live Activity
  teardown, **and** two of the three sweep runners. The problem is concern count,
  not lines. Split the two sweep runners into `notification_sweeps.js` — they are
  self-contained and `runTravelAwareReminderSweep` already lives separately.

### I6 — Callable guard prologue repeated 8× · impact: medium (security)
- **Where:** `places.js:136,192,254`; `wave/callables.js:133,211,243,275`; `invites.js:121`
- **Opportunity:** the LOC argument is weak; the real one is that `security.md`
  mandates a guard **order**, and an omitted `assertAdmin` on a new callable would
  fail no test and produce no error.

### I7 — Two overlapping always-alive `users` streams · impact: medium
- **Where:** `employees_providers.dart:17` and `:64` — both non-autoDispose live
  listeners on `users`; `watchEmployees()` is a strict subset of
  `watchAllUsers()`, and `employees_screen.dart:136,224` watch both.

### I8 — Two overlapping always-alive appointment mirrors on iOS · impact: medium
- **Where:** `widget_sync_service.dart:227-233` vs `schedule_snapshot_provider.dart:24-39`
  — the widget's `today..+3d` window is fully contained in the snapshot's `today..+8d`.

### I9 — Long functions in `functions/` worth one extraction each · impact: medium/low
- `wave/worker.js:574-737` — `dispatchQueuedJobs`, 163 lines carrying claim /
  dispatch / outcome; extract `:663-735` into `resolveJobOutcome(...)`.
- `travel_utils.js:486-604` — `runTravelAwareReminderSweep`, 118 lines; `:514-567`
  form a clean `loadSweepContext(...)` carrying the two subtle query bounds the
  comments spend 12 lines defending.

### I10 — `compute()` isolate spawn likely costs more than it saves on search · impact: low
- **Where:** `firebase_clients_repository.dart:182`, `firebase_appointments_repository.dart:356`

### I11 — Sequential per-pair ledger reads in the 5-minute travel sweep · impact: low
- **Where:** `functions/travel_utils.js:399-401`, `:575-600` — P pairs cost P
  sequential round trips; mirror the existing presence `getAll` batching at `:524`.

### I12 — `functions/` exported-but-unconsumed symbols · impact: low
- **Where:** `apns_client.js:386-392`, `notification_utils.js:1012-1029`,
  `travel_utils.js:679-689`, `live_activity_utils.js:235-237`,
  `client_propagation.js:223`, `wave/customers.js:684`, `bridge.js:275-276`,
  `widget_payload_utils.js:176,178`
- **Opportunity:** two carry a stale *"exported for unit tests"* comment where the
  test never imports them. Worse: `functions/scripts/backfill.js:25` keeps its own
  **duplicate** of `shouldHaveBridge` rather than requiring `bridge.js`'s export.

## 🟡 Code-quality suggestions (optional)
- `dashboard_hero.dart:25` — `Color(0xFF00A6F4)` exactly equals `AppColors.accent`.
  **Deliberately NOT auto-fixed:** it is one of a matched pair of "theme-invariant
  on-primary data hues", and its sibling `_overdueSegment = Color(0xFFF54A00)` maps
  to no token. Substituting only one would couple a data hue to a semantic brand
  token that can later change independently, and break the pair's symmetry. A
  judgment call, not a mechanical swap.
- Partial/ambiguous spacing literals, reported rather than swapped:
  `details_view_leaf_widgets.dart:179-182` (`vertical: 4` → `sp4`, but
  `horizontal: 11` maps to nothing) and `photo_picker_section.dart:200-202,237-239`
  (`Positioned(top: 4, right: 12)` — needs a policy call on whether the token rule
  extends past `EdgeInsets` to `Positioned` offsets).
- `settings_screen.dart:595-599` — `AuthFailure` from `reauthenticateWithPassword`
  surfaces a notice with no `logger.warn`. Counterpoint: the repo deliberately does
  not log *expected* validation outcomes (`EmployeeEmailInUse`,
  `employee_form_controller.dart:164-166`).
- `live_activity_registration_controller.dart:313-318` — `endLocalCards`' docstring
  claims it is *"called when the user marks a job done or cancels it in-app"*. Its
  one call site (`unregister()`) is correct per the CLAUDE.md invariant, but the
  comment invites someone to wire it to the status path, which would kill the card
  for the job the tech is driving to. **Doc fix only — do not change the wiring.**
- 3 remaining analyzer info lints: `live_map_screen.dart:384`
  (`avoid_catching_errors`), `wave_settings_section.dart:65`
  (`avoid_positional_boolean_parameters`), `app_bottom_sheet.dart:10`
  (`comment_references`).
- `lib/core/speech/` is an **empty directory** left over from the reverted
  dictation work — safe to delete.
- 14 test files sit at `test/` root against the documented "mirrors `lib/`"
  convention, producing near-duplicate pairs (`test/settings_screen_test.dart` vs
  `test/features/settings/settings_screen_mobile_test.dart`).
- `functions/__tests__/import_schedule.test.js` vs `wave_import_schedule.test.js`,
  and `mappers.test.js` vs `wave_mappers.test.js` — overlapping coverage of the
  same modules.

## Documentation drift
Most of this is fallout from the `AppSyncListeners` extraction — the code moved,
the docs didn't.

**CLAUDE.md**
1. `:104` — references `_seedSelectedEmployees`; the real symbol is
   `_enrichSelectedEmployees` (`event_details_controller.dart:115`).
2. `:434` — *"`main.dart`'s `_listenForSnapshotSync`"* — it is
   `AppSyncListeners._snapshotSync` (`app_sync_listeners.dart:97`).
3. `:122-124` — *"`main.dart` drives the drain"* — `drainPending()` is called only
   from `app_sync_listeners.dart:121,133`.
4. `:429-430` — *"`main.dart` drives `sync()`"* for push and presence — both live
   at `app_sync_listeners.dart:42-52` and `:54-60`.
5. `:62` — *"~1000 info lints; filter for real issues"*. `flutter analyze` now
   reports **3 issues total**; that advice teaches a filtering habit for noise
   that no longer exists.

**docs/ARCHITECTURE.md**
6. `:679-680`, `:688` — *"`flutter analyze` is clean — zero issues"*. It is 3.
7. `:677-679` — *"967 test cases… 568 jest tests"*. Actual: **1000** Dart / **644** jest.
8. `:15-33` — the `core/` map omits `lib/core/notifications/` (the load-bearing
   `fcm_background_handler.dart` isolate entry point).
9. `:37-42` — `shared/widgets/` listing omits `feedback/centered_error_text.dart`,
   `primitives/name_initials.dart`, `sheets/app_bottom_sheet.dart`.

**docs/CLOUD_FUNCTIONS.md**
10. `:242` — `endCardOnCompletion`; renamed to `endCardOnTerminal`
    (`notification_utils.js:706`). CLAUDE.md:433 documents the rename — this doc
    is the stale side.
11. `:166-167` — `placesReverseGeocode` marked *"Not yet deployed"*, contradicted
    by `:29-33` in the same file.
12. `:105-107` — `deleteAccount`'s `recursiveDelete` list says *"`fcmTokens` today,
    `presence` when the travel-time plan lands"*. Presence landed, and
    `liveActivityTokens` now exists too. Same stale wording duplicated at
    `functions/account.js:140-141`.

## Notes / uncertainties
- **Verified clean, recorded so the next audit doesn't re-litigate:** 429 ARB
  keys, all with a live call site and **zero EN/FR drift**; all 69 Riverpod
  providers used; all 10 route constants dispatched (5 indirectly via
  `AdaptiveDestination.route` → `settings_drawer.dart:320`); 0 unreferenced files
  out of 260; all 28 `shared/widgets` classes used; zero `throw Exception(...)` in
  `lib/`; no unsanctioned `ScaffoldMessenger` or UI-layer
  `FirebaseFirestore.instance`; all `LabeledTextField` caps via `TextLimits`; all
  hub FABs uniquely tagged; all `AppSearchBar` sites pass `textScaler`; all 16
  `composeErrorNotice` tag/log-label pairs match.
- **All 4 unused-dependency candidates from the static scan are false positives**
  and should not be re-flagged: `google_maps_flutter_ios_sdk9` (load-bearing SPM
  override, platform package), `build_runner` + `freezed` (genuinely used — 9
  `.freezed.dart` files), `flutter_launcher_icons` (live config at `pubspec.yaml:163`).
- Error-notice tags `DASH-LOAD`, `LIVEMAP-LOAD`, `APPT-LOAD`, `CLI-JOBS` are
  internally consistent but absent from CLAUDE.md's "existing tags" list — the doc
  is stale, not the code.
- The service/repository public-method sweep was a **sample** (~70 methods across
  the largest classes), not exhaustive; smaller `settings`/`wave` service classes
  were not individually checked.
- Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/.gen/**`,
  `firebase_options.dart`) were excluded throughout, per `analysis_options.yaml`.
- B6 (photo double-upload) is a timing-window race reasoned from the code paths,
  not reproduced on a device. Method-channel code is device-only verify per CLAUDE.md.
