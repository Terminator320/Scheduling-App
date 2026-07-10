# Siri App Intents — "How many appointments do I have today?"

**Status: design approved 2026-07-10 — implementation plan not yet written.**

Let users ask Siri about their schedule instead of opening the app. Approved
decisions: both roles (role-aware answers), three intents (today count / today
schedule / next appointment), iOS deployment target bumped 15.0 → 16.0,
App Group snapshot as the data source ("snapshot now, live later"), snapshot
written via the `home_widget` package.

## User-facing behavior

Three Siri queries, in English and French (Apple requires the app name in the
phrase — "…in ES Pro" / "…dans ES Pro"):

1. **"How many appointments do I have today in ES Pro?"** → "You have 4
   appointments today."
2. **"What's my schedule today in ES Pro?"** → reads the day's list: time +
   client name per visit.
3. **"What's my next appointment in ES Pro?"** → client name, start time, and
   address of the next upcoming job.

Role-aware: an employee hears only appointments where their users doc id is in
`employeeIds` (the standard visibility rule); an admin hears the whole
business's appointments.

Siri answers **from the lock screen without unlocking** — the hands-free
use case (plumber driving between jobs) is the point, and the data is the
user's own schedule.

## Architecture

```
Flutter app (whenever it runs)
  └─ writes role-filtered schedule snapshot (today + next 7 days, JSON)
     via home_widget → App Group container (group.net.vogas.scheduling)

Siri query
  └─ App Intents extension (Swift, iOS 16+, no Flutter, no Firebase)
     reads + decodes the snapshot → speaks the answer (ms latency, offline-capable)
```

- **App Intents framework (iOS 16+)**, not legacy SiriKit — phrases work out
  of the box with no user setup. Deployment target bumps to **16.0** (iOS 16
  runs on iPhone 8/2017 and later, ~97% of devices; app hasn't shipped, no
  stranded users). App Attest's ≥14 floor stays satisfied.
- **Dedicated App Intents extension target**, not intents in the app binary:
  in-app intents make iOS cold-boot the whole Flutter+Firebase app in the
  background per query (multi-second answers); the extension answers in
  milliseconds and needs only the App Group entitlement. No Siri entitlement
  is required for App Shortcuts.
- **Same snapshot the future WidgetKit widget will read** (push-notifications
  plan, Phase: widget). Built once here; the widget reuses it.

## Snapshot contract

Written by Flutter via `home_widget` (`HomeWidget.setAppGroupId(...)` +
`saveWidgetData('schedule_snapshot', jsonString)`); read in Swift from
`UserDefaults(suiteName: "group.net.vogas.scheduling")`.

```json
{
  "version": 1,
  "generatedAt": 1791234567890,
  "role": "employee",
  "days": [
    {
      "date": "2026-07-10",
      "appointments": [
        {
          "startMillis": 1791234567890,
          "endMillis": 1791238167890,
          "clientName": "…",
          "address": "…",
          "status": "pending"
        }
      ]
    }
  ]
}
```

- Window: today + next 7 days, device-local day boundaries.
- **Cancelled appointments excluded** at build time. Today's count/list =
  everything else; "next appointment" = earliest `startMillis > now` whose
  status is not `done`.
- Statuses pass through `AppointmentStatus.fromRaw(...).raw` (legacy
  `confirmed` docs normalize to the allowlist).
- Size cap: 30 appointments per day (defensive; Siri reads at most a day).
- `version` lets the Swift side reject snapshots from a future schema instead
  of mis-decoding.

**Refresh triggers (Flutter side):** after successful sign-in routing, on
appointments-stream emissions (debounced via the existing `Debouncer`
pattern), and on app-lifecycle resume. **Sign-out wipes the snapshot** —
client names/addresses must not outlive the session in the shared container
(same discipline as FCM-token deletion in the push plan). Account
deletion/kick-out paths wipe it too (they route through sign-out).

## Components

### Dart (all buildable + testable on this Windows box)

