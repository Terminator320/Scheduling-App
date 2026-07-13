# Travel-Time "Leave Now" Notifications — Implementation Plan

**Status: REVISED 2026-07-13 — v1 now ships with LIVE BACKGROUND GPS (design approved; supersedes the 2026-07-09 while-in-use-only design).**
**Prerequisite: the push-notifications plan (`docs/plans/2026-07-08-push-notifications.md`) Phases 1–4 — implemented and deployed 2026-07-11. Met.**

## Context

Employees get no cue about when to depart for their next appointment. This feature
computes drive time from the employee's location to their next job and pushes a
"time to leave" notification so they arrive on time.

### Decisions made with the user (2026-07-09)

- **Origin location (revised 2026-07-13):** **live background GPS.** A
  geolocator background position stream keeps `users/{docId}/presence/location`
  fresh while the app is foregrounded OR backgrounded/screen-off ("backgrounded
  app" depth — tracking stops on force-quit/reboot until the next app open;
  the survives-force-quit tier via paid plugins was explicitly rejected).
  Employee control is the **OS location permission only** — no in-app toggle
  (same philosophy as push). If presence is stale → fall back to the previous
  appointment's address; if neither → fall back to a fixed 30-min reminder.
  A while-in-use-only grant (iOS lets users downgrade) degrades gracefully:
  the stream simply stops delivering in background and the fallback chain
  covers it.
- **Upload discipline (2026-07-13):** stream `distanceFilter: 250` m, uploads
  throttled to ≥2 min apart, plus a **10-min heartbeat** re-upsert of the last
  known position so a *stationary* employee's doc stays fresh — freshness means
  "tracking is alive", not "recently moved". Server staleness window
  `PRESENCE_STALE_MINUTES = 25` (two missed heartbeats + slack; stale now
  reliably means tracking is dead, so the address fallback is correct).
- **Delivery:** FCM push from a scheduled Cloud Function, built on the push plan.
- **Travel time:** Google Routes API `computeRoutes` with traffic
  (`TRAFFIC_AWARE`), server-side only, same Secret Manager key as Places
  (`GOOGLE_MAP_API_KEY`).
- **Timing:** single notification at `startTime − travelTime − 10 min buffer`.

### Key design findings

- Routes API waypoints accept raw **address strings**, so there is no Geocoding
  API dependency, no lat/lng cache on appointment docs, and **zero changes to
  the appointment form** — GPS origin goes in as `location.latLng`; the
  fallback origin and the destination go in as `{address: "..."}`.
