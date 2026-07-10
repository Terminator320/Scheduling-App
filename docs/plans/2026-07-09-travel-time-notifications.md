# Travel-Time "Leave Now" Notifications — Implementation Plan

**Status: PLANNED — approved design 2026-07-09, not started.**
**Prerequisite: the push-notifications plan (`docs/plans/2026-07-08-push-notifications.md`) Phases 1–4 must be implemented first.**

## Context

Employees get no cue about when to depart for their next appointment. This feature
computes drive time from the employee's location to their next job and pushes a
"time to leave" notification so they arrive on time.

### Decisions made with the user (2026-07-09)

- **Origin location:** last-known GPS captured *while the app is in use*
  (when-in-use permission only), uploaded to Firestore. If stale → fall back to
  the previous appointment's address; if neither → fall back to a fixed 30-min
  reminder. **Live background GPS is a deferred future phase** — the
  origin-decision seam (`decideOrigin`) is designed so it slots in later.
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
   2. **Fresh GPS** — presence doc `updatedAt` ≤ 45 min old.
   3. **Recently-ended previous appointment's address** — newest non-terminal→
      ended job (non-empty address, `endTime` within the last 4 h).
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
`FALLBACK_LEAD_MINUTES = 30`, `PRESENCE_STALE_MINUTES = 45`,
`PREV_APPOINTMENT_LOOKBACK_HOURS = 4`.

Exports:
- `decideOrigin({presence, employeeAppointments, candidate, now})` →
  `{kind:'gps', lat, lng} | {kind:'address', address} | null`.
  Priority: intervening appointment (non-terminal, `startTime <
  candidate.startTime`, `endTime > now`, non-empty address) → fresh GPS
  (≤45 min) → recently-ended previous appointment (ended within 4 h) → null.
  `employeeAppointments` is the one per-employee context query result
  (terminal filtering uses the same set as `_terminalStatuses`: done /
  completed / cancelled). **This is the background-GPS seam** — a future phase
  only changes what writes the presence doc and tightens
  `PRESENCE_STALE_MINUTES`.
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

### 4. Flutter — presence capture + upload

**Package:** `geolocator: ^14.x` (`flutter pub add geolocator` — needs sandbox
disabled on this box). Chosen over `permission_handler`'s location group
(under SwiftPM there's no Podfile macro to strip unused permission groups;
geolocator keeps location contained in the one plugin that declares it) and it
provides `getLastKnownPosition`.

**New `lib/core/permissions/location_permission_service.dart`** — mirrors
`MediaPermissionService`:
`enum LocationPermissionResult {granted, denied, permanentlyDenied, servicesDisabled}`;
`Future<LocationPermissionResult> ensureWhenInUse()` wrapping geolocator's
`isLocationServiceEnabled()` + `checkPermission()` + `requestPermission()`;
injectable function fields for tests; `locationPermissionServiceProvider`.

**New `lib/features/presence/data/presence_repository.dart`** —
`PresenceRepository(FirebaseFirestore, {AppLogger? logger})`:
- `upsertLocation({userDocId, uid, lat, lng})` → `set` on
  `users/{docId}/presence/location` with
  `{lat, lng, uid, updatedAt: FieldValue.serverTimestamp()}` —
  log-and-swallow, never throws into callers.
- `deleteLocation({userDocId})` — best-effort, called on sign-out (privacy: no
  stale coordinates after leaving).

**New `lib/features/presence/application/presence_sync_controller.dart`:**
- Pure top-level
  `bool shouldUploadPresence({role, status, signedIn, lastUploadAt, now})` —
  employee ∧ active ∧ signed-in ∧ (`lastUploadAt == null` ∨ ≥10 min elapsed).
