# Codebase Audit — 2026-07-19 (deep pass)

**Branch:** `notification` · **Scope:** `lib/`, `functions/`, `firestore.rules`,
`storage.rules`, `test/`, `lib/l10n/*.arb` (whole repo)

> Supersedes the earlier run archived at `CODEBASE_AUDIT_2026-07-19-earlier.md`,
> which reported zero security findings and zero bugs. This pass verified the
> rules→bridge→deactivation chain, the declared Firestore indexes, and each
> hand-mirrored payload pair against source, and **contradicts that conclusion**.
> The earlier run's auto-applied spacing/token cleanups remain valid.

**Method:** deterministic static scan, then five parallel deep reviewers
(security, bugs, dead-code/convention, performance, maintainability). Every
headline finding below was independently re-verified against source before being
written down.

**Verification state:** `flutter analyze` → *No issues found*. `flutter test` →
**966/966 passing** (identical to the pre-audit baseline). `functions` ESLint →
clean. `dart fix --dry-run` → *Nothing to fix*.

---

## STATUS: all findings below were implemented on 2026-07-19

Everything in this report except the launch-time pre-ship switches has been
fixed, in the same working tree. Post-implementation verification:

| Check | Result |
|---|---|
| `flutter analyze` | **No issues found** (zero, including info lints) |
| `flutter test` | **979 passing** (was 966; +13 new) |
| `functions` jest | **552 passing in 24 suites** (was 420 in 22) |
| `functions` ESLint | clean |

Two items were **deliberately not implemented** — see "Declined, with reasons"
at the end. Three additional bugs were discovered *while* implementing (found by
the new tests) and are recorded in "Found during implementation".

---

## 1. What was auto-fixed

One change only — the static layer was already clean.

| File | Change |
|---|---|
| `lib/shared/widgets/fields/labeled_text_field.dart:173` | `EdgeInsets.only(top: 4)` → `EdgeInsets.only(top: AppSpacing.sp4)` (+ token import). `AppSpacing.sp4 == 4`, so this is byte-equivalent at runtime. |

Nothing else met the "reversible + obvious + behavior-preserving" bar. The
analyzer found no dead code, `dart fix` had nothing to apply, ESLint was clean,
there were no BOM'd files, and all four unused-dependency hits from the scan are
confirmed false positives (`freezed`/`build_runner` generate 9 model files,
`flutter_launcher_icons` is a CLI tool, `google_maps_flutter_ios_sdk9` is the
deliberate SPM endorsed override).

---

## 2. Deploy blockers — fix before the next `firebase deploy`

### D1. Missing `liveActivityTokens` composite index — the entire Live Activity feature silently no-ops
**Severity: HIGH · Confidence: high · `firestore.indexes.json` (absent entry)**

`live_activity_registry.js:116-125` and `:139-148` are **collection-group**
queries with two equality filters:

```js
q.where("kind", "==", KIND_PUSH_TO_START).where("employeeDocId", "in", chunk)
q.where("kind", "==", KIND_UPDATE).where("employeeDocId", "==", employeeDocId)
```

Two-field composite indexes are never created automatically. `firestore.indexes.json`
contains **zero** `liveActivityTokens` entries, so Firestore rejects both with
`FAILED_PRECONDITION` — and `_query`'s catch at `:100-103` swallows it and returns
`[]`. `startLiveActivity`/`updateLiveActivity`/`endLiveActivity` all return 0 and
degrade to the plain `leaveNow` push with only a `warn` line.

The feature's deliberate best-effort design masks its own breakage here. Since
Live Activities have never been deployed, this would present as "the card just
never appears," with no obvious error.

**Fix:** add a `COLLECTION_GROUP`-scope composite index on `liveActivityTokens`
for `(kind ASC, employeeDocId ASC)` before deploying.

### D2. On-site flip pass is skipped whenever there are no travel candidates
**Severity: HIGH · Confidence: high · `functions/travel_utils.js:341`**

