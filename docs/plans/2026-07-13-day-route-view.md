# Employee Day-Route View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status: IMPLEMENTED 2026-07-13 (Tasks 1–5) on branch `notification` — analyzer
clean, 9 new widget tests + 169 calendar tests green. Task 6 (device pass) still
pending on the Android dev device.**

**Goal:** A "Day route" screen showing an employee's jobs for a chosen day as
a numbered route timeline, with one-tap navigation per stop (existing map
chooser) and a pinned bottom button that opens the remaining stops as a
multi-stop Google Maps route; admins pick which employee to view.

**Architecture:** A standalone pushed route (dashboard pattern — NOT a new hub
tab) reached from an app-bar action on the calendar. It reuses
`myAppointmentsProvider` for the day's data (the `employeeIds` visibility
invariant is enforced by the underlying query), `AppointmentCard` for rows,
`AddressMapLauncher` per stop, and a new pure Google-Maps-directions URL
builder + launcher for the full route. **Zero new APIs, zero billing** — drive
times stay out of scope (that's the travel-time-notifications plan).

**Tech Stack:** Flutter/Dart, Riverpod, `url_launcher` (already a dep,
`pubspec.yaml:54`), `gen_l10n`.

---

## Context

### Decisions made with the user (2026-07-13)

- Ordered list + hand-off to the maps app; **no in-app map SDK**.
- No drive-time estimates in v1 (Routes API is the travel-time plan's job).
- Admins get an employee picker on the same screen.

### UI decision — mockup Option B chosen (2026-07-13)

Mockup artifact (3 options rendered, user picked B "numbered route timeline",
no grafts; refined render shows employee + admin views):
<https://claude.ai/code/artifact/4f79ba5d-6175-495b-afd2-1410a313dec4>

- **Timeline layout:** stops sit on a left rail — a numbered circular badge
  (employee color background, white number) per OPEN stop, a dimmed ✓ badge
  (success container colors) for Complete stops, connected by a 2 px
  outline-colored line. Numbering counts only open stops in time order (the
  route button launches the addressed subset of those).
- **Route action is a pinned bottom `FilledButton.icon`** ("Open route in
  Google Maps (N)"), NOT an app-bar icon. Disabled when no open stop has an
  address.
- **Per-stop navigate is an in-card tonal pill** (`primarySurface` background,
  primary text, route icon) below the meta rows — not a trailing IconButton.
- Complete stops keep their full card at 62 % opacity; cancelled never render.

### Key design findings (from codebase research)

- `myAppointmentsProvider` (`appointments_providers.dart:43`) takes a
  structural record key `(employeeId: String, range: AppointmentDateRange)` —
  the alias is library-private but records are structural, so any caller can
  build the literal. The backing query
  (`firebase_appointments_repository.dart:376`) is `employeeIds arrayContains`
  + `startTime` range + `orderBy startTime` — **already day-filterable and
  sorted**, and satisfies the employee-visibility rules via its constraints.
  Admins can watch it too (admin read clause) with any employee's id — so ONE
  provider serves both roles; no client-side filtering.
- `AppointmentDateRange` (`appointment_record.dart:109`) has a public
  `{start, end}` constructor — a single day is
  `AppointmentDateRange(start: dayStart, end: dayStart.add(Duration(days: 1)))`.
- `AddressMapLauncher.showMapChoices(context, address:)`
  (`address_map_launcher.dart`) is the existing single-stop chooser
  (Apple/Google/Waze) — reuse per row. It is single-address only; the
  multi-stop URL is new.
- Multi-stop format:
  `https://www.google.com/maps/dir/?api=1&destination=<last>&waypoints=<a>|<b>&travelmode=driving`.
  Google Maps (app + web, both platforms) caps waypoints at **9** (10 stops
  incl. destination). Apple Maps has no multi-stop URL — per-row navigation
  covers Apple users; the route button is Google-Maps-targeted by design.
- Clean each stop with `AddressParser.splitApt(addr)?.street ?? addr` exactly
  as `AddressMapLauncher` does.
- Route registration template: the `dashboard` case in
  `lib/routes/app_routes.dart:36-40` (`AppPageRoute`); typed args classes live
  at the bottom of the same file (lines 162-197).
- Entry point: `AppTopBar.actions` in `main_calendar_screen.dart` (line 295);
  `MainCalendar` already holds `{isAdmin, employeeId}` to forward.
- Row widget: `AppointmentCard{appointment, employeeColor, employeeName?,
  onTap}`; colors/names from `employeeColorMapProvider` /
  `employeeNameMapProvider` (`employees_providers.dart:56-60`); active-staff
  picker data from `employeesStreamProvider` (line 64).
- Detail sheet: `showEventDetails(context, appointment)`
  (`calendar/utils/sheet_helpers.dart:24`).
- Launcher template with notice-based errors: `launchWebUrl`
  (`lib/core/launchers/web_url_launcher.dart`).
- A standalone pushed route with ONE `ListView` does **not** need
  `PrimaryScrollScope`.

### Behavior rules

- The **timeline** shows every non-cancelled job for the day (including `done`
  — seeing the finished part of the day is useful). Open stops get numbered
  badges (1..N, start-time order); Complete stops get a dimmed ✓ badge and a
  62 %-opacity card.
- The **route button** includes only open stops: `pending` / `in_progress` /
  legacy `confirmed`, with a non-empty address, in start-time order, capped at
  10 stops (Google's limit) — when capped, an info notice says the route was
  truncated. Its label carries the launched stop count.
- Stops without an address (noFixedAddress clients) show no navigate pill and
  are excluded from the route button's set and count — but still get a number
  (they're still a job to drive to; the address just isn't recorded).

---

### Task 1: Pure route-URL builder (TDD)

**Files:**
- Create: `lib/features/maps/domain/route_url_builder.dart`
- Test: `test/features/maps/domain/route_url_builder_test.dart`

- [ ] **Step 1: Failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/maps/domain/route_url_builder.dart';

void main() {
  test('single stop becomes destination only', () {
    final uri = buildGoogleMapsRouteUrl(['12 Main St, Gatineau']);
    expect(uri, isNotNull);
    expect(uri!.queryParameters['destination'], '12 Main St, Gatineau');
    expect(uri.queryParameters.containsKey('waypoints'), isFalse);
  });

  test('multiple stops: last is destination, rest are ordered waypoints', () {
    final uri = buildGoogleMapsRouteUrl(['A St', 'B St', 'C St'])!;
    expect(uri.queryParameters['destination'], 'C St');
    expect(uri.queryParameters['waypoints'], 'A St|B St');
    expect(uri.queryParameters['travelmode'], 'driving');
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/dir/');
  });

  test('blank stops are skipped; all blank returns null', () {
    final uri = buildGoogleMapsRouteUrl(['  ', 'B St', ''])!;
    expect(uri.queryParameters['destination'], 'B St');
    expect(buildGoogleMapsRouteUrl(['', '  ']), isNull);
    expect(buildGoogleMapsRouteUrl(const []), isNull);
  });

  test('apartment suffix is stripped like AddressMapLauncher', () {
    final uri = buildGoogleMapsRouteUrl(['12 Main St apt 4, Gatineau'])!;
    expect(uri.queryParameters['destination'], isNot(contains('apt')));
  });

  test('caps at 10 stops', () {
    final stops = List.generate(14, (i) => 'Stop $i');
    final uri = buildGoogleMapsRouteUrl(stops)!;
    expect(uri.queryParameters['destination'], 'Stop 9');
    expect(uri.queryParameters['waypoints']!.split('|'), hasLength(9));
  });
}
```

(Adjust the apt-strip assertion to whatever `AddressParser.splitApt` actually
produces for that input — read `lib/features/maps/domain/address_parser.dart`
first and use a fixture it demonstrably splits.)

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/maps/domain/route_url_builder_test.dart`
Expected: FAIL (function missing).

- [ ] **Step 3: Implement**

```dart
import 'package:scheduling/features/maps/domain/address_parser.dart';

/// Google Maps caps directions URLs at 9 waypoints + 1 destination.
const int maxRouteStops = 10;

/// Builds a Google Maps directions URL through [addresses] in order, or null
/// when no usable stop remains. Apple Maps has no multi-stop URL scheme —
/// per-stop navigation covers those users.
Uri? buildGoogleMapsRouteUrl(List<String> addresses) {
  final stops = addresses
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty)
      .map((a) => AddressParser.splitApt(a)?.street ?? a)
      .take(maxRouteStops)
      .toList();
  if (stops.isEmpty) return null;
  final destination = stops.removeLast();
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': destination,
    if (stops.isNotEmpty) 'waypoints': stops.join('|'),
    'travelmode': 'driving',
  });
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/maps/domain/route_url_builder_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/maps/domain/route_url_builder.dart test/features/maps/domain/route_url_builder_test.dart
git commit -m "feat: multi-stop Google Maps route URL builder"
```

---

### Task 2: Route launcher

**Files:**
- Create: `lib/core/launchers/route_map_launcher.dart`

- [ ] **Step 1: Implement (modeled verbatim on `web_url_launcher.dart`)**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:scheduling/core/notices/notice_service.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Opens a prebuilt Google Maps directions [uri] in the external maps app.
/// Errors surface through the notice overlay (never a SnackBar).
Future<void> launchGoogleMapsRoute(
  BuildContext context,
  WidgetRef ref,
  Uri uri,
) async {
  final l10n = context.l10n;
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      ref.read(noticeServiceProvider).error(l10n.error_couldNotOpenMapApp);
    }
  } catch (_) {
    ref.read(noticeServiceProvider).error(l10n.error_couldNotOpenMapApp);
  }
}
```

(`error_couldNotOpenMapApp` already exists — reused from
`AddressMapLauncher`.)

- [ ] **Step 2: Verify + commit**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"` → clean.

```bash
git add lib/core/launchers/route_map_launcher.dart
git commit -m "feat: google maps route launcher"
```

---

### Task 3: l10n keys

**Files:**
- Modify: `lib/l10n/app_en.arb` + `lib/l10n/app_fr.arb` (lockstep; the on-save
  hook runs gen-l10n)

- [ ] **Step 1: Add keys**

`app_en.arb`:

```json
"calendar_dayRouteTitle": "Day route",
"@calendar_dayRouteTitle": {
  "description": "App bar title of the day-route screen"
},
"calendar_dayRouteOpenInMaps": "Open route in Google Maps ({count})",
"@calendar_dayRouteOpenInMaps": {
  "description": "Label of the pinned bottom button opening the remaining stops as a multi-stop route; count is the number of launched stops",
  "placeholders": {
    "count": {"type": "int"}
  }
},
"calendar_dayRouteNavigate": "Navigate",
"@calendar_dayRouteNavigate": {
  "description": "Label of the per-stop navigate pill on the day-route timeline"
},
"calendar_dayRouteEmptyTitle": "No jobs this day",
"@calendar_dayRouteEmptyTitle": {
  "description": "Empty-state title when the selected day has no visits"
},
"calendar_dayRouteEmptyBody": "Jobs scheduled for this day will appear here in driving order.",
"@calendar_dayRouteEmptyBody": {
  "description": "Empty-state body of the day-route screen"
},
"calendar_dayRouteTruncated": "Route limited to the first 10 stops",
"@calendar_dayRouteTruncated": {
  "description": "Info notice when the day has more stops than Google Maps supports"
},
"calendar_dayRouteEmployeeLabel": "Employee",
"@calendar_dayRouteEmployeeLabel": {
  "description": "Label of the admin-only employee picker on the day-route screen"
},
"calendar_dayRoutePreviousDay": "Previous day",
"@calendar_dayRoutePreviousDay": {
  "description": "Tooltip of the day switcher's back chevron"
},
"calendar_dayRouteNextDay": "Next day",
"@calendar_dayRouteNextDay": {
  "description": "Tooltip of the day switcher's forward chevron"
}
```

`app_fr.arb`: "Route du jour", "Ouvrir la route dans Google Maps ({count})",
"Naviguer", "Aucun rendez-vous ce jour-là",
"Les rendez-vous prévus ce jour-là apparaîtront ici en ordre de route.",
"Route limitée aux 10 premiers arrêts", "Employé", "Jour précédent",
"Jour suivant".

- [ ] **Step 2: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_fr.arb
git commit -m "feat: day route l10n keys"
```

---

### Task 4: `DayRouteScreen`

**Files:**
- Create: `lib/features/calendar/screens/day_route_screen.dart`
- Modify: `lib/features/calendar/widgets/cards/appointment_card.dart` (optional `footer` slot)
- Modify: `lib/routes/app_routes.dart`
- Modify: `lib/features/calendar/screens/main_calendar_screen.dart` (app bar action)

- [ ] **Step 1: Screen skeleton**

`DayRouteScreen` is a `ConsumerStatefulWidget{required bool isAdmin, required
String employeeId}`. State: `DateTime _day` (today, date-only) and
`String _selectedEmployeeId` (init `widget.employeeId`; for an admin the
picker can change it — seed from the first active employee if the admin's own
id yields nothing, but starting with the admin's own id is fine).

Data:

```dart
AppointmentDateRange _dayRange(DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  return AppointmentDateRange(start: start, end: start.add(const Duration(days: 1)));
}

final async = ref.watch(myAppointmentsProvider(
    (employeeId: _selectedEmployeeId, range: _dayRange(_day))));
final jobs = (async.value ?? const <AppointmentRecord>[])
    .where((a) => a.status != 'cancelled')
    .toList(); // already startTime-ordered by the query
```

Route-eligible stops (for the bottom route button):

```dart
const openStatuses = {'pending', 'in_progress', 'confirmed'}; // confirmed = legacy alias
final stops = jobs
    .where((a) => openStatuses.contains(a.status) && a.address.trim().isNotEmpty)
    .map((a) => a.address)
    .toList();
```

Build:

- `Scaffold` with `AppTopBar(title: l10n.calendar_dayRouteTitle,
  onBack: () => Navigator.pop(context), compact: context.isLandscape)` — no
  app-bar route action (mockup decision: the route action is the pinned
  bottom button), and `bottomNavigationBar` hosting it:

```dart
bottomNavigationBar: SafeArea(
  minimum: const EdgeInsets.fromLTRB(
      AppSpacing.sp16, 0, AppSpacing.sp16, AppSpacing.sp16),
  child: FilledButton.icon(
    icon: const Icon(Icons.alt_route_rounded),
    label: Text(l10n.calendar_dayRouteOpenInMaps(
        stops.length > maxRouteStops ? maxRouteStops : stops.length)),
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.r16)),
    ),
    onPressed: stops.isEmpty
        ? null
        : () {
            if (stops.length > maxRouteStops) {
              ref.read(noticeServiceProvider)
                  .info(l10n.calendar_dayRouteTruncated);
            }
            final uri = buildGoogleMapsRouteUrl(stops);
            if (uri != null) launchGoogleMapsRoute(context, ref, uri);
          },
  ),
)
```

- Body `Column`:
  1. **Day switcher** — a `Row` with `IconButton(Icons.chevron_left)` /
     `IconButton(Icons.chevron_right)` mutating `_day` ±1 day around a
     centered `Text(DateFormat.MMMMEEEEd(Localizations.localeOf(context).toString()).format(_day), style: textTheme.titleMedium)`.
     Padding `AppSpacing.sp8`/`sp16`; chevron tooltips are
     `l10n.calendar_dayRoutePreviousDay` / `l10n.calendar_dayRouteNextDay`
     (added in Task 3) — `IconButton.tooltip` doubles as the semantics label.
  2. **Admin employee picker** (only `if (widget.isAdmin)`) — a
     `DropdownButtonFormField<String>` labeled
     `l10n.calendar_dayRouteEmployeeLabel`, items from
     `ref.watch(employeesStreamProvider).value ?? const []` (active staff),
     value `_selectedEmployeeId` (fall back to the first employee when the
     current value isn't in the list), `onChanged` sets state.
  3. **List** — `Expanded(child: ...)`:
     - loading (`async.isLoading` with no value): `SkeletonLoader` rows (reuse
       the same skeleton style `EventList` uses);
     - stream error: compose via the standard pattern — a `ref.listen` on the
       provider pushing `composeErrorNotice` once on data→error transition
       (tag `APPT-LOAD`, reuse its existing intro), NOT in the builder;
     - empty: `AppEmptyState(icon: Icons.alt_route_rounded,
       title: l10n.calendar_dayRouteEmptyTitle,
       body: l10n.calendar_dayRouteEmptyBody)`;
     - data: `ListView.builder` of rows:

Each row is a timeline stop. First, `AppointmentCard` gains an optional
`footer` slot (`Widget? footer`, default null — existing call sites
unchanged), rendered inside the padded column after the employee row; this
hosts the navigate pill so the card keeps its Ink/tap semantics.

```dart
final colorMap = ref.watch(employeeColorMapProvider);
final empColor = colorMap[_selectedEmployeeId] ?? scheme.primary;
final statusColors = Theme.of(context).statusColors;
// Open-stop numbering: number only pending/in_progress/legacy-confirmed
// stops, in list (time) order.
final numberByJobId = <String, int>{};
var n = 0;
for (final j in jobs) {
  if (openStatuses.contains(j.status)) numberByJobId[j.id!] = ++n;
}
// row i:
IntrinsicHeight(
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _StopRail(
        number: numberByJobId[job.id], // null => done: ✓ badge
        badgeColor: numberByJobId[job.id] != null
            ? empColor
            : statusColors.successContainer,
        foreground: numberByJobId[job.id] != null
            ? contrastingForegroundFor(empColor)
            : statusColors.onSuccessContainer,
        showConnector: i < jobs.length - 1,
      ),
      const SizedBox(width: AppSpacing.sp12),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sp12),
          child: Opacity(
            opacity: numberByJobId[job.id] != null ? 1 : 0.62,
            child: AppointmentCard(
              appointment: job,
              employeeColor: empColor,
              onTap: () => showEventDetails(context, job),
              footer: job.address.trim().isEmpty ||
                      numberByJobId[job.id] == null
                  ? null
                  : _NavigatePill(
                      label: l10n.calendar_dayRouteNavigate,
                      onTap: () => AddressMapLauncher.showMapChoices(
                          context, address: job.address),
                    ),
            ),
          ),
        ),
      ),
    ],
  ),
)
```

`_StopRail` is a 28 px circular badge (number text or a 16 px check icon) over
an expanded 2 px vertical `Container` in `scheme.outlineVariant` (hidden on
the last row). `_NavigatePill` is a rounded `Material`+`InkWell` pill in
`scheme.primaryContainer` with `scheme.onPrimaryContainer` foreground — the
theme maps these to the mockup's exact colors (`themes.dart:72` light
`primarySurface`, `themes.dart:216` dark `darkPrimaryTint`); no raw
`AppColors.*` in build().

Keep `build()` under ~60 lines by extracting `_daySwitcher()`,
`_employeePicker()`, `_timeline()`, and `_routeButton()` builders (`_StopRail`
and `_NavigatePill` as private widgets in the same file). No `PrimaryScrollScope` needed
(single scrollable on its own pushed route). No FAB (no heroTag concern).

- [ ] **Step 2: Route registration**

`app_routes.dart`:

```dart
static const String dayRoute = '/day-route';
// in the switch:
case dayRoute:
  final args = settings.arguments as DayRouteArgs;
  return AppPageRoute(
    settings: settings,
    builder: (_) => DayRouteScreen(
      isAdmin: args.isAdmin,
      employeeId: args.employeeId,
    ),
  );
