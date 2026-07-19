# Live Activities — Mac handoff

The "time to leave" Live Activity (Lock Screen card + Dynamic Island). The
Swift here was authored on the Windows dev box and has **never been compiled**.
Everything below is Mac-side work.

Design: [`docs/plans/2026-07-19-ios-live-activities.md`](../../docs/plans/2026-07-19-ios-live-activities.md).
Plan: [`docs/plans/2026-07-19-ios-live-activities-implementation.md`](../../docs/plans/2026-07-19-ios-live-activities-implementation.md).

SPM-only project — there is no Podfile and never will be. Nothing here adds a
dependency; ActivityKit, AppIntents, and WidgetKit are system frameworks.

## Files and target membership

New `.swift` files under `ios/ScheduleWidget/` are picked up automatically by
the `PBXFileSystemSynchronizedRootGroup`, so **no `pbxproj` surgery** — but
that auto-sync wires them into the *widget extension* target only.

| File | Runner | ScheduleWidgetExtension |
|---|---|---|
| `JobActivityAttributes.swift` | **YES — tick manually** | yes (automatic) |
| `JobLiveActivity.swift` | no | yes (automatic) |
| `DirectionsIntent.swift` | no | yes (automatic) |
| `ScheduleWidget.swift` (edited) | no | yes (already) |

`JobActivityAttributes.swift` is the only file needing the manual **File
Inspector → Target Membership → Runner** checkbox. The app target needs it to
observe `pushToStartTokenUpdates` / `activityUpdates`; without it the card
never starts and there is no error.

## Edits already made in this repo

- `ScheduleWidget.swift`: `@main` moved off `ScheduleWidget` onto a new
  `ScheduleWidgetBundle: WidgetBundle` listing the home-screen widget plus,
  gated `if #available(iOS 17.2, *)`, `JobLiveActivity`. Required — an
  `ActivityConfiguration` cannot be hosted otherwise. The existing widget's
  styling is untouched.
- `ios/Runner/Info.plist`: `NSSupportsLiveActivities` = `true`.

## Still to do in Xcode

1. Tick Runner target membership on `JobActivityAttributes.swift` (above).
2. Confirm both targets still build at the **iOS 15.0** deployment target — no
   bump is needed or wanted. Every Live Activity path is
   `@available(iOS 17.2, *)` (17.2, not 17.0: `pushToStartTokenUpdates` is
   17.2+, and push-to-start is the only start path).
3. Optional: add a `BrandMark` image set to
   `ScheduleWidget/Assets.xcassets` (the ES mark, template rendering). The
   minimal Dynamic Island uses it tinted amber and falls back to the SF Symbol
   `wrench.and.screwdriver.fill` when the asset is absent, so this is cosmetic.
4. Push Notifications capability is already on Runner (FCM). Live Activity
   pushes reuse it — no new entitlement. Time Sensitive Notifications stays as
   wired for the `leaveNow` push.

## APNs key (owner, once)

Live Activity pushes cannot go through FCM — they need
`apns-push-type: liveactivity` on topic
`net.vogas.scheduling.push-type.liveactivity`, so the backend talks to APNs
directly (`functions/apns_client.js`).

1. Apple Developer portal → Keys → new key with **Apple Push Notifications
   service (APNs)** enabled. Download the `.p8` **once** (it cannot be
   re-downloaded) and note the **Key ID**.
2. Team ID is in Membership Details.
3. Load all three into Secret Manager, then redeploy functions:

   ```bash
   firebase functions:secrets:set APNS_AUTH_KEY   # paste the .p8 contents
   firebase functions:secrets:set APNS_KEY_ID
   firebase functions:secrets:set APNS_TEAM_ID
   firebase deploy --only functions
   ```

Until these land, every Live Activity path no-ops and the plain `leaveNow`
push behaves exactly as it does today.

## Device verification (real iPhone — the Simulator is meaningless here)

Live Activities do not meaningfully run in the Simulator. Run each on a real
device, iOS 17.2+, signed in as an employee with a job scheduled:

- [ ] Card appears on a **closed and locked** phone when the `leaveNow`
      reminder fires (this is the whole point — an app-driven start would not
      do it).
- [ ] Client name, address, and drive label all render; text is FR on a French
      device and EN on an English one (strings come from the server, so switch
      the app language, let `PushRegistrationController` re-upsert the token
      `locale`, then re-trigger).
- [ ] Status chip is amber while travelling and turns **red** once `leaveAt`
      passes, with no text change. Repaint arrives with the next update push
      (the 5-minute sweep) — confirm the lapse is visible within one sweep.
- [ ] Travel → on-site flip: chip turns green, the elapsed `Text(timerInterval:)`
      ticker starts counting up from `startTime` **with no push**, and the two
      buttons swap order (Complete leads on site).
- [ ] **Directions** opens Apple Maps with driving directions straight from the
      Lock Screen, without unlocking.
- [ ] **Complete** deep-links into the appointment sheet (`esproschedule://`)
      and the existing markAsDone path runs there — nothing writes from the
      extension.
- [ ] Dynamic Island: expanded leads on the absolute `Leave at 7:54`, never a
      countdown; compact reads label-leading / time-trailing across the cutout
      **without truncating** (the densest part of the design — check FR, which
      is longer, and the largest Dynamic Type setting); minimal shows the
      tinted mark.
- [ ] Card ends on done/cancel from **both** the app (local end) and the server
      (end push), and does not linger on the Lock Screen.
- [ ] Two Lock Screen buttons at the smallest supported width — the design doc
      flagged this as the densest part; confirm neither pill truncates.
- [ ] Degradation: an iOS 16 device and a device with Live Activities disabled
      in Settings both get the plain `leaveNow` push, no card, and no error.
