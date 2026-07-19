# SiriIntents — Mac setup runbook (Phase 1)

The Swift here is authored on the Windows box and compiled only on the Mac.
Design: [`docs/plans/2026-07-10-siri-app-intents-design.md`](../../docs/plans/2026-07-10-siri-app-intents-design.md).
Plan: [`docs/plans/2026-07-19-siri-app-intents-implementation.md`](../../docs/plans/2026-07-19-siri-app-intents-implementation.md).

The Dart half is done and on-device-ready: the app writes the snapshot into the
App Group under the key `schedule_snapshot` whenever the schedule changes, and
wipes it on sign-out. Nothing below touches Dart.

## Steps

1. **Add the target.** File → New → Target → **App Intents Extension**, name
   `SiriIntents`, embed in `Runner`. Delete the stub files Xcode generates and
   add the `.swift` files in this folder to the new target (Target Membership:
   `SiriIntents` only).
2. **Info.plist / entitlements.** Point the target's `INFOPLIST_FILE` at
   `SiriIntents/Info.plist` and its `CODE_SIGN_ENTITLEMENTS` at
   `SiriIntentsExtension.entitlements` (both are committed, mirroring the
   widget's pair), or add the **App Groups** capability in Signing &
   Capabilities and pick the existing `group.net.vogas.scheduling`. The extension
   needs no other capability — Phase 1 is Firebase-free and does no network I/O.
3. **Bump the deployment target 15.0 → 16.0.** App Intents requires iOS 16.
   Change `IPHONEOS_DEPLOYMENT_TARGET` in **all 6 build configurations** in
   `Runner.xcodeproj/project.pbxproj` (Runner *and* the `ScheduleWidget`
   extension, not Runner alone), and set the new target to 16.0 too.
   ⚠️ **This drops iOS 15 users** — a product decision, not just a build setting.
   App Attest's ≥14 floor stays satisfied. Update the "Deployment target is
   **iOS 15.0**" note in `CLAUDE.md` once this lands.
4. **Build and run on real hardware.** App Intents phrases are registered at
   install; give Siri a few seconds after first launch.

## Device verification checklist

Run the app once while signed in (that writes the snapshot), then ask Siri:

- [ ] EN + FR × all 3 phrases ("how many appointments today", "what's my
      schedule today", "what's my next appointment") — see `ESProShortcuts.swift`
      for the exact phrase list.
- [ ] **Employee vs. admin** — an employee hears only their assigned visits; an
      admin hears the whole business ("the team has…").
- [ ] **Empty day** — no jobs today answers "no appointments today", not silence.
- [ ] **Next-appointment rollover** — with today finished, it answers with
      tomorrow's first job.
- [ ] **Locked device** — reads answer without unlocking (intended: hands-free
      while driving).
- [ ] **Signed out** — the snapshot is wiped, so Siri answers "Open ES Pro to
      sync your schedule." Confirm the container key is actually gone, not just
      that the answer changed.
- [ ] **Offline** — answers still work (no network path in Phase 1).

## Boundaries to preserve

- **No Firebase, no network in this extension.** That's what makes an answer
  arrive in milliseconds and work offline. Phases 4–5 break that deliberately,
  as their own reviewed increment — not as drift.
- `ScheduleSnapshot.swift` is hand-mirrored with `buildScheduleSnapshot` in
  `lib/features/siri/domain/schedule_snapshot.dart`. Change one, change both,
  and bump `version` on either side of a schema change.
- The snapshot stays readable while the device is locked, so it carries only the
  fields the intents speak (client name, times, address, status) plus the doc
  `id` Phase-4 writes target. Don't widen it casually.