// with the other args classes:
class DayRouteArgs {
  const DayRouteArgs({required this.isAdmin, required this.employeeId});
  final bool isAdmin;
  final String employeeId;
}
```

- [ ] **Step 3: Calendar app-bar entry point**

In `main_calendar_screen.dart`'s `AppTopBar` actions (line ~295), before the
menu button:

```dart
IconButton(
  icon: Icon(Icons.alt_route_rounded, color: scheme.onPrimary),
  tooltip: context.l10n.calendar_dayRouteTitle,
  onPressed: () => Navigator.pushNamed(
    context,
    AppRoutes.dayRoute,
    arguments: DayRouteArgs(
      isAdmin: widget.isAdmin,
      employeeId: widget.employeeId,
    ),
  ),
),
```

- [ ] **Step 4: Verify + commit**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"` → clean.

```bash
git add lib/features/calendar/screens lib/features/calendar/widgets/cards/appointment_card.dart lib/routes/app_routes.dart
git commit -m "feat: day route screen with multi-stop maps handoff"
```

---

### Task 5: Widget tests

**Files:**
- Test: `test/features/calendar/screens/day_route_screen_test.dart`

- [ ] **Step 1: Write the tests**

Harness requirements (from the repo testing rules): full l10n delegates +
`supportedLocales`, `ThemeNotifier(..., child: ...)` wrapper, `ProviderScope`
overriding `myAppointmentsProvider` (family override with a fixed stream),
`employeesStreamProvider`, `employeeColorMapProvider`/`employeeNameMapProvider`.
`container.listen` in `setUp` for the autoDispose family.

