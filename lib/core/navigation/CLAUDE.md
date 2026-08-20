# Navigation (lib/core/navigation/)

Loaded when working under `lib/core/navigation/`. Root context: `../../../CLAUDE.md`.

- **Navigation (`lib/core/navigation/`, restructured 2026-07-30):**
  `AppDestination` is a **sealed** family — `enum HubTab {calendar, clients,
  employees, liveMap}` (the four `IndexedStack` panes) and
  `enum PushedDestination {dayRoute, history, dashboard, settings}` (plain
  routes above the shell). The split makes `select(settings)` a **compile
  error** instead of an `IndexedStack` range crash; that is the whole point —
  never collapse it back to one enum plus a list or an `isHubTab` flag.
  `implements Enum` keeps `.name`/`.values` on the union type, and `.name` is
  load-bearing: it is the persisted `tour_seen_tabs` key AND the showcase scope
  name, so **renaming a member silently replays or orphans a tour** (that is
  why the member stayed `employees` while its label became "Team" via
  `nav_team`). `navigateToDestination` is the one nav action; a hub tab reached
  from a pushed route goes through `selectAndReveal` (collapse, then switch) —
  the old `pushReplacementNamed` path left the wrong screen on top from a
  2-deep stack. `goHomeToCalendar` is the canonical go-home gesture behind the
  header's Calendar pill. **`_popToShell` targets the shell's captured
  `ModalRoute`, never `isFirst`** — on `_hubRoute`'s fallback branch the shell
  is not route #1, so `popUntil(isFirst)` pops the shell itself and strands the
  user. The **nav rail, `AdaptiveShell`, `AdaptiveDestination`,
  `Breakpoints.expanded` and `isExpanded` are all deleted**; `AppNavDrawer`
  (right-anchored, from `drawerGroups(isAdmin:)`) is the nav surface at every
  screen size, and `AppHeaderPair` sits in every `AppTopBar.actions` — on the
  **calendar only** it is built with `showCalendarPill: false` (a go-home pill
  on the screen it goes home to is dead weight; owner call 2026-07-31), so that
  header carries the day-route button and the hamburger alone.
  `_hubRoute` + `HubTabRedirectRoute` survive at three tab routes — they look
  dead but remain the cold-start fallback. **Both branches are pinned, one test
  each:** `test/routes/hub_shell_test.dart` covers the REDIRECT branch (it
  mounts a live `HubShell` as `home:` before pushing, so `_hubRoute` always
  finds one), and `test/routes/hub_route_cold_start_test.dart` (I2, 2026-08-19)
  covers the FALLBACK branch — no live shell, so `_hubRoute`
  (`lib/core/navigation/app_routes.dart`) must build a fresh `HubShell` with
  `initialTab` set to the tab that was asked for. Before that second file
  `initialTab` appeared nowhere under `test/`, so a push landing on the
  calendar instead of the requested tab (a push-notification tap, or a drawer
  entry taken before the shell exists) would not have failed anything.