Found independently by two reviewers; verified verbatim:

```js
if (candidates.length === 0) return {reminded: 0};   // line 341
...
const flipped = await runOnSiteFlipPass(deps);        // line 477 — unreachable
```

`runOnSiteFlipPass` is the **only** thing that flips a live card from `travel` to
`onSite`, and the only thing that clears a marker for a deleted/terminal job.
`selectTravelCandidates` requires `startTime > now`, so the moment a tech's job
starts they stop being a candidate — and if nobody else has a job in the next 90
minutes, the sweep returns at line 341 and the flip never runs. The card sits on
"On the way" for the whole visit and orphan markers survive to their 12h TTL. The
early return also yields a differently-shaped result object than the normal path.

**Fix:** run `runOnSiteFlipPass(deps)` before the early return, or restructure so
both paths reach it.

---

## 3. Security findings

### S1. Disabled employees retain read access to assigned appointments and photos
**Severity: HIGH · Confidence: high · `firestore.rules:46-49`, `storage.rules:26-37`**

The most consequential finding in this audit. Verified across all four links:

```
function isAssignedEmployee(appointmentData) {
  return userByUidExists()                     // existence only — no status gate
    && myDocId() in appointmentData.employeeIds;
}
```

`isActiveUser()` three lines above **does** require `status == 'active'`; this one
does not. The same omission exists in `storage.rules:26-37`
(`isAssignedToAppointment`), where the `isAdmin()` helper directly above it *does*
check status. That asymmetry is what makes this read as an oversight rather than a
deliberate carve-out.

The gap is reachable because:
- `functions/bridge.js:6` — `VALID_BRIDGE_STATUS = new Set(["active", "disabled"])`,
  so the `usersByUid` bridge doc is **deliberately retained** for disabled users.
- `firebase_employees_repository.dart:189-194` — `deactivateEmployee` flips only
  the Firestore `status` field. The Firebase Auth account is never disabled and
  refresh tokens are never revoked, so the credential keeps working.
- The runtime kick-out (`SplashScreen`, `account_status_provider`) is
  **client-side only** and bypassed by talking to the Firestore REST API directly.

**Impact:** a terminated employee can keep reading every appointment they were
assigned — client name, phone, full address, notes, photo URLs — plus the job
photos in Storage, indefinitely. Write access is correctly capped
(`firestore.rules:289-295` limits them to `status: 'done'` on
`['status','updatedAt']`), so the exposure is **read/PII**, not data corruption.

**Fix:** add the status gate to both helpers —
`return isActiveUser() && myDocId() in appointmentData.employeeIds;` and
`&& bridge.data.status == 'active'` in `storage.rules`. Consider also calling
`getAuth().updateUser(uid, {disabled: true})` + `revokeRefreshTokens` from
`syncUsersByUid` when status leaves `active`. **Requires a rules deploy.**

### S2. Live Activity dispatch has no recipient-status gate
**Severity: LOW-MED · Confidence: medium-high · `functions/notification_utils.js:726-734`, `functions/live_activity_dispatch.js:237-264`**

`sendToEmployee` filters on `user.status !== "active"` (`:539`), but
`updateLiveActivity`/`endLiveActivity` run unconditionally afterwards, gated only
on the card marker. `bridge.js:151` purges `presence` on deactivation but not
`fcmTokens`, `liveActivityTokens`, or the live card. A tech disabled mid-travel
keeps a Lock Screen card showing a client name + address, and a later reschedule
pushes a refreshed one.

**Fix:** end the card and delete `users/{docId}/liveActivityTokens/*` in the
`shouldPurgePresence` branch of `syncUsersByUid`; short-circuit
`updateLiveActivity` when the recipient isn't active.

### S3. Client-controlled `expiresAt` on `liveActivityTokens`
**Severity: LOW · Confidence: high · `firestore.rules:223-224`**

