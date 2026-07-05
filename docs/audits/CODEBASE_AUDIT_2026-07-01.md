# Codebase Audit — 2026-07-01

Scope: whole repo — `lib/` (190 non-generated Dart files), `test/` (101 files),
`functions/` (25 JS files), `firestore.rules`, `storage.rules`. Baseline: clean
working tree on branch `moblie` (`2c64072`).

## Summary
- Scanned: 190 `lib/` Dart + 101 `test/` + 25 `functions/` JS + Firestore/Storage rules.
- Auto-fixed (safe, in the diff): **3** — 2 on-scale spacing literals → `AppSpacing`
  tokens (`image_viewer.dart`), 1 stale/misleading security comment corrected
  (`invites.js`).
- Reported for your decision: **9** (⚠️ 1 pre-ship · 🔴 1 security · 🟠 2 bugs · 🔵 4 improvements · 🟡 2 code-quality)
- Verification: `flutter analyze` **pass** (no new errors/warnings vs. baseline) ·
  `flutter test` **599/599 pass** · `functions` ESLint **pass** · `dart fix` nothing to fix.

The static level was already clean (0 analyzer errors/warnings, 0 `dart fix`
candidates, 0 orphaned files, 0 unused providers/exports, 0 lint issues in
Functions). This app has clearly been through several audit passes — the findings
below are almost all "review / improve", not "broken".

## Update (2026-07-01) — findings implemented

Everything below **except the pre-ship App Check flips and B2** has since been
implemented on `moblie` (uncommitted). Verified after the changes:
`flutter analyze` clean · `flutter test` **607/607** · Functions ESLint clean ·
Jest **175/175**.

- ✅ **S1** — `enforceDurableRateLimit` now logs a sha256 prefix + `keyKind`
  instead of the raw key; `redeemSignupCode` passes `keyKind: "email"`. No PII in
  logs.
- ✅ **B1** — `isAccountDeletionSignal` is now a populated→empty *transition*
  test (using the `prev` from `ref.listen` in `main.dart`), so the invited-signup
  and fresh-sign-in bootstrap windows (both start empty) no longer trip a false
  "account disabled". A real deletion (populated→empty) still fires, including
  across a loading blip. (First shipped as a static `AuthService.isActivatingSignup`
  flag, then reworked to the transition test per the code-review altitude finding —
  no global mutable state. 7 unit cases.)
- ⏸️ **B2 — kept as-is (24h intentional).** Briefly changed `end == start` to be
  rejected, then reverted on request: `combineEndDateAndTime` again rolls
  overnight for `end <= start`, so an end time equal to the start remains a valid
  24-hour booking (the original, test-pinned behavior). No change from baseline.
- ✅ **I1** — added `firebase_appointments_repository_write_test.dart` covering
  `_toFirestoreMap` (status + `Timestamp` + server timestamps), `addAppointment`
  timestamps, and the load-bearing `updateAppointments` transaction skip-missing
  invariant.
- ✅ **I2** — `EventDetailsController.save()` extracted `_buildUpdatedRecord` +
  `_applySeriesChange`; the reentrancy guard / seed-settle / validation stay first.
- ✅ **I3** — `appointment_tile.dart` (`_TitleRow`/`_TimeRow`) and
  `appointment_card.dart` (`_TitleHeader`/`_TimeRow`/`_EmployeeRow`) sub-widgets
  extracted; titles stay plain `Text` (IntrinsicHeight constraint).
- ✅ **I4** — added a memoized `_employeeSearchIndexProvider`; per-keystroke
  filtering now normalizes only the query, not every employee (no lag added).
- ✅ **Code-quality** — `text_size_screen.dart` now uses `AppTopBar`.
- ⏸️ **Deferred (pre-ship):** the 6 App Check flips (see the checklist above).
- ⏸️ **Not done (intentional):** the `employee_color_grid` decorative
  `SweepGradient` — sourcing its stops from `AppColors.employeePalette` would
  change the visible gradient (not a behavior-preserving swap), so it's left as-is
  pending a deliberate design call.

The detailed findings below are retained as the rationale/record.

## Auto-applied cleanups (review the diff)
| File:line | Change | Why |
|---|---|---|
| `lib/features/calendar/widgets/dialogs/image_viewer.dart:5` | Added `import '.../core/theme/design_tokens.dart'` | needed for the token swaps below |
| `lib/features/calendar/widgets/dialogs/image_viewer.dart:103` | `EdgeInsets.all(8)` → `EdgeInsets.all(AppSpacing.sp8)` | design-token convention; `sp8 == 8`, byte-identical |
| `lib/features/calendar/widgets/dialogs/image_viewer.dart:117` | `EdgeInsets.only(top: 12)` → `EdgeInsets.only(top: AppSpacing.sp12)` | design-token convention; `sp12 == 12`, byte-identical |
| `functions/invites.js:14` | Comment "throttled per uid" → "keyed by token email (below)" | comment mislabeled the actual rate-limit key (`invites.js:114` keys by email); zero behavior change |

