# Siri App Intents — Implementation Plan

Companion to the design doc [`2026-07-10-siri-app-intents-design.md`](./2026-07-10-siri-app-intents-design.md).
That doc is the *what/why* (six phases, scope decisions, architecture). This is
the *how* — files, order, tests, Mac steps — grounded in the code that already
exists.

**Status: plan written 2026-07-19 — not yet started.**
**Reviewed 2026-07-19 against the code; corrections applied inline.** Phases 1–3
are ready to execute. **Phase 4 is blocked** on two paper decisions flagged in
its Mac steps (App Attest's bundle-ID binding; the not-yet-existing
`keychain-access-groups` entitlement).

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
   - **Drop records with a null `id`.** `AppointmentRecord.id` is `String?`
     ([appointment_record.dart:14](../../lib/features/calendar/domain/models/appointment_record.dart#L14))
     and the widget's `_job()` serializes it straight through, so an id-less job
     can reach the payload as `"id": null`. Phase 4 resolves every write target
     by snapshot `id`, so an id-less entry is unactionable — filter it at build
     time and keep `id` **non-optional** in the Swift `Codable`.
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
   (Snapshot writes happen on iOS only — same `Platform.isIOS` gate.)
   - **Clearing is implicit — do NOT add an explicit sign-out clear.** There is
     no widget clear on the sign-out path to sit alongside: the sign-out sites
     ([settings_screen.dart:463](../../lib/features/settings/screens/settings_screen.dart#L463),
     [main.dart:378](../../lib/main.dart#L378)) only unregister push + presence.
     The widget clears because sign-out makes `widgetEmployeeIdProvider` resolve
     null → `widgetPayloadProvider` emits `data(null)` → the listener calls
     `clear()` ([main.dart:469](../../lib/main.dart#L469)). Mirror that
     null-for-clear contract in `scheduleSnapshotProvider` and the snapshot wipes
     itself for free.

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
2. Bump `IPHONEOS_DEPLOYMENT_TARGET` 15.0 → **16.0** — across **all 6 build
   configurations** in `ios/Runner.xcodeproj/project.pbxproj` (lines 512, 569,
   615, 658, 779, 832), i.e. Runner *and* the `ScheduleWidget` extension, not
   Runner alone. Verify App Attest still passes (design doc: iOS 16 keeps the
   ≥14 App Attest floor). **This drops iOS 15 users** — a product decision, not
   just a build setting. Update the CLAUDE.md "Deployment target is **iOS
   15.0**" note when this lands.
3. Pull in the authored Swift files; wire the SPM `firebase-ios-sdk` **only if**
   later phases need it (Phase 1 extension is Firebase-free).

### Phase 1 tests
- `buildScheduleSnapshot`: role matrix (admin all vs employee `employeeIds`
  filter), 7-day bucketing + device-local boundaries, cancelled exclusion,
  legacy `confirmed`→allowlist normalization, per-day cap 30, empty input,
  `version`/`generatedAt`/`id` presence, **null-`id` records dropped**.
- `ScheduleSnapshotService.signatureForTesting` — dedup ignores `generatedAt`;
  a changed schedule changes the signature. **Pure statics only.** `home_widget`
  is a method-channel plugin, so the write / `clearSnapshot` / iOS-gate paths
  are *not* unit-testable here (CLAUDE.md's device-only rule) — mirror the
  existing pattern, which tests exactly these two pure surfaces:
  `test/features/home_widget/widget_payload_test.dart` +
  `widget_signature_test.dart`.
- Device (Mac): EN+FR phrase recognition × 3 intents; normal/empty/stale/
  signed-out/locked states; snapshot write + clear actually land in the App
  Group (the part the harness can't cover).

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
- **No Dart work for credential sharing.** An earlier draft had the Dart auth
  service writing the Firebase credential into a shared Keychain Access Group —
  `firebase_auth` exposes no such Dart API. The real mechanism is **native and
  automatic**: call `Auth.auth().useUserAccessGroup("$(AppIdentifierPrefix)net.vogas.scheduling")`
  in `AppDelegate.swift` **and** in the extension's bootstrap; Firebase Auth then
  syncs its own state through the keychain and Dart does nothing. See the Mac
  steps below — this is a Swift task, not a Dart one.
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
- ⚠️ **Resolve App Attest's bundle-ID binding BEFORE starting this phase.** App
  Attest keys are bound to a bundle ID, and `SiriIntents` gets a different one
  from `net.vogas.scheduling`. So the extension cannot simply inherit Runner's
  attestation: it likely needs its **own Firebase iOS app registration + its own
  App Check provider config in the console**, or its Firestore calls are
  rejected at the App Check gate with an opaque `permission-denied`. Decide this
  on paper first — discovering it mid-session on the Mac burns the session.
- Add `keychain-access-groups` to **`ios/Runner/Runner.entitlements`** (it has
  `appattest-environment`, `aps-environment`, and app groups today, but **no
  keychain sharing** — this entitlement does not exist yet) and to the extension
  entitlements; group `$(AppIdentifierPrefix)net.vogas.scheduling`.
- Call `Auth.auth().useUserAccessGroup(...)` in `AppDelegate.swift` and in the
  extension bootstrap (see Dart § — this replaces the credential-writing step).
- App Attest capability + `appattest-environment` entitlement on the **extension**
  target (Runner already has it).
- Add `firebase-ios-sdk` (Auth, Firestore, AppCheck) to the extension via SPM;
  keep linked products minimal (extension memory budget).

### Phase 4 tests
- Device (not Dart — the keychain sharing is native, see above): sign-out wipes
  the snapshot **and** drops the shared keychain credential, so a Siri write
  attempted after sign-out fails closed.
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
- **Snapshot data-protection class (decide in Phase 1, not later):** Siri answers
  while the device is locked, so the App Group payload must remain readable when
  locked — which puts client names, addresses, and phones at a weaker protection
  class than the rest of the app's data. The widget already accepts this for 2
  days of one employee's jobs; the snapshot widens it to **7 days and, for
  admins, the whole business**. That's a deliberate widening of at-rest PII
  exposure — record it in the design doc's Privacy §, and consider trimming the
  snapshot to the fields the intents actually speak (client name + time + status)
  rather than copying the full job shape.
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
