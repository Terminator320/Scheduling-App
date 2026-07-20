# iOS Live Activities — Implementation Plan

Companion to the design decision
[`2026-07-19-ios-live-activities.md`](./2026-07-19-ios-live-activities.md).
That doc is the *what/why* (chosen visual direction, architecture, failure
posture). This is the *how* — files, order, tests, Mac steps — grounded in the
code that already exists.

**Status: Tasks 1–12 BUILT 2026-07-19. Task 13 (secrets) is owner-only and
blocks every deploy and all verification.**

Landed: `params.js` APNs secrets, `apns_client.js`, `live_activity_utils.js`,
`live_activity_registry.js` (+ the `liveActivityCards` marker collection),
`live_activity_dispatch.js`, the `travel_utils.js` start hook + marker-driven
on-site flip pass, the `notification_utils.js` update/end hooks, the
`firestore.rules` `liveActivityTokens` + `liveActivityCards` rules,
`lib/features/live_activity/` with its `main.dart` / sign-out / `_setStatusOnRepo`
wiring, and the Swift in `ios/ScheduleWidget/` (attributes, activity UI,
Directions intent, `WidgetBundle` `@main` move, `NSSupportsLiveActivities`).

Verified on Windows: functions lint clean, **420 jest tests green**, flutter
analyze clean, **962 flutter tests green**, rules validate, no BOMs. The Swift
is NOT compiled — that and every runtime behavior wait on the Mac.

### Design changes made during the build

- The `appointmentId` **cannot** be written on the client's token row (a
  push-started activity's id is minted by ActivityKit and its attributes aren't
  readable back), so the `liveActivityCards/{employeeDocId}` marker — written
  server-side at start — became the appointment↔card association that update
  and end resolve through. Not in the original design; it is now load-bearing.
- The on-site flip reads those markers rather than querying every
  recently-started appointment each 5-minute sweep.
- See also the `PushRegistrationController` correction below.

## Correction to the design doc's gotcha list

The design doc says `PushRegistrationController._registeredToken` "must become a
set." **It must not.** An FCM token genuinely is one-per-device and that cache is
correct as written; touching it would risk the shipped push path for no gain.
The real constraint is that the *new* Live Activity controller tracks **one
update token per activity** — so it keeps a `Map<activityId, token>`, and the
one-token-per-device shape is simply not copied over. Everything else in that
list stands.

---

## Windows-buildable (Tasks 1–8)

### Task 1 — `functions/params.js`: APNs secrets

Add `APNS_AUTH_KEY` (`.p8` contents), `APNS_KEY_ID`, `APNS_TEAM_ID` beside
`GOOGLE_MAP_API_KEY`, exported from the same module. A secret may only be
`defineSecret`'d once — never re-define these in a feature module.

### Task 2 — `functions/apns_client.js`: direct APNs HTTP/2 client

FCM cannot send `apns-push-type: liveactivity`, so this is the one path that
talks to APNs directly.

- ES256 provider JWT from the `.p8`, signed with `node:crypto` (no new
  dependency), **cached and re-minted at ~50 min** (APNs rejects tokens older
  than 1 h and rate-limits re-minting under 20 min).
- `sendLiveActivityPush({token, topic, pushType, payload, ...})` over
  `node:http2` against `api.push.apple.com`, headers `apns-push-type:
  liveactivity`, `apns-topic: <bundleId>.push-type.liveactivity`,
  `apns-priority: 10`.
- Every export takes injected `{now, signer, session}` style deps so jest can
  drive it without a socket.
- Never throws to the caller: returns `{ok, status, reason}`. A `410`/
  `BadDeviceToken` means the activity is gone — the caller prunes that token row.

### Task 3 — `functions/live_activity_utils.js`: pure payload logic

Jest-testable, no Firebase, no network:

- `buildContentState({clientName, address, startTime, leaveAt, travelMinutes,
  phase})` — the ActivityKit content state the Swift `ContentState` decodes.
- `buildStartPayload` / `buildUpdatePayload` / `buildEndPayload` — the
  `aps` envelope (`timestamp`, `event`, `content-state`, `attributes-type`,
  `alert`, `stale-date`, `dismissal-date`).
- `liveActivityStrings(locale)` — EN/FR card text, sourced from the **same**
  `_MESSAGES`-style table shape as `notification_utils.js` (rejected:
  `NSLocalizedString` in Swift, which would fork translations outside the ARBs).
- `phaseFor({startTime, now})` — `travel` before `startTime`, `onSite` after.
  Clock-derived, mirroring `AppointmentRecord.displayStatus`; **no
  `markInProgress` write path is added.**

### Task 4 — `functions/live_activity_registry.js`: token registry reads

`collectionGroup('liveActivityTokens')` reads + prune, same shape as the
presence read. Doc id is the `activityId`; fields `{token, kind:
'pushToStart'|'update', appointmentId, employeeDocId, locale, uid, platform,
createdAt, updatedAt, expiresAt}`. Includes the TTL prune the design doc's
"Still open" section flagged, so a card the server never ends can't leak a row.

