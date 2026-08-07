# Feature Tour (showcaseview) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Role-aware, per-tab guided tours (showcaseview package, Option A anchored-tooltip visual) that auto-run once per tab per device and are replayable from Settings.

**Architecture:** A new `lib/features/feature_tour/` feature with a pure step catalog (`tourStepsFor`), a SharedPreferences-backed seen-flag store (`tourSeenProvider`), a per-tab `FeatureTourHost` that registers an isolated showcaseview *scope* per hub tab (the `IndexedStack` keeps all tabs alive, so scopes must never share) and auto-starts the tour only when its tab is the hub's current destination, the flags are loaded, and the tab's data has settled. Each highlighted widget is wrapped in a themed `TourShowcase`.

**Tech Stack:** Flutter, showcaseview (v5-era `ShowcaseView.register(scope:)` API), Riverpod (manual style), SharedPreferences, gen_l10n (EN/FR).

**Spec:** `docs/archive/2026-07-22-feature-tour-design.md` (Option A visual recorded there; archived alongside this doc 2026-07-22).

**Key codebase facts an implementer must know:**

- The post-login shell is `HubShell` (`lib/routes/hub_shell.dart`): six tabs in an `IndexedStack`, all kept alive after first visit, hidden tabs have `TickerMode(enabled: false)`. Tab visibility is exposed by `HubShellScope` (`lib/core/layout/adaptive_shell.dart`) which carries `current` and notifies dependents on change.
- **Clients, Employees, History, and Live Map are admin-only tabs** (both the nav rail `_destinationsFor` and the settings drawer gate on `isAdmin`). Employees only ever see Calendar + Settings. Employee tours exist only for those two tabs.
- The calendar's add-appointment FAB (`heroTag: 'addFab'`, `main_calendar_screen.dart:379`) is admin-only. The clients FAB is `heroTag: 'clientsAddFab'` (`clients_screen.dart:89`), employees FAB `'employeesAddFab'` (`employees_screen.dart:276`), live-map FABs `'liveMapRosterFab'`/`'liveMapRecenterFab'` (`live_map_screen.dart:507/514`).
- `Scaffold.appBar`'s `bottom` slot requires a `PreferredSizeWidget` — a bare `Showcase` wrapper breaks it, hence the `TourShowcaseBar` adapter in Task 6.
- SharedPreferences-provider pattern to mirror: `LiveActivityPreferenceController` (`lib/features/live_activity/application/live_activity_preference.dart`) — optimistic default + `late final Future<void> ready`, and **anything acting on the value must await `ready` first**.
- ARB edits auto-trigger `flutter gen-l10n` via a hook — do NOT run it manually. Every EN key needs an `@key` metadata block or generation fails.
- `flutter pub get` after dependency changes may fail in the sandbox with a plugin-symlink error — re-run with sandbox disabled if so.

---

### Task 1: Add the dependency and verify its API surface

**Files:**
- Modify: `pubspec.yaml` (dependencies block)

- [ ] **Step 1: Add the package**

Run: `flutter pub add showcaseview`
Expected: resolves to the latest stable (5.x). If it resolves below 5.0.0, run `flutter pub add showcaseview:^5.0.0` — the scope API this plan uses (`ShowcaseView.register(scope:)`, `ShowcaseView.getNamed`) is v5-era.

- [ ] **Step 2: Verify the exact API names this plan relies on**

