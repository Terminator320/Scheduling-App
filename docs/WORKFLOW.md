# App Workflow & UI Map

How the app actually works from the *user's* side — roles, navigation chromes,
screen anatomy, and the flows that connect them. Written as a redesign brief:
`ARCHITECTURE.md` covers layers and data flow, this covers what's on screen and
what a new layout may or may not change.

Companion mockup (three design directions, phone-width, theme-aware):
<https://claude.ai/code/artifact/5dbf4b99-a4ee-43b1-94f0-5ab648caa379>

---

## 1. Two apps in one binary

Role is the single biggest layout driver. It comes from Firestore
(`users/{docId}.role`), is **never** read from local storage, and is threaded
down as `isAdmin` through every screen constructor.

| Surface | Admin | Employee |
|---|---|---|
| Calendar | all appointments in the visible month | only jobs where their docId ∈ `employeeIds` |
| Add-appointment FAB | yes | **no FAB at all** |
| Edit / Cancel / Delete a job | yes | no (`showActions: false`) |
| Mark as complete | yes | yes — their only write affordance |
| Day route (multi-stop map) | yes, with an employee switcher | yes, own day only |
| Clients · Employees · History · Live map · Dashboard | yes | **not in nav at all** |
| Settings | yes (+ Wave integrations) | yes |

The employee app is effectively **two destinations** (calendar, settings) plus
the day-route screen and the job detail sheet. The admin app is six tabs plus a
pushed dashboard. A redesign has to look deliberate in both cases — a bottom nav
with two items for a tech is a real design problem the current nav rail sidesteps
by simply hiding entries.

---

## 2. Navigation architecture

Three chromes, selected by **two independent gates** (`core/layout/breakpoints.dart`):

```
portrait phone              landscape phone / tablet       tablet (shortestSide >= 600)
isSplitLayout = false       isSplitLayout = true           isTwoPane = true
+----------------+          +--+---------------+           +--+-------+--------+
| AppTopBar    = |          |R | AppTopBar     |           |R | list  | detail |
|                |          |a |               |           |a |       | pane   |
|    content     |          |i |   content     |           |i |       |        |
|           (+)  |          |l |               |           |l |       |        |
+----------------+          +--+---------------+           +--+-------+--------+
 end drawer = nav            rail replaces drawer;          list screens split
                             calendar -> month | agenda     (clients/employees/
                                                             history/settings)
```

- **`isSplitLayout`** (`width >= 840 || landscape`) → nav rail replaces the
  hamburger end-drawer, and the **calendar** becomes side-by-side month grid |
  day agenda (no detail pane).
- **`isTwoPane`** (`shortestSide >= 600`, orientation-independent) → master-detail
  on the list screens. A landscape phone gets the rail but *not* a detail pane —
  too narrow to read one. Rotating a phone never swaps a pane in.
- Third, independent axis: **`isCompact`** (`width < 360 || textScale > 1.4`) →
  dense rows stack vertically. `isNarrowWidth` is the width-only variant;
  `shortViewportHeight` (700) lets sheets grow on landscape phones.

**Hub shell.** The six destinations live in one persistent `IndexedStack`
(`routes/hub_shell.dart`): every tab stays mounted, switching is a 220 ms
cross-fade, tab state survives. Android back and the iOS left-edge swipe return
to the calendar tab. Hidden tabs are muted (`TickerMode`) and pin `viewInsets` to
zero. **There is no bottom navigation bar anywhere today** — the most obvious
open slot in the design.

### Route graph

```
OnboardingGate --first launch--> onboarding carousel --> SplashScreen
                                                            |
                     +--------------------------------------+
                     v                                      v
                  /login  (+ /forgot-password,           HubShell
                   create account via invite code)           |
                                                 +-----------+-----------+
                                    tabs: calendar clients employees     |
                                          history liveMap settings       |
                                                                         |
                              pushed routes: /dashboard  /day-route  text-size
```

`AppRoutes.onGenerateRoute` is the only routing entry point; every destination
takes a typed args class. Pushing a hub route while a shell is live is redirected
into a tab switch (`HubTabRedirectRoute`), so the rail, the drawer, and the back
arrows can't drift.

---

## 3. Screen anatomy

### Calendar — `features/calendar/screens/main_calendar_screen.dart`
The app's home.
- `AppTopBar` (primary blue, bold 17 px title) with a `bottom` strip: tappable
  month label on the left, selected-day job count on the right. Actions:
  day-route icon, hamburger (portrait only).
- Body: `table_calendar` month grid (row height derived from available height,
  employee-colour event dots) → divider → day agenda of `AppointmentCard`s.