The rule only checks `expiresAt is timestamp`. A client can write a year-out value
so its APNs token row is never reaped by `pruneExpiredActivityTokens`. Self-scoped,
so the impact is a stale row rather than cross-tenant exposure.

**Fix:** bound it — `request.resource.data.expiresAt < request.time + duration.value(4, 'd')`.

### S4. Routes API error body echoed into logs
**Severity: LOW · Confidence: medium · `functions/travel_utils.js:281-286`**

`preview = (await response.text()).slice(0, 200)` is logged on a non-200. The
request body carries staff GPS coordinates or a client street address, and Google
`INVALID_ARGUMENT` responses commonly echo the offending field. `places.js:63-65`
deliberately sets `logResponsePreview: false` on the reverse-geocode path for
exactly this reason — this site is the inconsistency.

**Fix:** log `status` only, matching `placesReverseGeocode`.

### S5. Wave callables deviate from the documented guard order
**Severity: LOW · Confidence: high · `functions/wave/callables.js:132-133, 210-211, 242-243`**

`assertPayloadShape` runs *before* `assertAdmin` in `waveBootstrap`,
`waveGetConnection`, and `waveSetImportSchedule`. `.claude/rules/security.md` pins
the order as auth → `assertAdmin` → payload → limiter. No slot-burning consequence
(the limiter is correctly below both), but it lets a non-admin distinguish
`unexpected-field` from `wave/not-admin`. `places.js` and `invites.js` follow the
correct order.

### S6. `functions/` transitive advisories — no action recommended
**Severity: LOW (informational) · Confidence: high**

`npm audit --omit=dev`: 1 critical + 8 moderate, all transitive through
`firebase-admin@13`. The critical (`websocket-driver`) arrives via the RTDB client,
which nothing in `functions/` uses — not reachable on any call path. Per the
existing decision, do **not** force `firebase-admin@14`; re-check on the next
admin-SDK minor.

### Security categories checked, nothing found
Injection (no SQL/shell/`eval`; inputs go through `requireString`/
`requireNumberInRange` + `encodeURIComponent`) · secrets (all `defineSecret` only;
nothing sensitive in `dev/.env`; no tracked `.p8`/`google-services.json`) · App
Check (`enforceAppCheck: true` on all 9 callables; `activate()` intact at
`main.dart:128`) · rate limiting (durable limiter on all 7 sensitive callables;
`redeemSignupCode` correctly email-keyed) · rules on every new collection
(`signupCodes`, `liveActivityCards`, `appointmentReminders`,
`appointmentOverduePrompts`, `rateLimits`, `wave`, `waveSyncQueue` all
`read, write: if false`; presence write self-only with the
`updatedAt == request.time` anti-spoof) · deep links (`esproschedule://` carries
only an id, requires auth, re-authorized by rules) · crypto (signup codes ~60-bit
`crypto.randomBytes`, sha256-stored; APNs JWT ES256 with correct P1363 encoding) ·
role handling (never cached — `auth_cache.dart:16` explicitly excludes it) ·
callable response casting · image magic-byte validation (both sides).

---

## 4. Bugs

### B1. Opt-out can leave the push-to-start row registered
**Severity: MED-HIGH · Confidence: medium-high · `live_activity_registration_controller.dart:336-347`**

`unregister()` deletes the push-to-start row only
`if (docId != null && pushToStart != null)`, and `_pushToStartToken` is populated
**only** by a stream emission in the current session (`:243-249`). Two holes: (a)
the stream hasn't emitted yet when the user flips the toggle off; (b) after a cold
start with the preference already `false`, `_syncGuarded` returns at `:146` before
`_docId`/`_pushToStartToken` are ever set, so a later `unregister()` is a no-op.
The row survives to its 30-day TTL and the server can keep push-starting cards on
an opted-out device — violating the CLAUDE.md invariant that the toggle "must call
`unregister()` to end the live card and delete this device's token rows."

