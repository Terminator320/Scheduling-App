# Siri App Intents — Implementation Plan

Companion to the design doc [`2026-07-10-siri-app-intents-design.md`](./2026-07-10-siri-app-intents-design.md).
That doc is the *what/why* (six phases, scope decisions, architecture). This is
the *how* — files, order, tests, Mac steps — grounded in the code that already
exists.

**Status: Phase 1 COMPLETE except on-device verification (2026-07-19).**
The Dart half (builder, service, provider, `main.dart` wiring, 15 unit tests) is
in `lib/features/siri/`; the Swift half is in `ios/SiriIntents/` with a Mac
runbook + device checklist at `ios/SiriIntents/README.md`. The `SiriIntents`
App Intents extension target **was created and embedded in Runner 2026-07-19**
and builds clean (bundle id `net.vogas.scheduling.SiriIntents`, entitlements
`SiriIntentsExtension.entitlements` sharing the App Group). The deployment
target went to **iOS 18.0**, not the 16.0 this plan originally called for — the
Live Activity Directions button's returnable `OpenURLIntent` forced the whole
app to an 18.0 floor. Remaining for Phase 1: the on-device Siri phrase pass.
Phases 2–3 not started.
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
| Emission-driven wiring | `_widgetSync()` in [`app_sync_listeners.dart`](../../lib/core/app/app_sync_listeners.dart) | `_snapshotSync()` sits beside it (both moved out of `main.dart` 2026-07-19) |
| Off-screen-mirror identity | `activeUserIdentityProvider` | Same provider — one active+role gate for both mirrors |
| Midnight rollover | `currentDayProvider` | Same provider — neither mirror may use a bare `DateTime.now()` |
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

## Phase 1 — read, today/next (the foundation) — ✅ BUILT

Everything below is **as-built** (2026-07-19), not a plan. Where the shipped
code diverges from what this doc originally specified, the divergence is called
out — those are the parts worth knowing before touching it.

### Dart — landed in `lib/features/siri/`

