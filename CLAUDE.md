# CLAUDE.md

Flutter app (Dart `^3.10.7`) for managing appointments, clients, and employees.
Backend: Firebase (Auth, Firestore, Storage, App Check). **iOS is the only
platform.**
**Ships to the App Store ONLY (decision 2026-07-08), and `android/` was
DELETED on 2026-08-05** (owner call) once development moved from a Windows box
to a Mac and iOS could build and run locally — Android had only ever been the
dev/test harness that gave that Windows box something runnable, and it was
never published to Play. Don't re-add it, don't restore Play-release work
(keystore, Data Safety, Play Integrity), and don't "fix" an iOS-only assumption
by reintroducing an Android branch. Recover the tree from git history if it is
ever genuinely needed. **`/android/` is now in `.gitignore`, and that entry is
load-bearing** (2026-08-08): a merge (`33715f82`) silently resurrected the tree
and brought `android/local.properties` with it, which carries a live
`MAPS_API_KEY` — a committed secret. `flutter` regenerates that directory on any
Android-touching command, so ignoring it is the only thing that stops a second
resurrection; deleting the files alone does not. Don't remove the entry to
"restore" an Android build. Two Android remnants survive **deliberately** and are
not dead code to clean up: `DefaultFirebaseOptions.android` (the Android
Firebase app still exists in the console, and the shared `dev/.env` keys feed
it) and the `platform: 'ios' | 'android'` field on `fcmTokens` docs, which the
CURRENT build still writes — `push_registration_controller.dart` stamps
`Platform.isIOS ? 'ios' : 'android'`, so on an iOS-only fleet the value is
always `'ios'` but the write is live code, not a legacy row. (An earlier note
here credited the 1.37.1 App Store build for it; that was wrong even then, and
retiring the shim on 2026-08-08 changed nothing about this field.)
**`web/`, `windows/`, `linux/` and `macos/` STAY** (owner call, 2026-08-05,
asked and answered when `android/` went). They are untouched `flutter create`
boilerplate for platforms nothing targets or builds — leave them alone; their
presence is not evidence that any of those platforms is supported. In
particular `macos/Podfile` is scaffold, not a CocoaPods setup, and does not
contradict the SPM-only rule in `ios/CLAUDE.md`.

iOS notes live in `ios/CLAUDE.md` (loads when working under `ios/`) — SPM-only
(there is no Podfile and never will be), iOS 18.0 deployment floor, App Attest,
the Crashlytics dSYM run-script phases, and the `homeWidget` deep-link param.
Since P4b a real `app_links` dispatcher exists (`lib/core/deep_links/`), but the
`homeWidget` param and the `home_widget` tap channel are **both still live** and
retire together — the dispatcher skips those URIs rather than replacing them.
**Do NOT re-run `flutterfire configure`** — `lib/firebase_options.dart` already
builds the iOS options from `dev/.env`; re-running it rewrites the file into the
literal-values style and breaks the env-based setup.

## Commands

```bash
flutter analyze   # baseline is `No issues found!` — any lint you see is yours
```

## Required environment

`dev/.env` (gitignored, bundled as asset). 8 keys: `FIREBASE_API_KEY`,
`APP_ID`, `MESSAGING_SENDER_ID`, `PROJECT_ID`, `STORAGE_BUCKET`, plus the iOS
pair `IOS_API_KEY`, `IOS_APP_ID` (read in `lib/firebase_options.dart` to build
the iOS `FirebaseOptions`), plus `IOS_MAPS_API_KEY` (iOS client Google Maps
key, parsed natively by `AppDelegate.swift`). The first five are still required
even though only iOS ships: three of them are platform-neutral, and
`FIREBASE_API_KEY`/`APP_ID` still back `DefaultFirebaseOptions.android`.
`IOS_MAPS_API_KEY` is a RESTRICTED CLIENT key — distinct from the server-side
Secret-Manager `GOOGLE_MAP_API_KEY`, which must never ship in the app.

- **`dev/.env` holds Firebase client config plus RESTRICTED client keys (e.g. `IOS_MAPS_API_KEY`) only.** It's an asset bundled into the IPA, so anything in it ships in the binary — restrict those keys app-side (bundle ID / package + API restrictions) in the Google Cloud Console. Server-side or unrestricted keys (Stripe, OpenAI, admin tokens, `GOOGLE_MAP_API_KEY`) must live in Google Secret Manager and be read from a Cloud Function — never in `dev/.env`.

## Critical invariants

- **Auth:** Every signed-in user needs a Firestore `users` doc with matching
  `uid`, and it must be `active` — with ONE exception. `SplashScreen` signs out
  otherwise. Don't break this. Gate with `!employee.isActive` — `isDisabled`
  only matches `'disabled'`, so it misses `''` and any future status.
  **The exception is `invited` (P4c, 2026-08-02): it routes to
  `AccountSetupScreen` and KEEPS the session**, at both gates
  (`splash_controller.dart`, `sign_in_controller.dart`). The admin created that
  account with a generated starting password and handed it over, and this is the
  person's first
  sign-in — signing them out makes setup unreachable, since the credential they
  just used is the one it needs. The test is `employee.isInvited`, an **exact**
  match checked BEFORE the active gate, so an empty or unknown status still
  gets the old sign-out. Tests pin both halves.