- Two FABs: `addFab` (admin, bottom-right) and `todayFab` (bottom-left, scales +
  fades in whenever the visible month isn't the current one).
- Card tap → appointment detail **bottom sheet**.

### AppointmentCard — the signature component
3 px employee-colour bar down the left edge · title + `StatusChip` on one row ·
clock icon + time range · colour dot + assignee names. Folds the title/chip row
into a column when `isCompact`. The title is a plain `Text`, not `AutoSizeText`
(see constraint 6).

### Appointment detail sheet (read-only)
`DetailSheetListView` inside a modal sheet, or a master-detail pane. Order:
edit chip (admin only) → header with title, time and the **time-derived**
`StatusChip` → **Call / Directions** quick-action tiles → client `InfoCard`
(name, tappable phone, tappable address) → extra business contacts → notes →
materials → assigned employees → photo carousel → action bar (Mark complete /
Cancel). Empty sections are omitted entirely rather than rendering "None", so a
sparse job stays short.

### Add / Edit appointment sheet
One shared field stack (`appointment_form_fields.dart`) in four sections:
1. **Templates** — add flow only; one-tap chips seed title + duration.
2. **Who** — service title, client search (with inline "Add … as a new client"),
   employee multi-picker.
3. **Schedule** — date, start | end time (side by side; stacked when narrow),
   status picker (edit flow only), repeat picker.
4. **Details** — address (client-address pill with *Change* ⇄ autocomplete),
   notes, materials, photo thumbnail strip.

### Clients / Employees / History
Same skeleton: `AppTopBar` with an `AppSearchBar` in the `bottom` slot, a master
list, a FAB (admin), and a detail that is a **sheet on phones / a pane on
tablets**.
- **Clients** — paginated newest-first (`infinite_scroll_pagination`); detail has
  quick actions, info card, contacts, and a **Job history** section.
- **Employees** — roster cards with colour swatch + `UserStatusChip`
  (active / invited / disabled); detail has the colour grid (colours taken by
  someone else are *hidden*, never greyed), admin toggle, disable/enable, and
  invite → one-time signup-code dialog.
- **History** — `HistoryFilterBar` (year / employee), grouped year → day,
  `AppointmentTile` rows, cancelled visits struck through.

### Live map (admin) — `features/presence/screens/live_map_screen.dart`
Full-bleed Google Map, staff markers drawn with initials on the employee colour,
info card, two small FABs (`liveMapRosterFab`, `liveMapRecenterFab`), and a
roster sheet sorted nearest-first. Staleness is **text only** — markers are never
dimmed.

### Day route — `features/calendar/screens/day_route_screen.dart`
`‹ date ›` day switcher (+ today), employee switcher (admin), numbered stop rail,
stop tiles with a *Navigate* pill, and one "route all stops" action that hands
off to Google Maps (10-stop cap, extras dropped with a warning).

### Dashboard (admin, pushed route)
Edge-to-edge hero → Upcoming today → Employee workload → Business trends
(`fl_chart` weekly bars) → Attention flags. Skeleton rows while loading.

### Settings
Profile card, then uppercase section headers over grouped cards: Appearance
(theme, text size, language) · Account · Security (biometric app-lock) ·
Notifications (+ iOS Live job card) · Integrations (Wave, admin) · Legal · Help
(replay tour) · version footer. Text size is a sub-page on phones, a detail pane
on tablets.

### Auth
`AuthScaffold` — surface scroll view, form centred and capped at 440 px on
wide/landscape, `AuthBrandHeader` (mascot above a centred title), one
reduce-motion-gated fade/rise for the whole form.

---

## 4. The flows that matter

```
BOOK A JOB (admin)
calendar FAB -> add sheet -> title (or template chip) -> client search
    +- no match -> inline add-client sheet -> returns the record WITH its doc id
 -> employees -> date + start/end (busy-conflict dialog on overlap)
 -> repeat? -> materializes every future visit up to 5 years in ONE WriteBatch
 -> address (client's, or custom) -> notes / materials / photos
 -> Save -> offline? fails fast with an offline notice
            online?  writes, then photos upload in the background via a
                     durable queue that survives going offline
 -> top-slide success notice

EMPLOYEE'S DAY
travel-aware "time to leave" push (or the iOS Live Activity card)
 -> tap -> deep link esproschedule://appointment?id=... -> detail sheet
 -> Directions -> Maps -> on site -> Mark as complete
 -> server ends the Live Activity card and stops the nudges

STATUS LIFECYCLE  (what's stored != what's shown)
stored:  pending -> in_progress -> done          (+ cancelled)
shown:   pending -> in_progress (clock inside the window) -> overdue (past end)
         ^ overdue is display-only: never written, never in the picker

EDIT A REPEAT SERIES
edit sheet -> Save -> "this visit only" or "this and future visits"
 -> apply-to-all propagates details + time-of-day to future non-terminal
    siblings, keeping each sibling's own date and status
```

**Feedback is uniform.** Notices slide in from the **top** of the screen via an
Overlay (`noticeServiceProvider.success/error/info`), with a per-kind haptic.
Not SnackBars — three sanctioned exceptions aside. Generic failures render as
`"{intro} — {cause}. (TAG)"` so a user's screenshot maps to a Crashlytics line.

---

## 5. The design system you're inheriting

**Tokens** (`core/theme/design_tokens.dart`)
`AppSpacing` 4 / 8 / 12 / 16 / 24 / 32 · `AppRadius` 8 / 12 / 16 / 20 / 24 / full ·
`AppShadow` card / sheet / pill · `AppDuration` 150 / 250 ms · `AppMotion`
(sheet curve, 220 ms tab switch).

**Palette** — royal blue `#005CC8` primary, navy `#00256B` ink, plunger red
`#D61F3A` error, bright blue accent, and a 10-colour employee palette. Full dark
theme on `#0A1633`. Status colours Material 3 has no slot for
(success / warning / invited / in-progress / overdue) live in the
`AppStatusColors` theme extension; light-vs-dark card treatment (shadow vs.
border) lives in `AppCardStyle`.

**Type** — Inter via `google_fonts`, and it is *small*: titleLarge 17, titleMedium
15, bodyLarge 15, bodySmall 13, labelLarge 11, labelSmall 9–10. This is the most
dated-feeling part of the current design and the safest thing to overhaul.

**Shared widgets to reuse or restyle** — `AppTopBar` · `AppointmentCard` ·
`AppointmentTile` · `StatusChip` / `UserStatusChip` · `AppAvatar` ·
`AppSearchBar` · `AppEmptyState` · `SkeletonLoader` · `InfoCard` + `InfoCardRow` ·
`QuickActionsRow` + `QuickActionButton` · `ListItemTile` · `LabeledTextField`
(built-in error shake) · `DetailSheetListView` · `FormSheetFrame` +
`SheetHeaderBar` ·
`showConfirmDialog` · `BusyButtonIcon` · `AnimatedLoadingButton` · `SectionLabel` ·
`BrandMark`.

**iOS adaptivity is one seam** — `context.isCupertino` drives action sheets,
spinners, scrollbars, confirm dialogs, and back buttons. Never branch on
`Platform.isIOS` at a call site.

---

## 6. Constraints a redesign must respect

**Free to change:** every visual token, the type scale, card / list / sheet
composition, adding a bottom nav or restructuring the hub, screen ordering,
iconography, chart styling, empty states, motion.

**Load-bearing** — breaking these causes bugs, not just ugliness:

1. `showEventDetails(..., showActions:)` stays a **required** param defaulting to
   **false** everywhere. A `true` default once showed employees admin controls
   that the rules then rejected with an opaque `permission-denied`.
2. Every FAB inside the hub needs a **unique `heroTag`** — all tabs are mounted
   simultaneously, so a shared tag collides. Current tags: `addFab`, `todayFab`,
   `clientsAddFab`, `employeesAddFab`, `liveMapRosterFab`, `liveMapRecenterFab`.
3. Every simultaneously-mounted primary scrollable needs its own
   `PrimaryScrollScope`, or the app-wide scrollbar throws "attached to more than
   one ScrollPosition".
4. Don't conflate `isSplitLayout` (rail chrome) with `isTwoPane` (detail pane).
5. Never branch on `isDark` / `brightness` for styling — add a field to a
   `ThemeExtension` instead. Never use `ColorScheme.tertiary` for success; that's
   the warning palette.
6. No `LayoutBuilder`-based widget (incl. `AutoSizeText`) inside an
   `IntrinsicHeight` subtree — it throws during the intrinsic pass and surfaces
   in release as a paint-time null check on the enclosing viewport.
7. All copy goes through `context.l10n`; a new string means paired EN + FR ARB
   keys with a `@key` metadata block, then `flutter gen-l10n`.
8. Respect `MediaQuery.textScaler` to 2.0 (the harness sweeps 0.8–2.0 at
   375×667) and collapse every animation when `disableAnimationsOf` is true.
9. Feature-tour steps target widgets by `GlobalKey` per tab — moving or removing
   a target means updating `tourStepsFor` and the screen's key wiring.
10. `AppSearchBar` call sites must pass `textScaler:` — its `preferredSize` has
    no context and will clip at large text sizes otherwise.
