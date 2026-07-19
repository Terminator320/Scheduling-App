# iOS Live Activities — "Time to Leave" Card (Design Decision)

**Status: DESIGN APPROVED 2026-07-19 — NOT started, NOT approved to build.**

This document records a design + mockup decision only. The build go-ahead is a
separate, explicit call from the owner. Do not scaffold code from this file.

**Mockup artifact:** https://claude.ai/code/artifact/28bef8ae-ab21-4e7a-b04f-540dabfb29f6

**Goal:** When the travel-aware sweep decides a field tech should leave for a
job, put a Live Activity on their Lock Screen and Dynamic Island showing the
client, the address, when to leave, and a Directions action — so the tech acts
without unlocking the phone.

---

## Chosen visual direction

**Option B ("job-card continuity")**, carried forward for BOTH the Lock Screen
card and the expanded Dynamic Island, with the Dynamic Island reworked to lead
on **"Leave at" + an absolute departure time**.

Three options were mocked (A countdown-led, B job-card, C run-progress). B won
on continuity — it mirrors `AppointmentCard` (employee colour rail, client as
headline, status chip, metadata row), so staff read a layout they already know
all day, and swapping the chip + metadata row covers every phase with one
layout.

### Grafted in / changed during review

- **Dynamic Island shows `Leave at 7:54`, not a `12:04` countdown.** Owner's
  call, and the more robust one: if a push is delayed or the device sleeps, an
  absolute time is still correct on wake, whereas a countdown frozen mid-tick is
  actively misleading. It also removes a `Text(timerInterval:)` from the Island.
- **Compact Island** puts the label leading and the time trailing so the phrase
  reads across the camera cutout rather than fighting it.
- **Both phases share one layout.** Travel = amber chip, Directions primary.
  On-site = green chip, Complete primary, button order swapped to match what the
  tech would actually tap next.

### Decisions made inside the visual review

- **Minimal Island cannot show the time.** That state is ~46 pt and shares the
  Island with other apps; `7:54` will not fit legibly. Falls back to the ES mark
  tinted amber to keep the "act soon" signal.
- **A lapsed state is required.** Once `leaveAt` passes and the tech has not
  left, "Leave at 7:54" reads as fine when it is not. Amber → red at `leaveAt`,
  with no text change.
- **Elapsed-time-on-site keeps a live ticker.** It is the one value that stays
  exact via `Text(timerInterval:)` with no push at all.

---

## Design decisions made with the user (2026-07-19)

### Product

- **Lifecycle:** travel → on-site → done. Card starts when the travel-aware
  `leaveNow` reminder fires and ends when the job is completed.
- **On-site transition is clock-derived, NOT stored.** `in_progress` is never
  written anywhere in the app today — `AppointmentRecord.displayStatus`
  (`appointment_record.dart:83-90`) derives it from the clock. The card follows
  the same rule, comparing `Date()` to the `startTime` in its content-state.
  **No `markInProgress` write path is being added.** This deliberately keeps the
  Live Activity from dragging in a whole separate feature.
- **Buttons:** "Directions" is a real App Intent (opens the maps URL, no auth
  needed — the genuine lock-screen win). "Complete" deep-links into the
  appointment sheet where the existing `markAsDone` path runs with real Auth +
  App Check. **No new authenticated write surface is placed in the extension.**
- **ETA is computed once and does not re-poll traffic.** One Routes API call at
  start — the one `runTravelAwareReminderSweep` already makes. No added
  recurring Routes billing, no added push traffic.

### Architecture

- **Server-owned lifecycle over direct APNs (push-to-start).** The card must
  appear on a phone that is closed and locked, which is the entire point; that
  rules out app-driven starts. FCM **cannot** send Live Activity pushes — they
  require `apns-push-type: liveactivity` on topic
  `net.vogas.scheduling.push-type.liveactivity` — so this adds a direct APNs
  HTTP/2 client and the APNs `.p8` key to Secret Manager.
- **Rejected:** driving the card from `firebaseMessagingBackgroundHandler`.
  CLAUDE.md deliberately pins that handler dependency-light, and a
  background-isolate ActivityKit call that silently no-ops gives no card and no
  diagnostic.
- **NO deployment-target bump.** `live_activities` declares `.iOS("13.0")` in
  its `Package.swift` and gates ActivityKit internally, so the app and widget
  extension both stay at **iOS 15.0** and every Live Activity path is
  `@available(iOS 17.2, *)`-gated. 17.2 (not 17.0) because
  `pushToStartTokenUpdates` is 17.2+ and push-to-start is the only start path.
  Devices below 17.2 register no token, receive nothing, and behave exactly as
  today. **No users are dropped.**