- `presenceSyncProvider` — gated exactly like the push plan's
  `pushRegistrationProvider` (watches `currentUserDocProvider` +
  `userRoleProvider` + `firebaseReadyProvider`; resolves own users doc id via
  `findUserByUid`). Owns an `AppLifecycleListener(onResume: _maybeUpload)` plus
  an initial upload on activation. `_maybeUpload`: pure-gate check →
  `ensureWhenInUse()` → **silent no-op on denied/permanentlyDenied/servicesDisabled**
  (the OS prompt appears once on first resume as an employee; never nag) →
  `getCurrentPosition(LocationSettings(accuracy: medium, timeLimit: 10s))`,
  falling back to `getLastKnownPosition()` on timeout → `upsertLocation`.
  Admins: hard no-op, never prompted.

**Modify `lib/main.dart`** (`_PaulAppState`): activate `presenceSyncProvider`
alongside `pushRegistrationProvider`. Sign-out path: best-effort
`deleteLocation` next to the push plan's token unregister (try/catch +
`logger.warn`, never block sign-out).

**Manifests:**
- `android/app/src/main/AndroidManifest.xml`: add
  `ACCESS_COARSE_LOCATION` + `ACCESS_FINE_LOCATION` (geolocator requires both
  declared even for when-in-use).
- `ios/Runner/Info.plist`: add `NSLocationWhenInUseUsageDescription` — "Your
  location while using the app tells you when it's time to leave for your next
  appointment." No background modes, no `NSLocationAlways*` keys.

### 5. Tests

**Jest — `functions/__tests__/travel_utils.test.js`:**
- `decideOrigin` full chain + boundaries: intervening appointment beats fresh
  GPS; intervening marked `done`/`cancelled` is skipped (GPS takes over);
  intervening with empty address skipped; fresh vs exactly-45-min presence;
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
- `shouldUploadPresence`: role/status/signed-in gating; throttle boundary
  (9 min 59 s vs 10 min, injected `now`).
- `PresenceRepository` with mocktail-mocked Firestore (remember
  `(captured as Map).cast<String, dynamic>()`).
- `LocationPermissionService` mapping with injected fakes
  (servicesDisabled / denied / deniedForever / granted).
- No plugin-channel tests for geolocator itself (same policy as
  `ImagePickerService` — device verification instead).

## Failure guarantees

| Failure | Behavior |
|---|---|
| Routes non-200 / transport throw / bad JSON / no route | null → 30-min fixed lead, plain `reminder` text |
| Back-to-back jobs (earlier job still occupies the employee) | origin = that job's address, not GPS |
| Presence doc absent or >45 min stale | recently-ended previous appointment's address |
| No intervening job, no fresh GPS, no recent previous job | 30-min fixed lead |
| Appointment `address` empty | 30-min fixed lead; Routes never called |
| One (appointment × employee) pair throws | caught + `logger.warn`, sweep continues |
| Location permission denied on device | silent client no-op; server falls through the chain |
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
  address. Employee sign-in → app resume → `users/{docId}/presence/location`
  appears; second resume within 10 min → `updatedAt` unchanged (throttle).
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
location permission prompt wording (Info.plist), real-device APNs delivery of
the `leaveNow` push, **Time Sensitive Notifications capability** (Xcode →
Signing & Capabilities; entitlement
`com.apple.developer.usernotifications.time-sensitive`) so `leaveNow` breaks
through Focus modes, and App Attest–gated presence writes on hardware. All
other Xcode-side push work is already the push plan's Phase 6; this feature
adds only the Info.plist key (authored on Windows).

## Future phase (explicitly out of scope for v1)

- **Live background GPS:** `NSLocationAlwaysAndWhenInUse` + background modes +
  App Store review justification + privacy policy update. Slots in behind
  `decideOrigin` — only the presence writer and `PRESENCE_STALE_MINUTES`
  change; nothing downstream moves.
- **In-app "travel notifications" toggle:** would need a Firestore-backed
  user-doc field (the server must read it); v1 follows the push plan — the OS
  notification permission is the switch.
- **`travelEstimates` cache** if the Maps bill ever warrants it.