**Fix:** delete by query (`liveActivityTokens where kind == 'pushToStart'`), or
persist the last token doc id locally so unregister works across sessions.

### B2. Day buckets never refresh across a midnight crossing
**Severity: MED · Confidence: medium-high · `schedule_snapshot_provider.dart:21`, `widget_sync_service.dart:219`**

Both providers capture `DateTime.now()` in the provider body to build the query
range and day keys, then only re-run when the appointments stream emits. Nothing
invalidates them on resume or at midnight (`main.dart:370` handles language change
only). With the app resident overnight and no appointment writes,
`buildScheduleSnapshot` keeps emitting yesterday's `_dayKey` buckets — so
`ScheduleSnapshot.today` matches nothing and **Siri answers "you have no
appointments today" while jobs exist.** The widget's `todayJobs` goes stale the
same way (`rolloverAt` only covers the finished-day case).

**Fix:** invalidate both providers on app-lifecycle `resumed`, and/or on a midnight
timer.

### B3. Widget payload mirrors have drifted on null handling
**Severity: MED (low reachability, high blast radius) · Confidence: high · `widget_sync_service.dart:24-37` vs `functions/widget_payload_utils.js:70-80`**

The JS mirror coerces every field (`String(r.id == null ? "" : r.id)`, `status` →
`"pending"`); the Dart builder emits `a.id` raw, and `AppointmentRecord.id` is
`String?`. The Swift `Job` decodes `id`/`clientName`/`title`/`address`/`status` as
**non-optional**, and `SchedulePayload.load()` uses `try?` — so a single null field
silently drops the **entire** payload and blanks the widget. Not reachable today
(records reach the widget via `fromMap`, which always sets `id`), but the
hand-mirrored pair no longer matches, which is exactly the invariant CLAUDE.md asks
to be kept in lockstep.

**Fix:** mirror the JS coercion in `_job` — `'id': a.id ?? ''`, etc.

### B4. Completing any job ends *all* of this device's live cards
**Severity: LOW · Confidence: high · `event_details_controller.dart:300-302`**

`endLocalCards()` calls `_plugin.endAllActivities()` unconditionally after any
status write. Marking job B done kills a live "time to leave" card for job A; the
server marker still points at A, so no re-start happens.

**Fix:** end only when the completed appointment matches the local card's job, or
accept and document the behavior.

### B5. `generatedAt` is a zone-less local ISO string
**Severity: LOW · Confidence: high · `widget_sync_service.dart:107`**

`now.toIso8601String()` emits no `Z`, while the server mirror emits `iso(nowMs)`
and the file's own comment at `:30` documents that the Swift `ISO8601DateFormatter`
can't parse a zone-less string. Harmless today (Swift keeps it as an opaque
`String`) but inconsistent in a payload whose contract is "absolute UTC instants."
**Fix:** `now.toUtc().toIso8601String()`.

### B6. Live Activity support probe cached for the process lifetime
**Severity: LOW · Confidence: high · `live_activity_registration_controller.dart:39-41`**

`liveActivitySupportedProvider` is a non-autoDispose `FutureProvider` wrapping
`canHostCards()`, which includes the **user-mutable** `areActivitiesEnabled()`.
Re-enabling Live Activities in iOS Settings won't restore the Settings row until
relaunch. **Fix:** invalidate on lifecycle `resumed`, as `settings_screen.dart:89`
already does for `notificationAuthStatusProvider`.

### B7. No size guard on the embedded `widgetPayload`
**Severity: LOW · Confidence: medium · `functions/notification_utils.js:552, 710`**

The change push embeds up to 3 days of jobs (with addresses) in the FCM `data` map.
FCM caps payloads at 4 KB; a busy window would make `sendEach` reject the message
and lose the **visible** notification too, not just the widget refresh.
**Fix:** drop `widgetPayload` when the encoded string exceeds ~3 KB.