Cover:
- three jobs out of order in the fixture → rendered in startTime order
  (`AppointmentCard` titles in vertical order via `tester.getTopLeft`);
- cancelled job excluded from the list;
- open stops numbered 1..N skipping done stops (done stop shows the ✓ badge,
  no number; numbering unaffected by it);
- open job with empty address → numbered but no `_NavigatePill`; done job →
  no pill either;
- day with no jobs → `AppEmptyState` visible, bottom route `FilledButton`
  disabled (`onPressed == null`); same when the only open stops lack
  addresses;
- admin picker visible only when `isAdmin: true`;
- `tester.takeException()` is null throughout; pump at 375×667 with
  textScale 2.0 once (`_scaledHarness` pattern) to catch overflow.

- [ ] **Step 2: Run**

Run: `flutter test test/features/calendar/screens/day_route_screen_test.dart`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/features/calendar/screens/day_route_screen_test.dart
git commit -m "test: day route screen coverage"
```

---

### Task 6: Device verification

No code. On the Android dev device:

- [ ] Employee sign-in → calendar app bar shows the route icon → screen lists
  only that employee's jobs for today, in time order.
- [ ] Chevrons move across days; tomorrow shows tomorrow's jobs.
- [ ] The per-stop Navigate pill opens the map chooser (Google/Waze on
  Android).
- [ ] The bottom route button with ≥2 open stops opens Google Maps with the
  stops in order (spot-check the waypoints); its count matches the numbered
  badges that have addresses.
- [ ] Admin sign-in → employee picker appears; switching employees swaps the
  list; visibility matches the calendar.
- [ ] A done job appears in the list but is excluded from the launched route;
  a cancelled job appears nowhere.
- [ ] Landscape: `AppTopBar(compact: true)` renders; no overflow at large
  text scale.

## Failure guarantees

| Failure | Behavior |
|---|---|
| No maps app / launch fails | Notice `error_couldNotOpenMapApp` (never a SnackBar) |
| Day has only address-less jobs | Timeline renders with numbers, bottom route button disabled |
| >10 open stops | First 10 launched + info notice `calendar_dayRouteTruncated` |
| Appointments stream errors | One-shot notice via `ref.listen` (APPT-LOAD), list keeps last data |
| Admin picker's employee deactivated mid-view | `employeesStreamProvider` drops them; picker falls back to first active employee |
