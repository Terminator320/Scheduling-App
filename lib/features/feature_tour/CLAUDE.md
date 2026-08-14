# Feature tours (lib/features/feature_tour/)

Tour rules moved out of the root `CLAUDE.md` on 2026-08-14 — this block is
self-contained Flutter UI with no `functions/` hand-mirror, so it only
needs to load when working here or on a screen that hosts a tour.

Note the cross-cutting half that stays in the root file: `AppDestination`
member names are load-bearing BOTH as tour storage keys and as navigation
identity, so a rename replays or orphans a tour.

- **Feature tours (`lib/features/feature_tour/`, showcaseview 5.x):** each
  scope registers its OWN showcaseview scope (`TourScope.storageKey`) — the hub
  IndexedStack keeps every tab mounted, so a shared scope would mix hidden
  tabs' targets into the visible tour. `FeatureTourHost` is the only start
  path.
  **A tour is keyed on the sealed `TourScope`, not on `AppDestination`**
  (`domain/tour_scope.dart`, 2026-08-04): `DestinationTour` wraps a screen,
  `FormTour` wraps one of the three create-flow sheets (`addAppointment`,
  `addClient`, `invitePerson`) — which is the only reason a walkthrough of
  "how do I create an appointment" is expressible at all. **`storageKey` is
  BOTH the showcase scope name and the SharedPreferences entry, and a
  destination's key is its bare `.name`** — do not prefix it, or every
  installed device replays every tour it has already seen. Form keys are
  namespaced `sheet_*` so they cannot collide. `.name` stays load-bearing:
  renaming a `HubTab`, `PushedDestination` or `TourForm` member replays or
  orphans that tour.
  **Its visibility gate is chosen by the scope's sealed type, not
  by a null `HubShellScope`**: a `HubTab` gates on `HubShellScope.currentOf`;
  a `PushedDestination` **and a `FormTour`** both gate on
  `ModalRoute.of(context)?.isCurrent` — one branch, because a
  `ModalBottomSheetRoute` IS a `ModalRoute`. A null scope is
  ambiguous — it also describes a hub screen hosted standalone in a test, where
  "never start" must be preserved. Before this split, Settings and History
  (now pushed routes) would have had `currentOf == null` and their tours would
  have silently never started.
  **A widget test that pumps `AddEventSheet`, `AddClientSheet` or
  `InvitePersonSheet` MUST call `markFormToursSeen()`**
  (`test/support/tour_test_support.dart`). A sheet's route is current the
  instant the test pumps it, so on a fresh-install preferences store the tour
  starts and showcaseview's repeating tooltip animation makes `pumpAndSettle`
  time out. Hub tabs are immune (no `HubShellScope` when hosted standalone).
  **A scrolling tour host passes `autoScroll: true` AND
  `kTourScrollCacheExtent`** — `isTargetRendered` cannot find a target a lazy
  list never built, and it drops that step silently rather than failing.
  **Wrap targets with `TourSteps.stepIf`, not `has(id) ? step(id, ...) : child`**
  — `step` force-unwraps `keys[id]!`, so an unguarded wrap crashes on a screen
  whose employee catalog is empty. A list-row step wraps the FIRST row only
  (the `GlobalKey` must stay unique), injected as a wrap callback so the widget
  stays reusable untoured — `ClientsListView` is also the booking flow's client
  picker.
  Route mode also awaits `_routeTransitionSettled()` so showcase measures a
  page that has finished sliding in. It
  awaits `tourSeenProvider.ready` before acting (the optimistic empty default
  would replay seen tours on cold start), and drops steps whose target isn't
  rendered via `isTargetRendered` — **never `GlobalKey.currentContext`: the
  5.x `Showcase` widget does NOT forward its key to the element tree, so
  currentContext is always null** (zero survivors → mark seen, never
  crash/retry). The auto-start sets a `_started` guard before its post-frame
  callback runs; **reset `_started` on the visibility-changed early-return** (the
  tab was switched away before the callback fired) — a stale `true` there
  permanently suppresses that tab's tour for the session, so a fast tab-switch
  during auto-start otherwise wedges it shut. **Data-dependent tabs MUST pass `FeatureTourHost(ready:)` false
  while their body shows a loading/error placeholder** — the tour's targets
  don't exist yet, so an ungated start finds zero survivors and permanently
  marks the tab seen against an empty body (bit LiveMap: its FAB targets live in
  the map stack, absent during the presence-data load). **A PARTIAL start is
  the same bug and is easier to miss** — the surviving steps run, the tour
  finishes, and `markSeen` fires for the WHOLE scope, so the dropped steps are
  gone for good (Settings › Replay is the only way back). Any scope holding
  even ONE data-dependent target needs the gate, not just one whose body is
  entirely a placeholder. Calendar gates on
  `!isLoading`; LiveMap gates on `_mapTargetsRendered` (the map stack, not the
  placeholder, is showing); Dashboard and Day route gate on `AsyncData`; Team
  gates on `allUsersStreamProvider.hasValue`. **Clients and History are
  paginated, so they have no `AsyncValue` to read** — `ClientsListView` and
  `AppointmentHistoryView` each expose `onFirstPageSettled`, fired post-frame
  after the first page resolves (success OR failure — either way the skeleton
  is gone and no further row arrives on its own), and the screen gates `ready`
  on it. Wire any new paginated tour host the same way rather than starting
  against the skeleton.
  Settings and the three form sheets instead FORCE their below-fold targets to
  mount via `autoScroll: true` + an inflated `scrollCacheExtent` — a lazy list
  won't build off-screen rows for `isTargetRendered` to find. Scopes are
  registered in initState and deliberately NEVER
  unregistered (register() replaces; unregister in dispose would race the
  replacement State's initState on a hub identity change), and every
  dismiss/mark-seen is gated by `_tourRunning` because the package fires
  onDismiss even when idle. Step catalogs are pure (`tourStepsFor`);
  Clients/Employees/History/LiveMap/Dashboard and all three form sheets are
  admin-only, so their employee catalogs are empty and their screens guard
  wraps on catalog membership. **Calendar, Day route and Settings are the
  three destinations an employee can reach, and each has an employee tour** —
  keep that set matching `drawerGroups(isAdmin: false)`.
  Seen flags are device-local SharedPreferences ONLY (`tour_seen_tabs`);
  sign-out does not reset them — the Settings "Replay app tour" row is the
  only reset.