### B8. Missing `mounted` guard after an awaited action sheet
**Severity: LOW · Confidence: medium · `wave_settings_section.dart:124`**

`setState(() => _scheduleBusy = true)` runs after an awaited
`showAdaptiveActionSheet` with no guard. Likely unreachable in practice (a disposed
widget makes the sheet return `null`, hitting the early return at `:121`).
**Fix:** one `if (!mounted) return;` after line 121.

---

## 5. Areas to improve

### Performance / cost

**P1 — Routes API billed ~14× more than necessary (IMPACT: HIGH).**
`functions/travel_utils.js:413-428`. `computeTravelSeconds` runs **before** the
`isDue` check. Candidates are everything starting within the 90-minute
`TRAVEL_WINDOW_MS`, so a job 90 minutes out is swept ~18 times and every sweep pays
a `computeRoutes` TRAFFIC_AWARE call — only the last one fires a push, the rest hit
`if (!isDue(...)) continue;` and discard the result. Roughly 210 wasted paid
calls/day at current volume, scaling linearly with jobs and headcount.
**Fix:** memoize `travelSeconds` per `(candidateId, employeeDocId)` for ~15 min and
re-check `isDue` against the cached estimate, only re-querying when stale or close
to the predicted leave time. One-line partial win: narrow `TRAVEL_WINDOW_MS` to
~45 min.

**P2 — Origin-context query reads ~15× more docs than it consumes (IMPACT: MEDIUM).**
`functions/travel_utils.js:371-377`. The query filters `endTime > lookbackStart`
with **no upper bound**, so it matches every future appointment for that employee
and relies on `CONTEXT_QUERY_MAX = 50` to cap it — while `decideOrigin` only ever
consumes a handful. Pre-booked repeating series will reliably saturate the cap.
~43k reads/day today; scales with headcount. **Fix:** add the matching upper bound
on the same field (no new index needed):
`.where("endTime", "<=", new Date(nowMs + TRAVEL_WINDOW_MS))`.

**P3 — New TLS + HTTP/2 handshake per Live Activity push (IMPACT: MED-LOW).**
`functions/apns_client.js:264`. Every push opens a fresh `http2` session to
`api.push.apple.com` and closes it in `finally`; APNs is designed for a long-lived
multiplexed session, and the sends are serial loops nested inside the sweep, so
~150-400ms of handshake compounds. (The provider-JWT caching at `:111-126` is
already correct.) **Fix:** cache the session at module scope keyed by host,
reconnect lazily on `close`/`error`/`goaway`.

**P4 — Three overlapping appointment listeners open for the whole session (IMPACT: MED-LOW).**
`schedule_snapshot_provider.dart:31-38` (today→+8d),
`widget_sync_service.dart:220-226` (today→+3d), and the calendar's own range
listener. `main.dart` holds `ref.listen` on the first two for the app lifetime so
their `autoDispose` never fires, and today's jobs are billed 3×. For an **admin**
the Siri provider is the business-wide query — the widest of the three.
**Fix:** derive the widget payload from the Siri snapshot (the 3-day window is a
strict subset of the 8-day one), or align both onto one `AppointmentDateRange`
family key.

### Test coverage

**T1 — `functions/live_activity_registry.js` (368 lines) has no test file at all (IMPACT: HIGH).**
Worse, `test/live_activity_dispatch.test.js:13` `jest.mock()`s the whole module out,
so it isn't exercised even transitively. It owns
`liveActivityCards/{employeeDocId}`, which CLAUDE.md calls **"load-bearing, not a
convenience."** Untested: `writeCardMarker`/`readCardMarker`/`setCardPhase`/
`clearCardMarker`, the `IN_QUERY_MAX` chunking, and the TTL logic. These are
pure-with-injected-`db` — directly jest-testable.