Open the resolved package source (`%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\showcaseview-<version>\lib\`) and confirm, adjusting later tasks if a name differs:
- `ShowcaseView.register({String scope, VoidCallback? onFinish, Function(GlobalKey?)? onDismiss, ...})` and `ShowcaseView.getNamed(String scope)` with `.startShowCase(List<GlobalKey>)`, `.dismiss()`, `.unregister()`.
- `Showcase` constructor params used in Task 6: `scope`, `title`, `description`, `titleTextStyle`, `descTextStyle`, `tooltipBackgroundColor`, `tooltipBorderRadius`, `tooltipPadding`, `targetBorderRadius`, `targetPadding`, `overlayColor`, `overlayOpacity`, `disableMovingAnimation`, `disableScaleAnimation`, `tooltipActions`, `tooltipActionConfig`.
- The action-button type enum: this plan writes `TooltipDefaultActionType.next/.skip`; older versions call it `TooltipActionButtonType`. Use whichever the installed version exports.
- The custom action constructor: this plan writes `TooltipActionButton.custom(button: ...)`; if the parameter is named differently (e.g. `widget`), use that name everywhere Task 6 uses it.
- **Lifecycle semantics — VERIFIED against showcaseview 5.1.0 (2026-07-22):**
  - `ShowcaseView.register(scope: x)` on an already-registered `x` silently REPLACES it (drops the old scope's controller map — mounted Showcase widgets bound to the old instance go dead until rebuilt). Hence Task 7 registers only in initState (before this subtree's Showcase widgets mount) and never re-registers at start time.
  - `ShowcaseView.getNamed(x)` on an unregistered `x` THROWS (plain `Exception`); it does not auto-create. Task 7 never unregisters, and wraps residual getNamed calls in try/catch.
  - `dismiss()` never throws when idle, but it DOES fire `onDismiss` (with a null key) even when no showcase is running — Task 7's `_tourRunning` gate is what prevents a phantom dismissal from marking an unseen tour as seen.

- [ ] **Step 3: Analyze + commit**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: no new issues.

```bash
git add pubspec.yaml pubspec.lock
git commit -m "Add showcaseview dependency for feature tours"
```

---

### Task 2: Pure step catalog (domain)

**Files:**
- Create: `lib/features/feature_tour/domain/tour_step_id.dart`
- Create: `lib/features/feature_tour/domain/tour_definitions.dart`
- Test: `test/features/feature_tour/domain/tour_definitions_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';

void main() {
  test('employee tours exist only for calendar and settings', () {
    for (final tab in AdaptiveDestination.values) {
      final steps = tourStepsFor(tab, isAdmin: false);
      if (tab == AdaptiveDestination.calendar ||
          tab == AdaptiveDestination.settings) {
        expect(steps, isNotEmpty, reason: '$tab should have an employee tour');
      } else {
        expect(steps, isEmpty, reason: '$tab is admin-only');
      }
    }
  });

  test('employee calendar tour has no admin-only steps', () {
    final steps = tourStepsFor(AdaptiveDestination.calendar, isAdmin: false);
    expect(steps, isNot(contains(TourStepId.calendarAddAppointment)));
  });

  test('admin calendar tour showcases booking', () {
    final steps = tourStepsFor(AdaptiveDestination.calendar, isAdmin: true);
    expect(steps, contains(TourStepId.calendarAddAppointment));
  });

  test('every admin tab has a tour and no catalog has duplicates', () {
    for (final tab in AdaptiveDestination.values) {
      final steps = tourStepsFor(tab, isAdmin: true);
      expect(steps, isNotEmpty, reason: '$tab should have an admin tour');
      expect(steps.toSet().length, steps.length,
          reason: '$tab catalog has duplicate steps');
    }
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/feature_tour/domain/tour_definitions_test.dart`
Expected: FAIL — files don't exist / functions undefined.

- [ ] **Step 3: Implement the domain files**

`lib/features/feature_tour/domain/tour_step_id.dart`:

```dart
/// One highlighted widget in a tab's feature tour. Step text is resolved in
/// the widget layer (`tourStepText`) so this stays pure and testable.
enum TourStepId {
  calendarGrid,
  calendarDayList,
  calendarAddAppointment,
  calendarDayRoute,
  clientsSearch,
  clientsAdd,
  employeesSearch,
  employeesAdd,
  historySearch,
  liveMapRoster,
  liveMapRecenter,
  settingsAppearance,
  settingsNotifications,
  settingsReplay,
}
```

`lib/features/feature_tour/domain/tour_definitions.dart`:

```dart
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';

/// The showcaseview scope name for a tab. Every hub tab registers its own
/// scope: the IndexedStack keeps all tabs mounted at once, so a shared scope
/// would mix hidden tabs' targets into the visible tab's tour.
String tourScopeName(AdaptiveDestination tab) => 'tour_${tab.name}';

/// Ordered step catalog for a tab and role. Clients/Employees/History/LiveMap
/// are admin-only tabs (see `_destinationsFor` in adaptive_shell.dart and the
/// settings drawer), so their employee catalogs are empty.
List<TourStepId> tourStepsFor(
  AdaptiveDestination tab, {
  required bool isAdmin,
}) => switch (tab) {
  AdaptiveDestination.calendar => [
    TourStepId.calendarGrid,
    TourStepId.calendarDayList,
    if (isAdmin) TourStepId.calendarAddAppointment,
    TourStepId.calendarDayRoute,
  ],
  AdaptiveDestination.clients => [
    if (isAdmin) ...[TourStepId.clientsSearch, TourStepId.clientsAdd],
  ],
  AdaptiveDestination.employees => [
    if (isAdmin) ...[TourStepId.employeesSearch, TourStepId.employeesAdd],
  ],
  AdaptiveDestination.history => [if (isAdmin) TourStepId.historySearch],
  AdaptiveDestination.liveMap => [
    if (isAdmin) ...[TourStepId.liveMapRoster, TourStepId.liveMapRecenter],
  ],
  AdaptiveDestination.settings => [
    TourStepId.settingsAppearance,
    TourStepId.settingsNotifications,
    TourStepId.settingsReplay,
  ],
};
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/feature_tour/domain/tour_definitions_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/feature_tour/domain test/features/feature_tour/domain
git commit -m "Add feature-tour step catalog with role-aware per-tab tours"
```

---

### Task 3: Seen-flag store (application)

**Files:**
- Create: `lib/features/feature_tour/application/tour_seen_store.dart`
- Test: `test/features/feature_tour/application/tour_seen_store_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/features/feature_tour/application/tour_seen_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  ProviderContainer newContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Keep the notifier alive across reads (project testing rule).
    c.listen(tourSeenProvider, (_, _) {});
    return c;
  }

  test('loads persisted tabs after ready resolves', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['calendar', 'settings'],
    });
    container = newContainer();
    await container.read(tourSeenProvider.notifier).ready;
    expect(
      container.read(tourSeenProvider),
      {AdaptiveDestination.calendar, AdaptiveDestination.settings},
    );
  });

  test('markSeen adds the tab and persists it', () async {
    SharedPreferences.setMockInitialValues({});
    container = newContainer();
    final notifier = container.read(tourSeenProvider.notifier);
    await notifier.ready;
    await notifier.markSeen(AdaptiveDestination.clients);
    expect(
      container.read(tourSeenProvider),
      contains(AdaptiveDestination.clients),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tour_seen_tabs'), contains('clients'));
  });

  test('resetAll clears state and storage', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['calendar'],
    });
    container = newContainer();
    final notifier = container.read(tourSeenProvider.notifier);
    await notifier.ready;
    await notifier.resetAll();
    expect(container.read(tourSeenProvider), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tour_seen_tabs'), isEmpty);
  });

  test('unknown stored names are ignored', () async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['calendar', 'no_such_tab'],
    });
    container = newContainer();
    await container.read(tourSeenProvider.notifier).ready;
    expect(container.read(tourSeenProvider), {AdaptiveDestination.calendar});
  });
}
```

- [ ] **Step 2: Run tests, verify FAIL**

Run: `flutter test test/features/feature_tour/application/tour_seen_store_test.dart`
Expected: FAIL — file/provider not defined.

- [ ] **Step 3: Implement the store**

`lib/features/feature_tour/application/tour_seen_store.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/logging/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key: names of hub tabs whose tour has been seen.
const _keyTourSeenTabs = 'tour_seen_tabs';

/// Which tabs' feature tours have already run on this device. Device-local by
/// design (a returning user on a new phone gets the tour again); sign-out does
/// NOT reset it — the Settings "Replay app tour" row is the only reset.
///
/// Mirrors [LiveActivityPreferenceController]: `build` returns an optimistic
/// empty set before the disk read finishes, so anything that *acts* on the
/// value (auto-starting a tour) MUST await [ready] first — the optimistic
/// "nothing seen" default would otherwise replay seen tours on cold start.
class TourSeenController extends Notifier<Set<AdaptiveDestination>> {
  late final Future<void> ready = _load();

  @override
  Set<AdaptiveDestination> build() {
    unawaited(ready);
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final names = prefs.getStringList(_keyTourSeenTabs) ?? const [];
      state = {
        for (final tab in AdaptiveDestination.values)
          if (names.contains(tab.name)) tab,
      };
    } catch (e, st) {
      // Fired unawaited from build(); default to "nothing seen" — the same
      // state a fresh install has.
      ref.read(loggerProvider).warn('TOUR read seen flags failed', e, st);
    }
  }

  Future<void> markSeen(AdaptiveDestination tab) async {
    state = {...state, tab};
    await _save();
  }

  Future<void> resetAll() async {
    state = const {};
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyTourSeenTabs, [
        for (final tab in state) tab.name,
      ]);
    } catch (e, st) {
      ref.read(loggerProvider).warn('TOUR write seen flags failed', e, st);
    }
  }
}

final tourSeenProvider =
    NotifierProvider<TourSeenController, Set<AdaptiveDestination>>(
      TourSeenController.new,
    );
```

- [ ] **Step 4: Run tests, verify PASS**

Run: `flutter test test/features/feature_tour/application/tour_seen_store_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/feature_tour/application test/features/feature_tour/application
git commit -m "Add device-local tour seen-flag store"
```

---

### Task 4: Expose the hub's current tab as a build dependency

**Files:**
- Modify: `lib/core/layout/adaptive_shell.dart` (the `HubShellScope` class, ~line 80)

- [ ] **Step 1: Add two static accessors to `HubShellScope`**

Below the existing `maybeOf`, add:

```dart
  /// The currently visible hub tab, as a build dependency: callers rebuild
  /// when the selection changes. Null outside a shell (standalone route,
  /// tests). Used by FeatureTourHost to start/stop a tab's tour.
  static AdaptiveDestination? currentOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<HubShellScope>()
      ?.current;

  /// One-shot read of the current tab (no rebuild dependency) — safe outside
  /// build, e.g. in a post-frame callback.
  static AdaptiveDestination? readCurrentOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<HubShellScope>()
      ?.current;
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add lib/core/layout/adaptive_shell.dart
git commit -m "Expose hub current tab from HubShellScope for tour gating"
```

---

### Task 5: Localization keys (EN + FR)

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_fr.arb`

- [ ] **Step 1: Add the EN keys (with @key metadata — required, generation fails without it)**