- **Live account-deletion signal (kick-out) needs a populated→empty transition.**
  `isAccountDeletionSignal` (`account_status_provider.dart`) fires the runtime
  sign-out only when the current doc is a *settled* empty following a
  previously-populated one — so pass `previous` (the prior emission) from the
  `ref.listen` in `AccountExitListeners._listenForDeletedAccount`
  (`core/app/account_exit_listeners.dart`), which `main.dart` only registers. A first-seen empty doc is a bootstrap window
  (fresh-sign-in `uid == null` branch, or an invited account signed in before
  `completeEmployeeSetup` activates its doc), NOT a deletion. Never simplify back to
  `doc.isEmpty` alone, or invited employees get wrongly kicked out mid-activation
  (cold-start already-deleted accounts are caught earlier by `SplashScreen`).
- **Employee visibility:** Employees see only appointments where their doc id is
  in `employeeIds`. Apply this filter on any new appointment view.
- **Editing an appointment must preserve assignees not in the active picker.**
  The employee picker never shows a disabled/removed person, so such an assignee
  can't be deselected — saving must re-append original `employeeIds` not in the
  active set, or that staff is silently unassigned (which also changes who can
  see the visit). **What the picker DOES offer has one owner,
  `offerableAssignees` (same file as the merge), and it narrows the ACTIVE list
  rather than unioning onto a pre-filtered one** — active crew, plus anyone
  active who is already on the job but no longer offerable by title (a
  dispatcher assigned before that rule existed, so it can be taken off). It
  keys on the appointment's STORED `employeeIds`, never the live selection —
  keyed on the selection, deselecting that dispatcher removed their own chip on
  the next rebuild, so the toggle was one-way and an accidental tap could only
  be undone by abandoning the edit. The
  distinction is the trap: a union of "assignable + already selected" also
  re-offers a DISABLED assignee, whose chip then deselects and is silently
  put back by the merge below on every save. Narrowing an active-only list
  cannot express that, which is why the rule lives beside the merge it has to
  agree with rather than inside `EmployeePicker`. The merge itself is the pure, tested `mergeRetainedAssignees`
  (`calendar/domain/assignee_resolver.dart`) — route the retain logic through it.
  Resolve the active set through the ONE owner, `_resolveActiveEmployees`
  (`event_details_controller.dart`), which awaits `watchEmployees().first` —
  never a cached provider value, and never a `.value ?? []` read. The await is
  the point: a cold or empty stream value at save time makes every original
  assignee look inactive, so all of them are retained and a real deselection is
  silently undone. (This bullet previously described a two-tier "cached value
  falling back to a fresh read" that the code does not have and should not
  grow — the single awaited read is both simpler and strictly safer.)
  **`employeeIds` and `employeeNames` are paired POSITIONALLY, and the bounds
  check has one owner: `assigneeNameAt(names, i)`** (same file, returns null for
  "no name here"). It was re-spelled at five sites; the differing missing-name
  fallbacks around it are legitimately per-surface (the day route shows the id,
  the history filter shows nothing), so the helper owns only the LOOKUP and each
  caller keeps its own substitute. The edit-sheet copy is the dangerous one — a
  blank name there flows into `mergeRetainedAssignees` and is written back.