- **Pure snapshot builder** — `buildScheduleSnapshot({appointments, role, now})`:
  day bucketing, cancelled exclusion, status normalization, per-day cap,
  `generatedAt` stamp. Pure function, plain `test()` coverage.
- **Writer service** — thin wrapper over `home_widget` with an injected
  interface so tests mock it (services are plain classes, optional injected
  deps, per convention). Exposes `writeSnapshot(...)` and `clearSnapshot()`.
- **Riverpod wiring** — a provider that watches the signed-in user's
  role + appointments stream and writes the debounced snapshot; activated
  from `main.dart` alongside the existing listeners. `clearSnapshot()` is
  called on the sign-out path (best-effort, try/catch + `logger.warn`;
  sign-out must never be blocked).
- `pubspec.yaml`: add `home_widget`. (`flutter pub get` needs sandbox
  disabled on this box — plugin-symlink issue.)

### Swift (authored here in `ios/SiriIntents/`, compiled only on the Mac)

- `ScheduleSnapshot.swift` — Codable structs + App Group `UserDefaults`
  loader; rejects missing/undecodable/wrong-version data.
- `AppointmentCountIntent.swift`, `TodayScheduleIntent.swift`,
  `NextAppointmentIntent.swift` — each returns a spoken
  `IntentDialog`; formatting via device-locale `DateFormatter`.
- `ESProShortcuts.swift` — `AppShortcutsProvider` with EN + FR phrase lists.
- Localized response strings (EN + FR string catalogs; response language
  follows the device's Siri language).

### Mac runbook (new doc, `docs/plans/` — same pattern as `IOS_APP_STORE_HANDOFF.md`)

1. Create App Group `group.net.vogas.scheduling` in the developer portal;
   add the App Groups capability to **both** Runner and the extension.
2. Add an **App Intents extension** target (iOS 16.0) named `SiriIntents`;
   pull in the authored Swift files.
3. Bump `IPHONEOS_DEPLOYMENT_TARGET` to 16.0 on Runner (the pbxproj edit may
   land from Windows; verify in Xcode).
4. Device test matrix (below).

## Error handling & freshness

| Condition | Siri response |
|---|---|
| No snapshot / decode failure / wrong version / signed out (wiped) | "I couldn't find your schedule — open ES Pro and sign in." |
| Snapshot `generatedAt` not today (device-local) | Answer prefixed with the caveat: "As of yesterday 5 PM, you had 3 appointments…" |
| Zero appointments today | "You have no appointments today." |
| No upcoming appointment (next-appointment intent) | "You have no upcoming appointments." |

The extension never crashes on bad data — every failure degrades to the
open-the-app message.

**Future freshness path (explicitly deferred):** when the push-notifications
plan lands, silent pushes can refresh the snapshot in the background; a live
Firestore query from Swift (keychain-shared auth + App Check) remains the
escalation if staleness proves painful in real use. Neither is built now.

## Privacy

The snapshot holds client names + addresses in the App Group container —
on-device only, sandboxed to this app's targets, never transmitted, wiped on
sign-out. No Firebase, no network, no analytics in the extension.

## Testing

**Windows (this box):**
- Pure builder tests: role matrix (admin vs employee input lists), day
  boundaries, cancelled exclusion, legacy-status normalization, per-day cap,
  empty input.
- Writer service with mocked `home_widget` interface; sign-out wipe test.
- Android dev harness: `home_widget` works on Android, so snapshot writes are
  verifiable end-to-end on the emulator (read back the stored JSON).

**Mac/device only (runbook test matrix):**
- Phrase recognition EN + FR × 3 intents.
- States: normal day, empty day, stale snapshot, signed out, locked phone.
- Confirm Runner still passes App Attest after the target bump.

## Out of scope (v1)

- Tomorrow/arbitrary-date queries; Siri *actions* (booking/cancelling —
  writes stay in-app); interactive snippets/custom Siri UI; Apple Watch;
  background snapshot refresh (arrives with the push plan); Android
  (Assistant has no equivalent surface and Android is dev-harness only).