- **`live_activities` ^2.5.1 clears the SPM-only gate** — verified it ships
  `ios/live_activities/Package.swift` alongside the podspec.
- **Card strings are built server-side in EN/FR** from the same `_MESSAGES`
  table as the notifications (`notification_utils.js:262`/`:309`), keyed off the
  per-token `locale` already stored. Rejected `NSLocalizedString` in Swift: it
  would fork translations into a second system outside the ARB files, invisible
  to `untranslated.json`.

### Integration points (verified against source)

- **Start hook:** `travel_utils.js:428`, immediately AFTER the
  `deliverRecipientOnce` call, gated on `kind === 'leaveNow' && delivered > 0`.
  That function owns the atomic `create()` ledger claim, so hanging the start off
  its return value inherits exactly-once for free. A start placed *before* the
  claim would double-fire on a claim collision. Capture the return in a local
  rather than `+=`-ing it directly.
- **Update / end hooks:** `notification_utils.js:752-775` — `rescheduled` →
  update, `cancelled`/`removed` → end. The `augmentData` callback at `:770` is
  the existing precedent for attaching a mirrored payload per locale.
- **On-site flip backstop:** a second pass in the existing 5-minute sweep pushes
  one update for cards whose `startTime` has passed. No new scheduler.
- **Local end:** `event_details_controller.dart:281` (`_setStatusOnRepo`) is the
  single choke point for `done` and `cancelled`.
- **Token registry:** `users/{docId}/liveActivityTokens/{activityId}`,
  client-written and self-only, mirroring the `fcmTokens` rule
  (`firestore.rules:167-180`) with a changed `hasOnly` allowlist and
  `platform in ['ios']`. Server reads across employees via `collectionGroup`,
  same shape as the presence read.

### Known gotchas captured during the code survey

- `PushRegistrationController`'s `_registeredToken` cache assumes **one token
  per device**; Live Activity update tokens are **one per activity**, so that
  cache must become a set.
- `shouldRegisterLiveActivity` must **delegate to** `shouldRegisterPush`, never
  re-inline its body — same rule `shouldTrackPresence` follows, or the audiences
  silently drift.
- `ScheduleWidget.swift:376` has `@main` on the `Widget`. Hosting an
  `ActivityConfiguration` **requires** moving `@main` onto a `WidgetBundle`
  listing both. This is a required edit, not optional.
- `Runner/Info.plist` has no `NSSupportsLiveActivities` key yet.
- The `ActivityAttributes` struct must be added to **both** the Runner and
  extension targets.
- New `.swift` files in `ios/ScheduleWidget/` are picked up automatically by the
  `PBXFileSystemSynchronizedRootGroup` — no `pbxproj` surgery.
- `appointmentReminders` is a shared ledger namespace; do NOT repurpose its doc
  ids for Live Activity state.

---

## Failure posture

Every Live Activity path is additive and best-effort. No token, APNs failure,
iOS < 17.2, or Live Activities disabled by the user — all degrade to the
existing `leaveNow` push, which fires independently and is unchanged. **Nothing
in the reminder pipeline gains a new way to fail.**

---

## Scope reality

Roughly 60% of this is buildable and testable on the Windows dev box (all Cloud
Functions, all Dart, `firestore.rules`). The remaining 40% is Swift that can be
written but **not compiled, run, or verified here** — a new Widget Extension
target hosting an `ActivityConfiguration`, App Intents, entitlements, and the
shared attributes type. That lands as a Mac handoff doc shaped like
`IOS_APP_STORE_HANDOFF.md`, and is not done until it runs on a real iPhone
(Live Activities do not work meaningfully in the Simulator).

New secrets required in Secret Manager: `APNS_AUTH_KEY` (the `.p8` contents),
`APNS_KEY_ID`, `APNS_TEAM_ID` — defined once in `params.js`.

---

## Still open

- Two buttons on the compact Lock Screen card is the densest part of the design.
  Worth watching on a real device before committing.
- The Live Activity token registry needs a TTL sweep: a card the server never
  gets to end would otherwise leak a token row indefinitely.
- Whether App Store Connect privacy disclosures need any update for the card's
  content (it surfaces client name + address on a Lock Screen).

---

## Next step

Nothing. This is a recorded decision, not a plan. On an explicit build
go-ahead, the next artifact is a task-by-task implementation plan in this same
directory, written with `superpowers:writing-plans`.
