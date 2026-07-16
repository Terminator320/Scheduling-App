# Admin Live Staff Location Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status: PLANNED — approved design 2026-07-15, not started.**

**Goal:** A Find My-style live map, **admin-only**, showing the most recent
location of every active staff member (employees AND admins) as colored
avatar markers, with per-person freshness ("2 min ago"), a dimmed
"last seen" state past the 25-minute staleness window, and — on marker tap —
an info card with the person's name, freshness, **the street address they are
at** (reverse-geocoded server-side), and an "Open in Maps" action. The map is
its own hub tab in the menu bar (NavigationRail + settings drawer), between
History and Settings.

**Architecture:** The tracking side already exists and is nearly untouched
(one freshness amendment — Task 4b's trailing flush):
`PresenceSyncController` (background GPS) writes
`users/{docId}/presence/location` = `{lat, lng, uid, updatedAt:
serverTimestamp}` throttled to 250 m / ≥2 min + a 10-min stationary
heartbeat; the server staleness window is `PRESENCE_STALE_MINUTES = 25`
(`functions/travel_utils.js`). This plan adds the **viewing** side: an
admin-only collection-group read rule, a single `collectionGroup('presence')`
listener joined in pure Dart to `watchAllUsers()`, a `google_maps_flutter`
screen (SPM-safe via the `google_maps_flutter_ios_sdk9` override), a new
`placesReverseGeocode` callable (Secret-Manager key, admin + App Check +
rate-limit guarded), and server-side presence-PII cleanup on user
delete/disable.

**Tech Stack:** Flutter (`google_maps_flutter` + `google_maps_flutter_ios_sdk9`),
Riverpod manual providers, Firestore collection-group query + rules, Firebase
Cloud Functions v2 (Geocoding API proxy), Jest, `gen_l10n`, mocktail.

**Map engine decision (2026-07-15, user-confirmed from a visual side-by-side):**
`google_maps_flutter` — Google cartography, live **traffic overlay**, and a
**satellite toggle**. `apple_maps_flutter` was rejected (CocoaPods-only —
violates the SPM-only invariant — and 17 months stale); flutter_map/OSM was
the runner-up. The default `google_maps_flutter_ios` is also CocoaPods-only:
the **`google_maps_flutter_ios_sdk9`** endorsed override (ships
`Package.swift`, pins Maps SDK 9.x, min iOS 15) is REQUIRED and matches the
project's iOS 15.0 target exactly. Never fall back to the default iOS
implementation — it would reintroduce a Podfile.

---

## Context

### Decisions made with the user (2026-07-15)

- **Admin-only viewing.** Employees never see the map or the tab; rules deny
  them the data as defence-in-depth.
- **Reuse the existing presence cadence.** No changes to the tracking side —
  the map shows the last fix with a freshness label; > 25 min ⇒ dimmed
  "Offline — last seen …" (Find My-style "last known", not disappearance).
  A 30 s UI ticker refreshes labels; positions move as staff move
  (~every 2 min on the road). A "live boost" mode was explicitly declined.
- **Own hub tab** ("Live map") in the menu bar — NavigationRail on wide
  layouts, settings drawer on phones — between History and Settings, in the
  existing admin-only cluster. Not a dashboard card, not a pushed route.
- **Tap a marker ⇒ show the street address** the person is currently at
  (reverse geocoding), plus freshness and "Open in Maps".

### Optimizations folded in (2026-07-15 post-review)

- **Pause the data side while the tab is hidden (Tasks 6/7).** The kept-alive
  `IndexedStack` posture stays (GL view + camera state survive tab switches),
  but the screen only *watches* the presence stream + 30 s tick while the
  Live map tab is current. `TickerMode` mutes Flutter tickers, not Riverpod
  streams — without this the collectionGroup listener bills a read for every
  staff presence write all day and the ticker rebuilds an invisible tab every
  30 s. Supersedes the earlier "optional later refinement".
- **Tick ≠ marker rebuild (Tasks 6/7).** Freshness labels re-render every
  30 s, but the marker set only re-assembles when a staleness flag actually
  flips — via a set-equality `staleDocIdsProvider`; the markers provider
  never watches the raw tick.
- **Tracking-side trailing flush (Task 4b).** A fix throttled by the 2-min
  upload gap is currently dropped, leaving a drive-then-park position up to
  ~12 min stale on the server; a one-shot trailing timer flushes the last
  fix when the gap expires. Same write volume, worst-case staleness ~2 min.

### Why the docs must change too (blocking)

`docs/legal/privacy-policy.html` §2.4 currently promises staff location is
NOT shared with other users and is readable only by the owner; the
`firestore.rules` presence comment says "peers and admins read nothing
client-side"; the iOS `NSLocation*UsageDescription` strings only mention
leave-time alerts. All three become false with this feature — shipping
without amending them is an App Store / privacy exposure. Treat Task 10 as
blocking for anything user-facing.

### User-side prerequisites (gate the on-device demo)

1. Google Cloud project `schedulingapp-88727`: enable **Maps SDK for
   Android**, **Maps SDK for iOS**, and the **Geocoding API** (add Geocoding
   to the `GOOGLE_MAP_API_KEY` API restriction — same step as the Routes API
   note in CLAUDE.md).
2. Create **two NEW restricted client API keys** (do NOT reuse the
   Secret-Manager `GOOGLE_MAP_API_KEY` — that is the server key and must
   never ship in the app): an Android key restricted to package
   `net.vogas.scheduling` + debug SHA-1, and an iOS key restricted to bundle
   id `net.vogas.scheduling`.
3. Put the Android key in `android/local.properties` as `MAPS_API_KEY=…`
   (gitignored); add `IOS_MAPS_API_KEY=…` to `dev/.env` (gitignored, carried
   to the Mac out-of-band like the rest).
4. Deploy after the code lands: `firebase deploy --only
   functions,firestore:rules`. Until rules deploy, the map screen shows the
   error state (`permission-denied`); until functions deploy, the address
   line is absent.

---

## Task 0 — Git setup

- [ ] `git fetch origin notification main`
- [ ] **SAFETY GATE:** `git log --oneline origin/main..claude/live-location-tracking-z49h7o`
      must print nothing (verified 2026-07-15: branch tip `f8284de` ==
      `origin/main`). Abort and reassess if it prints commits.
- [ ] `git checkout -B claude/live-location-tracking-z49h7o origin/notification`
- [ ] Final push is `git push -u --force-with-lease origin
      claude/live-location-tracking-z49h7o` (`origin/notification` has
      diverged from main). Any PR targets `notification`, NOT `main`.

## Task 1 — Dependencies (`pubspec.yaml`)

- [ ] Add:

```yaml
  # Admin live staff map (Google Maps; traffic overlay + satellite)
  google_maps_flutter: ^2.14.0
  # SPM-capable iOS implementation override (Maps SDK 9.x, iOS 15+) —
  # the default google_maps_flutter_ios is CocoaPods-only and would
  # reintroduce a Podfile. Keep this override while the project is SPM-only.
  google_maps_flutter_ios_sdk9: ^2.18.6
```

- [ ] `flutter pub get`; confirm the pair resolves (both flutter.dev-published;
      sdk9 is an endorsed federated override that replaces the default iOS
      implementation automatically). No Firebase interaction — the
      `firebase_core: 4.11.0` pin is unaffected. `LatLng`/`CameraUpdate` come
      from google_maps_flutter (no latlong2 dependency).
- [ ] Verify the resolved `BitmapDescriptor` bytes API name
      (`BitmapDescriptor.bytes` vs deprecated `fromBytes`) before writing the
      marker renderer.

## Task 2 — Platform key wiring

- [ ] **Android (dev harness):** `android/app/src/main/AndroidManifest.xml`
      gets `<meta-data android:name="com.google.android.geo.API_KEY"
      android:value="${MAPS_API_KEY}"/>`; `android/app/build.gradle` reads
      `MAPS_API_KEY` from `android/local.properties` into a manifest
      placeholder, **defaulting to empty string** so builds never break
      without the key.
- [ ] **iOS:** `GMSServices.provideAPIKey` must run in `AppDelegate.swift`
      before the first map. Read the bundled `dev/.env` asset via
      `FlutterDartProject.lookupKey(forAsset: "dev/.env")`, parse the
      `IOS_MAPS_API_KEY=` line (trim whitespace/quotes; ~15 lines of Swift),
      call `provideAPIKey` only when non-empty — missing key ⇒ blank map +
      console log, never a crash.
- [ ] Add a line to `docs/plans/IOS_APP_STORE_HANDOFF.md`: first Xcode open
      must resolve the new Google Maps SPM package; verify the AppDelegate
      env parse on device.

## Task 3 — Firestore rules + presence PII hygiene

- [ ] Add a collection-group match inside
      `match /databases/{database}/documents`, after the
      `match /users/{userId}` block:

```
    // ── presence (admin live-map read) ───────────────────────────────────
    // The nested self-only presence rules above still govern the owner's
    // get/create/update/delete. This grants ADMINS read (get + list,
    // including collectionGroup('presence')) over every presence
    // subcollection. isAdmin() is caller-side only — no resource-data
    // condition — so the UNFILTERED collection-group query stays provable
    // by the rules engine (see the query-rules invariant in CLAUDE.md).
    // NOTE: {path=**} reserves the subcollection name `presence` — any
    // future subcollection with that name becomes admin-readable.
    // (Verified 2026-07-15: users/{docId}/presence is the ONLY presence
    // subcollection in the codebase today.)
    match /{path=**}/presence/{presenceId} {
      allow read: if isAdmin();
    }
```

- [ ] Update the nested presence block's comment ("peers and admins read
      nothing client-side" is no longer true — admins read all presence via
      the collection-group rule; the reminder sweep still uses the Admin SDK).
