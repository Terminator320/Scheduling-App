# Codebase Audit — 2026-06-24

Scope: whole repo — `lib/` (195 Dart files), `functions/` (Node.js Cloud
Functions incl. `wave/*`), `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`. Baseline: working tree on branch
`wave-integration` (clean before this audit's edits).

## Summary
- Scanned: 195 Dart files + 15 functions JS files + rules.
- Auto-fixed (safe, in the diff): **4** — removed 4 confirmed-dead Riverpod
  providers and their now-unused imports (zero consumers, verified by two
  independent full-repo greps).
- Reported for your decision: **29** (⚠️ 1 pre-ship · 🔴 2 security · 🟠 6 bugs ·
  🔵 17 improvements · 🟡 4 quality groups + l10n/dep notes)
- Verification: `flutter analyze` **clean** (no new errors/warnings vs. baseline)
  · `flutter test` **535/535 pass** · `functions` lint **pass**.

**Top 3 to look at first**
1. **B1** — editing any appointment silently drops a since-disabled assignee from
   `employeeIds`, losing the assignment *and* altering employee visibility.
2. **⚠️ Pre-ship / S2** — App Check is `enforceAppCheck: false` on 5 callables;
   must flip to `true` before production.
3. **B2** — onboarding gate hangs forever (frozen launch) if secure-storage
   `read` throws — no try/catch, no recovery path.

---

## Auto-applied cleanups (review the diff)
All four are top-level Riverpod `Provider` declarations with **zero** `ref.watch/
read` consumers anywhere in `lib/` or `test/`. Unused lazy providers never
instantiate, so removal is behavior-preserving; verified green afterward.

| File:line | Change | Why |
|---|---|---|
| `lib/features/calendar/application/appointments_providers.dart:29` | Removed `appointmentByIdProvider` | 0 consumers; repo method `getAppointmentById` still used directly, unaffected |
| `lib/core/providers/firebase_providers.dart:15` | Removed `firebaseStorageProvider` + `firebase_storage` import | 0 consumers; image path uses `imageStorageProvider` |
| `lib/core/providers/firebase_providers.dart:19` | Removed `firebaseAppCheckProvider` + `firebase_app_check` import | 0 consumers; App Check activation in `main()` is separate and untouched |
| `lib/features/settings/application/settings_providers.dart:8` | Removed `settingsRepositoryProvider` + 3 now-unused imports | 0 consumers; `main.dart` instantiates `SharedPrefsSettingsRepository` directly. `SettingsSaveDebouncer` kept |

> Full detail is in `git diff`. Nothing below this line was auto-changed.

---

## ⚠️ Pre-ship checklist (act before release)
- [ ] `functions/index.js:604, 713, 944, 1051, 1073` — **App Check is disabled
  (`enforceAppCheck: false`)** on `deleteAccount`, `resolveMyInvite`,
  `waveBootstrap`, `waveGetConnection`, `waveImportCustomers`. Each is marked
  `TODO(pre-ship)` to restore once Play Integrity mints tokens for store builds.
  Flip all five back to `true` before production (needs a functions deploy). This
  is the single highest-priority pre-ship item. (No live *destructive*
  `TODO(pre-ship)` scaffolding was found — the prior testing-only delete is gone.)

---

## 🔴 Security findings (review required)
The codebase is in strong security shape — rules are deny-by-default,
role/`isAdmin` is always read from Firestore, all callables enforce App Check (in
prod) + payload-shape + admin + durable rate-limit guards, secrets live in Secret
Manager, callable responses use the safe loose-cast, and image uploads are
magic-byte validated server-side. Only two items, both low/medium hygiene:

### S1 — Crash-dump artifact committed to git  · low · high
- **Where:** `functions/bash.exe.stackdump`
- **Risk:** A 1.2 KB msys/bash crash trace is tracked and would deploy with the
  functions bundle. Inspected fully — only frame addresses + loaded-DLL list, **no
  secrets/tokens/PII**. Real risk is negligible; the concern is hygiene and the
  precedent (a future dump from another process could capture memory). Not
  gitignored, so it will recur.
- **Fix:** `git rm functions/bash.exe.stackdump`; add `*.stackdump` (and the
  untracked local `functions/ruvector.db`) to `.gitignore`. Redeploy functions so
  it isn't bundled. No rules deploy needed.

### S2 — App Check disabled on five callables  · medium · high
- **Where:** `functions/index.js:604, 713, 944, 1051, 1073`
- **Risk:** With App Check off, these callables accept requests that don't prove
  they come from the genuine app binary — widening the surface for scripted abuse
  of invite/delete flows (still bounded by the 5/15-min durable limiter) and
  admin-token replay against the Wave admin callables (still gated by
  `assertAdmin`). A deliberate, documented deferral, not an oversight.
- **Fix:** Restore `enforceAppCheck: true` on all five before release (functions
  deploy). Tracked in the Pre-ship checklist above.

---

## 🟠 Bug findings (review required)

### B1 — Disabled assigned employees silently dropped on appointment edit  · medium · high
- **Where:** `lib/features/calendar/application/event_details_controller.dart:106-123`
  (`_seedSelectedEmployees`) × `lib/features/employees/data/firebase_employees_repository.dart:32-42`
  (`watchEmployees`)
- **Problem:** `_seedSelectedEmployees` resolves the appointment's `employeeIds`
  against `watchEmployees()`, which filters `status == 'active'`. If an assignee
  was later disabled, they're absent from the resolved list, so
  `state.selectedEmployees` excludes them. `save()` rebuilds
  `employeeIds`/`employeeNames` purely from `selectedEmployees`, so the disabled
  employee is silently unassigned — losing the assignment and changing who can see
  the visit (the employee-visibility invariant keys on `employeeIds`). An admin
  editing only the title would unknowingly unassign staff.
- **Fix:** Seed already-assigned ids from an all-statuses source (e.g.
  `getEmployeeById` per id, or `watchAllUsers()`/`watchAssignableUsers`), or merge
  any saved `employeeIds` not found in the active list back into the record so
  existing assignments survive even when an assignee is disabled.

### B2 — Onboarding gate hangs forever if secure-storage read throws  · medium · high
- **Where:** `lib/features/onboarding/screens/onboarding_gate.dart:27-32` (`_load`)
- **Problem:** `_load()` awaits `readFlag(onboardingSeen)` with no try/catch.
  `FlutterSecureStorage.read` can throw `PlatformException` on Android (keystore/
  cipher failures after OS upgrade or backup-restore). On throw, `_seen` stays
  `null` forever and `build()` returns the bare brand-color `ColoredBox` — the app
  appears frozen on launch (matches the prior "splash hang" class of bug). The
  exception also escapes as an unhandled async error.
- **Fix:** Wrap the read in try/catch; on failure log via `logger.warn` and
  default to a safe value (treat as not-seen → show onboarding), then
  `if (mounted) setState(...)`.

### B3 — `ClientEditForm` Save has no in-flight guard (double-submit)  · low · high
- **Where:** `lib/features/clients/widgets/views/client_edit_form.dart:130-205`
  (`_save`) and `:340-346` (Save button)
- **Problem:** Unlike `AddClientSheet` (`_isSaving`) and the appointment
  controllers (`isSaving`), the edit form's `FilledButton` is always
  `onPressed: onSave`. A double-tap fires `updateClient` twice, bumps
  `clientsRefreshProvider` twice, runs `updateLinkedPhoneContact` twice, and
  invokes `onSaved` twice. Idempotent data-wise, but duplicate writes + callbacks.
- **Fix:** Add a `bool _isSaving` mirroring `AddClientSheet`; gate `_save` and
  disable the button while saving; reset in `finally`. (See also I8.)

### B4 — `displayStatus` labels stale past visits `in_progress` indefinitely  · low · med
- **Where:** `lib/features/calendar/domain/models/appointment_record.dart:74-79`
- **Problem:** `displayStatus` returns `'in_progress'` whenever `now.isAfter(startTime)`
  for any non-terminal status, with no `endTime` upper bound. A `pending`/`confirmed`
  visit whose start merely passed (incl. months-old ones never marked done) renders
  "In progress" forever.
- **Fix:** If only the live window should show in-progress, clamp with
  `&& DateTime.now().isBefore(endTime)`; otherwise document the intent. Confirm
  desired product behavior.

### B5 — Comprehensive client search excludes legacy docs missing `createdAt`  · low · med
- **Where:** `lib/features/clients/data/firebase_clients_repository.dart:95-98`
  (`searchClients`)
- **Problem:** The server-backed search orders by `createdAt`, and Firestore
  excludes any doc lacking the orderBy field. Legacy pre-Wave business-only client
  docs may lack `createdAt` — they'll be invisible to comprehensive search (the
  loaded-page local filter only covers them if already paged in). `fetchClientsPage`
  orders by `name`, so the two paths disagree on which docs are reachable.
