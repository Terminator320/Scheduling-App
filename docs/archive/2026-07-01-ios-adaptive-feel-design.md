# iOS Adaptive Feel — Design Spec

**Date:** 2026-07-01
**Branch:** moblie
**Status:** Approved design, pending implementation plan

## Goal

Make the app feel native on iPhone/iPad by swapping high-frequency UI
primitives to their Cupertino equivalents **only on iOS**, while leaving the
Android experience byte-for-byte unchanged. Reference:
<https://docs.flutter.dev/ui/widgets/cupertino>.

## Decisions (locked via brainstorming)

1. **Scope:** iOS-only, platform-adaptive. Cupertino renders on iOS/macOS;
   Android keeps the existing Material look. No shared "iOS everywhere" path.
2. **Depth:** Adaptive **component layer**. Material scaffolds, layout,
   design tokens, notices, master-detail, and `StatusChip` stay as the
   skeleton. We swap primitives, not screens.
3. **Extras:** Core plan **plus a few polish wins** (adaptive haptics on
   toggles/pickers, native selection feel where cheap, and fixing safe small
   UX rough edges encountered in the touched files).

## Non-negotiable invariant

**Android must render exactly as it does today.** Every adaptive branch has a
Material arm identical to current behavior. All Cupertino behavior is additive
and gated on `context.isCupertino`. This is the acceptance bar for every change.

## Architecture

New isolated layer: `lib/core/adaptive/`.

### A. Foundation — `lib/core/adaptive/adaptive.dart`

- `context.isCupertino` extension getter:
  `Theme.of(context).platform == TargetPlatform.iOS ||
   Theme.of(context).platform == TargetPlatform.macOS`.
- Single source of truth for the platform check. Reads `ThemeData.platform`
  (not `defaultTargetPlatform`) so widget tests can force either look via
  `ThemeData(platform: TargetPlatform.iOS)`.
- Mirrors the existing `context.isWide` / `context.isCompact` extension
  convention in `core/layout/breakpoints.dart`.

### B. Navigation — swipe-back (already free, no code)

**Verified during design:** Flutter's default `PageTransitionsTheme` maps
`TargetPlatform.iOS`/`macOS` to `CupertinoPageTransitionsBuilder`, which provides
the horizontal slide **and** the edge-swipe-back-to-pop gesture. `themes.dart`
has **no** `pageTransitionsTheme` override, so the auth/splash
`MaterialPageRoute`s (and the full-screen image viewer route) already animate
and swipe-back natively on iOS today. Confirmed against the Flutter docs
(`ui/adaptive-responsive/platform-adaptations`,
`release/.../page-transition-replaced-by-ZoomPageTransitionBuilder`).

- **No work item.** An `adaptivePageRoute` wrapper returning `CupertinoPageRoute`
  on iOS would only duplicate framework behavior (the extra it offers — nav-bar
  back-title semantics — is unused, since chrome is the custom `AppTopBar`).
  Adding it would violate YAGNI.
- **`_fadeRoute` stays unchanged.** The hub destinations (calendar / clients /
  employees / history / settings) are top-level nav-rail targets, not a push
  stack — a cross-fade is the correct, intentional chrome-stable transition,
  and edge-swipe-back does not belong between them.

### C. Adaptive primitives

Each is a shared helper or a built-in `.adaptive` constructor. Android arm ==
current behavior.

1. **Confirm dialog** — upgrade `showConfirmDialog`
   (`lib/shared/widgets/dialogs/confirm_dialog.dart`) to render
   `CupertinoAlertDialog` + `CupertinoDialogAction(isDestructiveAction:
   destructive)` on iOS via `showCupertinoDialog`. One file; upgrades **every**
   destructive confirm (client / appointment / account / series) at once.
   Preserve the `content`-vs-`message` API and the `destructive` flag semantics.

2. **Action sheet** — `showAdaptiveActionSheet<T>()` in
   `core/adaptive/adaptive_action_sheet.dart`: `CupertinoActionSheet` with a
   cancel action on iOS; the current `showModalBottomSheet` list on Android.
   Wire into:
   - image source picker `_showSourceSheet`
     (`calendar/widgets/sheets/image_source_picker.dart`) — Camera / Gallery.
   - series-scope chooser (`calendar/widgets/dialogs/series_scope_dialog.dart`)
     — This event / Whole series.