**T2 — `functions/wave/callables.js` (482 lines) has no test file (IMPACT: MED-HIGH).**
It contains the admin callables and their guard ordering, which
`.claude/rules/security.md` pins as an explicit invariant. Every other Wave module
has a test; this is the exception. `places_admin_gate.test.js` is the pattern to
copy — and a test here would have caught S5.

**T3 — `functions/time_utils.js` (128 lines) has no direct test (IMPACT: MED).**
The module exists specifically "so a push and the Live Activity card can't drift on
how they render the same instant" — a contract currently asserted only indirectly.
`businessMidnight`/`businessOffsetMs`/`businessYmd` are DST-sensitive and
Toronto-specific; a DST-boundary test is a handful of lines.

**T4 — `activeUserIdentityProvider` (43 lines) has zero test references (IMPACT: MED).**
CLAUDE.md: "returning null is what wipes both mirrors on sign-out." Both behaviors
that matter — the active+role gate returning null, and `retryAsync` surviving the
post-sign-in `permission-denied` lag — are untested. A regression here silently
wipes the iOS widget and the Siri snapshot for signed-in users.

**T5 — `functions/` has two parallel test directories (IMPACT: LOW).**
`functions/__tests__/` (8 files) and `functions/test/` (7 files), with
`security.test.js` existing in **both**, covering different exports of the same
module. Jest runs both so nothing is broken, but "where do I add a test for X" has
no answer. Consolidate and merge the two.

### Maintainability

Ranked by payoff. Note the clone detector found **no substantial duplication at 3+
instances** anywhere — these are size/comprehension items, not DRY violations.

| # | Location | Lines | Seam |
|---|---|---|---|
| A1 | `functions/wave/worker.js:466` `drainQueue()` | **296** | Already two phases separated by the author's own banner comments: reclaim pass (~493-597) + main drain (~598-761). Split into `reclaimStaleJobs()` + `dispatchQueuedJobs()`. Highest payoff — this is the transactional outbox, the hardest code in the repo to reason about. |
| A2 | `lib/main.dart` | **658** | Two clean seams: the deep-link block (191-331) → `AppointmentDeepLinkHandler`, and the ~10 `_listenFor*` wire-ups (415-588) → an `AppLifecycleListeners` class taking `WidgetRef`. The latter is currently untestable without building `MaterialApp`; extracting it makes it unit-testable. |
| A3 | `event_details_controller.dart:354` `save()` | **135** | Carries three separate CLAUDE.md invariants at once (assignee preservation, status normalization, flag-before-first-await). Pull the guard/validate front half into `_guardAndValidate()`. |
| A4 | `functions/travel_utils.js:325` `runTravelAwareReminderSweep()` | **156** | Extract the per-(job, assignee) body into `resolveReminderForAssignee()`; the sweep becomes a loop. Also where D2 and P1 live. |
| A5 | `functions/wave/client.js:140` `graphql()` | **142** | Split the retry/backoff loop from response/error parsing. |
| A6 | `appointment_form_fields.dart:176` `build()` | **178** | Largest `build()` in `lib/` by 65 lines; a linear field list → 3-4 `_xSection()` builders. |
| A7 | `live_map_screen.dart` | **591** | Lines 491-591 are four presentational widgets → `widgets/live_map_overlays.dart`. |
| A8 | `main_calendar_screen.dart:223` `_prepareBuild()` | **70** | Side effects (`ref.listen` registration, role-upgrade) hidden inside a method named `_prepare*` — lift them out. |
| A9 | `details_view_body.dart` | **588** | Lines 311-588 are six leaf widgets; the precedent (`details_view_widgets.dart`) already exists. |

**Explicitly not recommended for splitting:** `themes.dart`'s
`_buildLightTheme`/`_buildDarkTheme` (151/142 lines of linear `ThemeData` config),
`settings_screen.dart` (656, linear `_xCard()` sequence),
`firebase_appointments_repository.dart` (557, breadth not tangle — no method over
40 lines), `day_route_screen.dart` (569). The remaining 12 over-60-line `build()`
methods are all linear widget trees.