- **Fix:** Ensure the `createdAt` backfill/import has run in production before
  relying on search, or order the search by `name` (consistent with the page read)
  so docs missing `createdAt` aren't dropped. Treat as a deploy-ordering dependency.

### B6 — `AppLock` start-up storage read is unguarded (fails open, unhandled rejection)  · low · med
- **Where:** `lib/core/security/app_lock.dart:39-46` (`_lockOnStartIfEnabled`)
- **Problem:** `readFlag(biometricEnabled)` is awaited with no try/catch. If secure
  storage throws (same class as B2), the app-lock silently fails open (no lock) and
  the exception becomes an unhandled async error → Crashlytics fatal. For a security
  feature, failing open without logging is undesirable. (`_authenticate` itself is
  safe — it fails closed.)
- **Fix:** try/catch the read; on error log and choose the posture explicitly
  (recommend keeping the lock engaged when the flag can't be read).

**Notes (below the bar, for awareness):**
- **N1** — `add_event_controller.dart:233,285` / `event_details_controller.dart`
  reset `isSubmitting/isSaving` only on error paths; success relies on the sheet
  being torn down. Fine today, but if a success path ever leaves the sheet mounted
  the button stays spinning.
- **N2** — `findBusyEmployees` (`firebase_appointments_repository.dart:286-318`)
  uses two range filters + `arrayContainsAny`; valid (matching composite index
  exists). Not a bug — noted because it superficially resembles the old
  single-inequality restriction.

---

## 🔵 Areas to improve (review required)
Proactive improvement opportunities — report-only, since each reshapes code or
adds tests. Ordered by payoff.

### Performance

#### P1 — History search re-reads up to 1000 docs with no result cache  · medium · high
- **Where:** `lib/features/calendar/data/firebase_appointments_repository.dart:222-262`
  (`searchHistory`) via `appointments_providers.dart` (`historySearchProvider`,
  `autoDispose.family`)
- **Opportunity:** `searchClients` has a 50-entry LRU so repeat terms are free;
  `searchHistory` has none and reads `limit(1000)` every call. Because the provider
  is `autoDispose`, re-searching the same term after the view unmounts re-reads ~1000
  docs — the largest avoidable Firestore read on a user-facing path.
- **Suggested improvement:** Mirror the clients pattern — add a small LRU
  `Map<String, List<AppointmentRecord>>` (keyed by `ClientSearchPolicy.cacheKey`)
  in the long-lived repo (survives the provider's autoDispose).

#### P2 — Clients & History rebuild the whole nav shell on every keystroke  · medium · high
- **Where:** `lib/features/clients/screens/clients_screen.dart:108-133`;
  `lib/features/clients/screens/history_screen.dart:62-70`
- **Opportunity:** `ListenableBuilder(listenable: _searchController, ...)` wraps the
  entire `AdaptiveShell` (NavigationRail + destinations) and `MasterDetailScaffold`.
  Every character rebuilds the rail + chrome, not just the list. Pure rebuild waste
  in split/landscape (the actual search is debounced downstream).
- **Suggested improvement:** Lift `AdaptiveShell` out of the `ListenableBuilder`;
  rebuild only the master pane / list view on controller change.

#### P3 — History filter options recomputed every paged-list rebuild  · low-medium · high
- **Where:** `lib/features/clients/widgets/views/appointment_history_view.dart:246-252`
- **Opportunity:** `_yearsOf(loaded)` and `_employeesOf(loaded)` run inside the
  `PagingListener` builder — O(n·m) iteration + map/list allocation + sort on every
  rebuild (scroll, filter chip, search setState, parent rebuild from P2), even when
  `loaded` is unchanged.
- **Suggested improvement:** Memoize against `loaded` identity (the `!identical(...)`
  pattern already used for `_dayIndex` in `main_calendar_screen.dart:235-238`).

#### P4 — Read-only photo carousel decodes full-resolution images  · low-medium · med
- **Where:** `lib/features/calendar/widgets/views/appointment_image_carousel.dart:46-53`
  via `image_viewer.dart:135` (`buildImageProviders`)
- **Opportunity:** The carousel constrains `ResizeImage` height only with
  `BoxFit.cover` at `width: infinity`, so a 200px strip can decode a ~1600px-wide
  bitmap into the image cache. The edit thumbnail strip caps both dimensions; the
  carousel doesn't.
- **Suggested improvement:** Set `cacheWidth` (or both disk-cache caps) to match the
  strip's device-pixel width — bounded memory win on detail views, low risk.

#### P5 — `_seedSelectedEmployees` opens a throwaway snapshot listener as fallback  · low · med
- **Where:** `lib/features/calendar/application/event_details_controller.dart:106-123`
- **Opportunity:** On a cache miss it falls back to
  `watchEmployees().first`, spinning up a fresh `.snapshots()` listener for a single
  read on every detail open that races the auth token. `.first` cancels it, so it's
  bounded, but it's an extra round-trip + listener setup.
- **Suggested improvement:** Prefer `getEmployeeById` per id, or a one-shot `.get()`,
  over a `.snapshots()` listener for a single value. (Also resolves the B1 seeding.)

### Structure, complexity & maintainability

#### I1 — `functions/index.js` is a 1198-line god file  · high · high
- **Where:** `functions/index.js` (1198 lines, 25+ exports)
- **Opportunity:** Holds unrelated concerns — usersByUid bridge trigger, Places
  proxies, image validation, account deletion, invite resolution, history purge,
  legacy-name backfill, the whole Wave orchestration layer, AND the security
  primitives (`enforceRateLimit`, `assertPayloadShape`, `requireString`,
  `readSessionToken`, `enforceDurableRateLimit`, `assertAdmin`). Wave logic was
  already extracted into `wave/*`; `index.js` never got the same treatment.
- **Suggested improvement:** Extract domain-cohesive sibling modules mirroring
  `wave/`: `functions/security/` (the 6 guards), `functions/places.js`,
  `functions/account.js`, `functions/maintenance.js`. Keep `index.js` as the thin
  wiring/export surface. Group by domain — don't over-split.

#### I2 — Several `build()`/builder methods far exceed the 60-line rule  · high · high
- **Where:** `settings_screen.dart:107` `_buildMaster()` ~133 ·
  `photo_picker_section.dart:57` `build()` ~189 (worst build) ·
  `employee_details_view.dart:121` ~145 · `details_view_body.dart:38` ~146 ·
  `appointment_form_fields.dart:154` ~146 · `client_edit_form.dart:208` ~119 ·
  `add_client_sheet.dart:150` ~115 · `settings_drawer.dart:82` `_buildHeader()` ~99 ·
  `settings_tiles.dart:248` ~96
- **Opportunity:** `.claude/rules/code-quality.md` caps `build()` at ~60 lines;
  these bury layout, branches, and inline styling together.
- **Suggested improvement:** Extract named sub-widgets in call order. Highest
  payoff: split `settings_screen` `_buildMaster` into section widgets and
  `photo_picker_section` into its gallery/empty-edit/empty-readonly states. Don't
  extract single-use one-liners.

#### I3 — Two controller methods carry the whole save/submit pipeline inline  · medium · high
- **Where:** `event_details_controller.dart:307` `save()` ~182 lines;
  `add_event_controller.dart:186` `submit()` ~106 lines
- **Opportunity:** `save()` interleaves validation, record assembly, three series
  strategies (rewrite / apply-to-all / single), image cleanup, and background upload.
  Genuine complexity (not premature abstraction).
- **Suggested improvement:** Extract the two non-trivial series branches into private
  helpers (`_rewriteSeries`, `_propagateToSeries`) returning the counts, leaving
  `save()` as validate → assemble → dispatch → cleanup.

#### I10 — `main_calendar_screen.dart` `build()` is ~205 lines with embedded listeners  · medium · high
- **Where:** `lib/features/calendar/screens/main_calendar_screen.dart:163-368`
- **Opportunity:** Defines `onAsyncChange`/`upgradeIfAdmin` closures inline, branches
  `ref.listen`/`ref.watch` on `isAdmin`, and builds app-bar bottom + FAB + drawer +
  today-FAB stack in one method. The role-upgrade `ref.listen` + immediate `ref.read`
  (lines 220-224) was the subject of a prior login-crash bug — burying it in a
  200-line build invites regressions.
- **Suggested improvement:** Extract the app-bar `bottom` into a small widget and lift
  `onAsyncChange`/`upgradeIfAdmin` to private methods so the admin-upgrade logic is
  visibly separate from layout.

### Duplication

#### I4 — Date/time picker callbacks duplicated across the two appointment forms  · medium · high
- **Where:** `add_appointment_sheet.dart:71-108` vs `details_edit_body.dart:125-167`
  (`_pickDate`/`_pickStartTime`/`_pickEndTime`)
- **Opportunity:** Near-identical picker implementations; the `firstDate`/`lastDate`
  bounds (`DateTime(2020)`/`DateTime(2100)`) are duplicated verbatim.
- **Suggested improvement:** Extract the bounds as named constants at minimum. The
  callbacks differ enough (add has auto-end-time, edit threads `context`) that full
  extraction risks over-coupling — only add a shared `pickAppointmentDate` helper if
  a third call site appears.

#### I5 — Double-submit guard implemented inconsistently across forms  · medium · high
- **Where:** guarded — `add_client_sheet.dart`, `employee_form_sheet.dart`, the two
  appointment controllers; **unguarded** — `client_edit_form.dart` (see B3/I8)
- **Opportunity:** Same concern solved four ways (local flag vs controller flag) and
  missing in one place — unclear which is canonical.
- **Suggested improvement:** Mostly acceptable variation (local flag for simple
  sheets, controller flag for controller-backed forms). The actionable part is closing
  the one gap (I8), not unifying all four — a single helper here would be premature
  abstraction.

#### I11 — Repeated full-width-button `Size` + scattered magic sizing  · low · high
- **Where:** `employee_details_view.dart:217,240,258` (`Size(double.infinity, 48)` ×3),
  `client_edit_form.dart:342,351` / `add_client_sheet.dart:285` (`...,46`),
  `settings_drawer.dart:132,156,170` (hardcoded `fontSize:`), `photo_picker_section.dart`
  (font sizes `9/10/11/13/24`), `auth_form_widgets.dart:122,128` (`44×44`)
- **Opportunity:** The repeated `Size(double.infinity, 46/48)` is the most duplicated
  (~6 copies); hardcoded `fontSize:` bypasses `textTheme`.
- **Suggested improvement:** Add a `fullWidthButton` min-size constant (or reuse
  `button_styles.dart`); route hardcoded font sizes through `textTheme`. Leave the
  sanctioned sub-4px nudges and 1px calendar gutter raw.

### Test-coverage gaps

#### I6 — `functions/index.js` security layer has zero direct tests  · high · high
- **Where:** `functions/index.js` (only `functions/wave/__tests__/*` exist)
- **Opportunity:** The highest-risk primitives are untested — `enforceDurableRateLimit`
  (the 5/15-min limiter on `deleteAccount`/`resolveMyInvite`), `assertPayloadShape`/
  `requireString`/`readSessionToken` (payload sanitizers), `assertAdmin`, and the
  `syncUsersByUid` bridge (role-resolution invariant).
- **Suggested improvement:** Add `functions/__tests__/security.test.js` (or per-module
  after I1) covering the pure validators (`hasControlChar`, size/key rejection, trim/
  length cap) and the rate-limiter window with a faked clock/Firestore. Start with the
  pure-ish, high-value bits.

#### I7 — Appointment repository series/batch logic only tested indirectly  · medium · high
- **Where:** `firebase_appointments_repository.dart` — `rewriteSeries:57`,
  `updateAppointments:90`, `deleteAppointments:155`, `findBusyEmployees:286` (repo
  tests cover only search + status)
- **Opportunity:** `findBusyEmployees` implements the `whereArrayContainsAny` 30-item
  chunk-and-merge that CLAUDE.md calls the reference implementation — but the >30
  boundary has no direct test. Atomic batch methods are exercised only through mocked
  controller tests.
- **Suggested improvement:** Add repo-level tests (fake/mock Firestore) asserting: 31+
  IDs → 2 queries + dedupe; `rewriteSeries` writes update+copies+deletes in one batch.
  Behavior-level, per `.claude/rules/testing.md`.

#### I8 — `client_edit_form.dart` lacks a double-submit guard (robustness + coverage)  · medium · high
- **Where:** `client_edit_form.dart:130` `_save()` + `:340` `_EditActions`
- **Opportunity:** Same as B3 — no `_isSaving`, button stays enabled during the
  `await`s; a double-tap fires two concurrent writes. No single-submission test (the
  add-client sheet has one).
- **Suggested improvement:** Add `_isSaving` + early-return + disabled button +
  `finally` reset; add a widget test asserting a second tap during save is a no-op.

#### I9 — Untested pure transformation modules  · low · med
- **Where:** `lib/core/security/payload_guard.dart`, `wave_error_mapper.dart`,
  `maps_error_mapper.dart`, `contact_link_store.dart`, `photo_upload_notifier.dart`
- **Opportunity:** Error mappers + `payload_guard` are pure logic (plain `test()`,
  no Firebase) but untested, while `auth_error_mapper`/`maps_failure` are tested.
- **Suggested improvement:** Add plain `test()` files for the pure mappers +
  `payload_guard`. Skip the thin wiring providers. Proportionate quick wins.

### Robustness

#### I12 — One intentional empty catch (no action)  · low · high
- **Where:** `lib/features/auth/services/auth_service.dart:146` `_signOutQuietly`
  `catch (_) {}`
- **Opportunity:** The only truly empty catch in `lib/` — a deliberate best-effort
  sign-out. All other catch sites log via `loggerProvider.warn`.
- **Suggested improvement:** None required; a one-line `// best-effort` comment would
  satisfy `error-handling.md`'s "never swallow silently," but it's optional.

---

## 🟡 Code-quality suggestions (optional)
Convention drift — report-only because the fix reshapes call sites; best done as a
focused, reviewed pass, not silently.

- **Hardcoded spacing** (~77 sites) instead of `AppSpacing` — e.g.
  `address_autocomplete_field.dart:190,205`, `client_search_field.dart:55,76`,
  `additional_contacts_section.dart:55,138`, `photo_picker_section.dart:79,114,145,182`.
  `8→sp8`, `12→sp12`, `16→sp16`; `14` is off-scale (decide). Many files already mix
  tokens and raw values.
- **Hardcoded `BorderRadius.circular(n)`** instead of `AppRadius` — e.g.
  `animated_loading_button.dart:30`, `photo_picker_section.dart:83,118,157,180,185,209,260`,
  `additional_contacts_section.dart:58,141`, `client_search_field.dart:82`. `8/12/16`
  map cleanly; `6/10/14` are off-scale (design decision).
- **Hand-rolled shadow** at `settings_tiles.dart:211-220`
  (`BoxShadow(color: Color(0x1A000000)...)`) — replace with `AppShadow.card` if the
  elevation matches; a raw ARGB shadow also won't adapt across themes.
- **Dependency tidy-up** (`pubspec.yaml`, report-only — needs `pub get`+analyze+test):
  `flutter_lints` (line 90) is redundant — the lint baseline is
  `very_good_analysis` (`analysis_options.yaml:6`), nothing includes flutter_lints;
  `device_preview` (line 103) is parked/unwired (the pubspec comment says so). Both
  are genuinely removable. `http`/`path`/`path_provider` have no direct imports but
  are transitive needs — removing as *direct* deps is cosmetic only.

### Audited clean (no action — confirming, not whispering)
- `throw Exception(...)`: **zero** occurrences. All throws are typed `Failure`s or
  legit `ArgumentError`/`StateError`.
- `ScaffoldMessenger.showSnackBar`: exactly the 3 sanctioned sites
  (`main.dart:179`, `address_map_launcher.dart:89`, `main_calendar_screen.dart:85`),
  all via `errorSnackBar(...)`.
- `FirebaseFirestore.instance`: only the provider + emulator setup + a service ctor
  default — none in UI/widgets.
- `initState` heavy work: none — all screens extract to `_initStreams()` /
  `_initControllers()` / post-frame callbacks.
- `Colors.white/black`, `Color(0xFF...)` swatches, the single `isDark`
  (`settings_screen.dart`) are the documented sanctioned sites.
- `mounted`/`context.mounted` after `await`: present and correct everywhere inspected.
- No dead files (every `import`/`export` indexed; only `main.dart` is uninbound, as
  expected). `waveListBusinesses` (flagged stale in CLAUDE.md) is already gone.
- Callable response casting uses the safe `(value as Map?)?.cast<...>()` everywhere.

---

## Notes / uncertainties
- **Orphaned-looking l10n keys (flagged for a separate l10n pass — NOT deleted):**
  351 keys total; **16** have zero `context.l10n.<key>` consumers in `lib/`/`test/`.
  l10n keys resolve through generated getters and some `error_*` strings are
  deliberately kept as reserve per the "reuse before adding" convention, so these are
  candidates only. Lines in `lib/l10n/app_en.arb`: 151 `calendar_today`,
  297 `error_couldNotDeleteClientTryAgain`, 301 `error_couldNotSaveChangesTryAgain`,
  305 `error_couldNotAddClientTryAgain`,
  513 `error_somethingWentWrongCreatingTheAppointment`,
  517 `error_somethingWentWrongSavingChanges`, 545 `calendar_noNumber`,
  553 `calendar_noNotes`, 557 `calendar_noMaterials`,
  653 `calendar_selectAnAppointmentToViewDetails`, 729 `error_couldNotCreateEmployee`,
  877 `error_couldNotLoadAppointments`, 989 `common_searchAddress`,
  993 `common_typeToSearchAnAddress`, 997 `common_street`,
  1331 `error_couldNotDeleteAccount`. Run a deliberate prune (both ARBs in lockstep +
  `flutter gen-l10n`) — do not strip in a code sweep.
- Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/.gen/**`,
  `firebase_options.dart`, `build/`, `functions/node_modules`) were excluded throughout.
- The unused-dependency heuristic's other hits (`firebase_core_platform_interface`,
  `firebase_performance`, `riverpod_annotation`, `json_annotation`, `build_runner`,
  `freezed`, `json_serializable`, `riverpod_generator`, `flutter_launcher_icons`) are
  expected false positives (transitive / codegen / native-auto-init) — left alone.