1. **`domain/schedule_snapshot.dart`** (98 lines) — pure builder.
   `buildScheduleSnapshot({appointments, role, now})` → `Map<String, dynamic>`.
   Day-buckets `now.dateOnly … +7d` (device-local), **excludes cancelled**,
   per-day cap 30 (`scheduleSnapshotPerDayCap`), stamps
   `version: scheduleSnapshotVersion` + `generatedAt` + `role`, carries `id`.
   Records with a null/empty `id` are dropped — Phase-4 write actions resolve
   their target by `id`, so an id-less entry is unactionable, and `id` is
   **non-optional** in the Swift `Codable`.
   - ⚠️ **Divergence — status normalization needed a special case.** This plan
     said "normalize via `AppointmentStatus.fromRaw(a.status).raw`". That alone
     would **throw**: reading `AppointmentStatus.overdue.raw` throws on purpose
     (CLAUDE.md — it's a display-only state that must never be written), so a
     doc somehow storing `overdue` would fail the entire snapshot build rather
     than one record. The shipped `_storedStatus` maps `overdue → pending`
     first, then takes `.raw`. Keep that guard if you touch the builder.
2. **`application/schedule_snapshot_service.dart`** (83 lines) — imports
   `widgetAppGroupId` (not redefined), writes under the **public** const
   `scheduleSnapshotKey = 'schedule_snapshot'`, `_signatureOf` dedup minus
   `generatedAt`, `_lastState` with a distinct `_clearedState` sentinel so a
   repeat clear is also deduped, `Platform.isIOS` gate, `warn` on failure.
   Provider `scheduleSnapshotServiceProvider` injects `loggerProvider`.
   - **Divergence:** this plan (and the design doc) called for "an injected
     interface so tests mock it". The shipped service takes only an optional
     `AppLogger`; `home_widget` is called statically, exactly as
     `WidgetSyncService` does. Consequence: the write/clear paths are
     device-only, and just the two pure statics are unit-tested — which is the
     established pattern, not a shortfall.
3. **`application/schedule_snapshot_provider.dart`** (47 lines) — role-aware,
   `Provider.autoDispose`. Employee → `myAppointmentsProvider`, admin →
   `appointmentsInRangeProvider`. Signed-out/inactive → `data(null)` (clear).
   Two divergences, both deliberate and both load-bearing:
   - ⚠️ **Identity comes from `activeUserIdentityProvider`**, not
     `currentUserDocProvider` / a copy of `widgetEmployeeIdProvider`'s guard.
     Both off-screen mirrors (this and the home-screen widget) now resolve *who
     they're for* through that one provider — active-status gate,
     employee-or-admin, `retryAsync(findUserByUid)` for the post-sign-in token
     lag. It returns `(role, docId)`, and its null is what wipes both mirrors on
     sign-out. Route any new mirror through it rather than re-deriving.
   - ⚠️ **The provider watches `currentDayProvider`** (`core/utils/`) for its
     day bucketing instead of a bare `DateTime.now()`. The appointments stream
     only re-emits on a write, so an app left resident overnight otherwise kept
     publishing yesterday's buckets and **Siri answered "no appointments today"
     while jobs existed**. This was found and fixed by the 2026-07-19 audit
     (bug B2); don't reintroduce a bare `now` here.
4. **Wiring** — `_snapshotSync()` in
   [`lib/core/app/app_sync_listeners.dart`](../../lib/core/app/app_sync_listeners.dart),
   registered by `AppSyncListeners.registerAll()`.
   - **Divergence:** this plan said "add `_listenForSnapshotSync()` to
     `main.dart`". It landed there first, then moved: the ~10 `ref.listen`
     wire-ups were extracted out of `main.dart` into `AppSyncListeners` so they
     could be unit-tested without building a `MaterialApp`. The
     account-lifecycle listeners stayed in `main.dart` (their registration order
     is load-bearing). Old `main.dart:458/469/378` line references in earlier
     drafts of this doc are dead.
   - **Clearing is implicit — do NOT add an explicit sign-out clear.**
     `scheduleSnapshotProvider` emits `data(null)`, the listener calls
     `clearSnapshot()`. Same contract as the widget.

**No pubspec change** (`home_widget` already present). No new App Group.

### Swift — landed in `ios/SiriIntents/`

| File | Lines | What |
|---|---|---|
| `ScheduleSnapshot.swift` | 99 | `Codable` + App Group `UserDefaults` loader; rejects missing/undecodable/wrong-`version`; `day(on:)`, `today`, `nextAppointment(after:)`, `dayKey` mirroring the Dart `_dayKey`; `deepLink` → `esproschedule://appointment?id=…` |
| `AppointmentCountIntent.swift` | 30 | "how many appointments today" |
| `TodayScheduleIntent.swift` | 35 | reads today's list, time + client per line |
| `NextAppointmentIntent.swift` | 32 | earliest upcoming not-done visit across the **whole 7-day window**, so an empty rest-of-today still answers with tomorrow's first job |
| `ESProShortcuts.swift` | 50 | `AppShortcutsProvider`, 14 phrases across EN + FR |
| `SiriStrings.swift` | 132 | all spoken text, EN + FR |
| `Info.plist` | 11 | `NSExtensionPointIdentifier = com.apple.appintents-extension` |
| `README.md` | 86 | Mac runbook + device checklist |

- **Divergence:** the plan called for "EN/FR string catalogs". Shipped as one
  plain-Swift `SiriStrings.swift` instead, so both localizations sit side by
  side and review as one file. Response language follows `Locale.current`,
  matching how `ScheduleWidget.swift` picks its labels.
- All three intents set `openAppWhenRun = false` and
  `authenticationPolicy = .alwaysAllowed` — reads answer from the lock screen
  without unlocking, which is the hands-free point. **Phase-4 write intents must
  NOT copy that policy.**
- Types are gated `@available(iOS 16.0, *)` even though the app floor is now
  18.0. Harmless and left alone: the gate is what the App Intents API requires,
  and keeping it means the files don't need touching if the floor ever moves.

### Mac steps (Phase 1) — done 2026-07-19

1. ✅ **App Intents extension target `SiriIntents` created and embedded in
   Runner** — bundle id `net.vogas.scheduling.SiriIntents`, entitlements
   `SiriIntentsExtension.entitlements` sharing the App Group
   `group.net.vogas.scheduling`. Builds clean.
2. ✅ **Deployment target bumped — but to 18.0, not 16.0.** This plan called for
   15.0 → 16.0 across all 6 build configurations. What actually happened: the
   Live Activity Directions button's returnable `OpenURLIntent` is **iOS 18+**,
   so the whole app moved to an **18.0** floor in the same session, which
   subsumes Siri's 16.0 requirement. iOS 15–17 users are dropped — a product
   decision, taken. App Attest's ≥14 floor is still satisfied. (The pbxproj line
   numbers this plan used — 512, 569, 615, 658, 779, 832 — are stale; the file
   has changed since.) CLAUDE.md's deployment-target note is updated.