- **The picker DIMS whoever can't take the job on the chosen date, and the
  already-assigned test WINS over it.** `assigneeOfferState`
  (`calendar/domain/assignee_resolver.dart`, beside the two rules above because
  all three must agree) returns `free` / `unavailable` / `onTheJob`; only
  `unavailable` dims, and it is dimmed AND untappable, which is precisely why
  someone already on the job must never be. A chip that can't be tapped can't
  be taken off, and — worse — an assignee who is active but merely un-offered
  is NOT retained by `mergeRetainedAssignees`, so they'd be silently
  unassigned. The "on the job" set is the live selection **union the
  appointment's STORED `employeeIds`**: keyed on the selection alone,
  deselecting an unavailable stored assignee dims their own chip on the next
  rebuild and the toggle is one-way. Same trap as `offerableAssignees`.
  **ANY clash dims, not just a day off** (owner call, 2026-08-24), and the
  accepted cost is that deliberate double-booking is no longer reachable from
  the picker — the Save-time prompt stays as a backstop for races but will
  rarely fire. If putting two people on one big job turns out to matter, keep
  BOOKED chips tappable with a warning look and dim only time off.
  **Availability is date-DERIVED, live where it can be, one-shot where it
  can't.** `assigneeAvailabilityProvider` reduces the range the calendar
  ALREADY holds open (`openCalendarRangeProvider`, published by
  `MainCalendarScreen` and admin-only, since that stream constrains
  `startTime` alone and the rules reject a technician's query) and falls back
  to `findClashingAppointments` when the span falls outside it. The fallback is
  not optional: without it a date past the open range makes every clash
  invisible and the picker silently reports everyone as free, which is worse
  than not dimming at all. Forking a listener keyed on a span-derived range is
  what `forWeekBucketOf` and `forMirrors` carry long comments against.
  **An undetermined span answers nothing** — a date with no times could still
  become an 8 pm job, so `watchAssigneeAvailability`
  (`calendar/utils/assignee_availability_scope.dart`) offers everyone until the
  span is real, which covers "no date picked yet" too.
  **A PERSONAL block dims NOBODY, and that carve-out is load-bearing.** Dimming
  means untappable, and the person a day off is FOR is the one most likely to
  have jobs that day — so dimming made their absence unbookable, and made the
  clash alert that exists to clean up afterwards unreachable. It is the same
  carve-out, for the same reason, as both controllers skipping the Save-time
  busy prompt when `isPersonal`; both halves take `isPersonal` and must keep
  agreeing. A clash is never a reason to refuse time off — it is what the
  alert reports after the write.
- **Photo and image-upload rules live in `.claude/rules/images.md`** (moved
  2026-08-19) — magic-byte validation, the single-stage pick/compress pipeline,
  render-from-bytes, the two caches, the `appointments/{id}/images` migration
  and the offline upload queue. Loads when working under `lib/core/images/`,
  `lib/features/calendar/` or the image functions.
- **Offline write guard:** the appointment/client submit controllers
  (`add_event`, `event_details`, `client_form`) fail fast when
  `ref.read(isOfflineProvider)` is true by returning a fabricated
  `SocketException('offline')` **before** the in-flight flag is set; the widget
  maps it to the offline notice via `composeErrorNotice`/`error_cause.dart`
  (which keys on the `SocketException` *type*, so the message string is cosmetic).
  An awaited Firestore write only resolves on server ack, so without this Save
  spins until reconnect. Deliberate asymmetry: entity writes fail fast offline
  while photos retry via the queue above. `persistenceEnabled: true` is pinned in
  `main()` (serves cached reads) — don't remove it.
- **App Check:** `FirebaseAppCheck.instance.activate()` in `main()`. Do not remove.
- **Appointment rules live in `.claude/rules/appointments.md`** (moved
  2026-08-19) — the status allowlist and `displayStatusAt` ladder, mark-complete,
  `showActions`, personal jobs, all-day blocks, the 14-day multi-day span and
  `AppointmentDaySlice`, and the `findBusyEmployees` conflict check. Loads when
  working under `lib/features/calendar/` or `functions/`.
- **Job templates are display-only quick-fill, NEVER stored.** `JobTemplate`
  (`calendar/domain/models/job_template.dart`) backs the one-tap chips on the
  **add** flow only (`onApplyTemplate`, null on edit); picking one just seeds the
  title text and — if a start time is set — the end time from
  `defaultDurationMinutes` (clamped inside the same day). The appointment still
  saves with `status: 'pending'` and whatever the admin edits afterwards; there
  is no template field on the record. Add new types to the enum + a
  `jobTemplateLabel` case + EN/FR ARB keys (mirrors `statusLabel`).
- **No client `runTransaction` on routine/concurrent paths.** The
  cloud_firestore iOS plugin mutates an unsynchronized NSMutableDictionary from
  the transaction queue (`FLTTransactionStreamHandler` → `_transactions`), so
  concurrent client transactions can EXC_BAD_ACCESS (seen fatal in 1.34.1;
  unfixed upstream as of 6.7.0). The FCM + Live Activity token repos therefore
  use plain get-then-set (a double-upsert can only re-stamp `createdAt` —
  cosmetic); don't reintroduce transactions there. The two remaining client
  transactions (employee edit uniqueness re-check, series update) are isolated
  one-at-a-time admin actions — don't add new transaction call sites that can
  run concurrently with them or each other.
- **Secure storage is iOS `first_unlock_this_device`** (`SecureStorageService`):
  the default `unlocked` Keychain class made every read throw -25308 when a
  content-available push cold-started the app on a locked phone — Crashlytics
  noise AND the biometric app-lock silently not engaging that session — and
  `..._this_device` additionally keeps the cached identity out of
  device/iCloud backups (cache self-rebuilds on next sign-in after a restore).
  The service lazily migrates old items (backup-slot then delete-then-rewrite,
  marker `ios_keychain_accessibility_v2`) before any operation — keep
  `_ensureMigrated` first in every public method, and add new keys to
  `SecureStorageKeys.all` or they never migrate. `isKeychainLockedError`
  classifies residual -25308 (pre-first-unlock) as log-only at the three
  flag-read catch sites.
- **The app-lock flag is TRI-STATE, and BOTH lifecycle gates must honour it.**
  `AppLockController` (`app_lock_provider.dart`) holds `false` until a read
  actually settles, so "off" and "we could not find out" are the same value —
  `isResolved` tells them apart and `retryIfUnresolved()` re-reads. That
  distinction is the whole point: reading the bare bool meant ONE transient
  keychain error (the pre-first-unlock -25308 window above) disabled biometrics
  for the entire session with no sign anything was wrong. `AppLock`
  (`core/security/app_lock.dart`) therefore **retries BEFORE deciding on
  resume**, and — the half that was missed first time — **locks on
  background/`inactive` while UNRESOLVED**, since that is the gate the OS grabs
  its app-switcher snapshot behind and "we don't know yet" must not read there
  as "no lock". A defensive lock is released by `_afterRetry` once the retry
  settles: **a persistent read failure still degrades to unlocked**, on purpose
  — someone who never enabled biometrics must never be trapped behind a prompt
  they cannot satisfy — so the win is the switcher window, not a hard
  guarantee. Don't write it up as one, and don't "simplify" either gate back to
  a plain `ref.read(appLockEnabledProvider)`. Pinned by
  `test/core/security/app_lock_test.dart`.
- **Role cache:** Never read `isAdmin`/role from SharedPreferences — always Firestore.
- **Routing:** `AppRoutes.onGenerateRoute` is the single source of truth.
  Pass typed arg classes via `Navigator.pushNamed(..., arguments: ...)`.
- **Firestore query rules vs. get rules:** For list/query operations, security rules are
  evaluated against query *constraints*, not document data. If a rule checks
  `resource.data.status == 'active'`, queries must also `.where('status', isEqualTo: 'active')`
  or Firestore rejects the whole query with `permission-denied`. Direct `doc.get()` calls
  ARE evaluated against actual document data. See `watchEmployees()` for a corrected example.
- **Users collection read rule** has three clauses (see `firestore.rules`):
  admin, `status == 'active'`, or `uid == request.auth.uid` (own doc). New
  queries on `users` must satisfy one clause via their WHERE constraints or
  they'll be rejected. **Three, not four** — a fourth
  `email_verified && status == 'invited' && email == token.email` clause existed
  only because the retired code flow left `uid` empty until redemption, and it
  was deleted 2026-08-08 with the rest of the `#compat-1.37.1` shim. (That was a
  `firestore.rules` READ clause and is unrelated to `completeEmployeeSetup`'s
  `email_verified` callable guard, which was removed separately on 2026-08-21 —
  two different `email_verified` checks, both gone, for different reasons.) P4c mints
  the Auth account up front, so an invited person reads their own doc through
  clause 3; don't re-add an email-matched clause. An ordinary
  employee still cannot see a pending account: clause 2 requires `active`.
- **Employee, account and `users`-doc rules live in `.claude/rules/employees.md`**
  (moved 2026-08-19) — the P4c invite/setup flow, `changeEmployeeEmail`,
  the generated starting password and credential handling, `EmployeeFormActivity`,
  `watchEmployees`, `users.name` composition, `workingDays`, the rules caps, the
  `private/emergency` subcollection, `MyDetailsScreen`, the two-branch
  `allow update` on `/users`, and `travelAlertsEnabled`. Loads when working under
  `lib/features/employees/`, `lib/features/settings/` or the account functions.
- **The dashboard's window is SPLIT: one live listener, one `.get()`.**
  `DashboardAggregator.liveRangeAround` (this ISO week through next Monday /
  the 3-day pending horizon) is watched; `historyRangeAround` (the seven
  settled weeks behind it) is read once through
  `AppointmentsRepository.fetchInRange`. Held as one range it was a **70-day**
  business-wide live listener capped at `_rangeStreamLimit`, so above ~14
  jobs/day the 8-week trends, busiest-weekday and Attention list were computed
  over a silent PREFIX. The two results **must be merged by doc id**
  (`DashboardAggregator.mergeById`, live wins) and never concatenated — each
  query reaches back to its own `fetchStart`, so they overlap by a fortnight.
  Adding a reducer that needs older data means widening the HISTORY half, not
  the live one.
- **Client rules live in `.claude/rules/clients.md`** (moved 2026-08-19) —
  `ClientRecord` legacy back-compat, archive-not-delete, the type filter, the
  Wave sync badge, `jobCount`, the `clients/{id}.name` IS-the-phone rule and
  `ClientNamePolicy`, inline add-client, and the History screen's rail/sections.
  Loads when working under `lib/features/clients/`, `functions/clients.js`,
  `functions/client_*.js` or `functions/wave/`.
- **Calendar UI rendering rules live in `lib/features/calendar/CLAUDE.md`**
  (moved 2026-08-14) — the P2 month grid/pager/collapse rules, the
  `AppointmentCard` contract, and the agenda's closed-job sink. They are pure
  Flutter with no `functions/` twin, so they load only when working under that
  directory. Everything with a server-side mirror stayed here.
- **Navigation rules live in `lib/core/navigation/CLAUDE.md`** (moved
  2026-08-19) — the sealed `AppDestination` family, why `.name` is load-bearing
  for tour storage keys, `navigateToDestination`/`selectAndReveal`, and the
  `_popToShell` caveat.
- **Feature-tour rules live in `lib/features/feature_tour/CLAUDE.md`**
  (moved 2026-08-14) — `TourScope`, the visibility gates, `isTargetRendered`,
  the `ready:` gate for data-dependent tabs, and the widget-test caveat.
  Remember here: an `AppDestination`/`TourForm` member name IS the tour's
  storage key, so renaming one replays or orphans that tour.

## Conventions

- Feature-first: `lib/features/{auth,calendar,clients,employees,settings,splash}/`.
  Promote to `shared/` or `core/` only when reused across features.
- Services are plain classes; no DI container. `AuthService` accepts optional
  injected deps for testability — mirror this pattern.
- Normalize emails through `normalizeEmail()`
  (`core/validators/email_format.dart`) before any Firestore read/write — never
  a hand-spelled `.trim().toLowerCase()`, which had nine copies and a private
  `_norm` twin.
- `initState` must be thin — extract heavy init to `_initStreams()`.
- **Submit/save reentrancy:** in a controller's submit/save, set the in-flight
  flag (`isSubmitting`/`isSaving`) synchronously BEFORE the first `await` —
  including any pre-validation seed-settle await or conflict-check round-trip —
  and reset it on every early-return and `catch`. Awaiting before the flag is
  set leaves the button enabled, so a double-tap starts a concurrent write
  (duplicate appointment / series rewrite); an un-caught pre-check throw with
  the flag already set leaves the button stuck. A detail view that stays mounted
  after its action (master-detail pane — only a delete clears the selection)
  must also reset its busy flag after `onAction` under a `mounted` guard; the
  sheet variant unmounts there, so the guard covers both.
- All Firestore writes via service classes (never direct `FirebaseFirestore.instance` in UI).
  Always set `createdAt`/`updatedAt` server timestamps.
- Entity search matches in Dart (Firestore has no full-text search) — don't
  "fix" it into a server query. Clients/history search read a bounded window
  (`_historySearchScanLimit` 5000 / `_clientScanLimit` 5000) via `clientSearchProvider` /
  `historySearchProvider` (`autoDispose.family` keyed by query) and match across
  all fields in Dart; the loaded-page filter fills the gap until the debounced
  read settles. `ClientSearchPolicy.normalize` (accent-fold) + `digitsOnly`
  (phone) are the matching primitives, and `ClientSearchPolicy.matchesClient` is
  the single client-side fallback matcher — route new client matching through it.
  **A matcher that reads the RAW map to skip building a record must parse list
  fields through `firestoreStringList`** (`core/utils/firestore_parsing.dart`,
  beside `firestoreDateTime`/`firestoreInt`), never a private copy: the history
  filter reads `employeeNames` before there is a record, so a second spelling
  that accepted less would silently reject documents the record itself would
  have matched — a search that quietly stops finding a crew member, with
  nothing logged.
  `FirebaseAppointmentsRepository` keeps a bounded LRU of recent `searchHistory`
  results on the long-lived singleton; every write path clears it via
  `_invalidateSearchCache()`, so a new appointment-write method MUST call it too
  or history search serves stale results (including a just-deleted appointment
  that opens a detail view for a doc that no longer exists).
  **Both scan windows PAGE to their cap and then WARN**, the same posture
  `_mapRangeSnapshot` takes for the range streams. Paging is what stops a
  window truncating at one page; the cap is what stops it walking the whole
  collection, and the two are not alternatives — the 2026-08-19 cleanup
  commits deleted every ceiling and every warn when they added the paging, and
  both were restored the same day at 5000. It matters most on clients: that
  window is `orderBy('name')`, so at the cap it is the alphabetically FIRST N
  clients, and everything past that point goes invisible to search, to the
  type-filter chips and to the Archived chip at once, with no error anywhere.
  It arrives gradually as the roster grows, which is the kind of failure
  nobody reports. Never add a bounded read here without the warn, and never
  replace a ceiling with an unbounded `while (true)` paging loop —
  `fetchClientHistory` (`_clientHistoryScanLimit`, 1000) and
  `fetchClientsCreatedSince` carry the same pair.
  **The loop itself has ONE owner: `pageToCap` (`core/data/paged_scan.dart`),
  2026-08-19** — the four call sites had a hand-written copy each, which is
  four chances to omit the cap or the warn on the next one. The caller still
  supplies its own cap, page size and warn text (each names a different
  user-visible consequence); only the loop is shared. **Page size is NOT the
  display bound** — `fetchClientHistory` used its `limit` (50) as both against
  a 1000 cap, so one client-detail open cost up to 20 sequential round-trips;
  it pages at 500 like the other two windows.
- **Client "Job history" section** (`ClientJobHistorySection`, admin-only client
  detail) reads via `fetchClientHistory` (`clientJobHistoryProvider`, an
  `autoDispose.family` that re-fetches on `onLocalWrite`). It orders
  `startTime` DESC on the **server** — `(clientId ASC, startTime DESC)`, added
  2026-08-13 — and the `orderBy` is what makes the `limit` mean anything. It
  filtered on `clientId` alone before that, on the reasoning that the automatic
  single-field index served it and Dart could sort the page: but with no
  `orderBy` Firestore falls back to `__name__` order, so a client with more
  visits than the cap got an **arbitrary** slice of its history, and sorting
  that slice newest-first afterwards made the wrong page look like the right
  one. (The composite index the old note said this would need already existed —
  `propagateClientEdits` added it.) Consequence to keep in mind: an
  `orderBy('startTime')` makes Firestore exclude a doc that has no `startTime`,
  so `getAppointmentById` is now the only read in that repository that can
  reach a legacy or console-written row missing one — which is what
  `_recordFrom`'s breadcrumb is left for.
  **The SECTION renders at most `_maxRendered` (50) of them**, because it is a
  non-lazy `Column` inside the detail body's own scroll view — there is no
  sliver context to hand a builder, so every row it is given is built eagerly,
  and each is an `AppointmentCard` (an `IntrinsicHeight` subtree). Adding
  paging to the repository silently took that from 50 rows to up to 1000. Keep
  the bound until the surface grows a "show all" affordance or hands off to
  History filtered by client; a taller list means a builder, not a bigger
  number.
- **The team roster's "jobs today" count is ONE listener, not one per row.**
  `employeeJobsTodayProvider` reduces a single `appointmentsInRangeProvider` over
  today's range into a `Map<String,int>`; every row reads the map. The range
  comes from `todayRangeProvider`, which watches `currentDayProvider` — never
  `DateTime.now()`, or the counts stick on yesterday in an app left open across
  midnight. Cancelled visits don't count. **The employee detail's TODAY panel
  filters that SAME stream** (`employeeTodayJobsProvider`) rather than opening a
  per-employee query — the Team tab already holds the day range open, so a
  detail costs no extra read and the panel can't disagree with the count on the
  row that opened it.
- **Every widget-layer offline write guard goes through `guardedOffline`**
  (`core/errors/error_cause.dart`, beside `composeErrorNotice`) — it reads
  `isOfflineProvider`, pushes the standard offline notice and returns true so
  the caller returns. The block was copy-pasted at six sites. It takes no
  `tag`: notices carry no support code (2026-08-04), so a tag now lives only in
  the `logger.warn` label at the same site. **There are exactly TWO carve-outs,
  and this list is meant to be exact** — a stale entry here is what made the
  previous version read as drift. `AccountSetupScreen` surfaces offline through
  its own banner (`_bannerError`) rather than a notice; and
  `WaveSettingsSection._blockedOffline` surfaces
  `WaveNetwork().toLocalizedMessage` instead of `composeErrorNotice`, because
  the typed-`Failure`-branch-first rule gives it a better sentence than the
  generic cause vocabulary can. (This named "the two `accept_invite_*` screens"
  until 2026-08-11, both of which P4c deleted, so the rule pointed at nothing;
  the Wave carve-out was added 2026-08-15 for the same reason — it existed and
  went unnamed.) Controller-layer guards (`add_event`,
  `event_details`, `client_form`) keep returning a typed failure instead.
- **`DateFormat` is memoized per locale** (`calendar/domain/month_grid.dart`:
  `longDateFormatFor`, `weekdayAbbrevFormatFor`, `_symbolsFormat`). Constructing
  one verifies the locale and parses a skeleton into pattern fields, and the
  calendar built a fresh one PER DAY CELL for a semantics label — 30–90 per
  rebuild on every day tap and month swipe. Never call a `DateFormat.*`
  constructor inside a cell/item builder.
- **`TourSteps`** (`feature_tour/domain/tour_steps.dart`) owns a screen's step
  ids, keys and `step()` wrapper. Six screens had a copy of the trio that had to
  stay in sync (`keys[id]!` force-unwraps; `indexOf`/`length` feed "step N of
  M") and Settings had already drifted. One `late final _tour = TourSteps(dest,
  isAdmin:)` per screen — don't re-inline it. **The app bar's `bottom:` slot
  uses `stepBarIf`**, the `PreferredSizeWidget` sibling of `stepIf`: without it
  that one slot escaped the class's ownership and Clients, History and Team each
  re-spelled the same six-line `has(id) ? TourShowcaseBar(...) : bar` block by
  hand.
- **Account exit is SPLIT: `AccountExitListeners` detects, `AccountExitController`
  tears down** (`core/app/`, siblings of `AppSyncListeners`; the controller was
  split out 2026-08-19). The listeners are three `ref.listen` wire-ups
  (disabled / role revoked / doc deleted) and nothing else; every one of them
  calls `AccountExitController.exitAccount`, which owns the teardown, the
  navigation and the guard. Don't put teardown back in a listener — that is
  what made the order and the guard untestable. The ORDER is load-bearing:
  push, presence and Live Activity de-register BEFORE `signOut()`, because each
  needs the credential sign-out revokes. The controller's
  `_isHandlingAccountExit` guard is released by the post-frame callback on
  success and by the `finally` only on failure — three listeners can fire for
  one underlying event.
- Per-keystroke search debounces through `Debouncer` (`lib/core/utils/debouncer.dart`,
  own one per State, `dispose()` it) at the shared `kSearchDebounce` beside it.
  That constant is one cost dial, not a per-surface taste, and it lives in
  `core/` rather than on `ClientSearchPolicy` because its callers span features
  — the appointment sheets debounce a CLIENT search, History an APPOINTMENT
  one. **`Debouncer` is the ONLY one** — `SettingsSaveDebouncer` was deleted
  2026-08-19: making `onError` required (below) turned `Debouncer` into a
  strict superset, and a second wrapper whose `onError` stayed OPTIONAL voids
  exactly the guarantee that change buys. Its interval survives as
  `kSettingsSaveDebounce` beside `settings_providers.dart`, which is a
  different cost dial from `kSearchDebounce`. Don't add a second wrapper or a
  raw `Timer`, and don't re-spell an interval at a call site (it had already
  split 300 ms / 250 ms across four).
  **`Debouncer`'s `onError` is REQUIRED** (2026-08-19). It was optional, and
  five of the six call sites omitted it — the action runs from a `Timer`
  callback, so a throw inside a debounced search had no caller left to catch it
  and the search just returned nothing, with nothing logged and nothing in
  Crashlytics. Requiring it is what makes that omission impossible at a NEW
  call site.
  **Build one through `Debouncer.tagged(duration, logger:, tag:)`, not the raw
  constructor** (2026-08-22). All six sites use it. Requiring `onError` closed
  the omission case; what it could not close is *where the logger is resolved*
  — the handler can fire after dispose, and Riverpod 3 `ref.read` on an
  unmounted consumer throws (see `.claude/rules/error-handling.md`), so the
  logger has to be read where the `Debouncer` is CONSTRUCTED (`initState`),
  never inside the callback and never via a lazy `late final` touching `ref`.
  Prose cannot enforce that; a required `AppLogger` PARAMETER can, because an
  argument is evaluated at the construction site. Five of the six sites carried
  a restatement of this paragraph as a comment, and the sixth — the one that
  deviated — is the one that shipped a FATAL. `tag` is the Crashlytics warn tag.
  **`kAddressLookupDebounce` (700 ms) lives beside `kSearchDebounce`** for the
  one caller that needs a different interval: every address lookup is a BILLED
  Places call behind a per-uid rate limit, where a client search spends a
  Firestore read the app already pays for. Two dials, compared in one place,
  rather than a number re-spelled at a call site.
- Localization (`gen_l10n`):
  - Source of truth: `lib/l10n/app_en.arb` (template) + `lib/l10n/app_fr.arb`.
  - Generated `app_localizations*.dart` live in `lib/l10n/.gen/` and are
    **gitignored**. Regenerate with `flutter gen-l10n`; never hand-edit them.
  - Single canonical import: `package:scheduling/l10n/l10n.dart` (re-exports
    `AppLocalizations` + the `context.l10n` extension). Don't import
    `app_localizations.dart` directly.
  - `context.l10n` is non-nullable (`nullable-getter: false`) — no `!`.
  - `MaterialApp` uses `AppLocalizations.localizationsDelegates` and
    `AppLocalizations.supportedLocales`; don't hand-build the delegates list.
  - Every key MUST carry a `@key` metadata block (description + typed
    placeholders). Enforced by `required-resource-attributes: true` in
    `l10n.yaml` — `flutter gen-l10n` fails on a bare key.
  - Key naming: `feature_keyName`. Prefix buckets: `auth_`, `calendar_`,
    `clients_`, `employees_`, `settings_`, `maps_`, `status_`,
    `validation_`, `error_`, `common_`, `nav_`, `app_`.
  - Adding a key: update both ARBs in lockstep, add the `@key` block in EN,
    run `flutter gen-l10n`. EN/FR drift surfaces in
    `lib/l10n/.gen/untranslated.json`.
- Cast callable responses loosely: `(value as Map?)?.cast<String, dynamic>()`,
  never `as Map<String, dynamic>?`. This started as an Android-only `TypeError`
  (that plugin returned nested objects as `Map<dynamic, dynamic>`), so it can no
  longer bite now that Android is gone — but it stays the convention: it is the
  same cost, and it doesn't depend on a plugin's choice of map type.
- `whereArrayContainsAny` has a hard limit of 30 items. When querying by a
  list of IDs (e.g. employee IDs), chunk into batches of 30 and merge results
  in Dart. See `findBusyEmployees` in `firebase_appointments_repository.dart`
  for the reference implementation.

## Cloud Functions

Functions live in `functions/` (project `schedulingapp-88727`, region
`us-central1`), split into domain modules re-exported by a thin `index.js`.
The module map and the per-function notes are in `functions/CLAUDE.md`, which
loads when working under `functions/`. Three subject areas were split out of
it on 2026-08-19 because each spans more than that one directory:
`.claude/rules/notifications.md` (push, presence, widget, Live Activities,
Siri — JS + Dart + Swift), `.claude/rules/wave.md` (`functions/wave/**` plus
the Settings UI) and `.claude/rules/firestore-indexes.md` (TTL policies and
index exemptions — scoped to `firestore.indexes.json`, which
`functions/CLAUDE.md` never covered). Per-function reference:
`docs/CLOUD_FUNCTIONS.md`.

**A module that resolves a Storage bucket at load can't be tested, so
its decisions live in a pure `*_policy.js` sibling.** `maintenance.js` throws on
`require()` outside the emulator, but NOT from an admin `getStorage()` handle —
both of its calls resolve lazily inside the function bodies. The throw is
`onObjectFinalized`'s own bucket-name resolution at **trigger registration**
("Missing bucket name", `firebase-functions/lib/v2/providers/storage.js`), which
happens the moment the module is evaluated. Same conclusion, so don't go looking
for a load-time `getStorage()` that isn't there — and don't "fix" it by making
the handles lazier, because they already are. That untestability is why the only
unattended, irreversible deletion in the repo
(`purgeExpiredHistory`) had ZERO tests until 2026-08-04. Its orchestration now
lives in `maintenance_policy.js`, taking `db`/`deleteImages`/`now` injected,
the same split `notification_policy.js` ↔ `notification_utils.js` already uses.
Three rules there destroy data if they regress and are each pinned: the status
gate (only `done`/`cancelled` are ever purged — live work must survive at any
age), the ordering (images FIRST; a doc whose image cleanup failed is kept, or
the Storage bytes orphan with nothing pointing at them), and loop termination
(a full page that made no progress must end the loop, not respin it to the
1800 s timeout). Put a new unattended-deletion decision there, never in the
trigger module.

**Release deploy runbook: `docs/DEPLOYMENT.md`** — ordering (backend BEFORE the
app build, because `assertPayloadShape` rejects unknown keys), the
old-build-compatibility check, rollback, and the deploy log recording what
production actually runs. Read it before any deploy that touches a callable
payload or a rules cap.

Deploy: `firebase deploy --only functions,firestore:rules,firestore:indexes,storage`
(clear `AI_AGENT`/`CLAUDECODE`/`CLAUDE_CODE` in the shell first, or the CLI
stamps `agent-name/claude_code` into the audit log — see `docs/DEPLOYMENT.md` §5.)
(`storage:rules` is **not** a valid deploy target — use `storage`.)
**Never pass `--force`** — it deletes any prod Firestore TTL policy missing from
`firestore.indexes.json` (this removed all 5 live policies once, 2026-07-21).
Always run `cd functions && npm run lint` before deploying.

`GOOGLE_MAP_API_KEY` lives in Secret Manager only — it is **not** in `dev/.env`.

## Testing

- Catch overflow by pumping at a small-phone size with 2× text: set
  `tester.view.physicalSize` (260 logical px wide is the usual worst case) and
  wrap in a `MediaQuery` with `textScaler: TextScaler.linear(2)`. Each test file
  owns a local `_harness` helper for this — **there is no shared
  `_scaledHarness`**, despite what older plan docs call the pattern.
- Harness requirements, mocking rules and device-only caveats: the **Test
  Strategy** section of `docs/ARCHITECTURE.md`, mirrored by
  `.claude/rules/testing.md` — keep the two in step. **`.claude/` is COMMITTED
  as of 2026-08-14** (private repo, worked from both a Windows box and the Mac),
  so the rules, skills, agents, commands and hooks now reach every clone;
  before that date `.claude/` was gitignored and `docs/ARCHITECTURE.md` was the
  only copy anyone else could read. Only `.claude/settings.local.json` stays
  ignored, because it is machine-local. `code-quality.md`, `error-handling.md` and
  `security.md` are `alwaysApply: true`; the other nine
  (`testing.md`, `frontend.md`, and the 2026-08-19 additions
  `appointments.md`, `clients.md`, `employees.md`, `images.md`,
  `notifications.md`, `wave.md`, `firestore-indexes.md`) are `paths:`-scoped,
  so they load only when Claude touches a matching file. That scoping is verified working — a
  `paths:` rule is absent from context until its paths are touched — and it
  is what took this file from ~155k chars to ~31k.