### Convention drift (small)

- `address_autocomplete_field.dart:125, 167` — two `catch (e)` blocks set UI error
  state but never `logger.warn(...)`. A Places failure (quota, App Check rejection,
  `assertAdmin` denial) is invisible in Crashlytics. **Fix:** capture `catch (e, st)`
  and add `ADDR-AUTOCOMPLETE` / `ADDR-DETAILS` tagged warns.
- `wave_settings_section.dart:278` — the inline load-failure row renders
  `error_somethingWentWrong` directly, so offline vs. `permission-denied` is
  indistinguishable. Optional: route through `composeErrorNotice` with a new
  `WAVE-CONN` tag (needs a new ARB key pair).
- `biometric_auth_service.dart:16, 29` — documented fail-closed `catch (_)`
  returning `false`. Correct as-is; a permanently-failing `local_auth` channel is
  just undiagnosable. Optional non-fatal warn.

### Dead code (report-only — public API, not analyzer-flagged)

- `image_storage_service.dart:61` `uploadImages(...)` + `:131`
  `ImageUploadBatchResult` — zero call sites; the live pipeline calls `uploadImage`
  singly. A future caller could route around the `PendingUploadStore` queue without
  realizing it. Remove together, or add a `NOTE:` if reserved.
- `functions/live_activity_registry.js:84` `activityTokenExpiry(now)` (exported at
  `:357`) — declared, exported, never called; write paths use `TOKEN_TTL_MS`
  directly. Delete, or wire it in so expiry is computed in one place.

---

## 6. Verified clean — no action needed

Recorded so the ground is known to be covered:

- **l10n:** 429 EN keys, 429 FR keys, **zero drift**, **zero orphans**. Every key
  resolves to a real reference. Nothing to prune.
- **Providers:** 75+ declarations, all with ≥1 reference. No zero-ref providers.
- **Files:** the only zero-inbound-import files are the 9 `*.freezed.dart` parts and
  `main.dart`. Expected.
- **Convention:** zero `throw Exception(...)` in `lib/`; exactly the 3 sanctioned
  `ScaffoldMessenger` sites and all 3 go through `errorSnackBar(...)`; zero
  `FirebaseFirestore.instance` in UI; zero hardcoded `maxLength` integers; every
  `Platform.isIOS` site is device *capability*, never look; zero BOM'd files; zero
  `TODO`/`FIXME`/`HACK` markers.
- **Hand-mirrored pairs that DO still match:** `buildContentState` ↔
  `LiveActivitiesAppAttributes.ContentState`; `buildAttributes` ↔ the attributes
  struct; `ATTRIBUTES_TYPE` ↔ the Swift struct name ↔ `ActivityConfiguration(for:)`;
  `buildScheduleSnapshot` ↔ `ScheduleSnapshot.swift` (keys, `version`, `_dayKey`,
  id-drop rule); `presenceStaleAfter` (25 min) ↔ `PRESENCE_STALE_MINUTES`;
  `displayStatus` ↔ `OPEN_LIKE`/`selectOverdueCandidates`. **Only the widget payload
  pair has drifted — see B3.**
- **Reentrancy:** `PushRegistrationController.sync`, `PresenceSyncController.sync`,
  and `LiveActivityRegistrationController.sync` all set `_busy` before their first
  `await` on the acting path, with `_pendingResync` re-runs in `finally`.
- **Correctness spot-checks:** the ledger claim → `startLiveActivity` ordering
  correctly inherits the exactly-once claim; `businessMidnight` is DST-correct at
  both transition days; `findBusyEmployees` parallelizes its 30-ID chunks; every
  traced query except `liveActivityTokens` has a covering index.
- **Disposal:** every `StreamSubscription`/`Timer` found is cancelled. The
  never-closed `StreamController` in `firebase_appointments_repository.dart:73` is
  documented as intentional (app-lifetime singleton).