- [ ] **`firestore.indexes.json`: no change.** An unfiltered
      `collectionGroup('presence').snapshots()` runs on the automatic
      `__name__` index. Adding a `where`/`orderBy` on `updatedAt` later would
      require a COLLECTION_GROUP-scope fieldOverride — do staleness filtering
      in Dart instead.
- [ ] **Presence PII cleanup (server-side):** Firestore does not cascade
      subcollection deletes — a deleted/disabled user's `presence/location`
      doc (their coordinates) would orphan forever (the device's best-effort
      sign-out cleanup never runs for a deleted account). Extend the existing
      **`syncUsersByUid`** trigger (`functions/bridge.js`, fires on every
      `users/{id}` write including deletes): when the doc is **deleted** or
      `status` leaves `'active'`, delete `users/{id}/presence/location` via
      the Admin SDK (idempotent).
  - [ ] Pure decision helper ("should presence be purged for this
        before/after pair"), exported for jest, per the trigger-testing
        convention.
  - [ ] **Isolation constraint:** the bridge mirror is auth-critical (rules
        resolve roles through it) — run the purge AFTER the bridge write, in
        its own try/catch that logs-and-continues, so a purge hiccup can
        never fail or delay the bridge sync.

## Task 4 — Data layer

- [ ] **New** `lib/features/presence/domain/models/presence_fix.dart` —
      plain immutable class `PresenceFix { userDocId, lat, lng,
      DateTime? updatedAt }` (`updatedAt` is null while a
      latency-compensated own-write's serverTimestamp is pending — treat as
      fresh, never crash).
- [ ] **Extend** `lib/features/presence/data/presence_repository.dart`:

```dart
Stream<List<PresenceFix>> watchAllPresence()
```

  - `_firestore.collectionGroup('presence').snapshots().map(_toFixes)`,
    wrapped in `retryStream` (`lib/core/utils/retry.dart`) retrying
    `permission-denied` — the post-sign-in auth-propagation race twin used by
    the employees repository.
  - Mapping: `userDocId = doc.reference.parent.parent!.id`; `lat`/`lng` via
    `(v as num?)?.toDouble()`; **skip** malformed docs (one bad doc must not
    kill the map); `updatedAt = (v as Timestamp?)?.toDate()`.
  - Unlike the swallowed write path, stream errors **propagate** (the screen
    surfaces them via the dashboard-style notice pattern — no new `Failure`
    family needed).

## Task 4b — Tracking-side freshness: flush the throttled last fix

The map inherits the reminder sweep's write cadence, which has one freshness
hole: in `presence_sync_controller.dart`, a fix arriving inside the 2-min
`minPresenceUploadGap` is **dropped** (only `_lastPosition` updates), so a
drive-then-park inside the window isn't written until the 10-min heartbeat —
the marker can sit ~12 min behind where the person actually stopped.

- [ ] Pure helper beside `shouldWritePresenceFix` (same file, unit-testable):
      `Duration? trailingFlushDelay({required DateTime? lastUploadAt,
      required DateTime now})` — null when a write is allowed now (no timer
      needed), else the remaining portion of `minPresenceUploadGap`.
- [ ] In `_start`'s position listener, when a fix is throttled: cancel any
      armed trailing timer and arm a one-shot
      `Timer(trailingFlushDelay(...))` that re-checks
      `shouldWritePresenceFix` and uploads `_lastPosition` (setting
      `_lastUploadAt`). Cancel the timer in `_stop()` and whenever a
      movement/heartbeat write goes out. Write volume is unchanged (writes
      stay ≥2 min apart); worst-case staleness drops from ~12 min to ~2 min.
- [ ] Tests: `trailingFlushDelay` boundaries (null lastUploadAt ⇒ null; at/
      past the gap ⇒ null; inside it ⇒ exact remainder). The timer wiring
      itself is device-only, per the existing no-geolocator-channel-tests
      convention.

## Task 5 — Domain (pure, unit-testable)

- [ ] **New** `lib/features/presence/domain/live_map_aggregator.dart`,
      mirroring `dashboard/domain/dashboard_aggregator.dart` (static pure
      functions, explicit `now`):
  - `const presenceStaleAfter = Duration(minutes: 25);` — comment: keep in
    sync with `PRESENCE_STALE_MINUTES` in `functions/travel_utils.js`.
  - `StaffMapPoint` (user name + color from `EmployeeRecord`, lat/lng,
    updatedAt).
  - `join({fixes, users})` — joins by users-doc id; drops fixes with no
    matching user or `status != 'active'` (a disabled employee's leftover doc
    must never render); sorted by name.
  - `isStale(updatedAt, now)` (> 25 min; null ⇒ fresh) and a pure
    freshness-bucket function (`justNow` | `minutesAgo(n)` | `hoursAgo(n)`)
    so widgets only map buckets to l10n strings.

## Task 6 — Application providers

- [ ] **New** `lib/features/presence/application/live_map_providers.dart`
      (manual Riverpod, mirrors `dashboard_providers.dart`):
  - `allPresenceStreamProvider` — `StreamProvider.autoDispose` over
    `watchAllPresence()`.
  - `liveMapClockProvider` — injectable `DateTime Function()` (twin of
    `dashboardClockProvider`).
  - `liveMapTickProvider` — `StreamProvider.autoDispose` of
    `Stream.periodic(30 s)` so freshness labels / stale flips update while
    the tab is visible.
  - `liveMapPointsProvider` — presence fixes ⋈ `allUsersStreamProvider`
    (existing admin path = `watchAllUsers()`; `join()` filters to active)
    into `AsyncValue<List<StaffMapPoint>>`, same reduction shape as
    `dashboardStatsProvider`.
  - `staleDocIdsProvider` — `Provider.autoDispose<Set<String>>` deriving the
    set of currently-stale user doc-ids from `liveMapPointsProvider` + tick +
    clock, **with set-equality notification** (compare against the previous
    value via `setEquals`, e.g. through `ref.watch(...).select(...)` or a
    cached-previous provider) so dependents are only notified when membership
    actually changes. A 30 s tick that flips nobody must not rebuild the
    marker set — only the freshness labels re-render.
- [ ] Pause-when-hidden: providers stay `autoDispose`; the SCREEN gates its
      watches on the tab being current (Task 7), so leaving the tab
      un-watches them and autoDispose tears down the collectionGroup
      listener and the ticker automatically. `TickerMode` alone can't do
      this — it mutes Flutter tickers, not Riverpod streams. The GL platform
      view stays alive across tab switches (camera state preserved) — its
      offstage memory is the accepted cost; the live listener + ticker are
      not.

## Task 7 — UI

- [ ] **New** `lib/features/presence/screens/live_map_screen.dart` —
      `LiveMapScreen({required isAdmin, required employeeId,
      @visibleForTesting mapBuilder})`, **modeled on `HistoryScreen`** (the
      simplest admin hub tab): `AppTopBar(title: l10n.liveMap_title, onBack:
      → calendar tab)`, `endDrawer: SettingsDrawer.endDrawerFor(...)`, body
      in `AdaptiveShell`. Error surfacing: `ref.listen` one-shot data→error →
      `noticeServiceProvider.error(composeErrorNotice(context, intro:
      l10n.error_introLoadLiveMap, tag: 'LIVEMAP-LOAD', ...))` (like
      `DashboardScreen`).
- [ ] Body `switch` on `liveMapPointsProvider`:
  - **Data:** `GoogleMap(initialCameraPosition: <Montréal, zoom 9>, markers:
    _markers, trafficEnabled: _traffic, mapType: _satellite ? hybrid :
    normal, myLocationEnabled: false, onMapCreated: ...)`.
    - Camera fits **once** on first non-empty data, after `onMapCreated`:
      **≥2 points** → `CameraUpdate.newLatLngBounds(bounds, 48)`; **exactly
      1 point** → `CameraUpdate.newLatLngZoom(point, 14)` (single-point
      bounds over-zoom/throw); a recenter FAB re-applies the same logic.
      Google logo is built in — no attribution widget.
    - **Toggles:** traffic on/off + normal/satellite, small stacked buttons
      top-right, tooltips via l10n.
    - Empty list → map renders + translucent `liveMap_emptyState` card.
    - `mapBuilder` test seam (mirrors `HubShell.screenBuilder`): defaults to
      the real `GoogleMap`; widget tests inject a stub recording the marker
      set — GoogleMap is a platform view and can't render in flutter_test.
    - **Selection robustness:** if the selected person drops out of the
      points list (disabled mid-view, presence purged), clear
      `_selectedDocId` instead of rendering a card over vanished data.
  - **Error:** centered error body (dashboard `_ErrorBody` shape).
    **Loading:** `CircularProgressIndicator.adaptive()`.
- [ ] **New** `lib/features/presence/widgets/staff_marker_icon.dart` —
      google_maps_flutter markers are **bitmaps, not widgets**: a
      `StaffMarkerIconRenderer` draws the avatar-colored circle + initials +
      surface ring + pointer tip with `dart:ui` (`PictureRecorder` →
      `toImage` → PNG bytes → `BitmapDescriptor.bytes`), honoring
      `devicePixelRatio`. Variants: normal / stale (grey ring, ~50% alpha) /
      selected (primary halo). Cache in a `Map` keyed by (initials,
      colorValue, stale, selected, dpr). Reuse `AppAvatar`'s initials +
      `contrastingForegroundFor` logic — extract to a shared helper, don't
      copy.
- [ ] **Marker-set assembly is NOT done in `build()`** (`toImage` is async;
      awaiting in build causes frame churn): a small `liveMapMarkersProvider`
      (or screen-owned memoized step) maps `AsyncValue<List<StaffMapPoint>>`
      + dpr + selected id → `AsyncValue<Set<Marker>>`, re-rendering only
      icons whose cache key changed. Its staleness input is
      `staleDocIdsProvider` (set-equality, Task 6) — it must NEVER watch the
      raw tick or a per-tick `now`, or the whole set re-assembles every 30 s
      even when nothing flipped. Full dependency list: (points, staleIds,
      selectedId, dpr).
- [ ] **New** `lib/features/presence/widgets/staff_info_card.dart` — bottom
      overlay on marker tap (local `_selectedDocId`, `AnimatedSwitcher` +
      `SafeArea`): `AppAvatar`, name, freshness line
      (`liveMap_lastUpdatedJustNow` / `..MinutesAgo(n)` / `..HoursAgo(n)`;
      stale ⇒ `liveMap_offlineLastSeen(ago)` greyed), **the street address
      the person is at** (Task 8 — `liveMap_resolvingAddress` shimmer while
      resolving, line hidden on failure), and `liveMap_openInMaps` →
      `AddressMapLauncher.showMapChoices(context, address: <resolved address,
      falling back to '<lat>,<lng>'>)`. **Verified 2026-07-15:** none of
      `AddressParser.splitApt`'s four regexes match a bare `lat,lng` string
      (no `Apt`/unit token; the dash rule's first group can't contain `.` or
      `,`), so `splitApt` returns null and the launcher passes the raw string
      through to Google `query=` / Apple `q=` / Waze `q=`, which all accept
      coordinates. Lock it with the unit test in Task 12.
- [ ] Freshness recompute: `ref.watch(liveMapTickProvider)` (value unused —
      drives the 30 s rebuild) + `now = ref.watch(liveMapClockProvider)()`.
      Scope the tick watch to the freshness-label subtrees (info card, stale
      dimming), not the whole screen build.
- [ ] **Pause-when-hidden:** add a dependency-creating accessor beside
      `HubShellScope.maybeOf` in `adaptive_shell.dart` —
      `static AdaptiveDestination? currentOf(BuildContext context)` via
      `dependOnInheritedWidgetOfExactType` (`updateShouldNotify` already
      fires on `current` changes; `maybeOf` deliberately creates no
      dependency, so it can't be reused for this). When hosted in a shell and
      `currentOf(context) != AdaptiveDestination.liveMap`, the screen skips
      the `ref.watch` of the points/tick/markers providers and renders the
      kept-alive map with its last-known marker set — autoDispose then drops
      the Firestore listener + ticker within a frame of switching away. A
      null scope (standalone route, widget tests) counts as visible.
      Returning to the tab re-attaches the stream (Firestore serves the warm
      cache, so the refresh is quick); keep the last `Set<Marker>` in screen
      state so there's no marker blink while the stream re-settles.

## Task 8 — Reverse geocoding ("what address are they at")

Follows the repo's server-proxy invariant (the client never holds the Google
key — same as `placesAutocomplete`/`placesGetDetails`):

- [ ] **New callable `placesReverseGeocode`** in `functions/places.js`,
      re-exported from `index.js`:
  - Guards mirrored from `placesGetDetails` via the shared `security.js`
    helpers (App Check + auth + `assertPayloadShape`), **plus `assertAdmin`**
    (only the admin live map uses it) **plus `enforceDurableRateLimit` keyed
    by uid** (generous, tap-driven — e.g. 120/hour; a compromised admin
    session must not be able to run up Geocoding billing).
  - Input `{lat, lng, locale}`: lat/lng validated `typeof number`, finite,
    in `[-90,90]`/`[-180,180]` (add a `requireNumberInRange` helper to
    `security.js` beside `requireString`); `locale` validated against
    `['en','fr']` (same allowlist as the fcmTokens rule) and passed as the
    Geocoding `language=` param so French admins get French addresses.
  - Calls the Google **Geocoding API** (`latlng=` reverse mode) with the
    Secret-Manager `GOOGLE_MAP_API_KEY`; **round coordinates to 5 decimals
    before the upstream call** (defense-in-depth against cache-busting query
    spam); return ONLY the top `formatted_address` string (or null on zero
    results) — minimal response.
  - **Never log coordinates or resolved addresses** (staff location is PII)
    — log only outcome codes/status.
- [ ] **Client:** extend the maps feature (`PlacesRepository` interface +
      `GooglePlacesRepository`) with `reverseGeocode(lat, lng)` calling the
      callable — remember the Android callable-cast convention
      (`(value as Map?)?.cast<String, dynamic>()`). Surface errors as the
      existing `MapsFailure` family; the widget layer treats failure as "no
      address", never a notice.
- [ ] **Provider:** `reverseGeocodeProvider` —
      `FutureProvider.autoDispose.family` keyed by coordinates **rounded to
      4 decimals** (~11 m) so a person idling at a job site doesn't re-bill a
      lookup per tap; `keepAlive()` on success for session-length caching.
      Lookup fires only when a marker is tapped — never for every marker.
- [ ] Deploy note (user): `cd functions && npm run lint`, then
      `firebase deploy --only functions`.

## Task 9 — Hub tab wiring (the "menu bar")

- [ ] `lib/core/layout/adaptive_shell.dart`:
  - Add `liveMap` to `enum AdaptiveDestination` **between `history` and
    `settings`** (the `IndexedStack` iterates `.values`, so ordering just
    works).
  - `destinationRoute(...)`: `liveMap => (route: AppRoutes.liveMap,
    arguments: MainCalendarArgs(isAdmin: isAdmin, employeeId: employeeId))`.
  - `_destinationsFor(...)`: new `_RailEntry` inside the `if (isAdmin)` block
    — `icon: Icons.map_outlined, selectedIcon: Icons.map_rounded, label:
    l.common_liveMap`.
- [ ] `lib/routes/app_routes.dart`: `static const String liveMap =
      '/live-map';` + `case liveMap:` → `_hubRoute(settings,
      AdaptiveDestination.liveMap, ...)` (args as `MainCalendarArgs`,
      mirroring `employees`).
- [ ] `lib/routes/hub_shell.dart` `_screenFor`: `liveMap =>
      LiveMapScreen(key: key, isAdmin: _isAdmin, employeeId: _employeeId)`.
- [ ] `lib/features/settings/widgets/views/settings_drawer.dart`: new
      admin-only item (`Icons.map_rounded`, `l10n.common_liveMap`,
      `onTap: () => go(AdaptiveDestination.liveMap)`) after the History item.
- [ ] Gating posture: rail entry + drawer item are `isAdmin`-gated (same as
      clients/employees/history); no runtime role check in the screen —
      rules deny the data to non-admins anyway.

## Task 10 — l10n (both ARBs in lockstep, `@key` metadata in EN, then `flutter gen-l10n`)

- [ ] EN keys: `common_liveMap` "Live map" · `liveMap_title` "Staff map" ·
      `liveMap_emptyState` "No one is sharing their location right now" ·
      `liveMap_lastUpdatedJustNow` "Just now" · `liveMap_lastUpdatedMinutesAgo`
      `{minutes, plural, =1{1 min ago} other{{minutes} min ago}}` ·
      `liveMap_lastUpdatedHoursAgo` `{hours, plural, =1{1 hr ago} other{{hours} hrs ago}}` ·
      `liveMap_offlineLastSeen` "Offline — last seen {ago}" ·
      `liveMap_resolvingAddress` "Finding address…" · `liveMap_openInMaps`
      "Open in Maps" · `liveMap_trafficToggle` "Traffic" ·
      `liveMap_satelliteToggle` "Satellite" · `error_introLoadLiveMap`
      "Couldn't load the staff map".
- [ ] FR values: "Carte en direct" · "Carte du personnel" · "Personne ne
      partage sa position en ce moment" · "À l'instant" ·
      `{minutes, plural, =1{il y a 1 min} other{il y a {minutes} min}}` ·
      `{hours, plural, =1{il y a 1 h} other{il y a {hours} h}}` ·
      "Hors ligne — vu {ago}" · "Recherche de l'adresse…" ·
      "Ouvrir dans Maps" · "Circulation" · "Satellite" · "Impossible de
      charger la carte du personnel".

## Task 11 — Privacy/legal + docs (REQUIRED — current docs contradict this feature)

- [ ] `docs/legal/privacy-policy.html` §2.4: amend — **administrators can
      view each active staff member's most recent location on a live map in
      the App while location sharing is active**; still no location history
      (single most-recent fix), still deleted on sign-out/deletion (now also
      server-purged on account delete/disable, Task 3).
- [ ] `docs/legal/terms-of-service.html` §7: one sentence that staff location
      is visible to administrators on the live staff map.
- [ ] `ios/Runner/Info.plist` `NSLocation*UsageDescription` strings (these
      SHIP to the App Store) currently only mention leave-time alerts —
      extend to cover manager visibility. (The Android foreground-notification
      string in `presence_sync_controller.dart` is dev-harness-only; update
      opportunistically.)
- [ ] CLAUDE.md: append the live-map read path to the presence bullet (admin
      collection-group read; `presenceStaleAfter` in sync with
      `PRESENCE_STALE_MINUTES`; `presence` subcollection name reserved by the
      wildcard rule; presence purge in `syncUsersByUid`); update the
      required-env section (`dev/.env` gains `IOS_MAPS_API_KEY`; Android
      needs `MAPS_API_KEY` in `local.properties`); note the client-Maps-keys
      vs server `GOOGLE_MAP_API_KEY` distinction and the
      `google_maps_flutter_ios_sdk9` SPM override.

## Task 12 — Tests

- [ ] `test/features/presence/live_map_aggregator_test.dart` (pure, fixed
      clock): join carries name/color; fix without user dropped;
      `disabled`/`invited` dropped; sorted by name; staleness boundary
      (24m59s fresh, 25m00s fresh, 25m01s stale; null fresh); freshness
      buckets (<60 s justNow; 1–59 min minutesAgo; ≥60 min hoursAgo).
- [ ] Trailing-flush helper (Task 4b): `trailingFlushDelay` boundary cases
      beside the existing `shouldWritePresenceFix`/`shouldHeartbeat` tests.
- [ ] `AddressParser` pass-through: `splitApt('45.5017,-73.5673')` returns
      null and `toCanonical`/`canonicalToDisplay` return the string unchanged
      (pins the coordinate-fallback launch path, Task 7).
- [ ] `functions/` jest: bridge isolation — when the presence purge throws,
      the `usersByUid` bridge mirror still writes (tests the wiring order,
      not just the pure decision helper).
- [ ] Provider test: a tick that flips no one's staleness leaves
      `staleDocIdsProvider` un-notified (same set instance / no dependent
      rebuild) and the marker set identical; a tick that crosses the 25-min
      boundary for one person rebuilds only that marker's icon variant.
- [ ] Screen test (pause-when-hidden): hosted under a fake `HubShellScope`
      with `current` ≠ liveMap, the presence stream/tick providers are not
      listened to (autoDispose released — assert via `ProviderContainer`
      observer or an override recording listener counts); flipping `current`
      to liveMap re-attaches.
- [ ] `test/features/presence/presence_repository_watch_test.dart`
      (mocktail, pattern of the existing `presence_repository_test.dart`,
      which stays untouched): collectionGroup snapshot → `PresenceFix` list
      with parent users-doc id; malformed doc skipped, siblings survive;
      missing `updatedAt` → null; stream error propagates.
- [ ] `test/features/presence/staff_marker_icon_test.dart`: renderer returns
      non-empty PNG bytes (dart:ui works in flutter_test); cache returns the
      identical object for the same key and distinct objects across
      stale/selected variants.
- [ ] `test/routes/hub_shell_test.dart` — update for the new destination
      (`screenBuilder` seam); assert the liveMap tab builds/selects.
- [ ] `test/features/presence/screens/live_map_screen_test.dart` —
      `ProviderScope` overrides + the `mapBuilder` stub (records the marker
      set; no platform view): marker set built for two staff; stale point
      flagged; tap → info card with name + freshness + resolved address
      (override `reverseGeocodeProvider`); address line hidden when the
      lookup errors; empty → `liveMap_emptyState`; error → error body. l10n
      delegates + `ThemeNotifier` wrapper per testing conventions.
- [ ] `functions/` jest tests — `placesReverseGeocode` is an `onCall` module
      (loads lazily, safe to `require` directly per CLAUDE.md): input
      validation (missing/out-of-range/non-numeric lat/lng rejected; bad
      locale rejected), coordinate rounding applied before the upstream
      call, formatted-address extraction from a stubbed Geocoding response,
      null on zero results. Plus the **presence-purge decision helper**:
      deleted doc → purge; `active`→`disabled` → purge; `active`→`active` →
      no purge; `invited`→`active` → no purge.

## Task 13 — Verification

- [ ] `flutter pub get` → `flutter gen-l10n` (check
      `lib/l10n/.gen/untranslated.json` clean) →
      `flutter analyze 2>&1 | grep -E "error -|warning -"` → `flutter test`.
- [ ] `cd functions && npm run lint && npm test`.
- [ ] Manual on the Android dev harness (Play-services AVD, App Check debug
      token registered), after the user deploys rules + functions and puts
      the Android key in `local.properties`: admin sees the Live map tab in
      rail/drawer; own marker appears (admins track too); traffic + satellite
      toggles work; freshness ticks; marker tap → info card shows name,
      freshness, and the resolved street address → Open in Maps launches with
      the address. Employee account → no Live map tab; presence self-writes
      still work (rules regression). Disable a test employee → their presence
      doc disappears from Firestore (purge trigger) and their marker leaves
      the map. Trailing flush: simulate movement then stop inside the 2-min
      gap (AVD route playback) → the presence doc updates ~when the gap
      expires, not 10 min later at the heartbeat.
- [ ] iOS remains Mac-side: SPM resolution of the Maps SDK, AppDelegate key
      parse, on-device map render — tracked in the handoff doc.

## Ordered sequence

Branch reset → pubspec + pub get → rules + purge trigger (early, so the user
can deploy) → Android manifest/gradle + iOS AppDelegate key wiring → domain
model/aggregator + pure tests → repository + tests → tracking trailing flush
(Task 4b) + tests → l10n + gen-l10n →
providers (incl. staleDocIds) → marker icon renderer + tests → screen +
widgets (incl. pause-when-hidden) →
reverse-geocode callable + client + tests → hub-tab wiring (enum, routes,
shell, drawer) → hub/screen tests → legal/docs/CLAUDE.md → verify → commit →
force-push `-u`.

## Risks

- **User-side prerequisites gate the demo:** two restricted client keys +
  Maps SDKs enabled + Geocoding API enabled on the `GOOGLE_MAP_API_KEY`
  restriction + rules AND functions deployed. Missing Android key ⇒ blank
  map ("Authorization failure" in logcat); missing rules ⇒ error state;
  missing Geocoding API ⇒ address line silently absent.
- **SPM override:** `google_maps_flutter_ios_sdk9` ships `Package.swift`
  (verified 2026-07-15) and pins Maps SDK 9.x / iOS 15 — matches the project
  exactly, but first Xcode open must resolve the new package (Mac step).
  Never fall back to plain `google_maps_flutter_ios` (CocoaPods-only →
  Podfile).
- **Marker bitmaps:** `BitmapDescriptor` API naming shifted across versions
  (`fromBytes` → `BitmapDescriptor.bytes`) — verify against the resolved
  version at pub get.
- **Legal-doc contradiction** — Task 11 is blocking for anything
  user-facing.
- Collection-group rule must stay caller-side only (`isAdmin()`); any
  `resource.data` condition breaks the unfiltered query's provability. The
  `{path=**}` wildcard reserves the subcollection name `presence`.
- `syncUsersByUid` is the auth-critical bridge — the presence purge added to
  it must stay isolated (post-bridge, own try/catch) so it can never break
  role resolution.
- `AddressMapLauncher` with raw "lat,lng" — RETIRED 2026-07-15: verified
  pass-through by inspection (see Task 7); pinned by a Task 12 unit test.
- Kept-alive GL platform view in the IndexedStack costs memory while on
  other tabs — accepted (camera state preserved). The data side does NOT
  stay hot: the screen un-watches the presence stream + tick when the tab
  isn't current (Task 7 pause-when-hidden), so the collectionGroup listener
  and ticker die with autoDispose while hidden.
- Task 4b touches the auth-adjacent tracking controller — keep the trailing
  timer strictly inside the existing throttle contract (cancel in `_stop()`,
  cancel on every real write) so it can never double-write or outlive the
  stream.
- Reverse-geocode spend is bounded three ways: tap-driven only, client-side
  ~11 m cache, server-side per-uid durable rate limit.
