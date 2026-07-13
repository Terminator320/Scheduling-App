# Codebase Audit — 2026-07-13

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`, `test/`). Baseline: clean working tree on branch `notification`.

> **Update — findings implemented (2026-07-13).** After the audit the user said "do all", so every non-pre-ship finding was implemented (uncommitted): **B1** (main.dart tap handlers wrap deep-link opens in try/catch → no more non-crashes logged as fatal), **I2** (`resolveAssigneeNames` unit test), **I3** (`main_calendar_screen` build() imperative block extracted to `_prepareBuild`), the `DateUtils.isSameDay` nit, the `dashboard_aggregator` `AppointmentStatus.fromRaw` consistency fix, and both orphaned l10n keys pruned (+ `flutter gen-l10n`). **I1** (series-edit notification fan-out) was intentionally LEFT as reported — a blanket dedup would suppress legitimate single-occurrence cancels; it needs a design decision, not a mechanical fix. Verification: `flutter analyze` **clean**; `flutter test` **823 pass**.
> **Also fixed a blocking dependency drift:** the 1.30.0 release bumped the whole FlutterFire suite one patch (cloud_firestore 6.6.0→6.7.0, firebase_auth 6.5.4→6.5.5, etc.), and that wave `extends FirebasePlugin` — a type `firebase_core_platform_interface 7.1.0` removed (now `FirebasePluginPlatform`) — so every Firebase-importing test failed to compile. Fixed by pinning `firebase_core: 4.11.0` in `pubspec.yaml`, which cascades the whole suite back to the 1.29.0 green versions. Revert to a range once a fixed FlutterFire wave ships.

## Summary
- Scanned: `lib/` + `functions/` + rules + `test/` (full deep-review fan-out: security, bugs, dead-code/cleanliness, performance, maintainability).
- Auto-fixed (safe, in the diff): **0** — static scan is clean (`flutter analyze`: no errors/warnings; `dart fix`: nothing to fix; functions ESLint: clean; no analyzer-confirmed dead code, no unused deps). Nothing met the "safe to auto-apply" bar this run.
- Reported for your decision: **7**  (⚠️ 0 pre-ship · 🔴 0 security · 🟠 1 bug · 🔵 3 improvements · 🟡 3 quality/l10n)
- Verification: `flutter analyze` clean (baseline, no changes made) · tests not touched · functions lint clean.

## Auto-applied cleanups
None. The tree is untouched — every finding below is report-only by design (semantic/behavioral or a deliberate l10n pass).

## ⚠️ Pre-ship checklist
None. No `TODO(pre-ship)` markers remain anywhere in `lib/`/`functions/`, and all Cloud Function callables already `enforceAppCheck: true` (the temporary carve-out was retired in 1.25.1). Nothing is gated on launch.

## 🔴 Security findings
None. Full security pass over rules, all function modules, and the callable/auth/notification client paths came back clean:
- Deny-by-default rules hold; sensitive collections (`rateLimits`, `signupCodes`, `wave`, `waveSyncQueue`, `appointmentReminders`, `appointmentOverduePrompts`) are `if false` to clients. `fcmTokens` writes are shape-constrained with `uid == request.auth.uid` + a `hasOnly` key allowlist.
- All callables enforce App Check; guard order correct everywhere (auth → `assertAdmin` → payload validation → `enforceDurableRateLimit` → work). `redeemSignupCode` rate-limited by token email.
- Secrets all in Secret Manager; no keys/tokens/PII in source or logs (rate-limit email key is sha256-hashed).
- Callable responses use the Android-safe loose cast; emails normalized before use; App Check active in `main()`.

## 🟠 Bug findings

### B1 — Notification/widget tap failures are recorded to Crashlytics as FATAL crashes · severity: low · confidence: medium
- **Where:** `lib/main.dart:180-189` (`_setupWidgetTapHandling` IIFE) and `lib/main.dart:205-206` (`_setupPushTapHandling`); the `.listen(...)` callbacks at `:182` and `:206`.
- **Problem:** `unawaited(service.initialMessage().then(_handlePushTap))` and the widget-tap IIFE have no `.catchError`/try-catch. `_handlePushTap`/`_handleWidgetTap` → `_openAppointmentDeepLink` are async and can throw at the tail (`showEventDetails`, l10n lookup, a Firestore fetch). A rejection there — or a rejection thrown inside the async `.listen` callback body (the `onError:` arg only catches *stream* errors, not a rejected callback future) — propagates to `runZonedGuarded`/`PlatformDispatcher.onError`, both of which record with `fatal: true`. So a deep-link that fails to open on a notification/widget tap is logged as a **fatal crash** (inflating the crash-free-users metric) even though the app keeps running. Also violates the project rule "async calls in initState / stream subscriptions must have `.catchError` or try/catch."
- **Fix:** Wrap the `_handlePushTap`/`_handleWidgetTap` bodies (or the `.then`/IIFE and each `.listen` callback) in try/catch that logs via `ref.read(loggerProvider).warn(...)`, mirroring the `.catchError` already used on `recordFuture` inside `_openAppointmentDeepLink`.

_Non-blocking observation (below the report bar):_ `lib/features/dashboard/domain/dashboard_aggregator.dart:205` — `computeAttentionFlags` checks `a.status.toLowerCase() == 'pending'` directly instead of routing through `AppointmentStatus.fromRaw`, so a legacy `confirmed` doc wouldn't appear in the "pending soon" flag. `confirmed` is retired, so real-world impact is effectively nil; every other status check in that file already goes through `fromRaw`. Fix only if you want consistency.

## 🔵 Areas to improve

### I1 — Series "apply to future" edit fans out N cancel pushes + N redundant backend queries · impact: medium · confidence: medium
- **Where:** root cause `lib/features/calendar/application/appointment_series_editor.dart:40-58` (`rewriteSeries` deletes every future sibling and recreates them); surfaces at `functions/notification_utils.js:169-174` via `notifyAppointmentChanges`.
- **Opportunity:** When an admin reschedules/edits a repeating series with "apply to future," `rewriteSeries` issues 1 anchor update + N sibling deletes + N fresh creates. `onDocumentWritten` fires once per doc: the N deletes each hit the `before && !after` branch → a **"Job cancelled" push per deleted occurrence**, plus the anchor update → one "rescheduled" push. (The N creates are correctly suppressed by the anchor check at `notification_utils.js:164-165`; deletes/updates have no such dedup.) Each change-push invocation also runs `fetchEmployeeWidgetWindow` (an `array-contains` + range query) + user-doc read + token read. Net: one ordinary admin edit → ~2N+1 function invocations and the assigned employee gets N "cancelled" + 1 "rescheduled" notifications. N is bounded by the booking horizon (usually small), so nothing melts — but it's real duplicated backend work plus notification spam on a normal path.
- **Suggested improvement:** Treat a series rewrite as one logical event — either (a) update surviving sibling docs in place (reuse their ids) so deletes only fire for genuinely removed occurrences, or (b) extend the anchor-dedup idea to change pushes: suppress the cancelled/rescheduled push for non-anchor docs sharing the same `seriesId` within a rewrite, letting the anchor send a single "series updated" push.

### I2 — `resolveAssigneeNames` has no direct unit test · impact: low · confidence: high
- **Where:** `lib/features/dashboard/domain/assignee_names.dart` (~20 lines).
- **Opportunity:** The only genuinely untested pure logic in the newer (push/widget/dashboard/Wave) areas — everything else there is well-covered (`notification_utils.test.js` 891 lines, `dashboard_aggregator_test.dart`, widget payload/signature tests, Wave `import_schedule.test.js`, push client tests). It's a trivial nameMap-with-fallback join.
- **Suggested improvement:** A 2-3 case `test()` (all-known names, an unknown id falling back, empty list). Marginal value; close it only if you're touching the file.

### I3 — `main_calendar_screen.dart` build() mixes imperative wiring with its widget tree · impact: low · confidence: high
- **Where:** `lib/features/calendar/screens/main_calendar_screen.dart:211-344` (~133 lines).
- **Opportunity:** Unlike the other over-60-line `build()` methods (which are flat declarative trees already decomposed into named sub-widgets and fine as-is), this one interleaves `ref.listen` wiring, day-index memoization, and locale-format caching *before* the `Scaffold`. The imperative pre-return block (~lines 222-268) is the clean extraction seam.
- **Suggested improvement:** Move the pre-return imperative block into a private helper so `build` is just the widget tree. Only worth doing if you're already in this file.

## 🟡 Code-quality suggestions (optional)

- **Orphaned l10n keys — for a deliberate l10n pass, do NOT strip in a code sweep:**
  - `lib/l10n/app_en.arb:1548` — `dashboard_unassigned` ("Unassigned"). No `context.l10n.dashboard_unassigned` call site in `lib/`/`test/` (only the generated getter + ARBs). The sibling `dashboard_unassignedCount` IS used (`dashboard_hero.dart:212`); only the bare key is orphaned. Prune from `app_en.arb` **and** `app_fr.arb:373` if confirmed.
  - `lib/l10n/app_en.arb:1612` — `settings_management` ("Management"). No call site. Prune from both ARBs (`app_fr.arb:384`) if confirmed.
- `lib/features/calendar/widgets/views/details_view_body.dart:250-253` — `_DetailsViewData.from` hand-rolls same-day comparison (`.year == && .month == && .day ==`) instead of the `isSameDay(...)` helper already used in `main_calendar_screen.dart:109,153` and `app_calendar_view.dart:79`. One-line consistency nit: `isSameDay(appointment.startTime, now)`.

## Notes / uncertainties
- Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/.gen/**`, `firebase_options.dart`) excluded per `analysis_options.yaml` — not scanned or reported.
- **Dependency heuristic false positives (verified, NOT removable):** `build_runner`, `freezed` (drive codegen — `.freezed.dart` files + `@freezed` annotations exist), `flutter_launcher_icons` (CLI tool, `dart run flutter_launcher_icons`). All three are `dev_dependencies` used via CLI/codegen, not `import`ed.
- Documented, intentional, left untouched (surfaced for completeness): `dashboard_hero.dart:25-26` hardcoded data-hue colors (justified by an in-file comment — theme-invariant hues on `scheme.primary`); `employee_color_grid.dart:194-200` picker swatches (intentional palette per CLAUDE.md); `functions/scripts/backfill.js` (retained one-shot ops migration script); the Dart-vs-server widget day-boundary timezone divergence (accepted single-timezone tradeoff, documented in CLAUDE.md); `startOfDay` `DateTime(y,m,d)` construction repeated 16× across 4 files (borderline vs. the "no premature abstraction" rule — a `core/utils` helper is only worth it if you touch day-boundary math again).