- **No substantial duplication** at 3+ instances anywhere (verified with a
  normalized token-window clone detector; all hits were widget-tree noise).

---

## Pre-ship checklist (unchanged, launch-time switches — not code defects)

iOS App Attest env flip to `production` · Firestore ledger TTL policy enablement in
the console · on-device verification of push / presence / widget / Live Activity /
Siri phrases. See `docs/plans/APP_STORE_SUBMISSION.md`.

---

## Found during implementation

Three bugs the new test suites exposed, all fixed:

- **`time_utils.toMillis` threw `RangeError` on a non-finite number.** Every
  other bad input degrades to `""`; `NaN`/`Infinity` instead threw out of
  `Intl`, which would take down a notification build in a module whose three
  consumers are all best-effort. Now finite-checked on both the number and
  `Timestamp.toMillis()` paths.
- **`listCardsDueForOnSite` filtered `phase` AFTER `.limit()`** — a batch of
  already-flipped cards could consume the whole cap and starve the cards
  actually due for a flip. `phase` is server-written and closed-set, so the
  filter moved into the query (new `(phase, startTime)` composite index).
- **`selectBusiness` threw a raw `TypeError`** when a listed Wave business had
  no `name`, surfacing as a misleading generic Wave error instead of
  `wave/business-not-found`. Now type-guarded.

Also fixed beyond the original report: a **fourth** Wave callable
(`waveImportCustomers`) had the same guard-order deviation as S5 — the review
listed only three.

## Declined, with reasons

- **P3 (APNs HTTP/2 session reuse)** — not implemented. An explicit test
  (`apns_client.test.js:163`, "closes the session after the request") pins the
  current teardown as deliberate; the win is latency-only across a handful of
  sends inside a 120 s budget; and caching the session adds stale/GOAWAY
  handling to the one best-effort path that talks to Apple with a TTL'd JWT.
  The cost/benefit doesn't justify making that path stateful.
- **`activityTokenExpiry` (dead code)** — kept, not deleted. It is now covered
  by the new registry tests, and deleting an exported symbol mid-flight would
  have broken them. More importantly its `TOKEN_TTL_MS` (3 d) **disagrees** with
  the client's real `liveActivityPushToStartTtl` (30 d); a `NOTE:` now records
  that wiring it in as-is would silently cut the push-to-start TTL by 10×.

**A correction to S3 worth recording:** the review proposed bounding
`expiresAt` at `request.time + 4 d`, reasoning from the server's 3-day
constant. The client actually writes **30 days** for push-to-start rows, so
that bound would have rejected every legitimate registration and broken the
feature. The shipped ceiling is 31 d.

## What still needs YOU

The code is done; these are the things I can't do from here.

1. **Deploy** — `firebase deploy --only functions,firestore:rules,firestore:indexes,storage`.
   Note `firestore:indexes` is required this time: two new composite indexes
   (`liveActivityTokens` collection-group, `liveActivityCards`) are what make
   the Live Activity feature work at all. **Build the indexes before or with the
   functions**, or the feature keeps silently no-opping. The S1 rules fix also
   only takes effect on deploy.
2. **Consider revoking Auth credentials on deactivation.** The S1 rules fix
   closes the read hole, but `deactivateEmployee` still leaves the Firebase Auth
   account enabled with live refresh tokens. Adding
   `getAuth().updateUser(uid, {disabled: true})` + `revokeRefreshTokens` to the
   `syncUsersByUid` purge branch is the defense-in-depth follow-up — I left it
   out because it changes account lifecycle behavior (reactivation would need
   the symmetric re-enable) and deserves your call.
3. **Pre-ship switches** (unchanged): App Attest env → `production`, Firestore
   TTL policies on the ledger collections, and on-device verification of push /
   presence / widget / Live Activity / Siri phrases.