Append inside `app_en.arb` (before the closing brace, comma-separated like the neighbors). Reminder: paste real Unicode (don't let the editor write `\u` escapes):

```json
"tour_next": "Next",
"@tour_next": {"description": "Advance button on a feature-tour tooltip"},
"tour_skip": "Skip",
"@tour_skip": {"description": "Dismiss button ending a feature tour early"},
"tour_stepCounter": "{current} of {total}",
"@tour_stepCounter": {
  "description": "Position indicator on a feature-tour tooltip",
  "placeholders": {
    "current": {"type": "int"},
    "total": {"type": "int"}
  }
},
"tour_calendarGridTitle": "Your month at a glance",
"@tour_calendarGridTitle": {"description": "Tour step title: calendar month grid"},
"tour_calendarGridDesc": "Days with a dot have booked jobs. Tap a day to see its schedule below.",
"@tour_calendarGridDesc": {"description": "Tour step description: calendar month grid"},
"tour_calendarDayListTitle": "The day's schedule",
"@tour_calendarDayListTitle": {"description": "Tour step title: selected day's job list"},
"tour_calendarDayListDesc": "Jobs for the selected day. Tap one to open its details and photos.",
"@tour_calendarDayListDesc": {"description": "Tour step description: selected day's job list"},
"tour_calendarAddTitle": "Book a job",
"@tour_calendarAddTitle": {"description": "Tour step title: add-appointment FAB (admin)"},
"tour_calendarAddDesc": "Tap + to create an appointment, pick the client, and assign your team.",
"@tour_calendarAddDesc": {"description": "Tour step description: add-appointment FAB (admin)"},
"tour_calendarDayRouteTitle": "Day route",
"@tour_calendarDayRouteTitle": {"description": "Tour step title: day-route app bar action"},
"tour_calendarDayRouteDesc": "Open the day's jobs as one driving route in Google Maps.",
"@tour_calendarDayRouteDesc": {"description": "Tour step description: day-route app bar action"},
"tour_clientsSearchTitle": "Find a client",
"@tour_clientsSearchTitle": {"description": "Tour step title: clients search bar"},
"tour_clientsSearchDesc": "Search by name, phone, or address — results update as you type.",
"@tour_clientsSearchDesc": {"description": "Tour step description: clients search bar"},
"tour_clientsAddTitle": "Add a client",
"@tour_clientsAddTitle": {"description": "Tour step title: add-client FAB"},
"tour_clientsAddDesc": "Create a new client file. You can also add one while booking an appointment.",
"@tour_clientsAddDesc": {"description": "Tour step description: add-client FAB"},
"tour_employeesSearchTitle": "Find a team member",
"@tour_employeesSearchTitle": {"description": "Tour step title: employees search bar"},
"tour_employeesSearchDesc": "Search your staff by name or email.",
"@tour_employeesSearchDesc": {"description": "Tour step description: employees search bar"},
"tour_employeesAddTitle": "Invite an employee",
"@tour_employeesAddTitle": {"description": "Tour step title: invite-employee FAB"},
"tour_employeesAddDesc": "Create an invite with a one-time signup code to share with your new team member.",
"@tour_employeesAddDesc": {"description": "Tour step description: invite-employee FAB"},
"tour_historySearchTitle": "Search past jobs",
"@tour_historySearchTitle": {"description": "Tour step title: history search bar"},
"tour_historySearchDesc": "Completed and cancelled visits live here — search by client or employee, and filter by year.",
"@tour_historySearchDesc": {"description": "Tour step description: history search bar"},
"tour_liveMapRosterTitle": "Staff roster",
"@tour_liveMapRosterTitle": {"description": "Tour step title: live-map roster FAB"},
"tour_liveMapRosterDesc": "See everyone sharing their location, sorted by distance from you.",
"@tour_liveMapRosterDesc": {"description": "Tour step description: live-map roster FAB"},
"tour_liveMapRecenterTitle": "Recenter",
"@tour_liveMapRecenterTitle": {"description": "Tour step title: live-map recenter FAB"},
"tour_liveMapRecenterDesc": "Bring the map back to your team after panning around.",
"@tour_liveMapRecenterDesc": {"description": "Tour step description: live-map recenter FAB"},
"tour_settingsAppearanceTitle": "Make it yours",
"@tour_settingsAppearanceTitle": {"description": "Tour step title: settings appearance card"},
"tour_settingsAppearanceDesc": "Switch dark mode, text size, and language here.",
"@tour_settingsAppearanceDesc": {"description": "Tour step description: settings appearance card"},
"tour_settingsNotificationsTitle": "Notifications",
"@tour_settingsNotificationsTitle": {"description": "Tour step title: settings notifications card"},
"tour_settingsNotificationsDesc": "Check push permission and the on-the-road Live Activity card here.",
"@tour_settingsNotificationsDesc": {"description": "Tour step description: settings notifications card"},
"tour_settingsReplayTitle": "Replay this tour",
"@tour_settingsReplayTitle": {"description": "Tour step title: replay-tour settings row"},
"tour_settingsReplayDesc": "Tap here any time to see these tips again on every screen.",
"@tour_settingsReplayDesc": {"description": "Tour step description: replay-tour settings row"},
"settings_help": "Help",
"@settings_help": {"description": "Settings section header for help/tour actions"},
"settings_replayTour": "Replay app tour",
"@settings_replayTour": {"description": "Settings row that resets all feature-tour seen flags"},
"settings_replayTourDone": "Tour tips will show again.",
"@settings_replayTourDone": {"description": "Success notice after resetting the feature tours"}
```

- [ ] **Step 2: Add the FR keys (values only — FR carries no @metadata)**

Append inside `app_fr.arb`:

```json
"tour_next": "Suivant",
"tour_skip": "Passer",
"tour_stepCounter": "{current} de {total}",
"tour_calendarGridTitle": "Votre mois en un coup d'œil",
"tour_calendarGridDesc": "Les jours marqués d'un point ont des rendez-vous. Touchez un jour pour voir son horaire ci-dessous.",
"tour_calendarDayListTitle": "L'horaire du jour",
"tour_calendarDayListDesc": "Les travaux du jour sélectionné. Touchez-en un pour ouvrir ses détails et photos.",
"tour_calendarAddTitle": "Réserver un travail",
"tour_calendarAddDesc": "Touchez + pour créer un rendez-vous, choisir le client et assigner votre équipe.",
"tour_calendarDayRouteTitle": "Itinéraire du jour",
"tour_calendarDayRouteDesc": "Ouvrez les travaux de la journée comme un seul itinéraire dans Google Maps.",
"tour_clientsSearchTitle": "Trouver un client",
"tour_clientsSearchDesc": "Cherchez par nom, téléphone ou adresse — les résultats se mettent à jour pendant la saisie.",
"tour_clientsAddTitle": "Ajouter un client",
"tour_clientsAddDesc": "Créez une fiche client. Vous pouvez aussi en ajouter une pendant la réservation.",
"tour_employeesSearchTitle": "Trouver un membre de l'équipe",
"tour_employeesSearchDesc": "Cherchez votre personnel par nom ou courriel.",
"tour_employeesAddTitle": "Inviter un employé",
"tour_employeesAddDesc": "Créez une invitation avec un code unique à partager avec votre nouvel employé.",
"tour_historySearchTitle": "Chercher les anciens travaux",
"tour_historySearchDesc": "Les visites terminées et annulées sont ici — cherchez par client ou employé, et filtrez par année.",
"tour_liveMapRosterTitle": "Liste du personnel",
"tour_liveMapRosterDesc": "Voyez qui partage sa position, trié par distance.",
"tour_liveMapRecenterTitle": "Recentrer",
"tour_liveMapRecenterDesc": "Ramenez la carte sur votre équipe après l'avoir déplacée.",
"tour_settingsAppearanceTitle": "À votre goût",
"tour_settingsAppearanceDesc": "Changez le mode sombre, la taille du texte et la langue ici.",
"tour_settingsNotificationsTitle": "Notifications",
"tour_settingsNotificationsDesc": "Vérifiez la permission des notifications et la carte Live Activity ici.",
"tour_settingsReplayTitle": "Revoir cette visite",
"tour_settingsReplayDesc": "Touchez ici en tout temps pour revoir ces conseils sur chaque écran.",
"settings_help": "Aide",
"settings_replayTour": "Revoir la visite guidée",
"settings_replayTourDone": "Les conseils de la visite s'afficheront de nouveau."
```

- [ ] **Step 3: Verify generation + drift**

The ARB-edit hook regenerates `lib/l10n/.gen/`. Check `lib/l10n/.gen/untranslated.json` — the new keys must NOT appear (EN/FR in lockstep).

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_fr.arb
git commit -m "Add EN/FR strings for the feature tour"
```

---

### Task 6: Themed showcase wrappers (widgets)

**Files:**
- Create: `lib/features/feature_tour/widgets/tour_step_text.dart`
- Create: `lib/features/feature_tour/widgets/tour_showcase.dart`

- [ ] **Step 1: Implement the step-text resolver**

`lib/features/feature_tour/widgets/tour_step_text.dart` — an exhaustive switch, so adding a `TourStepId` without strings is a compile error:

```dart
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Localized title + description for a tour step.
({String title, String description}) tourStepText(
  AppLocalizations l,
  TourStepId id,
) => switch (id) {
  TourStepId.calendarGrid => (
    title: l.tour_calendarGridTitle,
    description: l.tour_calendarGridDesc,
  ),
  TourStepId.calendarDayList => (
    title: l.tour_calendarDayListTitle,
    description: l.tour_calendarDayListDesc,
  ),
  TourStepId.calendarAddAppointment => (
    title: l.tour_calendarAddTitle,
    description: l.tour_calendarAddDesc,
  ),
  TourStepId.calendarDayRoute => (
    title: l.tour_calendarDayRouteTitle,
    description: l.tour_calendarDayRouteDesc,
  ),
  TourStepId.clientsSearch => (
    title: l.tour_clientsSearchTitle,
    description: l.tour_clientsSearchDesc,
  ),
  TourStepId.clientsAdd => (
    title: l.tour_clientsAddTitle,
    description: l.tour_clientsAddDesc,
  ),
  TourStepId.employeesSearch => (
    title: l.tour_employeesSearchTitle,
    description: l.tour_employeesSearchDesc,
  ),
  TourStepId.employeesAdd => (
    title: l.tour_employeesAddTitle,
    description: l.tour_employeesAddDesc,
  ),
  TourStepId.historySearch => (
    title: l.tour_historySearchTitle,
    description: l.tour_historySearchDesc,
  ),
  TourStepId.liveMapRoster => (
    title: l.tour_liveMapRosterTitle,
    description: l.tour_liveMapRosterDesc,
  ),
  TourStepId.liveMapRecenter => (
    title: l.tour_liveMapRecenterTitle,
    description: l.tour_liveMapRecenterDesc,
  ),
  TourStepId.settingsAppearance => (
    title: l.tour_settingsAppearanceTitle,
    description: l.tour_settingsAppearanceDesc,
  ),
  TourStepId.settingsNotifications => (
    title: l.tour_settingsNotificationsTitle,
    description: l.tour_settingsNotificationsDesc,
  ),
  TourStepId.settingsReplay => (
    title: l.tour_settingsReplayTitle,
    description: l.tour_settingsReplayDesc,
  ),
};
```

- [ ] **Step 2: Implement `TourShowcase` + `TourShowcaseBar`**

`lib/features/feature_tour/widgets/tour_showcase.dart`. This is the Option A visual: surface bubble, r16 radius, arrow, "n of N" counter left, text Skip, filled primary Next pill; ~62% scrim; animations collapse under reduced motion. (If Task 1 found different names for `TooltipDefaultActionType` / `TooltipActionButton.custom(button:)`, use those here.)

```dart
import 'package:flutter/material.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/widgets/tour_step_text.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:showcaseview/showcaseview.dart';

/// One step of a tab's feature tour: wraps the highlighted widget in a themed
/// [Showcase] (design: Option A anchored tooltip — see
/// docs/plans/2026-07-22-feature-tour-design.md). [index]/[count] come from
/// the tab's `tourStepsFor` catalog so the counter matches the tour order.
class TourShowcase extends StatelessWidget {
  const TourShowcase({
    required this.showcaseKey,
    required this.tab,
    required this.id,
    required this.index,
    required this.count,
    required this.child,
    this.targetBorderRadius,
    super.key,
  });

  final GlobalKey showcaseKey;
  final AdaptiveDestination tab;
  final TourStepId id;
  final int index;
  final int count;

  /// Rounding of the lit target cutout; defaults to r12 (cards/tiles). FABs
  /// pass r16 to match their shape.
  final BorderRadius? targetBorderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = tourStepText(context.l10n, id);
    final noMotion = MediaQuery.disableAnimationsOf(context);
    return Showcase(
      key: showcaseKey,
      scope: tourScopeName(tab),
      title: text.title,
      description: text.description,
      titleTextStyle: theme.textTheme.titleMedium?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      descTextStyle: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      tooltipBackgroundColor: scheme.surface,
      tooltipBorderRadius: BorderRadius.circular(AppRadius.r16),
      tooltipPadding: const EdgeInsets.all(AppSpacing.sp16),
      targetBorderRadius:
          targetBorderRadius ?? BorderRadius.circular(AppRadius.r12),
      targetPadding: const EdgeInsets.all(AppSpacing.sp4),
      overlayColor: scheme.scrim,
      overlayOpacity: 0.62,
      disableMovingAnimation: noMotion,
      disableScaleAnimation: noMotion,
      tooltipActionConfig: const TooltipActionConfig(
        position: TooltipActionPosition.inside,
        alignment: MainAxisAlignment.spaceBetween,
        actionGap: AppSpacing.sp8,
      ),
      tooltipActions: [
        TooltipActionButton.custom(
          button: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sp8),
            child: Text(
              context.l10n.tour_stepCounter(index + 1, count),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        TooltipActionButton(
          type: TooltipDefaultActionType.skip,
          name: context.l10n.tour_skip,
          backgroundColor: Colors.transparent,
          textStyle: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        TooltipActionButton(
          type: TooltipDefaultActionType.next,
          name: context.l10n.tour_next,
          backgroundColor: scheme.primary,
          borderRadius: BorderRadius.circular(AppRadius.rFull),
          textStyle: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onPrimary,
          ),
        ),
      ],
      child: child,
    );
  }
}

/// [TourShowcase] adapter for `AppTopBar.bottom`, which requires a
/// [PreferredSizeWidget] — a bare Showcase wrapper would break the app-bar
/// layout contract.
class TourShowcaseBar extends StatelessWidget implements PreferredSizeWidget {
  const TourShowcaseBar({
    required this.showcaseKey,
    required this.tab,
    required this.id,
    required this.index,
    required this.count,
    required this.bar,
    super.key,
  });

  final GlobalKey showcaseKey;
  final AdaptiveDestination tab;
  final TourStepId id;
  final int index;
  final int count;
  final PreferredSizeWidget bar;

  @override
  Size get preferredSize => bar.preferredSize;

  @override
  Widget build(BuildContext context) => TourShowcase(
    showcaseKey: showcaseKey,
    tab: tab,
    id: id,
    index: index,
    count: count,
    child: bar,
  );
}
```

- [ ] **Step 3: Analyze + commit**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: clean (fix any param-name drift found in Task 1 now).

```bash
git add lib/features/feature_tour/widgets
git commit -m "Add themed TourShowcase wrappers (Option A anchored tooltip)"
```

---

### Task 7: FeatureTourHost (auto-start gating)

**Files:**
- Create: `lib/features/feature_tour/widgets/feature_tour_host.dart`
- Test: `test/features/feature_tour/widgets/feature_tour_host_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Notes for the harness: `FeatureTourHost` needs a `ProviderScope`, l10n delegates (TourShowcase children call `context.l10n`), and a `HubShellScope` ancestor. The showcase overlay animates, so prefer bounded `tester.pump(...)` calls over `pumpAndSettle` if the latter times out.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/features/feature_tour/application/tour_seen_store.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
import 'package:scheduling/features/feature_tour/widgets/tour_showcase.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeShell implements HubTabSelector {
  @override
  void select(
    AdaptiveDestination destination, {
    required bool isAdmin,
    required String employeeId,
    String userName = '',
    String userEmail = '',
  }) {}
}

