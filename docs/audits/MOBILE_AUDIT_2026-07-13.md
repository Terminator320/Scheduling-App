# Codebase Audit — 2026-07-13 (mobile-optimization focus)

Scope: whole repo (`lib/`, `functions/`, rules), lens = mobile performance,
responsiveness, memory, battery, network efficiency, mobile UX.
Baseline: working tree on branch `notification` (clean).

## Summary
- Scanned: `lib/` (all features), Cloud Functions, rules — deep review by 3
  parallel agents (perf/memory, responsive UX, hot-path bugs) + static scan.
- Auto-fixed (safe, in the diff): **0** — `flutter analyze` "No issues found",
  `dart fix` "Nothing to fix", ESLint clean. Nothing mechanical to apply.
- Reported for your decision: **6** (⚠️ 0 pre-ship · 🔴 0 security · 🟠 0 bugs
  · 🔵 1 improvement · 🟡 5 minor polish/notes)
- Verification: `flutter analyze` PASS (no errors/warnings, ran 21.2s) ·
  tests not re-run (no code changed) · functions lint PASS.

**Verdict: the app is already strongly optimized for mobile.** Nearly every hot
path already implements the exact mitigation this audit hunts for — bounded &
kept-warm Firestore streams, off-thread `compute()` search with LRU caches,
content-memoized derived maps, resize-bounded image decode, disposed
controllers/subscriptions, reentrancy flags before the first await, and
`mounted` guards after every await. No high- or medium-impact perf/battery/
memory bottleneck and no correctness bug cleared the confidence bar. Findings
below are minor and report-only (each changes layout/output, so none were
auto-applied).

## Top 3 to look at first
1. **I1 — Calendar month bar can overflow horizontally at large text scale**
   (home screen). The only medium item.
2. **Text-size settings preview shows hardcoded English strings** (bilingual gap).
3. **Dashboard stats run synchronous O(n) passes on the main thread** — fine at
   today's data volume; first thing to move to an isolate if the business scales.

---

## ⚠️ Pre-ship checklist
None. No destructive `TODO(pre-ship)` scaffolding or launch-gated switches
surfaced in this mobile-focused pass. (App Check enforcement / iOS-Mac store
items are tracked separately in the store-readiness notes, not part of this sweep.)

## 🔴 Security findings
None in scope for this pass.

## 🟠 Bug findings
None met the confidence bar. One low-severity observation is filed under Notes.

## 🔵 Areas to improve (review required)

### I1 — Calendar month bar has no horizontal overflow guard · impact: medium · confidence: medium
- **Where:** `lib/features/calendar/screens/main_calendar_screen.dart:476-489`
  (`_CalendarMonthBar`)
- **Opportunity:** The bar is a `Row(mainAxisAlignment: spaceBetween)` with two
  bare `Text` widgets — the tappable `monthLabel` ("September 2026") and
  `jobLabel` ("5 appointments" / "5 rendez-vous"). Neither is `Flexible`/
  `Expanded`-wrapped and neither sets `overflow`/`maxLines`. The `PreferredSize`
  height already scales with `textScalerOf` to prevent *vertical* clipping, but
  the *horizontal* axis is unprotected. On a narrow phone (≤360 px) at a large
  OS accessibility scale, the two labels' intrinsic width + 32 px padding can
  exceed the width → `RenderFlex overflow` on the app's home surface. French
  plurals lengthen `jobLabel`, tightening the margin.
- **Suggested improvement:** Wrap `monthLabel` in
  `Flexible(child: Text(monthLabel, style: labelStyle, overflow: TextOverflow.ellipsis, maxLines: 1))`
  and give `jobLabel` a `maxLines: 1` + ellipsis (optionally `Flexible` too).
  Behavior-preserving at normal sizes; only truncates at pathological scale.

## 🟡 Code-quality / polish suggestions (optional)

- **Localize the text-size preview.**
  `lib/features/settings/widgets/views/text_size_view.dart:63,70,74` renders
  literal `'Appointment Title'`, `'Tuesday, May 12 - 9:00 - 9:45 AM'`,
  `'Sarah Johnson - 514-555-0101'`. A French user opening Settings → Text Size
  sees English. Route through `context.l10n` keys (or document as a deliberate
  fixed sample).

- **Employee-picker chip label not overflow-guarded.**
  `lib/features/calendar/widgets/fields/employee_picker.dart:93-104` shows
  `employee.name.split(' ').first` with no `maxLines`/`overflow` and no
  `Flexible`. It sits in a `Wrap`, so normal names are safe — risk is only a
  single very long token at large scale. Same shape at
  `appointment_status_picker.dart:56` (app-controlled short labels, lower risk).

- **`widgetSync` employee-id read lacks the post-sign-in retry.**
  `lib/features/home_widget/application/widget_sync_service.dart:214,222-230` —
  `widgetEmployeeIdProvider` calls `findUserByUid(uid)` without the `retryAsync`
  auth-propagation wrapper used in `splash_controller`/`sign_in_controller`. A
  transient post-sign-in `permission-denied` falls through to `data(null)` →
  `service.clear()`, briefly clearing the iOS home-screen widget. Self-heals on
  the next `currentUserDocProvider` emission; iOS-only, cosmetic. Wrap in
  `retryAsync` for parity if desired.

- **Push `sync()` fires on every root rebuild.**
  `lib/main.dart:419,498` — `_listenForPushRegistration()` runs in
  `_PaulAppState.build()`, calling `pushRegistrationControllerProvider.sync()`
  on theme/text-scale/language change. Cheap: `sync()` has a fast-path guard
  (`_busy` + already-registered uid/locale) that returns before any query/write,
  so these are no-ops. Optional micro-cleanup only.

## Notes / uncertainties
- **Dashboard aggregation is synchronous on the main thread.**
  `lib/features/dashboard/domain/dashboard_aggregator.dart:219` (`computeStats`)
  runs 5 sequential O(n) passes over the 8-week window when the dashboard is open
  and appointments re-emit. Imperceptible for a single-region business (a few
  hundred docs); if appointment volume ever reaches thousands, move it to a
  `compute()` isolate (mirroring the search paths). Not a live bottleneck today.
- **Full-screen image viewer decodes at full resolution**
  (`lib/features/calendar/widgets/dialogs/image_viewer.dart:130`, no
  `cacheWidth`) — intentional: source images are already capped at 1600 px /
  quality-70 at pick time, and full res is needed for the 4× pinch-zoom. Not a
  problem.
- Unused-dependency heuristic hits (`build_runner`, `freezed`,
  `flutter_launcher_icons`) are all expected false positives — codegen/tooling
  used via `build_runner`, not a `package:` import. No action.
- No dead code, no unused files, no analyzer findings. No security or auth paths
  were touched by this mobile-focused pass.