3. ✅ Swift files pulled in. `firebase-ios-sdk` deliberately **not** linked into
   the extension — Phase 1 is Firebase-free.

### Phase 1 tests — 15, all passing

- `test/features/siri/schedule_snapshot_test.dart` — **12 tests** over the pure
  builder: role matrix, 7-day bucketing + device-local boundaries, cancelled
  exclusion, legacy `confirmed`→allowlist normalization, per-day cap 30, empty
  input, `version`/`generatedAt`/`id` presence, null-`id` records dropped.
- `test/features/siri/schedule_snapshot_signature_test.dart` — **3 tests** on
  `signatureForTesting`: dedup ignores `generatedAt`; a changed schedule changes
  the signature.
- `test/features/auth/application/active_user_identity_provider_test.dart` —
  added by the 2026-07-19 audit (finding T4). It covers the identity provider
  both mirrors now depend on: the active+role gate returning null, and
  `retryAsync` surviving the post-sign-in `permission-denied` lag. A regression
  there silently wipes both the widget and this snapshot.
- **Not unit-testable** (CLAUDE.md device-only rule): the write / `clearSnapshot`
  / iOS-gate paths — `home_widget` is a method-channel plugin.

### Phase 1 remaining: on-device verification

The only thing left. Per `ios/SiriIntents/README.md`: EN + FR phrase
recognition × 3 intents; normal / empty / stale / signed-out / locked states;
snapshot write + clear actually landing in the App Group.

**Phase 1 exit:** three read intents answer from the snapshot on a device;
sign-out wipes it. *(Code complete; awaiting the device pass.)*

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
- **Snapshot data-protection class — ✅ decided and applied in Phase 1.** Siri
  answers while the device is locked, so the App Group payload stays readable
  when locked, putting everything in it at a weaker protection class than the
  rest of the app's data. The widget already accepts this for 2 days of one
  employee's jobs; the snapshot widens it to **7 days and, for admins, the whole
  business**. The mitigation this section asked for **was taken**: the payload
  carries only the fields the intents actually speak — `id`, start/end millis,
  client name, address, status. **Never** notes, phone, pictures, or materials.
  The builder's doc comment records why; keep it that way when adding a field.
- **Privacy review gate:** Phase 4 is where the extension stops being
  Firebase-free — flag for security-review/App-Review as a conscious change, not
  drift (design doc, Privacy §). Note the snapshot itself adds **no new App
  Privacy data type** — everything in it is already declared (Name, Physical
  Address, Other User Content); see `docs/plans/APP_STORE_SUBMISSION.md` Part 8.
- **CLAUDE.md updates when phases land:** ✅ deployment target (Phase 1 — landed
  as 18.0, see Mac steps) and the Siri App Intents invariant note (snapshot key,
  `activeUserIdentityProvider` routing, `currentDayProvider` rollover, the
  hand-mirrored Dart↔Swift pair, the id-drop rule) are both in CLAUDE.md today.
  Still to add when Phase 4 lands: the Firebase-in-extension boundary.

## Suggested sequencing

Phase **1 is built** — only its device pass remains. **Phase 2 next**: it is
pure-additive Swift over a snapshot that already carries all 7 days, so it needs
no Dart and no schema change, making it the highest value-per-effort increment
left. Then **3**. Treat **4** as a standalone reviewed milestone (the
Firebase-in-extension inflection, and still blocked on the two paper decisions
in its Mac steps). **5–6** are opportunistic follow-ups. Android stays out
(design doc).
