# Push Notifications: Job Assignments, 30-min Reminders, Nightly Digest

> **Revised 2026-07-09** — aligned to the retired `confirmed` status (lifecycle
> is now `pending → in_progress → done`, plus `cancelled`; rules and
> `_allowedStatuses` reject `confirmed` writes, but pre-retirement docs may
> still carry it and the app treats it as pending via
> `AppointmentStatus.fromRaw`). See also
> `docs/plans/2026-07-09-travel-time-notifications.md`, which modifies
> `sendUpcomingJobReminders` into a travel-aware sweep after Phases 1–4 land.
>
> **Revised 2026-07-10** — added the **overdue "is the job done yet?" prompt**
> (item 7 below): a scheduled push nudging an assigned employee to close out a
> job whose end time has passed while still `pending`/`in_progress`. Mirrors the
> app's new display-only `overdue` state (`AppointmentRecord.displayStatus`,
> `AppointmentStatus.overdue`) server-side. Implemented 2026-07-10
> (`sendOverdueJobPrompts` + `runOverduePromptSweep` + ledger rules + tests);
> deploy + device verify pending with the rest of Phase 4.

## Context

Employees currently have no way to know a job was assigned, moved, or cancelled unless they open the app. This feature adds phone notifications (user-approved decisions):

1. **Assignment alerts** — push when an appointment is created with the employee in `employeeIds`.
2. **Change alerts** — push when an assigned appointment's `startTime` changes, is cancelled/deleted, or the employee is unassigned.
3. **30-min reminder** — push ~30 minutes before an employee's next job.
4. **Nightly digest** — every day at **6:00 PM America/Toronto**, each employee with ≥1 job tomorrow gets a summary push. Employees with no jobs get nothing.
5. **Overdue "is the job done yet?" prompt** — push to each assigned employee when a job's `endTime` has passed but its status is still `pending`/`in_progress` (i.e. the app now shows it as `overdue`), nudging them to mark it Done or Cancelled. Fires once per job occurrence.
6. **Employees always; admins for time-based only.** Employees get every
   notification. An **admin assigned to a job** also registers a token and
   receives the **time-based** pushes (30-min reminder, overdue prompt, 6 PM
   digest) but **not** change-driven ones (assigned/rescheduled/cancelled) —
   an admin usually makes those edits themselves, so a push for their own
   change would be noise. (Revised 2026-07-11 from the original "admins get no
   notifications"; admins are now prompted for permission on sign-in.)
7. **iOS home-screen widget** — shows the employee's next job (small) and today's job list (medium/large). Data refreshes whenever the app runs (open or push tap); the widget's own timeline rolls past jobs off without the app. Native WidgetKit target is created on the Mac; Swift code + all Flutter data-sync is authored here.

**Delivery: Firebase Cloud Messaging (FCM) for everything, server-side.** No `flutter_local_notifications`, no on-device scheduling — reminders/digests come from scheduled Cloud Functions, so they work with the app closed and can't go stale when an admin reschedules a job. The OS notification permission is the on/off control; no in-app toggle in v1.

The app currently has **zero** notification infrastructure (no packages, no FCM function, no APNs). iOS-native steps (APNs key, Xcode capability) are isolated into the Mac handoff doc — everything else builds and tests on this Windows box with the Android dev harness.

## Key design decisions

- **Token storage:** `users/{docId}/fcmTokens/{token}` subcollection (doc id = the token). Keyed by the users **doc id** because that's what `appointments.employeeIds` contains — the send path needs no uid translation. One doc per device supports multi-device; stale tokens are deleted on send failure (`messaging/registration-token-not-registered`).
- **Locale per token doc** (`locale: 'en'|'fr'`): functions send localized text per device from an inline EN/FR string table. No ARB keys needed (server owns notification text).
- **Reminder idempotency:** Admin-SDK-only ledger collection `appointmentReminders`, doc id `${appointmentId}_${startTimeMillis}`. `create()` fails if it exists → fires exactly once; a reschedule changes the key → moved job earns a fresh reminder. No field on the appointment doc (would be wiped by client rewrites, would need appointment-rules churn).
- **Overdue-prompt idempotency:** separate Admin-SDK-only ledger `appointmentOverduePrompts`, doc id `${appointmentId}_${endTimeMillis}` (keyed on the **end** time, since that's what makes a job overdue). Same `create()`-fails-if-exists → at most one prompt per occurrence; a reschedule that moves `endTime` re-arms it, and a claim that delivered **zero** pushes (no live tokens yet, or the send threw) is **released** (ledger doc deleted) so a later sweep retries while the job is still eligible. `overdue` is display-only and **never stored** (the rules allowlist stays pending/in_progress/done/cancelled) — the sweep derives it from `endTime` + status, exactly as `displayStatus` does client-side; nothing writes `overdue` back to the appointment. Both ledgers write an `expiresAt` (+7 days) for a console-enabled Firestore TTL policy so they don't grow forever.
- **Payload:** notification messages (`notification` block) + `data: {appointmentId, kind}` — OS-displayed with app closed, no extra iOS entitlements beyond Push capability.
- **No `retry: true` on the trigger** — a duplicate push is worse than a rare missed one.
- Recipients filtered server-side by `status == 'active'` and a per-category
  role set (`notification_utils.js`): `CHANGE_RECIPIENT_ROLES = {employee}` for
  assigned/rescheduled/cancelled; `TIMED_RECIPIENT_ROLES = {employee, admin}`
  for reminder/overdue/digest. `sendToEmployee` takes the allowed-roles set
  (default: employees only).

## Phase 1 — Cloud Functions (all buildable/testable on Windows)

### New `functions/notification_utils.js` — pure + orchestration logic, jest target
Following the `client_propagation.js` / `signup_code_utils.js` pattern (no admin/scheduler requires so jest can load it):
- `diffAppointmentForNotifications(before, after, now)` → `[{employeeDocId, kind}]`, kind ∈ `assigned|rescheduled|cancelled|removed`:
  - created → `assigned` for all `employeeIds` (skip if created already `cancelled`).
  - deleted OR status → `cancelled` → `cancelled` for `before.employeeIds`.
  - ids removed → `removed`; `startTime` changed → `rescheduled` for remaining ids (just-added ids get `assigned`, not both).
  - Dedupe one event per employee, priority `cancelled > removed > rescheduled > assigned`. Skip past appointments (`startTime < now`).
- `buildNotificationMessage(kind, {clientName, startTime, address}, locale)` → `{title, body}`; EN/FR table; times via `Intl.DateTimeFormat('fr-CA'|'en-CA', {timeZone: 'America/Toronto'})`. Kinds: assigned / rescheduled / cancelled / removed / reminder / digest / **doneCheck**. The **reminder** body appends the job's address (user-approved wording in the notification-previews artifact). The **doneCheck** copy: EN title "Job finished?" / body "Is the job for {clientName} done yet? Open the app to update its status." — FR title "Travail terminé ?" / body "Le travail pour {clientName} est-il terminé ? Ouvrez l'application pour mettre à jour son statut." ("Open the app", not "Tap" — the tap handler only surfaces the calendar root until the deferred appointment deep-link exists.)
- `buildDigestMessage(jobs, locale)` — "You have N jobs tomorrow. First: {clientName} at {time}" (FR variant); `jobs` sorted by startTime.
- `groupTomorrowsJobsByEmployee(docs, now)` — pure grouping for the digest sweep.
- `selectReminderCandidates(docs, now)` — window/status filter.
- `selectOverdueCandidates(docs, now)` — pure filter for the overdue prompt: keep docs whose status is `pending`/`in_progress`/legacy `confirmed` (NOT `done`/`cancelled`, nor legacy `completed` — the `done` alias in `_terminalStatuses`; the keep-list is an allowlist precisely so terminal aliases stay excluded) AND `endTime` in `(now-24h, now]` — the explicit 24 h endTime freshness bound (not just the query window) is what expires ancient never-closed jobs.
- `reminderLedgerId(appointmentId, startTimeMillis)`; `overduePromptLedgerId(appointmentId, endTimeMillis)`; `isStaleTokenError(code)`.
- `handleAppointmentWrite(id, before, after, deps)` and `runReminderSweep(deps)` / `runDailyDigest(deps)` / `runOverduePromptSweep(deps)` orchestration with injected `{db, messaging, now, logger}` so jest can drive them with mocks.

### New `functions/notifications.js` — trigger registrations only (not require()'d by jest)
- Shared `sendToEmployees(...)`: `db.getAll()` users docs → filter active employees → read each `fcmTokens` subcollection → per-token localized message → `getMessaging().sendEach()` → delete stale-token docs on failure. No employees/tokens → log and return. Every message sets `android: {priority: 'high'}` and `apns: {payload: {aps: {sound: 'default'}}}` — without these, Android delivery can be doze-deferred and iOS alerts arrive silent.
- `notifyAppointmentChanges = onDocumentWritten('appointments/{appointmentId}', ...)` — thin wrapper calling `handleAppointmentWrite`.
- `sendUpcomingJobReminders = onSchedule({schedule: 'every 5 minutes', timeZone: 'America/Toronto', maxInstances: 1}, ...)`: query `status in ['pending', 'confirmed'] && startTime > now && startTime <= now+30min` — `'confirmed'` stays in the filter ONLY as the retired legacy alias (treated as pending by `AppointmentStatus.fromRaw`; new writes are rejected since 2026-07-09, so it ages out naturally); `in_progress` is deliberately excluded (visit already started). Existing `(status, startTime)` composite index covers it — **no new index**. Per candidate, `appointmentReminders` `create()` (skip on ALREADY_EXISTS) then send. First run after entering the window fires (~25–30 min before); missed runs self-heal, never double-send, never fire after start.
- `sendDailyJobDigest = onSchedule({schedule: '0 18 * * *', timeZone: 'America/Toronto', maxInstances: 1}, ...)`: query `status in ['pending', 'confirmed']` (same legacy-alias note as above) with `startTime` in [tomorrow 00:00, day-after 00:00) Toronto time; group by employee; one digest push per employee with ≥1 job. No ledger (runs once daily; rare crash-retry duplicate accepted).
- `sendOverdueJobPrompts = onSchedule({schedule: 'every 15 minutes', timeZone: 'America/Toronto', maxInstances: 1}, ...)`: query `status in ['pending', 'in_progress', 'confirmed'] && startTime >= now-48h && startTime <= now` — reuses the existing `(status, startTime)` composite index (**no new index**; querying by `endTime` would need one). The **48 h** floor = 24 h eligibility + the form's <24 h max booking duration, so even the longest visit is still in range when its `endTime` passes. Then `selectOverdueCandidates` filters to `endTime` in `(now-24h, now]` in code. Per candidate: `appointmentOverduePrompts` `create(overduePromptLedgerId(id, endTimeMillis))` (skip on ALREADY_EXISTS) then `sendToEmployees(doc.employeeIds, 'doneCheck', ...)` — the candidate doc's own `employeeIds` (this is a scheduled sweep; there is no before/after snapshot here); the send loop is try/caught so one candidate's transient failure can't abort the sweep, and a claim with **zero** delivered pushes is released (ledger deleted) for retry next sweep. Fires at most once per delivered occurrence, within ~15 min of the end time; a re-open after a reschedule earns a fresh prompt under the new end-time key. (Accepted v1 gap: a job whose `endTime` passed >24 h ago and was never closed gets no prompt — it aged out of the eligibility window.)

### Modify `functions/index.js`
Re-export the four functions (thin wiring surface, per convention).

### Modify `functions/account.js`
`deleteAccount`: subcollections survive parent deletion, so deleting the doc alone leaves the account still receiving pushes. Replace the doc delete with Admin SDK `firestore.recursiveDelete(userDocRef)` — one call removes the doc plus ALL its subcollections (`fcmTokens` now, `presence` when the travel-time plan lands) with no per-subcollection cleanup list to keep in sync.

### Tests — `functions/__tests__/notification_utils.test.js`
Diff matrix (create/cancel/delete/remove+add/reschedule/dedupe-priority/past-appointment), reminder window edges, digest grouping + day-boundary math, **overdue candidate filter (end-passed-but-open kept; done/cancelled and not-yet-ended dropped) + `overduePromptLedgerId` + `runOverduePromptSweep` fires-once orchestration**, ledger ids, EN/FR formatting (incl. `doneCheck`), stale-error codes, injected-deps orchestration tests. `cd functions && npm run lint && npm test`.

## Phase 2 — Firestore rules

In `firestore.rules`, inside `match /users/{userId}`:
```
match /fcmTokens/{token} {
  allow read, delete: if isActiveUser() && myDocId() == userId;
  allow create, update: if isActiveUser()
    && myDocId() == userId
    && request.resource.data.keys().hasOnly(
        ['platform', 'locale', 'uid', 'createdAt', 'updatedAt'])
    && request.resource.data.locale in ['en', 'fr']
    && request.resource.data.platform in ['ios', 'android']
    && request.resource.data.uid == request.auth.uid;
}
```
Plus deny-all for both ledgers (rateLimits style): `match /appointmentReminders/{id} { allow read, write: if false; }` and `match /appointmentOverduePrompts/{id} { allow read, write: if false; }`

No `firestore.indexes.json` change.

## Phase 3 — Flutter client

### `pubspec.yaml`
`flutter pub add firebase_messaging` (resolver picks the line compatible with `firebase_core ^4.7.0`). Note: `flutter pub` needs sandbox disabled on this box (plugin-symlink issue).

### New `lib/core/notifications/push_notification_service.dart`
Plain class, injected `FirebaseMessaging` + optional `AppLogger` (mirrors `MediaPermissionService`):
- `requestPermission()` (plain, not provisional; surfaces Android 13+ POST_NOTIFICATIONS dialog too);
- `configureForegroundPresentation()` → `setForegroundNotificationPresentationOptions(alert/badge/sound: true)` (iOS foreground banners);
- `currentToken()` — on iOS await `getAPNSToken()` first (brief retry if null) then `getToken()`; warn + null on failure;
- `onTokenRefresh` passthrough; `deleteToken()`.

### New `lib/features/notifications/data/fcm_token_repository.dart`
Injected `FirebaseFirestore` (never `FirebaseFirestore.instance` from UI): `upsertToken({userDocId, token, platform, locale, uid})` (server timestamps) and `deleteToken({userDocId, token})`; log via injected logger, never throw into callers.

### New `lib/features/notifications/application/push_registration_controller.dart`
Manual Riverpod providers: `pushNotificationServiceProvider`, `fcmTokenRepositoryProvider`, and `pushRegistrationProvider` that watches `currentUserDocProvider` + `userRoleProvider` + `firebaseReadyProvider` + app language, and when signed-in ∧ `role == 'employee'` ∧ `status == 'active'` ∧ firebase ready: request permission → resolve own users doc id (via the `usersByUid/{uid}` bridge / `findUserByUid`) → `upsertToken`. Subscribes `onTokenRefresh`; re-upserts on language change (locale field). Extract a pure `shouldRegisterPush({role, status, signedIn})` helper for tests (matches the `isAccountDeletionSignal` pure-helper style). Exposes `unregisterCurrentDevice()` for sign-out. Admins: no-op, no prompt.

### Modify `lib/main.dart` (`_PaulAppState`)
- Activate `pushRegistrationProvider` alongside the existing `_listenForAccountDisabled()`-style listeners.
- Tap handling: `getInitialMessage()` (terminated launch) + `onMessageOpenedApp` → navigate to the calendar via `_navigatorKey` and `AppRoutes` (only when authed; `data.appointmentId` carried for a future deep link).

### Modify sign-out path (`lib/features/auth/services/auth_service.dart` call sites)
Before `signOut()`: best-effort `unregisterCurrentDevice()` (delete token doc + `messaging.deleteToken()`), try/catch + `logger.warn` — sign-out must never be blocked.

### `android/app/src/main/AndroidManifest.xml`
Add `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>`.

Accepted v1 gap: Android shows no banner while the app is **foregrounded** (background/killed delivery works). Android is the dev harness only.

### Flutter tests
`FcmTokenRepository` with mocked Firestore; `shouldRegisterPush` pure tests. No widget tests for the FCM plugin (platform channels).

## Phase 4 — Deploy + Android verification (this box)

1. `cd functions && npm run lint && npm test`; `flutter analyze` + `flutter test`.
2. `firebase deploy --only firestore:rules` then `--only functions:notifyAppointmentChanges,functions:sendUpcomingJobReminders,functions:sendDailyJobDigest,functions:sendOverdueJobPrompts,functions:deleteAccount`. One-time: enable a Firestore **TTL policy** on `expiresAt` for `appointmentReminders` AND `appointmentOverduePrompts` (GCP Console → Firestore → Time-to-live) so ledger docs self-delete.
3. On the Android device/emulator (google-services.json present, App Check debug token registered):
   - Employee sign-in → token doc appears in console.
   - Admin creates/reschedules/cancels/unassigns an appointment → correct push arrives with app killed.
   - Appointment starting 28 min out → reminder within ~5 min; ledger doc written; move the time → fresh reminder under the new key.
   - Digest: temporarily trigger `sendDailyJobDigest` from the console (or wait for 6 PM) with a tomorrow-job seeded.
   - Overdue prompt: seed a job whose `endTime` is a few minutes past and status still `pending`/`in_progress` → "Job finished?" push within ~15 min; `appointmentOverduePrompts` ledger doc written; a second sweep sends nothing; marking it Done before the sweep suppresses it.
   - Sign-out deletes the token doc; FR-language device gets French text.

## Phase 5 — iOS home-screen widget (Flutter + Swift authored here; target wired on Mac)

User-approved scope: **small** widget = next job (client, time, address); **medium/large** = today's job list. Refresh = whenever the app runs; the widget timeline rolls jobs off as they pass. iOS-only (no Android glance widget).

**Approved visual design — "System Card" (Option B, final mockup in the widget artifact):** native iOS card that follows the phone's light/dark mode; red uppercase date label; blue accent (`#1565C0` light / brighter blue dark) for the next-job time, count pill, and "+N more"; per-job status bars matching the app's `StatusChip` palette — amber pending, blue in-progress/next, green done (the mockup predates the 2026-07-09 status collapse that retired `confirmed`; map its green-confirmed bar to done); finished jobs dimmed. **Fit guarantees (hard requirements):** every text line is single-line truncated (`lineLimit(1)`), medium caps at 3 rows and large at 6 with a "+N more today" row, small shows exactly one job with an "in 45 min · 3 left today" footer, and layout uses fixed slots so any day length renders identically. Small "done" state = checkmark + "No more jobs today"; FR variants follow the app language (14 h 30 / "+2 autres aujourd'hui").

### Flutter side (buildable/testable on this box)
- `pubspec.yaml`: add `home_widget`.
- New `lib/features/home_widget/application/widget_sync_service.dart` (+ provider): serializes the employee's remaining-today + next-job appointments to JSON and writes via `HomeWidget.saveWidgetData` (App Group `group.net.vogas.scheduling`), then `HomeWidget.updateWidget(iOSName: 'ScheduleWidget')`. Pure `buildWidgetPayload(appointments, now)` helper for unit tests.
- New provider watching a today+lookahead range for the signed-in employee (reuse `watchForEmployeeInRange`); app-wide `ref.listen` in `_PaulAppState` calls the sync service on data changes / resume. Employees only; no-op on Android and for admins. Clear widget data on sign-out.

### Swift side (authored here as files under `ios/ScheduleWidget/`, compiled only on Mac)
- `ScheduleWidget.swift` — WidgetKit `TimelineProvider` reading the App Group UserDefaults JSON; timeline entries at each job's end time so "next job" rolls over without the app; small/medium/large SwiftUI views; placeholder + "no jobs today" states; FR/EN strings from the payload's locale field.

## Phase 6 — Mac handoff (append "Push Notifications + Widget" section to `docs/plans/IOS_APP_STORE_HANDOFF.md`)

- [ ] Apple Developer portal: create APNs Auth Key (.p8); note Key ID + Team ID.
- [ ] Firebase Console → Cloud Messaging → iOS app `net.vogas.scheduling` → upload the .p8.
- [ ] Xcode → Runner → Signing & Capabilities → add **Push Notifications** capability; commit `Runner.entitlements`.
- [ ] No `UIBackgroundModes` needed (display messages only). Never run `flutterfire configure`. SwiftPM pulls FirebaseMessaging automatically.
- [ ] **Widget:** File → New → Target → Widget Extension named `ScheduleWidget` (no intent config); delete the template Swift files and add the pre-authored `ios/ScheduleWidget/*.swift`; add **App Groups** capability (`group.net.vogas.scheduling`) to BOTH Runner and the extension; set the extension's deployment target to iOS 15.0.
- [ ] Verify on a **physical** iPhone: permission prompt → token doc → all four trigger scenarios + reminder + digest → tap-from-killed lands on the calendar → add the widget in all three sizes, confirm today's jobs render and roll over.

## Risks / notes
- **Repeating-series creation sends ONE assignment push, not one per
  occurrence.** A repeat pre-books many docs in a single write; only the
  **anchor** occurrence (`id === seriesId`) emits the `assigned` event
  (`diffAppointmentForNotifications` suppresses copies where
  `seriesId !== "" && seriesId !== id`), and its message uses the "repeating
  job" variant naming the interval (`_repeatLabel`, EN "repeats every 6 months"
  / FR "se répète aux 6 mois"). Non-repeating appointments have an empty
  `seriesId` and are never suppressed. This dedup applies to `assigned`
  (create) only — a series **reschedule/cancel** (`propagate`) still writes N
  docs → N pushes (each a real per-occurrence change; accepted v1).
- Client can only read/write its own tokens; ledger and other users' tokens are invisible.
- `sendEach` batching keeps one bad token from failing the batch; stale tokens self-clean.