> Full detail is in `git diff`. Nothing below this line was auto-changed.

## ⚠️ Pre-ship checklist (act before release)

- [ ] **App Check enforcement is OFF on 6 callables** — flip to `enforceAppCheck: true`
  before the store release. All are marked `TODO(pre-ship)` and are gated by
  `auth` + `assertAdmin`/re-auth + durable rate limits, so this is abuse-surface,
  not an open door — but it must be flipped once Play Integrity can mint verified
  App Check tokens.
  - `functions/invites.js:37` (`createEmployeeInvite` **and** `redeemSignupCode` — shared `APP_CHECK` const)
  - `functions/account.js:41` (`deleteAccount`)
  - `functions/wave/callables.js:100` (`waveBootstrap`)
  - `functions/wave/callables.js:181` (`waveGetConnection`)
  - `functions/wave/callables.js:206` (`waveImportCustomers`)
  - (The billing-sensitive Places callables — `places.js:71,146` — correctly keep `enforceAppCheck: true`.)

> No destructive `TODO(pre-ship)` scaffolding remains in `lib/` (the testing-only
> delete/scaffold code referenced in older audits has already been removed). The
> App Check flips are the only in-code pre-ship items.

## 🔴 Security findings (review required)

### S1 — Email (PII) written to Cloud Logging on `redeemSignupCode` rate-limit breach · severity: low · confidence: high
- **Where:** `functions/security.js:135` (`logger.warn("enforceDurableRateLimit: limit exceeded", {route, uid})`), reached from `functions/invites.js:114-116` where `rateKey = tokenEmail.trim().toLowerCase()` is passed as the `uid` argument.
- **Risk:** For the `redeemSignupCode` route only, the rate-limit "uid" is actually the caller's email, so a raw email address is logged whenever someone trips the redeem throttle. Cloud Logging retains it; anyone with log-view/export access sees the email. Every other caller (`deleteAccount`, Places, Wave import) passes a real opaque UID, so this is the one PII-in-logs leak. Not attacker-exploitable — a hygiene/compliance gap against the project's "never log PII" rule. (The `rateLimits/redeemSignupCode__<email>` doc-id also embeds the email, but that collection is fully denied to clients, so it's server-only.)
- **Fix:** Give `enforceDurableRateLimit` a `keyKind` param (or hash the key) so the email-keyed route logs `email:sha256(...)` instead of the raw value. Report-only — it touches the security/rate-limit path, so it's your call, but it's a small, low-risk change.

## 🟠 Bug findings (review required)

### B1 — Invited-signup can race the global account guard and dump a new employee on the login screen with a false "account disabled" message · severity: medium · confidence: medium-high
- **Where:** `lib/main.dart:206-219` (`_listenForDeletedAccount`) + `lib/main.dart:162-184` (`_handleAccountDisabled`); interacts with `lib/features/auth/services/auth_service.dart` (`signUpWithCode`), `lib/features/auth/application/account_status_provider.dart` (`isAccountDeletionSignal`, `currentUserDocProvider`), and `lib/features/auth/screens/login_screen.dart` (`_routeAfterSignUp`).
- **Problem:** During `signUpWithCode`, `register()` creates + signs in the Auth user, but the invite `users` doc is not activated (its `uid` is still `''`) until `redeemSignupCode` returns. In that window the user is "signed in with no matching users doc." `authUidProvider` (driven by `authStateChanges()`) propagates the new uid → `currentUserDocProvider` opens `watchUserDoc(newUid)` → its first *settled server* snapshot is empty → `isAccountDeletionSignal` returns true → `_handleAccountDisabled` signs out, routes to `login`, and shows `error_thisAccountHasBeenDisabled`. This races `redeemSignupCode`: if the empty server read (~100–300 ms after uid propagation) settles before the redeem callable returns (~200–800 ms), the guard wins — redeem still succeeds server-side, but the client is already signed out, so `_routeAfterSignUp` sees `currentUser == null` and silently returns, stranding the new employee on the login screen under a false "account disabled" banner. The author's own comment in `auth_service.dart` acknowledges this guard signs out the half-created user — but the mitigation is applied only to the *rollback/failure* path, not the *success* path.
- **Impact:** Intermittent, alarming, self-contradictory UX on the exact happy path the invited-signup redesign is built around. Recoverable (re-login works, since the doc is now active) — not data loss. Reportedly passed manual testing, which suggests redeem usually wins the race; confirm on-device.
- **Fix:** Suppress the account-exit listeners while an invited signup is in flight. Simplest: have `signUpWithCode` set an `isActivatingSignup` flag that `_handleAccountDisabled` (or `isAccountDeletionSignal`) early-returns on until routing completes — i.e. ignore the transitional "signed-in uid has no doc yet, activation pending" state.

### B2 — Zero-duration appointment (end time == start time) silently becomes a 24-hour booking · severity: low · confidence: medium
- **Where:** `lib/features/calendar/domain/policies/appointment_form_validator.dart:90` (`combineEndDateAndTime`).
- **Problem:** The end-time is rolled to the next day whenever `end.isAfter(start)` is false — which includes the `end == start` case, not just `end < start`. So picking an end time equal to the start time produces a 24-hour appointment, and the validator's `!end.isAfter(start)` check never fires, so no `endTimeMustBeAfterStart` error is shown. The overnight roll for `end < start` is clearly intentional (the DST comment confirms it); only the `==` edge is ambiguous.
- **Fix (product decision):** If same start/end should be invalid, roll to next day only when `end < start` *strictly* and let `==` fall through to the "end must be after start" error. If the 24h behavior is intentional, add a one-line comment saying so. Report-only — it changes validation behavior.

## 🔵 Areas to improve (review required)

### I1 — Test gap: appointments repository write + transaction paths (incl. the status allowlist) · impact: medium-high · confidence: high
- **Where:** `lib/features/calendar/data/firebase_appointments_repository.dart` (379 lines). Only `findBusyEmployees` and `searchHistory` have repo-level tests today.
- **Opportunity:** The highest-risk, invariant-bearing methods have no direct repo test: `updateAppointmentStatus` (enforces the `_allowedStatuses` allowlist — a documented critical invariant), `updateAppointments`/`rewriteSeries` (the transactional claim-guarded write — a load-bearing "outbox" invariant), `_toFirestoreMap` (must set `status` + server timestamps, or the doc drops out of `orderBy`), `fetchHistoryPage`, `watchInRange`. Controller tests use a **mock** repo, so they never exercise the actual mapping, the allowlist, or the transaction reconciliation — a regression there fails silently.
- **Suggested improvement:** Add a focused `firebase_appointments_repository_write_test.dart` on the existing mocktail-Firestore harness (see `..._busy_test.dart`). Prioritize: (a) `updateAppointmentStatus` rejects a value outside `_allowedStatuses`; (b) `_toFirestoreMap` sets `status` + `createdAt`/`updatedAt`; (c) `updateAppointments` only writes matching docs. Cover the invariant branches, not 100%.

### I2 — `EventDetailsController.save()` is a ~146-line method with a 3-way series branch · impact: medium-low · confidence: medium
- **Where:** `lib/features/calendar/application/event_details_controller.dart:356` (file is 571 lines — the largest in `lib/`).
- **Opportunity:** `save()` does reentrancy-guard + seed-settle + validation + id guard + time combination + 19-field `AppointmentRecord` construction + a three-way series branch (rewrite / propagate / plain update) + orphan-image cleanup + background upload + error handling in one method. CLAUDE.md carries several fragile invariants about exactly this method (reentrancy-flag ordering, seed-settle-before-validate) — length is where those get accidentally broken during edits. It's well-tested and already had `AppointmentSeriesEditor`/`_resolveAssignees` extracted, so this is refinement, not rescue.
- **Suggested improvement:** Proportionate extraction only — pull the `AppointmentRecord` construction into `_buildUpdatedRecord(...)` and the series-branch block into `_applySeriesChange(...)` returning the counts. Keep the reentrancy guard + `await _seedFuture` + validation in `save()` (they must stay first).

### I3 — A handful of `build()` methods exceed the ~60-line guideline · impact: low-medium · confidence: high
- **Where (measured):** `appointment_form_fields.dart:155` (160 lines) · `appointment_tile.dart:35` (134) · `details_view_body.dart:40` (133) · `appointment_card.dart:27` (125) · `main_calendar_screen.dart:210` (125) · `client_view_body.dart:26` (123) · `settings_tiles.dart:280` (115) · `photo_picker_section.dart:115` (114).
- **Opportunity:** `.claude/rules/frontend.md` caps `build()` at ~60 lines; these run 2–2.7× over. Most are inherently long declarative trees already decomposed into sub-widgets — low real cost. The genuinely refactorable ones: `appointment_tile.dart` / `appointment_card.dart` (deeply nested `Row→Column→Row` — the title row and time-label row are natural `_TitleRow`/`_TimeRow` extractions) and `details_view_body.dart` / `client_view_body.dart` (a ~35-line data-derivation preamble that could move into getters/a computed record, shrinking `build` to the tree).
- **Suggested improvement:** Extract the two card widgets' nested subtrees into named private `StatelessWidget`s. Leave the flat field-list/settings-tile builders as-is — splitting a one-use declarative list would be the premature abstraction the anti-defaults warn against. Opportunistic cleanup, not a sweep.

### I4 — Employee search re-normalizes the whole staff list per keystroke (undebounced) · impact: low · confidence: high (undebounced) / low (measurable)
- **Where:** `lib/features/employees/screens/employees_screen.dart:172` → `filteredEmployeesProvider(_searchController.text)` (`lib/features/employees/application/employees_providers.dart:41-60`).
- **Opportunity:** Unlike the clients/history search (250 ms `Debouncer` + instant local fallback), employee search recomputes on every keystroke, re-normalizing `name`/`email`/`phone` for the whole staff list each time. At realistic staff counts (5–50, capped 500) this is sub-millisecond pure string work — not measurable — so it's a consistency/polish item, not a bottleneck.
- **Suggested improvement:** Only if you ever expect hundreds of staff: add a 250 ms `Debouncer` mirroring the clients/history pattern, or pre-normalize an index rebuilt when the users stream emits (mirroring the `employeeColorMapProvider` memoization right beside it). Otherwise leave as-is.

## 🟡 Code-quality suggestions (optional — need a real edit, so not auto-applied)

- `lib/features/settings/screens/text_size_screen.dart:13` — the **only** hand-built bare `AppBar` in the app (`.claude/rules/frontend.md`: every screen uses `AppTopBar`). It also re-hardcodes the title style (`fontSize: 17`, `w700`) instead of `AppTopBar`'s `titleLarge`, so it will drift from every other screen title. Suggest `appBar: AppTopBar(title: ..., onBack: ...)` and drop the manual `AppBackButton`/`TextStyle`. (Covered by `test/text_size_screen_test.dart`, so a swap is safe to verify.)
- `lib/features/employees/widgets/fields/employee_color_grid.dart:194-200` — the 7-stop decorative `SweepGradient` uses raw `Color(0xFF…)` values that duplicate hues from `AppColors.employeePalette`. No single `ColorScheme` token maps to a rainbow, so it fails the "unambiguous target" test and was left alone. If tightening, source the stops from `AppColors.employeePalette`. Very low priority; arguably fine as decorative UI.

## Notes / uncertainties
- **16 orphaned-looking l10n keys** in `lib/l10n/app_en.arb` have zero generated-getter
  references — flagged for a **separate, deliberate l10n pass**, NOT deleted in this
  code sweep (ARB keys are reached via generated getters; deletion needs EN/FR lockstep
  + `flutter gen-l10n`). Med-confidence orphans: `calendar_today` (:159),
  `calendar_noNumber` (:553), `calendar_noNotes` (:561), `calendar_noMaterials` (:565),
  `calendar_selectAnAppointmentToViewDetails` (:661), `common_searchAddress` (:977),
  `common_typeToSearchAnAddress` (:981), `common_street` (:985). **Low-confidence /
  likely intentional** (the "reuse before adding new ones" failure-string pool named in
  CLAUDE.md — verify before touching): `error_couldNotDeleteClientTryAgain` (:305),
  `error_couldNotSaveChangesTryAgain` (:309), `error_couldNotAddClientTryAgain` (:313),
  `error_somethingWentWrongCreatingTheAppointment` (:521),
  `error_somethingWentWrongSavingChanges` (:525), `error_couldNotCreateEmployee` (:737),
  `error_couldNotLoadAppointments` (:885), `error_couldNotDeleteAccount` (:1331).
- **4 unused-dependency heuristic hits are all false positives** (verified, do NOT remove):
  `firebase_performance` (native auto-init, no import), `build_runner` / `freezed` /
  `flutter_launcher_icons` (dev-only codegen/icon tooling run via CLI, not imported).
- **B1 needs on-device confirmation** — the race is real and mechanically present, but
  its window is nondeterministic and the flow reportedly passed manual testing.
- **Verified sound, no action** (from the deep review): signup-code flow (60-bit CSPRNG
  code, sha256 at rest, email-keyed throttle, atomic activation, Auth-user rollback),
  Firestore/Storage rules (deny-by-default, role/status write-allowlists, `signupCodes`/
  `rateLimits`/`wave` locked), callable payload validation (`assertPayloadShape` +
  `requireString`), loose Map casts, role-always-from-Firestore, email normalization,
  server-side image magic-byte validation, Wave outbox transactional claim-guard, search
  cache invalidation on every write path, reentrancy-flag ordering, and assignee
  preservation on edit. Hot paths (Firestore reads, rebuilds, resource disposal) are
  already well-optimized.