3. **Progress indicator** — `AdaptiveProgressIndicator`
   (`core/adaptive/adaptive_progress_indicator.dart`): `CupertinoActivityIndicator`
   on iOS, `CircularProgressIndicator` on Android. Exposes a `color` so
   in-button brand spinners stay on-brand (iOS activity indicator honors
   `color:`) rather than defaulting to grey. Apply to **neutral** spinner sites;
   leave whole-label swap buttons (`AnimatedLoadingButton`) driven by their own
   styling but source their spinner from this helper.

4. **Switch** — replace `Switch(...)` / `SwitchListTile` with `Switch.adaptive`
   (+ `SwitchListTile.adaptive`) at the 4 sites: settings, employee form,
   client edit form, add-client sheet. Built-in → `CupertinoSwitch` on iOS.

5. **Pull-to-refresh** — `RefreshIndicator.adaptive` at the 2 list sites
   (`clients_list_view.dart`, `appointment_history_view.dart`) for the native
   iOS refresh spinner.

6. **Back button** — `AppBackButton` (and `AppTopBar`'s back affordance) render
   an iOS chevron (`CupertinoIcons.back` / `Icons.arrow_back_ios_new`) on iOS,
   `Icons.arrow_back` on Android. Preserve semantics label + 48×48 target.

7. **Scrollbar** — `AppScrollBehavior extends MaterialScrollBehavior`
   (`core/adaptive/app_scroll_behavior.dart`) overrides `buildScrollbar` to wrap
   scrollables in a fading `CupertinoScrollbar` on iOS/macOS and defers to
   `super` (Material default: no persistent scrollbar on touch) elsewhere. Set
   once on `MaterialApp.scrollBehavior` in `main.dart`, so it applies app-wide
   with no per-list wrapping. Verified there is no existing `Scrollbar` /
   `scrollBehavior` in `lib/`, so no double scrollbars, and Android is
   byte-identical (the subclass only overrides the iOS arm).

### D. Polish wins (approved extras)

- **Adaptive haptics** on the toggle/picker interactions where iOS users expect
  a selection tick and Material does not add one (light-impact on switch flips /
  action-sheet selection). Do **not** double up where Cupertino widgets already
  self-haptic, and route through the existing haptic conventions (notices
  already fire haptics — no call-site haptic alongside a notice).
- **Native selection feel:** confirm Material `TextField` already uses
  `cupertinoTextSelectionControls` on iOS (it does by default) — no change
  needed; documented here so it isn't "added" redundantly.
- **Rough-edge fixes:** while in each touched file, fix only *safe, small* UX
  gaps (e.g. a missing loading/empty state, an obvious a11y label omission).
  Each such fix is listed in the PR/summary; anything non-trivial is reported,
  not silently changed.

## Explicitly out of scope

- `CupertinoPageScaffold` / `CupertinoNavigationBar` / large-title nav bars.
- Rewriting Material `Scaffold`s or `AppTopBar`.
- Cupertino text fields, Cupertino tab bars, a `CupertinoApp` root.
- Bouncing scroll physics: already the Flutter default on iOS via
  `MaterialScrollBehavior`; no override exists to remove. Not a work item.

## Testing

- **Adaptive helpers** get widget tests that pump the same widget under
  `ThemeData(platform: TargetPlatform.iOS)` and `TargetPlatform.android` and
  assert the correct Cupertino vs Material subtree renders (e.g.
  `find.byType(CupertinoSwitch)` vs `find.byType(Switch)` internals,
  `CupertinoAlertDialog` vs `AlertDialog`). This is the core of the
  no-Android-regression guarantee.
- Reuse the existing `l10n` + `ThemeNotifier` test harness requirements
  (see `.claude/rules/testing.md`).
- `flutter analyze` clean; run the specific touched test files, not the full
  suite.
- Device verification note: swipe-back gesture, haptics, and the iOS spinners
  are device-only feel — verify on an iPhone (or simulator) via `flutter run`;
  the harness can't assert gesture/haptic feel.

## Risk & rollback

- Isolated `core/adaptive/` layer; each swap is independent and revertible.
- Highest-leverage / lowest-risk first: foundation → progress indicator →
  `showConfirmDialog` → action sheets → switches → refresh → back button →
  polish.
- No Firestore, rules, functions, or data-model changes. Pure UI.