- **Status filter (aligned with the push plan's 2026-07-09 revision):**
  candidates are `status in ['pending', 'confirmed']` — `confirmed` was
  retired 2026-07-09 (rules + `_allowedStatuses` reject new writes) but there
  was no data migration, so pre-retirement docs may still carry it and the app
  treats it as pending (`AppointmentStatus.fromRaw`). Keep it in the filter
  until legacy docs age out. `in_progress` is deliberately excluded (visit
  already started).
- The reminder ledger key gains an employee dimension:
  `${appointmentId}_${startTimeMillis}_${employeeDocId}` — each crew member on
  a multi-assignee job has their own origin and therefore their own leave time.
  Reschedules still re-key (fresh reminder); exactly-once per
  (employee, appointment, scheduled time) is preserved by ledger `create()`.

## Architecture

The push plan's `sendUpcomingJobReminders` sweep
(`onSchedule('every 5 minutes')`, `timeZone: 'America/Toronto'`,
`maxInstances: 1`) is **modified in place** to become travel-aware — one sweep,
one notification per (employee, appointment), no second scheduled function.

Per sweep, for each candidate appointment (`status in ['pending', 'confirmed']`
— legacy alias, see above) with `startTime ∈ (now, now + 90min]`, per assigned
employee (each pair in its own try/catch):

1. **Ledger short-circuit:** skip if
   `appointmentReminders/{apptId}_{startMillis}_{empDocId}` exists (cheap `get`
   before any Routes spend; the atomic `create()` at send time remains the real
   guard).
2. **Decide origin** (`decideOrigin`), priority order:
   1. **Intervening appointment's address** — another non-terminal appointment
      of the same employee with `startTime < candidate.startTime` and
      `endTime > now` (they'll depart from *that* job, not from wherever they
      are now — critical for back-to-back bookings; marking the earlier job
      `done` makes it terminal, which promotes GPS below).
   2. **Fresh GPS** — presence doc `updatedAt` ≤ 25 min old (the background
      stream's 10-min heartbeat keeps a live tracker well inside this).
   3. **Recently-ended previous appointment's address** — newest job whose
      `endTime` passed within the last 4 h, non-empty address, any status
      except `cancelled` (a cancelled visit never happened; a `done` one did —
      the employee was physically there).
   4. **null** → fixed 30-min fallback.

   Prongs 1 and 3 are served by ONE per-employee query
   (`employeeIds array-contains E`, `endTime > now − 4h`, `orderBy endTime` —
   existing `(employeeIds CONTAINS, endTime ASC, startTime ASC)` index),
   partitioned in memory by `endTime > now`.
3. **Compute lead:** origin non-null ∧ appointment address non-empty →
   Routes API → `leadMinutes = min(ceil(travelSeconds/60) + 10, 90)`.
   Origin null, empty address, or any Routes failure →
   `leadMinutes = 30` and the plain `reminder` message kind.
4. **Fire:** if `now >= startTime − lead`: ledger `create()` (skip on
   ALREADY_EXISTS) → send localized `leaveNow` push to that one employee's
   `fcmTokens` via the push plan's per-token send + stale-token cleanup.
5. **Per-sweep batching:** collect the distinct employee doc ids across all
   candidates first, then `db.getAll()` their presence docs in one round-trip
   and run the per-employee appointment-context query ONCE per employee —
   reused across all of that employee's candidates in the sweep (an employee
   with two jobs in the window costs one presence read + one context query,
   not two of each).
6. **Cost stance:** recompute Routes each sweep deliberately — ≤16 sweeps per
   pair inside the 90-min window, Routes Essentials TRAFFIC_AWARE ≈ $5/1k
   calls (worst realistic day ≈ $1–2), and recomputing self-corrects as traffic
   and the employee's position change. A `travelEstimates` cache is a deferred
   optimization; keep the Maps billing alert.

## Changes

### 1. Firestore schema + rules

**New single doc `users/{docId}/presence/location`:** `{lat, lng, uid, updatedAt}`.
Deliberately NOT on the users doc: active users can read active peers' user
docs (location would leak to peers — staff-tracking optics), and employees
cannot write their own users doc (update is admin-only).

**`firestore.rules`** — new block inside `match /users/{userId}`, sibling of the
push plan's `fcmTokens` block:

```
match /presence/{presenceId} {
  // Self-only; peers/admins read nothing client-side (sweep uses Admin SDK).
  allow read, delete: if isActiveUser() && myDocId() == userId;
  allow create, update: if isActiveUser()
    && myDocId() == userId
    && presenceId == 'location'
    && request.resource.data.keys().hasOnly(['lat', 'lng', 'updatedAt', 'uid'])
    && request.resource.data.lat is number
    && request.resource.data.lat >= -90 && request.resource.data.lat <= 90
    && request.resource.data.lng is number
    && request.resource.data.lng >= -180 && request.resource.data.lng <= 180
    && request.resource.data.updatedAt == request.time
    && request.resource.data.uid == request.auth.uid;
}
```

(`updatedAt == request.time` forces `FieldValue.serverTimestamp()` — a client
can't post a future timestamp to make a stale location look fresh.)

(An employee spoofing their own coordinates only games their own reminder —
acceptable; the freshness check bounds the damage.)

`appointmentReminders` stays Admin-SDK-only deny-all (push plan Phase 2); only
the doc-id format changes.

**Indexes: none needed.** Sweep query uses the existing
`(status ASC, startTime ASC)` composite; the previous-appointment fallback
query (`employeeIds array-contains` + `endTime` range, `orderBy endTime`) is
served by the existing `(employeeIds CONTAINS, endTime ASC, startTime ASC)`
index (verified in `firestore.indexes.json`).

### 2. Cloud Functions

**New `functions/travel_utils.js`** — pure module, no admin/scheduler requires
(the `image_magic.js` / `signup_code_utils.js` jest convention).

Constants: `BUFFER_MINUTES = 10`, `MAX_LEAD_MINUTES = 90`,
`FALLBACK_LEAD_MINUTES = 30`, `PRESENCE_STALE_MINUTES = 25`,
`PREV_APPOINTMENT_LOOKBACK_HOURS = 4`.

Exports:
- `decideOrigin({presence, employeeAppointments, candidate, now})` →
  `{kind:'gps', lat, lng} | {kind:'address', address} | null`.
  Priority: intervening appointment (non-terminal, `startTime <
  candidate.startTime`, `endTime > now`, non-empty address) → fresh GPS
  (≤25 min) → recently-ended previous appointment (ended within 4 h) → null.
  `employeeAppointments` is the one per-employee context query result
  (terminal filtering uses the same set as `_terminalStatuses`: done /
  completed / cancelled). The origin seam absorbed the background-GPS upgrade
  exactly as designed: only the presence writer (now a background stream) and
  `PRESENCE_STALE_MINUTES` changed; nothing downstream moved.
- `selectTravelCandidates(docs, now)` — status pending (+ legacy `confirmed`),
  `now < startTime <= now+90min`.
- `computeLeadMinutes(travelSeconds)` — `min(ceil(s/60)+10, 90)`; `null` → 30.
  (Cap means a >80-min drive fires at the first sweep inside the window —
  accepted.)
- `isDue({startTimeMillis, leadMinutes, nowMillis})`.
- `buildRoutesRequestBody({origin, destinationAddress, departureTimeIso})` —
  `travelMode: 'DRIVE'`, `routingPreference: 'TRAFFIC_AWARE'`.
- `parseRoutesDurationSeconds(json)` — parses `routes[0].duration` (`"1234s"`),
  `null` on any malformed shape.
- `computeTravelSeconds({fetchImpl, apiKey, origin, destinationAddress, now, logger})`
  — POST `https://routes.googleapis.com/directions/v2:computeRoutes`, header
  `X-Goog-FieldMask: routes.duration`, `departureTime = now + 60s` ISO (Routes
  rejects past times). `places.js` error discipline: transport catch → warn →
  null; non-200 → 200-char body preview log → null; bad JSON → null.
  **Returns null on every failure — never throws.** Injected `fetchImpl` for jest.
- `travelReminderLedgerId(appointmentId, startTimeMillis, employeeDocId)`.
- `runTravelAwareReminderSweep(deps)` — orchestrator with injected
  `{db, messaging, fetchImpl, apiKey, now, logger}` (push-plan
  `runReminderSweep` style).

**Modify `functions/notification_utils.js`** (created by the push plan): add
kind `leaveNow` to `buildNotificationMessage`, extra param `travelMinutes`:
- EN: "Time to leave — {clientName} at {time}" /
  "About {N} min drive · {address}"
- FR: "C'est l'heure de partir — {clientName} à {time}" /
  "Environ {N} min de route · {address}"

Server-side inline EN/FR only — no ARB keys; v1 has **no in-app UI strings**.

`leaveNow` messages additionally set
`apns.payload.aps['interruption-level'] = 'time-sensitive'` — a departure
alert is useless if it sits in a Focus-mode notification summary. Requires the
**Time Sensitive Notifications** capability in Xcode (Mac handoff below);
until that entitlement lands, iOS silently downgrades it to `active` — safe to
ship server-first. Other kinds keep the default level.

**Modify `functions/notifications.js`** `sendUpcomingJobReminders`: same
schedule; add `secrets: [GOOGLE_MAP_API_KEY]` (`defineSecret` as in
`places.js`) and `timeoutSeconds: 120`; body delegates to
`runTravelAwareReminderSweep`. Expose a single-employee send helper from the
push plan's `sendToEmployees` if not already factored that way. Whole handler
in try/catch + `logger.error`.

**No `functions/account.js` change:** the push plan's `deleteAccount` uses
Admin SDK `recursiveDelete(userDocRef)`, which already removes the `presence`
subcollection along with `fcmTokens` and the doc.

**`functions/index.js`:** no new export (the sweep is already re-exported by
the push plan).

### 3. Console (manual, one-time)

Project `schedulingapp-88727`:
1. APIs & Services → enable **Routes API** (no Geocoding API needed).
2. Credentials → the key stored as Secret Manager `GOOGLE_MAP_API_KEY`: add
   Routes API to its API restriction allowlist.
3. Confirm/extend the Maps Platform billing alert (same caveat as `places.js`).

No new secret; nothing enters `dev/.env` (server-side only per CLAUDE.md).

### 4. Flutter — live background presence stream (revised 2026-07-13)

**Package:** `geolocator: ^14.x` (`flutter pub add geolocator` — needs sandbox
disabled on this box). Chosen over `permission_handler`'s location group
(under SwiftPM there's no Podfile macro to strip unused permission groups;
geolocator keeps location contained in the one plugin that declares it), it
provides `getPositionStream` with per-platform background settings, and
`geolocator_apple` ships SwiftPM support (required — no Podfile).

**New `lib/core/permissions/location_permission_service.dart`** — mirrors
`MediaPermissionService`:
`enum LocationPermissionResult {granted, denied, permanentlyDenied, servicesDisabled}`;
`Future<LocationPermissionResult> ensureLocation()` wrapping geolocator's
`isLocationServiceEnabled()` + `checkPermission()` + `requestPermission()`.
With BOTH usage-description keys in Info.plist, iOS runs the provisional
Always flow (user sees the while-in-use prompt; iOS confirms Always later),
so `LocationPermission.whileInUse` AND `.always` both map to `granted` —
while-in-use is a *working degraded mode* (no background delivery), never an
error. Injectable function fields for tests; `locationPermissionServiceProvider`.

**New `lib/features/presence/data/presence_repository.dart`** —
`PresenceRepository(FirebaseFirestore, {AppLogger? logger})`:
- `upsertLocation({userDocId, uid, lat, lng})` → `set` on
  `users/{docId}/presence/location` with
  `{lat, lng, uid, updatedAt: FieldValue.serverTimestamp()}` —
  log-and-swallow, never throws into callers.
- `deleteLocation({userDocId})` — best-effort, called on sign-out (privacy: no
  stale coordinates after leaving).

**New `lib/features/presence/application/presence_sync_controller.dart`** —
mirrors `PushRegistrationController` (provider + `sync()` driven from
`main.dart`, `_busy`/`_pendingResync` reentrancy guard, gate re-checked every
call):
- Pure top-level helpers (unit-tested, no plugins):
  - `bool shouldTrackPresence({required String role, required String status,
    required bool signedIn})` — employee ∧ active ∧ signed-in. Admins: hard
    no-op, never prompted. (Deliberately narrower than `shouldRegisterPush`,
    which includes admins.)
  - `bool shouldWritePresenceFix({required DateTime? lastUploadAt,
    required DateTime now})` — `lastUploadAt == null` ∨ ≥2 min elapsed
    (`minUploadGap`). Movement granularity itself comes from the stream's
    250 m `distanceFilter`; this guards Firestore write volume on a highway.
  - `bool shouldHeartbeat({required DateTime? lastUploadAt,
    required DateTime now})` — lastUploadAt != null ∧ ≥10 min elapsed
    (`heartbeatEvery`); the timer tick re-upserts the last known position so a
    stationary employee stays fresh (their old coordinates are still correct).
- `sync()`: gate fails → `_stop()` (cancel stream + heartbeat timer; keep the
  presence doc — sign-out deletes it). Gate passes and stream already live for
  this uid → no-op fast path. Otherwise: `ensureLocation()` → **silent no-op on
  denied/permanentlyDenied/servicesDisabled** (the one OS prompt appears on
  first activation as an employee; never nag) → resolve own users-doc id via
  `findUserByUid` (as push does) → start:
  - `Geolocator.getPositionStream(locationSettings: _settingsForPlatform())`
    where iOS gets `AppleSettings(accuracy: LocationAccuracy.medium,
    distanceFilter: 250, activityType: ActivityType.automotiveNavigation,
    allowBackgroundLocationUpdates: true, showBackgroundLocationIndicator:
    true, pauseLocationUpdatesAutomatically: true)` and Android gets
    `AndroidSettings(accuracy: LocationAccuracy.medium, distanceFilter: 250,
    foregroundNotificationConfig: ForegroundNotificationConfig(...))` — the
    foreground-service notification is what keeps the stream alive in
    background on Android (dev harness; text can be plain English, it never
    ships).
  - Platform branch uses `defaultTargetPlatform` (no BuildContext in a
    controller; the `context.isCupertino` seam is for UI look, and this is
    device capability — same rationale as `AddressMapLauncher`).
  - Stream listener: keep `_lastPosition`; if `shouldWritePresenceFix` →
    `upsertLocation` + stamp `_lastUploadAt`.
  - `Timer.periodic(heartbeatEvery ~ 10 min)`: if stream alive ∧
    `shouldHeartbeat` ∧ `_lastPosition != null` → re-upsert.
  - Stream `onError`: `logger.warn('PRESENCE stream error', e, st)` + `_stop()`
    (a revoked permission kills the stream); the next `sync()` (account-doc
    emission or app resume) retries the whole gate.
  - An `AppLifecycleListener(onResume:)` calls `sync()` — restarts a dead
    stream after the user flips permission in system Settings, and pushes one
    immediate fix on return to foreground.
- `unregister()`: called from sign-out — `_stop()` + best-effort
  `deleteLocation` (try/catch + `logger.warn`, never block sign-out).

**Modify `lib/main.dart`** (`_PaulAppState`): a `_listenForPresenceSync()`
sibling of `_listenForPushRegistration()` — `ref.listen(currentUserDocProvider,
… sync())` plus the same eager first `sync()` (relaunch-while-authed can beat
the listener registration). Sign-out path: `presenceSyncControllerProvider`
`.unregister()` next to `unregisterCurrentDevice()`.

**Manifests:**
- `android/app/src/main/AndroidManifest.xml`: add `ACCESS_COARSE_LOCATION`,
  `ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION` (Android 10+ background
  delivery), and `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION`
  (Android 14 requires the typed foreground-service permission in the app
  manifest for geolocator's service).
- `ios/Runner/Info.plist`:
  - `NSLocationWhenInUseUsageDescription` — "Your location tells you when it's
    time to leave for your next appointment."
  - `NSLocationAlwaysAndWhenInUseUsageDescription` — "Allowing location in the
    background keeps your 'time to leave' alerts accurate even when the app is
    closed."
  - `UIBackgroundModes` gains `location` (array already exists with
    `remote-notification`). This IS the Xcode "Background Modes → Location
    updates" capability — authored here on Windows; nothing extra on the Mac
    for it.

### 5. Tests

**Jest — `functions/__tests__/travel_utils.test.js`:**
- `decideOrigin` full chain + boundaries: intervening appointment beats fresh
  GPS; intervening marked `done`/`cancelled` is skipped (GPS takes over);
  intervening with empty address skipped; fresh vs exactly-25-min presence;
  previous-appointment filters (terminal-status handling, empty address
  skipped, outside 4-h lookback skipped, newest `endTime` wins); nothing →
  null.
- `computeLeadMinutes`: round-up, +10 buffer, 90 cap, null → 30.
- `isDue` boundary (exactly at `startTime − lead`).
- `selectTravelCandidates` window edges + status filter (`in_progress` /
  `done` / `cancelled` excluded; legacy `confirmed` included as pending).
- `buildRoutesRequestBody` both origin kinds; `parseRoutesDurationSeconds`
  good/missing/garbage shapes.
- `computeTravelSeconds` with fake `fetchImpl`: 200 happy path; non-200 →
  null; transport throw → null; invalid JSON → null.
- `runTravelAwareReminderSweep` with injected mocks: Routes failure → 30-min
  fallback still sends; existing ledger doc short-circuits before any fetch;
  one throwing pair doesn't stop the others; ledger id includes employeeDocId.
- Update `notification_utils.test.js`: `leaveNow` EN/FR formatting.
- `cd functions && npm run lint && npm test`.

**Flutter — `test/features/presence/`:**
- `shouldTrackPresence`: role/status/signed-in gating (admin excluded).
- `shouldWritePresenceFix`: throttle boundary (1 min 59 s vs 2 min, injected
  `now`); null `lastUploadAt` → true.
- `shouldHeartbeat`: boundary at 10 min; null `lastUploadAt` → false.
- `PresenceRepository` with mocktail-mocked Firestore (remember
  `(captured as Map).cast<String, dynamic>()`).
- `LocationPermissionService` mapping with injected fakes
  (servicesDisabled / denied / deniedForever / whileInUse→granted /
  always→granted).
- No plugin-channel tests for geolocator itself (same policy as
  `ImagePickerService` — device verification instead; the background stream is
  device-only behavior).

## Failure guarantees

| Failure | Behavior |
|---|---|
| Routes non-200 / transport throw / bad JSON / no route | null → 30-min fixed lead, plain `reminder` text |
| Back-to-back jobs (earlier job still occupies the employee) | origin = that job's address, not GPS |
| Presence doc absent or >25 min stale | recently-ended previous appointment's address |
| No intervening job, no fresh GPS, no recent previous job | 30-min fixed lead |
| Appointment `address` empty | 30-min fixed lead; Routes never called |
| One (appointment × employee) pair throws | caught + `logger.warn`, sweep continues |
| Location permission denied on device | silent client no-op; server falls through the chain |
| Permission downgraded to while-in-use | stream delivers only while foregrounded; presence goes stale in background → address fallback |
| App force-quit / phone rebooted | stream dead until next app open (accepted depth); presence stale → address fallback |
| Stream error (permission revoked mid-run) | `logger.warn` + stop; next `sync()` (resume / account emission) retries the gate |
| Duplicate sends | ledger `create()` atomicity; no `retry: true` |

## Sequencing

1. **Prerequisite:** push plan Phases 1–4 implemented and verified (the push
   plan doc was revised 2026-07-09 to the retired-`confirmed` status model —
   legacy alias kept in queries). Phases 5–6 (widget, Mac) are independent of
   this feature.
2. **T1 — Functions:** `travel_utils.js` + tests → `notification_utils.js`
   `leaveNow` kind → `notifications.js` sweep rewrite (+ secret, timeout).
   Lint + jest.
3. **T2 — Rules:** presence block in `firestore.rules`. No index changes.
4. **T3 — Console:** Routes API enable + key restriction + billing alert.
   (Safe in either order vs T5 — before enablement the sweep just logs
   fallbacks.)
5. **T4 — Flutter:** geolocator, `LocationPermissionService`,
   `PresenceRepository`, `presence_sync_controller`, `main.dart` + sign-out
   wiring, both manifests. `flutter analyze` + `flutter test`.
6. **T5 — Deploy:** `firebase deploy --only firestore:rules` then
   `--only functions:sendUpcomingJobReminders`.

## Verification

**On this Windows box (Android emulator/device):**
- Emulator Extended Controls → Location → set a point ~20 min from a test
  address. Employee sign-in → `users/{docId}/presence/location` appears and
  the geolocator foreground-service notification shows.
- Background the app → move the emulator location >250 m → presence doc
  updates without reopening the app (background stream). Two moves inside
  2 min → one write (throttle). Leave it stationary >10 min → `updatedAt`
  refreshes anyway (heartbeat).
- Seed a pending appointment ~60 min out at a real address → push arrives at
  ≈ `startTime − travel − 10` (function logs show the computed duration), not
  at −30.
- Back-to-back path: seed an ongoing job (started, not done) plus a second job
  ~60 min out → the second job's leave time is computed from the FIRST job's
  address even with fresh GPS elsewhere; mark the first job done → next sweep
  switches the origin to GPS.
- Stale-presence path: backdate/delete presence, seed a recently-ended prior
  appointment at a known address → logs show address-origin route.
- Full-fallback path: no presence + no prior job → −30 push with plain
  reminder text.
- Failure injection: temporarily remove Routes API from the key restriction →
  sweep logs upstream failure, −30 fallback still delivered, other pairs
  unaffected.
- Rules: employee writes own presence OK; another user's presence or extra
  fields → permission-denied.
- FR-locale device receives the French `leaveNow` text.

**Needs the Mac** (append to `docs/plans/IOS_APP_STORE_HANDOFF.md`): iOS
location permission prompt wording + the provisional-Always confirmation flow,
background delivery on a real device (blue location indicator while
backgrounded), real-device APNs delivery of the `leaveNow` push, **Time
Sensitive Notifications capability** (Xcode → Signing & Capabilities;
entitlement `com.apple.developer.usernotifications.time-sensitive`) so
`leaveNow` breaks through Focus modes, and App Attest–gated presence writes on
hardware. All other Xcode-side push work is already the push plan's Phase 6;
this feature's Info.plist keys AND the location background mode are authored on
Windows (UIBackgroundModes edit — no separate entitlement).

**App Store submission items (user-owned, not code):** App Review note
justifying Always + background location ("field employees receive 'time to
leave' alerts computed from live drive time to their next appointment"); App
Store Connect privacy form gains precise-location collection (linked to
identity, not used for tracking); privacy policy gains a location clause.

## Future phase (explicitly out of scope for v1)

- **Survives-force-quit tracking:** iOS significant-location-change relaunch /
  the paid `flutter_background_geolocation` plugin. Rejected 2026-07-13 for v1
  (hardest App Store justification, worst surveillance optics); the same
  `decideOrigin` seam absorbs it if ever wanted.
- **In-app "travel notifications" / background-location toggle:** decided
  against 2026-07-13 — the OS location permission is the one switch (matches
  the push plan's philosophy).
- **`travelEstimates` cache** if the Maps bill ever warrants it.