### Task 5 — start hook in `functions/travel_utils.js`

Immediately **after** the `deliverRecipientOnce` call, gated on
`kind === 'leaveNow' && delivered > 0`. Capture the return in a local rather
than `+=`-ing it directly — a start placed before the claim would double-fire on
a claim collision. Best-effort, its own try/catch: a Live Activity failure must
never affect `reminded`.

### Task 6 — update/end hooks in `functions/notification_utils.js`

At the `handleAppointmentWrite` event loop: `rescheduled` → update,
`cancelled`/`removed` → end. Mirrors the existing `augmentData` precedent for
per-locale payloads. Plus the **on-site flip backstop**: a second pass in the
existing 5-minute sweep pushes one update for cards whose `startTime` has
passed. No new scheduler.

### Task 7 — `firestore.rules`: `liveActivityTokens`

Mirror the `fcmTokens` rule with a changed `hasOnly` allowlist and
`platform in ['ios']`. Self-only; the server reads via the Admin SDK.

### Task 8 — Dart: `lib/features/live_activity/`

- `pubspec.yaml`: `live_activities: ^2.5.1` (ships `Package.swift` — clears the
  SPM-only gate).
- `shouldRegisterLiveActivity` **delegates to** `shouldRegisterPush` — never
  re-inline the body, or the audiences drift (the rule `shouldTrackPresence`
  already follows).
- `LiveActivityRegistrationController` — mirrors `PushRegistrationController`
  (provider + `main.dart`-driven `sync()` per account-doc emission, `_busy` /
  `_pendingResync`): registers the **push-to-start** token and each per-activity
  **update** token into `users/{docId}/liveActivityTokens/{activityId}`, keeping
  a `Map<activityId, token>` (see the correction above). Torn down on
  sign-out beside `unregisterCurrentDevice`.
- **Local end** at `event_details_controller.dart` `_setStatusOnRepo` — the
  single choke point for `done`/`cancelled` — so the card clears instantly
  in-app without waiting for the server round-trip.
- Every path iOS-gated and best-effort; a failure degrades to the existing
  `leaveNow` push, which is unchanged.

---

## Mac-only (Tasks 9–12, Swift authored here)

9. `ios/ScheduleWidget/JobActivityAttributes.swift` — the shared
   `ActivityAttributes` + `ContentState`. Must be added to **both** the Runner
   and extension targets.
10. `ios/ScheduleWidget/JobLiveActivity.swift` — `ActivityConfiguration`: Lock
    Screen card (Option B job-card continuity: employee colour rail, client
    headline, status chip, metadata row) + Dynamic Island (expanded leads on
    **"Leave at 7:54"**, an absolute time — not a countdown; compact puts label
    leading / time trailing; minimal falls back to the amber-tinted ES mark).
    Amber → red at `leaveAt` for the lapsed state. On-site keeps a live
    `Text(timerInterval:)` elapsed ticker — the one value that stays exact with
    no push.
11. `ios/ScheduleWidget/DirectionsIntent.swift` — App Intent opening the maps
    URL. No auth needed; the genuine lock-screen win. "Complete" is a deep link
    into the appointment sheet, **not** a new authenticated write surface in the
    extension.
12. Required Xcode edits: move `@main` from `ScheduleWidget` onto a
    `WidgetBundle` listing both the widget and the activity (**required, not
    optional**); add `NSSupportsLiveActivities` to `Runner/Info.plist`. New
    `.swift` files in `ios/ScheduleWidget/` are picked up automatically by the
    `PBXFileSystemSynchronizedRootGroup` — no `pbxproj` surgery. **No
    deployment-target bump** — every path is `@available(iOS 17.2, *)`-gated
    (17.2, not 17.0: `pushToStartTokenUpdates` is 17.2+).

## Task 13 — owner-only

Create the APNs `.p8` auth key in the Apple Developer portal and load
`APNS_AUTH_KEY` / `APNS_KEY_ID` / `APNS_TEAM_ID` into Secret Manager. Nothing
server-side can be deployed or verified until this lands.

---

## Verification

- **Windows:** `cd functions && npx jest` for Tasks 2–6, `flutter test` +
  `flutter analyze` for Task 8, `firebase deploy --dry-run` unavailable — rules
  reviewed by hand against the `fcmTokens` precedent.
- **Device (Mac, real iPhone — Live Activities are meaningless in the
  Simulator):** card appears on a closed+locked phone when `leaveNow` fires;
  amber → red lapse at `leaveAt`; travel → on-site flip; Directions opens maps
  from the Lock Screen; Complete deep-links; end on done/cancel from both the
  app and the server; iOS < 17.2 and Live-Activities-disabled both degrade to
  the plain `leaveNow` push with no card and no error.
