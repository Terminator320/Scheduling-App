# Siri App Intents — Implementation Plan

Companion to the design doc [`2026-07-10-siri-app-intents-design.md`](./2026-07-10-siri-app-intents-design.md).
That doc is the *what/why* (six phases, scope decisions, architecture). This is
the *how* — files, order, tests, Mac steps — grounded in the code that already
exists.

**Status: plan written 2026-07-19 — not yet started.**

## Key head-start: the widget already paved this road

The design doc frames the App Group snapshot as new infrastructure. It mostly
isn't — the iOS home-screen widget already established every foundation piece:

| Foundation | Already exists | Reuse |
|---|---|---|
| `home_widget` package | `pubspec.yaml` (`^0.9.3`) | No new dep |
| App Group `group.net.vogas.scheduling` | `widgetAppGroupId` in [`widget_sync_service.dart`](../../lib/features/home_widget/application/widget_sync_service.dart#L23); entitlements on Runner + `ScheduleWidget` | Same container, **new key** `schedule_snapshot` |
| Pure payload builder pattern | `buildWidgetPayload(...)` (same file) | Copy the shape for `buildScheduleSnapshot(...)` |
| Sync service w/ dedup + iOS-gate | `WidgetSyncService` (`_signatureOf` dedup, `_lastState`, `clear()`) | Copy for `ScheduleSnapshotService` |
| Employee-id + payload providers | `widgetEmployeeIdProvider`, `widgetPayloadProvider` | Copy/parametrize for the snapshot |
| `main.dart` emission-driven wiring | `_listenForWidgetSync()` ([main.dart:458](../../lib/main.dart#L458)) | Copy for `_listenForSnapshotSync()` |
| Deep-link scheme | `esproschedule://appointment?id=…` | Siri result tap reuses it |

So **Phase 1 is ~90% "clone the widget path with a wider date window and a
count/next projection"** — very little genuinely new Dart.

Divergences from the widget payload to design in deliberately:
- **Window:** widget carries today+tomorrow; the snapshot needs **today + 7
  days** (design doc), so `days[]` is a per-day bucket array, not two lists.
- **Role:** widget is employee-scoped only; the snapshot is **role-aware** —
  admins hear the whole business. `widgetEmployeeIdProvider` returns null-for-
  clear semantics; the snapshot provider must instead branch employee (own
  `employeeIds`) vs admin (all) — see the appointments providers below.
- **Cancelled excluded at build**; widget keeps them for its rollover math.

---

## Phase 1 — read, today/next (the foundation)

### Dart (buildable + testable on this box)

New feature dir `lib/features/siri/` (feature-first per convention):

1. **`domain/schedule_snapshot.dart`** — plain data + pure builder.
   - `buildScheduleSnapshot({required List<AppointmentRecord> appointments,
     required String role, required DateTime now})` → `Map<String, dynamic>`.
   - Day-buckets `now.dateOnly … +7d` (device-local, mirror `.dateOnly` usage
     from the widget builder), **excludes cancelled**, normalizes status via
     `AppointmentStatus.fromRaw(a.status).raw`, per-day cap 30, stamps
     `version: 1` + `generatedAt` + `role`, carries `id` per appointment.
   - Pure → plain `test()`, no Firebase. This is the bulk of the testable work.
2. **`application/schedule_snapshot_service.dart`** — clone `WidgetSyncService`:
   - Same App Group id constant (import `widgetAppGroupId`, don't redefine),
     **new** `_snapshotKey = 'schedule_snapshot'`, `_signatureOf` dedup minus
     `generatedAt`, `_lastState`, iOS-gate, `writeSnapshot(payload)` +
     `clearSnapshot()`, `warn` on failure. Provider
     `scheduleSnapshotServiceProvider`.
3. **`application/schedule_snapshot_provider.dart`** — clone
   `widgetPayloadProvider`, but role-aware:
   - Resolve `role` + active-status from `currentUserDocProvider` (reuse the
     guard shape in `widgetEmployeeIdProvider`).
   - Employee → `myAppointmentsProvider((employeeId, range: today..+7d))`.
     Admin → `appointmentsInRangeProvider(range)` (business-wide `watchInRange`;
     the widget only used the employee-scoped one). Signed-out/inactive →
     `data(null)` (clear).
4. **`main.dart`** — add `_listenForSnapshotSync()` mirroring
   `_listenForWidgetSync()` ([main.dart:458](../../lib/main.dart#L458)); call it
   from the same block that calls `_listenForWidgetSync()` (~line 560).
   `clearSnapshot()` on the sign-out path alongside the existing widget clear.
   (Snapshot writes happen on iOS only — same `Platform.isIOS` gate.)

**No pubspec change** (`home_widget` already present). No new App Group.

### Swift (author here in `ios/SiriIntents/`, compile on Mac)

Per the design doc Components list: `ScheduleSnapshot.swift` (Codable + App
Group `UserDefaults` loader, rejects missing/undecodable/wrong-version, decodes
`id`), `AppointmentCountIntent.swift`, `TodayScheduleIntent.swift`,
`NextAppointmentIntent.swift`, `ESProShortcuts.swift`
(`AppShortcutsProvider`, EN+FR phrases), EN/FR string catalogs.

### Mac steps (Phase 1)

The App Group already exists on Runner + `ScheduleWidget`. Remaining:
1. Add **App Intents extension** target `SiriIntents` (iOS 16.0); add it to the
   existing App Group `group.net.vogas.scheduling`.
2. Bump `IPHONEOS_DEPLOYMENT_TARGET` 15.0 → **16.0** on Runner + verify App
   Attest still passes (design doc: iOS 16 keeps the ≥14 App Attest floor).
   Update the CLAUDE.md "Deployment target is **iOS 15.0**" note when this lands.
3. Pull in the authored Swift files; wire the SPM `firebase-ios-sdk` **only if**
   later phases need it (Phase 1 extension is Firebase-free).

### Phase 1 tests
- `buildScheduleSnapshot`: role matrix (admin all vs employee `employeeIds`
  filter), 7-day bucketing + device-local boundaries, cancelled exclusion,
  legacy `confirmed`→allowlist normalization, per-day cap 30, empty input,
  `version`/`generatedAt`/`id` presence.
- `ScheduleSnapshotService` with a mocked `home_widget` surface: write, dedup
  skip (same signature), `clearSnapshot`, iOS-gate no-op elsewhere.
- Device (Mac): EN+FR phrase recognition × 3 intents; normal/empty/stale/
  signed-out/locked states.

**Phase 1 exit:** three read intents answer from the snapshot on a device;
sign-out wipes it.

---

## Phase 2 — date queries (pure additive)

No snapshot schema change — the 7-day window already carries every day.

- **Dart:** extend `buildScheduleSnapshot` tests only if a helper is added to
  resolve a relative-day label → bucket; the data is unchanged. (Most Phase-2
  work is Swift.)
- **Swift:** `DayScheduleIntent.swift` with a resolved date `@Parameter`; map to
  a `days[]` bucket; out-of-window → "I only have your schedule for the next 7
  days." Add "…tomorrow / on {day}…" phrases (EN+FR) to `ESProShortcuts.swift`.
- **Tests:** arbitrary-date bucket resolution incl. out-of-window; device phrase
  recognition for the new shapes.

**Exit:** "what's my schedule Friday / tomorrow?" reads the right day.

---

## Phase 3 — multi-turn

Swift-only; no data change.
- Return continuation results from the read intents so "and tomorrow?" / "read
  me the third one" stay in-session (App Intents conversation flow).
- **Tests (device):** follow-up stays in-session across the read + date intents.

---

## Phase 4 — write actions ⚠️ inflection point

**This is the first phase that puts an authenticated Firebase client inside the
extension** — a real security-surface + App-Review change (design doc:
Architecture + Privacy). Ship it as its own reviewed increment.

### Dart
- **Auth service:** on sign-in, write the Firebase credential into a **shared
  Keychain Access Group**; on sign-out/delete, clear it *and* `clearSnapshot()`.
  (New step in the auth service; mirror the existing sign-out cleanup that wipes
  FCM tokens + presence.)
- No new write repository — Siri writes must go through the **same** appointment
  repository methods the app uses, so status normalization
  (`AppointmentStatus.fromRaw(...).raw`) and `firestore.rules` apply unchanged.
  The Swift side calls Firestore directly, so the invariant to enforce in review
  is *field-shape parity* with the Dart repository writes.

### Swift
- `FirebaseExtensionBootstrap.swift` — minimal Firebase app in-extension,
  restore auth from the shared keychain group, activate App Check (App Attest).
- `CancelAppointmentIntent`, `CompleteJobIntent`, `RescheduleIntent`,
  `BookAppointmentIntent` — resolve target by snapshot `id` (booking by client
  name), `requestConfirmation` reads the change back, then commit. Booking lands
  last (needs client resolution + duration default).

### Mac steps (Phase 4)
- App Attest capability + `appattest-environment` entitlement on the **extension**
  target (Runner already has it).
- Shared Keychain Access Group `$(AppIdentifierPrefix)net.vogas.scheduling` on
  Runner + extension.
- Add `firebase-ios-sdk` (Auth, Firestore, AppCheck) to the extension via SPM;
  keep linked products minimal (extension memory budget).

### Phase 4 tests
- Dart: sign-out wipes snapshot **and** shared keychain item.
- Device: confirm-then-commit happy path; offline write → spoken retry, **no
  partial commit**; ambiguous-target disambiguation; role scoping (employee
  can't mutate another's job); Siri-unlock gate before commit.

**Exit:** cancel / complete / reschedule (then book) by voice, confirmed,
role-scoped, rules-enforced.

---

## Phase 5 — live data

- **Swift:** `LiveScheduleClient.swift` — direct Firestore read (reuse Phase-4
  bootstrap) when the snapshot is stale/missing; **fall back to snapshot on
  network failure** (never regress below Phase 1).
- **Functions/Dart:** silent-push snapshot refresh — reuse the push plan's
  `content-available` path (`fcm_background_handler.dart` already rewrites the
  *widget* payload in a background isolate; extend it to also rewrite the
  snapshot key, or add a sibling handler). Keep the isolate dependency-light per
  the existing background-handler invariant.
- **Tests (device):** live query when snapshot stale; snapshot fallback on
  network fail; silent-push refresh.

---

## Phase 6 — proactive & other surfaces (à la carte, Mac-only)

Independent, ship-when-wanted: intent **donations** (`IntentDonationManager`)
after in-app views → Siri Suggestions; interactive `SnippetView` cards; CarPlay
scene; Spotlight `CSSearchableItem` indexing; Apple Watch companion; Action
button. Each is its own small increment; none blocks the others.

---

## Cross-cutting

- **Localization:** all Siri phrases + responses ship EN + FR (matching
  `AppLocalizations.supportedLocales`); response language follows the device's
  Siri language. Add ARB keys only if any string surfaces in-app (the Swift
  string catalogs are separate from `gen_l10n`).
- **Privacy review gate:** Phase 4 is where the extension stops being
  Firebase-free — flag for security-review/App-Review as a conscious change, not
  drift (design doc, Privacy §).
- **CLAUDE.md updates when phases land:** deployment target 15→16 (Phase 1);
  a new "Siri App Intents" invariant note describing the snapshot key + the
  Firebase-in-extension boundary (Phase 4).

## Suggested sequencing

Phases **1–2 first** — highest value-per-effort, almost entirely a clone of the
widget path plus a wider window, and testable on this box. Then **3**. Treat
**4** as a standalone reviewed milestone (the Firebase-in-extension inflection).
**5–6** are opportunistic follow-ups. Android stays out (design doc).