void main() {
  Widget harness({
    required AdaptiveDestination current,
    required AdaptiveDestination tab,
    required Map<TourStepId, GlobalKey> stepKeys,
    required Widget child,
    required ProviderContainer container,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: HubShellScope(
          shell: _FakeShell(),
          current: current,
          child: FeatureTourHost(
            tab: tab,
            isAdmin: true,
            stepKeys: stepKeys,
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
  }

  ProviderContainer newContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(tourSeenProvider, (_, _) {});
    return c;
  }

  testWidgets('does not start while its tab is hidden', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = newContainer();
    final key = GlobalKey();
    await tester.pumpWidget(harness(
      current: AdaptiveDestination.calendar, // another tab is visible
      tab: AdaptiveDestination.clients,
      stepKeys: {TourStepId.clientsSearch: key},
      container: container,
      child: TourShowcase(
        showcaseKey: key,
        tab: AdaptiveDestination.clients,
        id: TourStepId.clientsSearch,
        index: 0,
        count: 2,
        child: const Text('target'),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Find a client'), findsNothing);
    expect(
      container.read(tourSeenProvider),
      isNot(contains(AdaptiveDestination.clients)),
    );
  });

  testWidgets('marks seen without starting when no target is mounted',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = newContainer();
    await tester.pumpWidget(harness(
      current: AdaptiveDestination.clients,
      tab: AdaptiveDestination.clients,
      stepKeys: {TourStepId.clientsSearch: GlobalKey()}, // never attached
      container: container,
      child: const Text('no showcase targets here'),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(
      container.read(tourSeenProvider),
      contains(AdaptiveDestination.clients),
    );
  });

  testWidgets('starts and shows the first step when visible and unseen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = newContainer();
    final searchKey = GlobalKey();
    final addKey = GlobalKey();
    await tester.pumpWidget(harness(
      current: AdaptiveDestination.clients,
      tab: AdaptiveDestination.clients,
      stepKeys: {
        TourStepId.clientsSearch: searchKey,
        TourStepId.clientsAdd: addKey,
      },
      container: container,
      child: Column(children: [
        TourShowcase(
          showcaseKey: searchKey,
          tab: AdaptiveDestination.clients,
          id: TourStepId.clientsSearch,
          index: 0,
          count: 2,
          child: const Text('search target'),
        ),
        TourShowcase(
          showcaseKey: addKey,
          tab: AdaptiveDestination.clients,
          id: TourStepId.clientsAdd,
          index: 1,
          count: 2,
          child: const Text('add target'),
        ),
      ]),
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Find a client'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets('does not start when already seen', (tester) async {
    SharedPreferences.setMockInitialValues({
      'tour_seen_tabs': ['clients'],
    });
    final container = newContainer();
    final key = GlobalKey();
    await tester.pumpWidget(harness(
      current: AdaptiveDestination.clients,
      tab: AdaptiveDestination.clients,
      stepKeys: {TourStepId.clientsSearch: key},
      container: container,
      child: TourShowcase(
        showcaseKey: key,
        tab: AdaptiveDestination.clients,
        id: TourStepId.clientsSearch,
        index: 0,
        count: 2,
        child: const Text('target'),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Find a client'), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests, verify FAIL**

Run: `flutter test test/features/feature_tour/widgets/feature_tour_host_test.dart`
Expected: FAIL — `FeatureTourHost` undefined.

- [ ] **Step 3: Implement the host**

`lib/features/feature_tour/widgets/feature_tour_host.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scheduling/core/layout/adaptive_shell.dart';
import 'package:scheduling/features/feature_tour/application/tour_seen_store.dart';
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:showcaseview/showcaseview.dart';

/// Owns one hub tab's feature tour: registers the tab's showcaseview scope,
/// auto-starts the tour exactly once when (a) the tab is the hub's current
/// destination, (b) its seen-flag is loaded AND unset, and (c) [ready] is
/// true (never showcase over a skeleton), and marks the tour seen on finish,
/// skip, or when zero targets survive the mounted-filter.
///
/// Outside a [HubShellScope] (standalone route, widget tests) the tour never
/// auto-starts. Hidden IndexedStack tabs never start: visibility is a build
/// dependency via [HubShellScope.currentOf]. Losing visibility while a tour
/// is RUNNING dismisses the overlay (which marks the tab seen — same
/// semantics as Skip); [_tourRunning] gates both the dismiss and the
/// mark-seen so a tour that never started can't be marked seen by a mere tab
/// switch, and the dismiss is deferred post-frame (overlay teardown must not
/// run during build).
class FeatureTourHost extends ConsumerStatefulWidget {
  const FeatureTourHost({
    required this.tab,
    required this.isAdmin,
    required this.stepKeys,
    required this.child,
    this.ready = true,
    super.key,
  });

  final AdaptiveDestination tab;
  final bool isAdmin;

  /// Gate for data-dependent tabs: pass `!isLoading` so the tour doesn't
  /// anchor onto skeleton content. Chrome-only tabs leave it true.
  final bool ready;

  /// The screen's stable per-step keys; ids missing from the tab's catalog
  /// are ignored, ids whose key has no mounted context are dropped at start.
  final Map<TourStepId, GlobalKey> stepKeys;

  final Widget child;

  @override
  ConsumerState<FeatureTourHost> createState() => _FeatureTourHostState();
}

class _FeatureTourHostState extends ConsumerState<FeatureTourHost> {
  bool _started = false;
  bool _wasVisible = false;

  /// True from startShowCase until onFinish/onDismiss. Gates the
  /// tab-switch dismiss AND the mark-seen: without it, dismissing a scope
  /// whose tour never started could fire onDismiss and permanently mark an
  /// unseen tour as seen.
  bool _tourRunning = false;

  String get _scope => tourScopeName(widget.tab);

  @override
  void initState() {
    super.initState();
    // register() REPLACES an existing scope of the same name (verified in
    // showcaseview 5.1.0) — that makes this safe on a hub identity-change
    // rebuild: the replacement State registers here, and this subtree's
    // Showcase widgets mount afterwards, binding to THIS registration.
    ShowcaseView.register(
      scope: _scope,
      onFinish: _onTourEnd,
      onDismiss: (_) => _onTourEnd(),
    );
  }

  @override
  void dispose() {
    // Deliberately NO unregister: on an identity-change rebuild the new
    // State's initState runs before this dispose finalizes, so unregistering
    // here would tear down the registration the replacement just made (and
    // getNamed on a torn-down scope throws). A stale registration is
    // harmless — the next register replaces it. Just close a live overlay.
    if (_tourRunning) {
      _tourRunning = false; // suppress _onTourEnd: unfinished, not seen
      try {
        ShowcaseView.getNamed(_scope).dismiss();
      } catch (_) {
        // Scope already replaced/gone — nothing to close.
      }
    }
    super.dispose();
  }

  /// Finish and dismiss both end the tour; only a tour that actually ran
  /// marks the tab seen.
  void _onTourEnd() {
    if (!_tourRunning) return;
    _tourRunning = false;
    _markSeen();
  }

  void _markSeen() {
    unawaited(ref.read(tourSeenProvider.notifier).markSeen(widget.tab));
  }

  @override
  Widget build(BuildContext context) {
    final seen = ref.watch(tourSeenProvider);
    final visible = HubShellScope.currentOf(context) == widget.tab;
    if (_wasVisible && !visible && _tourRunning) {
      // Tab switched away mid-tour: never leave the overlay over another
      // tab. Post-frame — overlay teardown (and the provider write its
      // onDismiss triggers) must not run during build. onDismiss then marks
      // this tab seen (switching away == skipping).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_tourRunning) return;
        try {
          ShowcaseView.getNamed(_scope).dismiss();
        } catch (_) {
          _tourRunning = false;
        }
      });
    }
    _wasVisible = visible;
    if (seen.contains(widget.tab)) {
      // Re-arm so a Settings "replay" reset can start the tour again.
      _started = false;
    } else if (visible && widget.ready && !_started) {
      _started = true;
      unawaited(_start());
    }
    return widget.child;
  }

  Future<void> _start() async {
    // Never act on the optimistic empty default — see TourSeenController.
    await ref.read(tourSeenProvider.notifier).ready;
    if (!mounted) return;
    if (ref.read(tourSeenProvider).contains(widget.tab)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Conditions may have changed across the await/frame boundary.
      if (HubShellScope.readCurrentOf(context) != widget.tab) return;
      final steps = tourStepsFor(widget.tab, isAdmin: widget.isAdmin);
      final keys = <GlobalKey>[
        for (final id in steps)
          if (widget.stepKeys[id]?.currentContext != null)
            widget.stepKeys[id]!,
      ];
      if (keys.isEmpty) {
        // Nothing to point at (layout variant, role) — don't retry forever.
        // Direct markSeen: _onTourEnd is only for tours that ran.
        _markSeen();
        return;
      }
      _tourRunning = true;
      try {
        ShowcaseView.getNamed(_scope).startShowCase(keys);
      } catch (_) {
        // getNamed throws if the scope vanished (shouldn't happen — nothing
        // unregisters — but a dead tour must not crash the tab).
        _tourRunning = false;
      }
    });
  }
}
```

- [ ] **Step 4: Run tests, verify PASS**

Run: `flutter test test/features/feature_tour/widgets/feature_tour_host_test.dart`
Expected: PASS (4 tests). If the "starts and shows" test can't find the tooltip text, add one more `await tester.pump(const Duration(seconds: 1));` (overlay entrance animation) before the expectations.

Note on the visibility re-check in `_start`: inside the hub, `readCurrentOf` returns the live tab. In the test harness the `HubShellScope` is static per pump, which still exercises both branches.

- [ ] **Step 5: Commit**

```bash
git add lib/features/feature_tour/widgets/feature_tour_host.dart test/features/feature_tour/widgets
git commit -m "Add FeatureTourHost with visibility, readiness, and seen gating"
```

---

### Task 8: Wire the Calendar tab

**Files:**
- Modify: `lib/features/calendar/screens/main_calendar_screen.dart`

- [ ] **Step 1: Add imports, keys, and catalog to the State**

Add imports:

```dart
import 'package:scheduling/features/feature_tour/domain/tour_definitions.dart';
import 'package:scheduling/features/feature_tour/domain/tour_step_id.dart';
import 'package:scheduling/features/feature_tour/widgets/feature_tour_host.dart';
import 'package:scheduling/features/feature_tour/widgets/tour_showcase.dart';
```

Add fields to the calendar screen State (near the other fields):

```dart
  late final List<TourStepId> _tourSteps = tourStepsFor(
    AdaptiveDestination.calendar,
    isAdmin: widget.isAdmin,
  );
  late final Map<TourStepId, GlobalKey> _tourKeys = {
    for (final id in _tourSteps) id: GlobalKey(),
  };
```

And a small helper method (used by every wrap below):

```dart
  Widget _tourStep(
    TourStepId id, {
    required Widget child,
    BorderRadius? targetBorderRadius,
  }) => TourShowcase(
    showcaseKey: _tourKeys[id]!,
    tab: AdaptiveDestination.calendar,
    id: id,
    index: _tourSteps.indexOf(id),
    count: _tourSteps.length,
    targetBorderRadius: targetBorderRadius,
    child: child,
  );
```

Note: `_upgradeIfAdmin` triggers a full screen rebuild via a key change in `HubShell` (`_screenFor`'s `ValueKey` includes `isAdmin`), so a live role upgrade recreates this State and the `late final` catalog is safe.

- [ ] **Step 2: Wrap the Scaffold in the host**

In `build` (~line 299), wrap the returned `Scaffold` — `data.isLoading` is already in scope from `_prepareBuild`:

```dart
    return FeatureTourHost(
      tab: AdaptiveDestination.calendar,
      isAdmin: widget.isAdmin,
      ready: !data.isLoading,
      stepKeys: _tourKeys,
      child: Scaffold(
        // ...existing Scaffold unchanged...
      ),
    );
```

- [ ] **Step 3: Wrap the four targets**

1. **Add FAB** — in `_addAppointmentFab` (~line 377), wrap the `FloatingActionButton` (keep the admin null-return above it):

```dart
    return _tourStep(
      TourStepId.calendarAddAppointment,
      targetBorderRadius: BorderRadius.circular(AppRadius.r16),
      child: FloatingActionButton(
        heroTag: 'addFab',
        // ...unchanged...
      ),
    );
```

2. **Day-route icon** — in `_appBarActions` (~line 355), wrap the first `IconButton`:

```dart
    _tourStep(
      TourStepId.calendarDayRoute,
      targetBorderRadius: BorderRadius.circular(AppRadius.rFull),
      child: IconButton(
        icon: Icon(Icons.alt_route_rounded, color: scheme.onPrimary),
        // ...unchanged...
      ),
    ),
```

3. **Month grid** — `_buildCalendar` (~line 392): change its return type from `AppCalendar` to `Widget` and wrap:

```dart
  Widget _buildCalendar(Map<String, Color> colorMap, double rowHeight) =>
      _tourStep(
        TourStepId.calendarGrid,
        child: AppCalendar(
          // ...unchanged args...
        ),
      );
```

4. **Day list** — in `_content` (~line 409), wrap the `EventList` (change the local's type to `Widget`):

```dart
    final Widget eventList = _tourStep(
      TourStepId.calendarDayList,
      child: EventList(
        // ...unchanged args...
      ),
    );
```

- [ ] **Step 4: Analyze + run calendar tests**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Run: `flutter test test/features/calendar/`
Expected: clean / all pass. (Standalone-hosted calendar screens in tests have no `HubShellScope`, so no tour auto-starts.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/screens/main_calendar_screen.dart
git commit -m "Wire the calendar tab feature tour"
```

---

### Task 9: Wire Clients, Employees, and History

**Files:**
- Modify: `lib/features/clients/screens/clients_screen.dart`
- Modify: `lib/features/employees/screens/employees_screen.dart`
- Modify: `lib/features/clients/screens/history_screen.dart`

Each screen follows the identical pattern: add the same four imports as Task 8 **plus `package:scheduling/core/theme/design_tokens.dart` if the screen doesn't already import it** (the FAB wraps use `AppRadius`; `clients_screen.dart` and `history_screen.dart` currently don't import it — the calendar screen already does), add `_tourSteps`/`_tourKeys`/`_tourStep` fields (with the screen's own `AdaptiveDestination` and `isAdmin: widget.isAdmin`), wrap the `Scaffold` in `FeatureTourHost` (`ready` stays default `true` — every target is chrome), and wrap the targets. The `_tourStep` helper is three lines of indirection per screen — deliberate repetition (rule: three similar lines beat a helper shared across features).

- [ ] **Step 1: Clients screen**

State additions (mirror Task 8 Step 1 with `AdaptiveDestination.clients`). Then in `build` (line 66):

- Wrap the `Scaffold` return in `FeatureTourHost(tab: AdaptiveDestination.clients, isAdmin: widget.isAdmin, stepKeys: _tourKeys, child: Scaffold(...))`.
- Search bar (line 72) — replace the `bottom:` value with a `TourShowcaseBar`:

```dart
        bottom: TourShowcaseBar(
          showcaseKey: _tourKeys[TourStepId.clientsSearch]!,
          tab: AdaptiveDestination.clients,
          id: TourStepId.clientsSearch,
          index: _tourSteps.indexOf(TourStepId.clientsSearch),
          count: _tourSteps.length,
          bar: AppSearchBar(
            textScaler: MediaQuery.textScalerOf(context),
            controller: _searchController,
            hintText: context.l10n.clients_searchByNameOrPhone,
          ),
        ),
```

- FAB (line 83) — inside the existing `widget.isAdmin ?` branch, wrap the `FloatingActionButton` (heroTag `'clientsAddFab'`) in `_tourStep(TourStepId.clientsAdd, targetBorderRadius: BorderRadius.circular(AppRadius.r16), child: ...)`.

Caveat: for an employee, `_tourSteps` is EMPTY (`_tourSteps.indexOf` would be -1 and `_tourKeys[...]!` would throw) — but the clients tab is unreachable for employees, and to keep the build technically safe for any stray standalone hosting, guard the bar wrap on the catalog:

```dart
        bottom: _tourSteps.contains(TourStepId.clientsSearch)
            ? TourShowcaseBar(/* as above */)
            : AppSearchBar(
                textScaler: MediaQuery.textScalerOf(context),
                controller: _searchController,
                hintText: context.l10n.clients_searchByNameOrPhone,
              ),
```

(The FAB needs no guard — it's already inside `widget.isAdmin ?`.)

- [ ] **Step 2: Employees screen**

Same pattern with `AdaptiveDestination.employees`. Targets: the `AppSearchBar` in the `AppTopBar` `bottom:` slot (~line 127) → `TourShowcaseBar` with `TourStepId.employeesSearch` (same catalog-contains guard as clients); the `FloatingActionButton` with `heroTag: 'employeesAddFab'` (~line 271, already admin-gated) → `_tourStep(TourStepId.employeesAdd, targetBorderRadius: BorderRadius.circular(AppRadius.r16), child: ...)`. Wrap the `Scaffold` in the host.

- [ ] **Step 3: History screen**

Same pattern with `AdaptiveDestination.history`; single target: the `AppSearchBar` (line 52) → `TourShowcaseBar` with `TourStepId.historySearch` plus the catalog-contains guard. Wrap the `Scaffold` (line 47) in the host.

- [ ] **Step 4: Analyze + targeted tests + commit**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Run: `flutter test test/features/clients/ test/features/employees/`
Expected: clean / pass.

```bash
git add lib/features/clients lib/features/employees
git commit -m "Wire clients, employees, and history feature tours"
```

---

### Task 10: Wire the Live Map

**Files:**
- Modify: `lib/features/presence/screens/live_map_screen.dart`

- [ ] **Step 1: State additions**

Same imports + `_tourSteps`/`_tourKeys`/`_tourStep` fields as Task 8, with `AdaptiveDestination.liveMap`. Wrap the screen's `Scaffold` (the one whose `appBar:` is at ~line 119) in `FeatureTourHost(tab: AdaptiveDestination.liveMap, isAdmin: widget.isAdmin, stepKeys: _tourKeys, child: ...)`.

- [ ] **Step 2: Wrap the two FABs**

The FABs live in the private bottom-right FAB-stack widget at the end of the file (contains `heroTag: 'liveMapRosterFab'` at ~line 507 and `'liveMapRecenterFab'` at ~line 514), which is a separate widget class — it can't reach the State's keys. Add two optional wrapper params to that widget:

```dart
  final Widget Function(Widget child)? rosterTourWrap;
  final Widget Function(Widget child)? recenterTourWrap;
```

apply them around the two `FloatingActionButton.small`s:

```dart
          (rosterTourWrap ?? (w) => w)(
            FloatingActionButton.small(
              heroTag: 'liveMapRosterFab',
              // ...unchanged...
            ),
          ),
```

and pass them from the screen State where the widget is constructed (~line 443, beside `onOpenRoster: _openRoster`):

```dart
            rosterTourWrap: (child) => _tourStep(
              TourStepId.liveMapRoster,
              targetBorderRadius: BorderRadius.circular(AppRadius.r16),
              child: child,
            ),
            recenterTourWrap: (child) => _tourStep(
              TourStepId.liveMapRecenter,
              targetBorderRadius: BorderRadius.circular(AppRadius.r16),
              child: child,
            ),
```

(If the FAB stack turns out to be built inline in the State rather than a separate class, skip the params and wrap directly with `_tourStep`.)

- [ ] **Step 3: Analyze + commit**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Run: `flutter test test/features/presence/`
Expected: clean / pass.

```bash
git add lib/features/presence
git commit -m "Wire the live map feature tour"
```

---

### Task 11: Wire Settings + the "Replay app tour" row

**Files:**
- Modify: `lib/features/settings/screens/settings_screen.dart`
- Test: `test/features/settings/replay_tour_row_test.dart` (create)

- [ ] **Step 1: State additions**

Same imports + fields as Task 8, with `AdaptiveDestination.settings` and `isAdmin: widget.role == 'admin'` (this screen carries role as a string). Settings tours run for BOTH roles (catalog is role-independent for this tab). Wrap the screen's `Scaffold` in `FeatureTourHost(tab: AdaptiveDestination.settings, isAdmin: widget.role == 'admin', stepKeys: _tourKeys, child: ...)`.

Also import the store + notice service:

```dart
import 'package:scheduling/features/feature_tour/application/tour_seen_store.dart';
```

(`noticeServiceProvider` is already imported by this screen; if not, add its import.)

- [ ] **Step 2: Add the Help section with the replay row**

In `_buildMaster` (~line 205), after `_legalCard(scheme)` and before the version footer, insert:

```dart
        const SizedBox(height: AppSpacing.sp24),
        SettingsSectionHeader(
          label: context.l10n.settings_help.toUpperCase(),
        ),
        _helpCard(scheme),
```

New methods (beside `_legalCard`):

```dart
  Widget _helpCard(ColorScheme scheme) {
    return SettingsSectionCard(
      child: _tourStep(
        TourStepId.settingsReplay,
        child: SettingsTile(
          iconBg: scheme.primaryContainer,
          icon: Icons.tour_rounded,
          iconColor: scheme.primary,
          label: context.l10n.settings_replayTour,
          isLast: true,
          onTap: _onReplayTour,
        ),
      ),
    );
  }

  Future<void> _onReplayTour() async {
    await ref.read(tourSeenProvider.notifier).resetAll();
    if (!mounted) return;
    ref
        .read(noticeServiceProvider)
        .success(context.l10n.settings_replayTourDone);
  }
```

Note: because the user is on the Settings tab when tapping this, the reset immediately re-arms `FeatureTourHost` and the Settings tour restarts on the spot — that's intended feedback, not a bug.

- [ ] **Step 3: Wrap the two other step targets**

In `_buildMaster`, wrap the appearance and notifications cards:

```dart
        _tourStep(
          TourStepId.settingsAppearance,
          child: _appearanceCard(scheme, notifier, langCode: langCode),
        ),
        // ...
        _tourStep(
          TourStepId.settingsNotifications,
          child: _notificationsCard(scheme),
        ),
```

- [ ] **Step 4: Write the replay-row test**

`test/features/settings/replay_tour_row_test.dart` — mirror the harness of the existing settings screen tests in `test/features/settings/` (they already set up `FlutterSecureStorage.setMockInitialValues({})`, `PackageInfo.setMockInitialValues(...)`, `ProviderScope`, `ThemeNotifier`, and l10n delegates — copy that scaffolding):

```dart
    testWidgets('replay row clears the tour seen flags and notifies',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'tour_seen_tabs': ['calendar', 'settings'],
      });
      // ...pump SettingsScreen with the existing harness...
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Replay app tour'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Replay app tour'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('tour_seen_tabs'), isEmpty);
    });
```

(No `HubShellScope` in the harness → the settings tour cannot auto-start and pollute the test.)

- [ ] **Step 5: Run tests, analyze, commit**

Run: `flutter test test/features/settings/`
Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: pass / clean.

```bash
git add lib/features/settings test/features/settings
git commit -m "Wire the settings tour and add the replay app tour row"
```

---

### Task 12: Docs, full suite, device checklist

**Files:**
- Modify: `docs/plans/2026-07-22-feature-tour-design.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Correct the design doc's role assumption**

In the design doc's "Draft step catalogs" section, replace the employee mentions for Clients/Employees/History with a note reflecting reality: *"Clients, Employees, History, and Live Map are admin-only tabs (rail + drawer both gate on isAdmin) — employees get tours only on Calendar and Settings."*

- [ ] **Step 2: Add the CLAUDE.md invariant bullet**

Under "Critical invariants", add:

```markdown
- **Feature tours (`lib/features/feature_tour/`, showcaseview):** each hub tab
  registers its OWN showcaseview scope (`tourScopeName`) — the hub IndexedStack
  keeps every tab mounted, so a shared scope would mix hidden tabs' targets
  into the visible tour. `FeatureTourHost` is the only start path: it gates on
  HubShellScope.currentOf (hidden tabs never start), awaits
  `tourSeenProvider.ready` before acting (the optimistic empty default would
  replay seen tours on cold start), and drops steps whose key isn't mounted
  (zero survivors → mark seen, never crash/retry). Step catalogs are pure
  (`tourStepsFor`); Clients/Employees/History/LiveMap are admin-only tabs, so
  their employee catalogs are empty. Seen flags are device-local
  SharedPreferences ONLY (`tour_seen_tabs`); sign-out does not reset them —
  the Settings "Replay app tour" row is the only reset.
```

- [ ] **Step 3: Full verification**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: clean.
Run: `flutter test`
Expected: full suite green (was 1020 pre-change).

- [ ] **Step 4: Commit**

```bash
git add docs/plans/2026-07-22-feature-tour-design.md CLAUDE.md
git commit -m "Document feature-tour invariants and correct design doc roles"
```

- [ ] **Step 5: Device verification checklist (flutter run on the Android dev device — overlay rendering is device-only)**

1. Fresh state (`adb shell pm clear net.vogas.scheduling`, sign in as ADMIN): calendar tour auto-starts after data loads — grid → day list → + FAB → day-route icon; counter reads 1 of 4; Next advances; last Next ends it.
2. Re-open the calendar tab: tour does NOT replay.
3. Visit Clients / Employees / History / Live Map / Settings: each tour runs once (2 / 2 / 1 / 2 / 3 steps).
4. Skip on step 1 of a tour → tour ends, never replays on revisit.
5. Switch tabs mid-tour (start clients tour, tap rail → calendar): overlay closes, clients marked seen.
6. Settings → Replay app tour: notice appears, Settings tour restarts immediately; other tabs replay on next visit.
7. Employee account: only Calendar (3 steps, no + FAB step) and Settings tours; nothing on other surfaces.
8. Landscape/split layout: tours still anchor correctly (rail instead of drawer changes no targets).
9. Dark mode: tooltip surfaces/text legible.
10. Accessibility: enable "remove animations" (or Reduce Motion on iOS later) → overlay appears instantly; text scale 2.0 → tooltip text wraps, buttons reachable.

---

## Self-review notes (already applied)

- Spec coverage: per-tab role-aware tours (Tasks 2, 8–11), first-visit auto-start + data-settle + visibility gating (Task 7), skip-marks-seen (Task 7 onDismiss), Settings replay (Task 11), EN/FR l10n (Task 5), reduced-motion + theming (Task 6), pure/controller/widget tests (Tasks 2, 3, 7, 11), device verification (Task 12). Design-doc divergence (employee tabs) is corrected by Task 12 rather than silently ignored.
- Type consistency: `tourStepsFor(tab, {required bool isAdmin})`, `tourScopeName(tab)`, `tourSeenProvider` / `TourSeenController.ready/markSeen/resetAll`, `TourShowcase(showcaseKey:, tab:, id:, index:, count:, targetBorderRadius:, child:)`, `TourShowcaseBar(..., bar:)`, `FeatureTourHost(tab:, isAdmin:, ready:, stepKeys:, child:)`, `HubShellScope.currentOf/readCurrentOf` — used with these exact names throughout.
- Known API risk is isolated in Task 1 Step 2 (enum name `TooltipDefaultActionType` vs `TooltipActionButtonType`; custom-action param name; register/getNamed/dismiss lifecycle semantics) with explicit instructions to reconcile once against the resolved package version.
- Review pass 2 (2026-07-22) fixed three host defects before implementation:
  (1) an unconditional tab-switch `dismiss()` could fire `onDismiss` for a
  tour that never started and permanently mark it seen — now gated by
  `_tourRunning` (Task 1 verification later CONFIRMED dismiss() fires
  onDismiss with a null key even when idle); (2) `dismiss()` ran during
  `build` (overlay teardown + provider write mid-build) — now deferred
  post-frame; (3) on a hub identity change the replacement State's
  `initState` runs before the old `dispose` finalizes, so the old unregister
  could kill the new scope registration. After Task 1's package verification
  (register REPLACES an existing scope and drops its controller bindings;
  getNamed THROWS on a missing scope), fix (3) became: register in initState
  only (replace semantics + Showcase children mount after initState), NEVER
  unregister, and dismiss-if-running in dispose with `_tourRunning` zeroed
  first (sign-out mid-tour leaves the tour unseen, so it replays).
