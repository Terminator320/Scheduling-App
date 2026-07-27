# Codebase Audit — 2026-07-26

> **Implementation status (same session, uncommitted on `notification`).**
> ALL reported findings implemented ("do all of them"). B1 (22 `max-len` lint
> errors wrapped — functions lint now green), I1 (5 settings cards extracted to
> their own `ConsumerWidget`s), I2 (`notification_utils.js` → new
> `notification_messages.js`, 1122→893 lines), I3 (2 new test files, +22 tests:
> keychain `_migrate` + presence throttle math), I4 (`ref.onDispose` on the 3
> sync controllers), I5 (`settings_tiles.dart` split into 4 cohesive files +
> barrel), and both 🟡 quality nits (dashboard_hero token dedup; the
> employee_color_grid ring was left — intentional). Plus the 3 safe auto-fixes.
> Verification: `flutter analyze` clean · `flutter test` **1055/1055** ·
> functions `npm run lint` green · functions `npm test` **664/664** · no BOM on
> any new file. No pre-ship items existed this run.

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`). Baseline: working tree on branch
`notification` (clean at start; last commit `912f972`).

## Summary
- Scanned: ~282 Dart files (`lib/`) + ~59 JS files (`functions/`) + rules/indexes.
- Auto-fixed (safe, in the diff): **3** — 1 unused import removed, 2 unused
  `show` names trimmed from imports.
- Reported for your decision: **8**  (⚠️ 0 pre-ship · 🔴 0 security · 🟠 1 bug/blocker · 🔵 5 improvements · 🟡 2 quality)
- Verification: `flutter analyze` **clean** (no errors/warnings vs. baseline) ·
  presence + live_activity tests **87/87 pass** · Functions lint **FAILS**
  (22 `max-len` errors — see B1, pre-existing, not introduced here).

**Top 3 to look at first:**
1. **B1** — Functions `npm run lint` is currently red (22 `max-len` errors in
   committed code). The documented deploy pre-flight runs this, so a deploy
   would fail at the lint gate until these lines are wrapped.
2. **I1** — Split `settings_screen.dart` (700 lines, 8 card builders) and the
   3–4 >75-line `build()` methods into standalone widgets.
3. **I3** — Add targeted tests for the keychain `_migrate()` and the presence
   throttle/rollback logic — both load-bearing, both currently untested.

The security, bug, and performance deep reviews came back **clean** — no
exploitable findings, no traceable defects above the confidence bar, no
significant performance wins. This is a repeatedly-audited, well-maintained
codebase; the findings below are proportionate polish, not defects.

## Auto-applied cleanups (review the diff)
| File:line | Change | Why |
|---|---|---|
| `lib/core/permissions/location_permission_service.dart:3` | Removed unused import `media_permission_service.dart` | `unused_import` (dart fix) |
| `lib/features/live_activity/application/live_activity_registration_controller.dart:21` | Trimmed unused `PushRegistrationController` from `show` (kept `shouldRegisterPush`) | `unused_shown_name` |
| `lib/features/presence/application/presence_sync_controller.dart:16` | Trimmed unused `PushRegistrationController` from `show` (kept `shouldRegisterPush`) | `unused_shown_name` |
> Full detail is in `git diff`. Nothing below this line was auto-changed.

## ⚠️ Pre-ship checklist
None this run. No `TODO(pre-ship)` scaffolding, no destructive testing-only
actions wired into the UI, and no `enforceAppCheck: false` carve-outs remain in
`lib/` or `functions/`. App Check is active in `main()`.

## 🔴 Security findings
None. The `security-reviewer` pass over rules, callables, secret handling, and
client trust boundaries found no real, exploitable finding. Everything that
looked like a gap traced back to a correct server-side control (deny-by-default
rules, Admin-SDK-only collections, `enforceAppCheck: true` + guard-ordered
callables, role never cached, `toMap` never emitting `wave*`).

*Informational only (already documented + accepted):* `firestore.rules:271-292`
`isValidClientData` caps the `contacts` array at 50 entries but cannot cap each
contact's field lengths, so an admin write could theoretically approach
Firestore's 1 MB ceiling and fan out via `propagateClientEdits`. Admin-only
surface; the noted real fix is a per-field `TextLimits` cap in the contacts
editor, not a rules change. No action unless the contacts editor gains untrusted
input.

## 🟠 Bug / blocker findings (review required)

### B1 — Cloud Functions lint gate is currently red (22 `max-len` errors) · severity: medium · confidence: high
- **Where:** `functions/` — `bridge.js:10,38`, `security.js:56,71,87`,
  `notification_utils.js:76`, `time_utils.js:12`, `wave/callables.js:30`,
  `wave/client.js:363`, `wave/customers.js:119,131,152,177,312`,
  `wave/worker.js:117,180,234,249,297,300,333`, `__tests__/wave_customers.test.js:322`.
- **Problem:** `cd functions && npm run lint` (Google ESLint, 80-char cap) exits
  non-zero with 22 `max-len` errors on committed code. The project's deploy flow
  and the `/deploy` skill both run `npm run lint` as a required pre-flight, so a
  functions/rules deploy would stop at the lint step. These are pre-existing (not
  introduced by this audit's edits) — likely a lint run was skipped on an earlier
  commit.
- **Fix:** Wrap the offending lines to ≤80 chars. `eslint --fix` does **not**
  auto-fix `max-len`, so this is manual (mechanical) line-wrapping — behavior-
  preserving but needs a human choice of break points, hence report-only rather
  than auto-applied. Then re-run `npm run lint` to confirm green. Good candidate
  for the implement pass.

## 🔵 Areas to improve (review required)

### I1 — Split `settings_screen.dart` and the longest `build()` methods · impact: medium · confidence: high
- **Where:** `lib/features/settings/screens/settings_screen.dart` (700 lines,
  2 State classes, 8 `_*Card` builders; `_buildMaster` @172 ~70 lines,
  `_notificationsCard` @307 ~63); plus
  `lib/features/employees/widgets/sheets/employee_form_sheet.dart`
  `_buildAccountStatusSection` @265 (~93 lines);
  `lib/features/calendar/screens/day_route_screen.dart` `build` @106 (~82);
  `lib/features/calendar/widgets/views/details_view_body.dart` `build` @37 (~79);
  `lib/features/presence/screens/live_map_screen.dart` `_mapStack` @454 (~77).
- **Opportunity:** All exceed the project's ~60-line `build()` guideline. They're
  cohesive, not tangled, but the settings cards and the account-status block are
  the clearest wins — extracting each `_*Card` into a standalone widget both
  shrinks the 700-line file and shortens the builders.
- **Suggested improvement:** Pull the settings `_*Card` builders and the
  `employee_form_sheet` account-status block into their own widget files; extract
  the remaining inline bodies of `day_route_screen`/`details_view_body`/`live_map_screen`
  into `_body()`/section methods. No behavior change.

### I2 — `functions/notification_utils.js` is a 1122-line god file · impact: medium · confidence: high
- **Where:** `functions/notification_utils.js` (1122 lines, 69 functions).
- **Opportunity:** Diff logic + the `_MESSAGES` i18n table + message builders +
  ledger helpers + `sendToEmployee` all live in one module. Fully jest-tested and
  cohesive, but there's a clean seam: message-building (`_MESSAGES` +
  `build*Message`) is separable from the diff/ledger/send pipeline.
- **Suggested improvement:** Extract the message table + builders into a sibling
  (e.g. `notification_messages.js`), re-required by `notification_utils.js`.
  Keep the jest tests pointed at whichever module owns each pure helper. Optional;
  do only if this file keeps growing.

### I3 — Test-coverage gap: keychain `_migrate()` and presence throttle/rollback · impact: medium · confidence: medium
- **Where:** `lib/core/storage/secure_storage_service.dart` `_migrate()` (the
  `ios_keychain_accessibility_v2` backup-slot → delete → rewrite migration);
  `lib/features/presence/application/presence_sync_controller.dart` (250 m/2 min
  throttle, 10-min heartbeat, failed-write clock rollback, `denied → _stop()`).
- **Opportunity:** Both are called out as load-bearing in CLAUDE.md (the -25308
  lock fix; the presence-drift/Crashlytics-spam fixes) yet neither has a direct
  test. Only the `shouldTrackPresence` gate predicate is covered today. The
  decision logic in both is pure enough to test with a fake storage/repo + clock.
- **Suggested improvement:** Add a targeted test for `_migrate()` (exercise the
  non-injected branch against a mock `FlutterSecureStorage`, or extract the
  migration to a pure helper taking a storage interface) and one for the presence
  throttle/rollback orchestration with a fake repo returning
  `ok`/`failed`/`denied`.

### I4 — Three app-scoped sync controllers lack a `ref.onDispose` cleanup hook · impact: low · confidence: high
- **Where:** `presence_sync_controller.dart`,
  `live_activity_registration_controller.dart`,
  `push_registration_controller.dart` (the plain `Provider`s that open
  `StreamSubscription`s/`Timer`s).
- **Opportunity:** They cancel their streams/timers in their own `_stop()`/
  `dispose()` (driven by `AppSyncListeners` on sign-out) and live for the app
  lifetime, so nothing leaks today — but they don't register
  `ref.onDispose(() => _stop())`, unlike `appointments_providers.dart` which
  wires it correctly. Adding it hardens cleanup against any future container
  disposal.
- **Suggested improvement:** Add `ref.onDispose(() => controller._stop())` (or
  `dispose()`) in each provider body, mirroring `appointments_providers.dart`.

### I5 — `settings_tiles.dart` holds 11 widget classes in one file · impact: low · confidence: high
- **Where:** `lib/features/settings/widgets/cards/settings_tiles.dart` (476 lines,
  11 widget classes).
- **Opportunity:** Against the project's "one class/widget per file" convention.
  All small and cohesive, so low urgency — flag for consistency only.
- **Suggested improvement:** Split into per-tile files under the same folder if/
  when the file is touched next; not worth a dedicated pass.

## 🟡 Code-quality suggestions (optional)
- `lib/features/dashboard/widgets/sections/dashboard_hero.dart:24` —
  `static const Color _inProgressSegment = Color(0xFF00A6F4)` is a verbatim
  duplicate of `AppColors.accent` (`0xFF00A6F4`). Reference the token instead so
  the segment follows a future brand-blue change. (The sibling
  `_overdueSegment = Color(0xFFF54A00)` has no exact token match — leave it, or
  add a token if a fixed overdue hue is wanted.) The other three segments already
  use `statusColors`/`scheme.error` correctly.
- `lib/features/employees/widgets/fields/employee_color_grid.dart:192-198` — the
  custom-color dialog's decorative swatch ring hardcodes 7 hex colors that
  overlap `AppColors.employeeColors`. Low value and **likely intentional**
  (CLAUDE.md marks `EmployeeColorGrid` a deliberate design surface, and this is a
  decorative loop, not the selectable palette). Report-only; leave unless a
  palette-unification pass is wanted.

## Notes / uncertainties
- Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/.gen/**`,
  `firebase_options.dart`, `build/**`) were excluded per `analysis_options.yaml`.
- **Dead-code scans came back clean beyond the 3 auto-fixed imports:** 0 orphaned
  files (2,864 import/export lines cross-checked), **0 orphaned l10n keys** (all
  463 `app_en.arb` keys referenced — no separate l10n pass needed), 0 dead design
  tokens, 0 dead public types/top-level functions, 0 dead JS exports.
- **Unused-dependency heuristic hits are all false positives:**
  `google_maps_flutter_ios_sdk9` (endorsed SPM override), `build_runner` +
  `freezed` (codegen for the `.freezed.dart` value classes — confirmed in use),
  `flutter_launcher_icons` (icon-gen tool). None removable.
- Sub-threshold notes from the deep review (not defects, logged for completeness):
  `notification_utils.js:695` `endCardOnTerminal` doesn't explicitly
  `clearCardMarker` after `endLiveActivity` in the narrow "card push-started but
  update-token not yet registered" window — TTL-backstopped, no wrong card
  produced; `travel_utils.js:386-388` one extra ledger `.get()` per candidate per
  sweep — a deliberate trade to avoid billable Routes spend.
