# Codebase Audit — 2026-08-14

> **STATUS: implemented same day**, on the owner's "do all" instruction —
> everything below EXCEPT the ⚠️ pre-deploy item, which is a destructive
> production action (it deletes three live Cloud Functions) and is the owner's
> to run. Three findings were deliberately NOT implemented after reading the
> code more closely; each is recorded with its reasoning in
> "What was not done" at the bottom, rather than quietly dropped.
>
> Verification after the pass: `flutter analyze` → **No issues found!** ·
> `flutter test` **2071 passing** (up from 2042) · `functions npm run lint`
> clean · `jest` **1077 passing / 45 suites** (up from 1028).
>
> Two things found only while implementing, both fixed and neither in the
> report above: `deregisterThisDevice` awaited its three teardowns bare, so a
> throw in the first silently skipped the other two — and the two it skipped
> are the ones whose residue is visible to other people (a stale presence pin
> on the admin map); and `functions/account.js` had `assertFreshReauth`'s
> entire body hand-inlined rather than calling it.

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `lib/l10n/*.arb`, `pubspec.yaml`,
`functions/package.json`, `docs/`, `ios/Runner/Info.plist`).
Baseline: working tree at `bf316828` on `redesgin`. Tree was dirty at start —
`CLAUDE.md` carries one uncommitted owner edit (a testing-rules doc
correction). Nothing in this audit was auto-applied, so that edit is still the
only change in `git status`.

The four commits since the last audit (`c56a53dc`, `5d4b280c`, `1250552d`,
`bf316828` — 7717 insertions across 84 files) are unreviewed, and **most of
what follows is in them**: the photo subcollection migration, the
`ClientNamePolicy` reversal, the Wave scheduler consolidation, and the
dashboard's new-clients rewrite.

## Summary

- Scanned: 379 `lib/` Dart files, 29 `functions/` modules + 7 scripts, both
  rules files, 721×2 ARB keys, 256 Flutter test files, 45 jest suites.
- **Auto-fixed (safe, in the diff): 0.** Nothing qualified. `flutter analyze`
  is clean of errors and warnings, `dart fix --dry-run` reports "Nothing to
  fix!", functions ESLint is clean, there are **zero** orphaned files, **zero**
  `TODO`/`FIXME`/`HACK`/`XXX` markers anywhere, and all four unused-dependency
  hits are verified false positives. Every finding below either changes
  behaviour or is a judgement call, so all of it is report-only by the
  audit's own split.
- **Reported for your decision: 30** (⚠️ 1 pre-deploy · 🔴 3 security ·
  🟠 9 bugs · 🔵 10 improvements) + 7 code-quality notes.
- Verification (baseline, unchanged since nothing was edited):
  `flutter analyze` → **no errors or warnings** ·
  `flutter test` → **2042 passing** ·
  `functions npx jest` → **1021 passing / 45 suites** ·
  `functions npm run lint` → clean.

### Top 3 to look at first

1. **B1** — editing any Wave-imported client renames the customer on real Wave
   invoices. The edit sheet seeds the Name field from `displayName`, which for
   a client with no `type` resolves to the *contact person*, and the save
   writes that back into `clients/{id}.name` — the field synced verbatim to
   Wave. `fromWaveCustomer` never sets `type`, so this applies to **every**
   imported business.
2. **B2** — the photo-subcollection read is never adopted. The `identical()`
   guard in `event_details_controller.dart:147` can never be true, so
   `fetchAppointmentPictures` runs and its result is discarded. Harmless today;
   it silently blanks every photo at the CONTRACT step the migration is
   heading for.
3. **B4** — Riverpod 3 makes `ref.read` **throw** on an unmounted widget, and
   `.claude/rules/error-handling.md` mandates the pattern that triggers it at
   ~8 sites. The worst is a fatal on the app's most-used field.

## Auto-applied cleanups

**None.** The static level is clean and no finding met the
"reversible + obvious + behaviour-preserving, one unambiguous target" bar.

Verified false positives, recorded so the next pass doesn't re-chase them:

| Flagged | Why it stays |
|---|---|
| `google_maps_flutter_ios_sdk9` | No Dart import by design — registered natively (`ios/Runner/GeneratedPluginRegistrant.m:93`). The SPM-capable replacement for the CocoaPods-only default. |
| `build_runner`, `freezed` | Codegen dev deps producing the 9 `.freezed.dart` files; `freezed_annotation` is the imported half (10 files). |
| `flutter_launcher_icons` | Dev tool with its config block at `pubspec.yaml:166`. |

L10n is clean: 721 keys each side, **exact EN/FR parity**, every key carries a
`@meta` block, `untranslated.json` is empty, and the 7 identical EN/FR values
are legitimately identical (placeholder-only patterns, and "Notifications").

## ⚠️ Pre-deploy checklist

- [ ] **The backend is undeployed since 2026-08-11, and the export SET changed
      by six while the COUNT stayed at 25.** Three functions were deleted
      (`waveSyncWorker`, `waveScheduledImport`, `sendOverdueJobPrompts`) and
      three added (`cascadeDeleteAppointmentImages`,
      `recountAppointmentPictures`, `waveRetryFailedJobs`). This is exactly the
      shape the deploy log records being bitten by before — *"the 3-day gap the
      unchanged 25-function count had hidden"* — so a count check passes while
      six functions move. `firebase deploy` **aborts non-interactively on
      deletions**, so the deletion step must run first.
      `docs/DEPLOYMENT.md:257-315` already carries the correct runbook
      (`firebase functions:delete` + three `gcloud scheduler jobs delete`); it
      has not been executed. Also pending: 75 lines of new `firestore.rules`
      (the `appointments/{id}/images` block and the `pictureCount` guards) and
      166 lines of new indexes — and `cascadeDeleteAppointmentImages` is
      load-bearing, since Firestore does not delete a subcollection with its
      parent.

There are **zero** `TODO(pre-ship)` markers, and no destructive testing
scaffolding survives anywhere in `lib/` or `functions/`.

## 🔴 Security findings

The security pass found **no critical and no high** findings. Guard order,
App Check enforcement, credential handling, magic-byte validation, secret
placement and the rules' field denylists all hold up, and each documented
guard's actual predicate was checked against its description (results in
"Verified clean" below).

### S1 — Permanent, rules-free Storage download URLs are persisted to unencrypted SharedPreferences · severity: low · confidence: high (mechanism), medium (real-world impact)
- **Where:** `lib/features/calendar/data/pending_upload_store.dart:64-67`
- **Risk:** `_imageToJson` spreads `image.toMap()`, which emits `url` — the
  `?alt=media&token=…` download URL. The whole queue is JSON-encoded into the
  SharedPreferences key `pending_photo_uploads` (7-day prune). That token URL
  is readable **with no auth and no rules evaluation**, and survives
  `deactivateEmployee` and `revokeRefreshTokens` — it is precisely what
  `AppointmentImageUrlResolver` was built to stop rendering. On iOS
  SharedPreferences is an unencrypted plist inside the app container, included
  in local and iCloud backups. That is deliberately weaker than
  `SecureStorageService`, which was moved to `first_unlock_this_device`
  specifically to keep the cached identity out of backups — so the queue
  stores something more sensitive in the weaker of the two stores.
- **Fix:** persist only `storagePath`/`fileName`/`uploadedAt`. **Wrinkle to
  handle in the same change:** the re-link uses `arrayUnion` with
  `_imageToFirestoreMap`, which matches by deep map equality, so the drain must
  reconstruct the identical map (re-resolving `url` at drain time) or the
  idempotent re-link silently stops deduping and photos land twice.

### S2 — `waveGetConnection` has no rate limit, and the documented reason it is exempt is no longer true · severity: low · confidence: high
- **Where:** `functions/wave/callables.js:212-268`, unbounded work at `:246-257`
- **Risk:** `functions/CLAUDE.md` justifies the omission with *"no secret, no
  rate limit — it only reads the `wave/connection` doc."* It now also runs two
  `count()` aggregates on `waveSyncQueue` per call. This is the
  comment-vs-predicate drift class this repo has been bitten by twice. It is
  `assertAdmin` + App Check gated, so the exposure is cost/availability, not
  confidentiality — but it is the only admin write-callable in the repo with no
  durable cap while every sibling has one.
- **Fix:** add `enforceDurableRateLimit` after `assertPayloadShape` with a
  generous cap (Settings calls this on mount), **or** correct the doc. Do not
  leave the two disagreeing.

### S3 — `isValidAppointmentData` leaves `repeat` unbounded and the two instants untyped when either is absent · severity: low · confidence: high
- **Where:** `firestore.rules:500-529` and `:474-481`
- **Risk:** Admin-only, so this is a durability boundary rather than a
  privilege one — and it fails silently. `isValidAppointmentSpan`
  short-circuits to `true` when *either* instant is missing, so
  `d.startTime is timestamp` is never asserted on a doc carrying only one. A
  doc whose `startTime` is a string or absent is excluded by every
  `orderBy('startTime')` — it vanishes from the travel sweep, the digest, the
  day-slice mirrors and the Siri snapshot with nothing erroring. Same failure
  shape already documented for `archived` on clients. `repeat` is the one
  string `toMap()` emits with no cap.
- **Fix:** add `(!('repeat' in d.keys()) || isBoundedString(d.repeat, 32))`,
  and assert each instant's type individually when its key is present rather
  than only as a pair inside the span check. Needs a rules deploy.

### Not a finding — recorded because it cost a reviewer a false positive
`NSLocationAlwaysAndWhenInUseUsageDescription` at `ios/Runner/Info.plist:63`
was flagged as a violation of `functions/CLAUDE.md:187` ("never re-add"). It is
**correct as-is**: `ios/CLAUDE.md:49-63` documents it as deliberate — removing
it triggers **ITMS-90683** on every upload because `geolocator_apple` compiles
`requestAlwaysAuthorization` into the binary, and it cannot change behaviour
because the plugin tests `NSLocationWhenInUseUsageDescription` first and only
falls through as an `else if`. `UIBackgroundModes` correctly carries only
`remote-notification`. **The finding is the doc contradiction, not the plist**
— see Q1.

### npm advisories — no action
`npm audit` in `functions/` reports 8 moderate, all fanning out from one root
(`uuid` v3/v5/v6 buffer bounds check) reached transitively via
`firebase-admin`. Not reachable from this codebase — nothing calls `uuid` with
an explicit `buf`, and the app's own `Uuid().v4()` is the Dart package. The fix
path is blocked by the documented "do not bump `firebase-admin` to 14 on
functions 7.x" constraint. Recorded so it isn't rediscovered.

## 🟠 Bug findings

### B1 — Editing a Wave-imported client renames the customer on real Wave invoices · severity: high · confidence: high
- **Where:** `lib/features/clients/widgets/sheets/edit_client_sheet.dart:85`
  (seed) and `:201-204` (save); root cause at
  `functions/wave/mappers.js:285-302`
- **Problem:** `fromWaveCustomer` sets `name`, `firstName`, `lastName` — and
  **never sets `type` or `businessName`** (confirmed: the create branch at
  `functions/wave/customers.js:664-668` stamps only `archived`/`createdAt`/
  `updatedAt`). So every imported client arrives `type: unset`, which makes
  `ClientNamePolicy.isBusiness` return **false for every Wave-imported
  business**. `displayFor` then takes the person branch and returns
  `firstName + lastName`, ignoring the stored `name` entirely.

  The edit sheet seeds its Name field from `c.displayName`, so for
  `name: "Vogas Plumbing"` / `firstName: "Marc"` / `lastName: "Tremblay"` the
  field reads **"Marc Tremblay"**. An admin opens Edit to fix a postal code and
  saves; `composeStored` writes `name = "Marc Tremblay (514) 555-1234"`;
  `waveUpsertCustomer` fires and — since the drain moved inline on 2026-08-13 —
  pushes to Wave **in seconds**. The customer is renamed on real invoices,
  unrecoverably from the doc. The next scheduled import then pulls the
  corrupted name back down (`merge: true` on the update branch), closing the
  loop.

  This is the exact hazard `CLAUDE.md` and
  `backfill-client-name-with-phone.js:27-32` call out — *"writing the display
  name back would rename 'Vogas Plumbing' to 'Marc Tremblay' on real Wave
  invoices"*. The backfill obeys it; the edit sheet does not. The seed's own
  comment shows the reasoning that went wrong: it correctly wanted to avoid
  handing a name-plus-number to `composeStored`, and reached for `displayName`
  to get it.

  Second consequence, independent of saving: **every in-app surface renders the
  contact person instead of the business** for these clients.
- **Fix:** seed from
  `ClientNamePolicy.stripPhone(c.name, phone: c.phone, mobile: c.mobile)`. That
  satisfies the documented reason for not using the raw field without ever
  substituting the contact person. **There is already an in-repo precedent
  doing exactly this**: `contact_export_launcher.dart:113-117`. Consider also
  making `fromWaveCustomer` infer a `type`, or widening `isBusiness` to treat a
  `waveCustomerId` with a distinct `name` as a business — but the seed fix is
  the one that stops the write.

### B2 — The photo-subcollection read can never be adopted; the `identical()` guard is always false · severity: high · confidence: high
- **Where:** `lib/features/calendar/application/event_details_controller.dart:147`
  (with the seed at `:106`)
- **Problem:** `_seededImages = List.of(appointment.pictures)` is a plain
  growable list, but `EventDetailsState.existingImages` is a freezed collection
  getter (`event_details_controller.freezed.dart:284-288`) that returns
  `EqualUnmodifiableListView(_existingImages)` — **a new object on every
  access** — unless the backing field already is one, which a `List.of` never
  is. So `identical(state.existingImages, _seededImages)` is always false and
  `_loadStoredPictures` always returns early.

  Today that costs one wasted Firestore subcollection read per detail-sheet
  open. At the CONTRACT step described in `CLAUDE.md` (array removed,
  `pictures: []`), `existingImages` seeds empty, adoption still never fires,
  and **the edit sheet shows zero photos for every job** — silently.
  `CLAUDE.md`'s claim that this controller "adopts the read" is not true of the
  code. There is no controller-level test; coverage stops at the repository
  (`firebase_appointments_repository_images_test.dart`).
- **Fix:** compare by value (`listEquals`) or track edits with an explicit
  `bool _imagesTouched` set by `addImages`/`removeExistingImage`.
  **Handle in the same change:** once adoption works, subcollection-derived
  images carry `url: ''` (dropped by `_imageToSubcollectionMap`), and
  `removeAppointmentPictures` (`firebase_appointments_repository.dart:353`)
  removes from the parent array via `FieldValue.arrayRemove`, which matches by
  **deep map equality**. An adopted photo will not match its array entry, so
  the subcollection doc is deleted while the array keeps it — and the shipped
  1.45.0 build still renders from the array.

### B3 — Image magic-byte validation has drifted across the Dart↔JS mirror · severity: high · confidence: high
- **Where:** `lib/core/images/image_storage_service.dart:23` (3 bytes) vs
  `functions/image_magic.js:20` (4 bytes)
- **Problem:** Dart accepts PNG on `89 50 4E`; JS requires `89 50 4E 47`. A
  file beginning `89 50 4E <not 47>` passes the client gate, uploads to
  Storage, and `maintenance_policy.js:112` then classifies it
  `"deleted-invalid"` and **deletes it server-side**. The user watches a photo
  upload succeed and then silently vanish, with no error on either side. Dart
  also accepts a 3-byte file (`bytes.length < 3` is the only length guard)
  where JS reads `b[3]` as `undefined`.

  Note both `CLAUDE.md` and `.claude/rules/security.md` document the **3-byte**
  form, so the docs match Dart and the JS is the divergent half — though JS is
  the more *correct* one (the real PNG signature is 8 bytes).
- **Fix:** reconcile to the 4-byte form on both sides and pin them against each
  other. `hasValidImageMagic` is already tested (`maintenance.test.js:11`); the
  Dart half has **no test** — its four `test/` hits are all
  `class _Mock… implements ImageStorageService`, so the real class is never
  constructed. Both throw paths run before touching `FirebaseStorage.instance`,
  so a temp-file test needs no Firebase init.

### B4 — Riverpod 3 makes `ref.read` throw on an unmounted widget, and the project's own rule mandates it · severity: high · confidence: high
- **Where:** ~8 sites; worst at
  `lib/shared/widgets/fields/address_autocomplete_field.dart:125` and
  `lib/features/settings/screens/settings_screen.dart:212`
- **Problem:** Verified in the resolved SDK — `flutter_riverpod 3.4.2`,
  `lib/src/core/consumer.dart:469-476`: `_assertNotDisposed()` is an
  **unconditional `throw StateError`**, not a debug assert, and it guards
  `read`, `watch`, `listen`, `invalidate`, `refresh`, `exists` and
  `listenManual`.

  This inverts `.claude/rules/error-handling.md:30-32` — *"Call `warn` BEFORE
  any `if (!mounted) return;` guard."* That rule is right about `AppLogger`
  being context-free, but wrong about `ref.read(loggerProvider)`, which is how
  every site reaches it.

  The worst site is ordinary user behaviour: type 3+ characters in any address
  field, dismiss the sheet while the Places call is in flight, and have the
  call fail. The comment at `:124` literally says *"Logged before the mounted
  guard so it reaches Crashlytics even if the field is gone by then."* The
  throw escapes `_fetch`, which runs from a `Debouncer` `Timer` callback with
  no handler, so it lands in the zone handler as a **FATAL**.
  `_toggleLiveActivity` (`settings_screen.dart:208-218`) is the second worst —
  it `await`s twice and has **no `mounted` check at all**, conspicuously the
  only async handler in that file without one.

  Other sites: `settings_screen.dart:148`, `image_viewer.dart:146`,
  `details_edit_body.dart:218`, `clients_list_view.dart:92`,
  `splash_screen.dart:54,61`, `onboarding_gate.dart:38,55`,
  `account_exit_listeners.dart:87,102`.
- **Fix:** hoist `final logger = ref.read(loggerProvider);` (and any other
  provider) to **before the first `await`**, then log from the `catch`. That
  satisfies the rule's intent — the log still survives unmount — and Riverpod
  3's constraint. `settings_screen.dart:212` additionally needs a plain
  `if (!mounted) return;`. **Update the rule text in
  `.claude/rules/error-handling.md` in the same change**, or the next author
  reintroduces it. This is mechanically greppable (`ref.read` inside a `catch`)
  and worth a lint.

### B5 — The dashboard's New clients rows render the raw stored name, phone number and all · severity: medium · confidence: high
- **Where:** `lib/features/dashboard/widgets/sections/new_clients_section.dart:268, 272`
- **Problem:** `CLAUDE.md` is explicit — *"The app never renders it. Every
  in-app surface reads `ClientRecord.displayName`."* Every other surface
  complies (`client_tile.dart:56`, `client_search_field.dart:112`,
  `client_detail_view.dart:194`, `appointment_form_fields.dart:217`). These two
  read `client.name`, which as of this commit range ends in the phone number,
  so the rows read `Marc Tremblay (514) 555-1234` — and `AppAvatar` derives its
  initials from the same string.
- **Fix:** `client.displayName` in both places. (Behaviour-changing, so not
  auto-applied — but it is a two-token edit.)

### B6 — The person-name sub-line duplicates the title on every person client · severity: low · confidence: high
- **Where:** `lib/features/clients/widgets/views/client_detail_view.dart:187`
- **Problem:** `showPersonName` tests `fullName != client.name`, but the title
  one line down renders `client.displayName` (`:194`). For a person client
  `displayName` **is** `firstName + lastName` == `fullName`, while
  `client.name` is the stored Wave string ending in the phone number — so the
  two are never equal and the sub-line always renders, repeating the title
  verbatim in tertiary text. The comment above it says it should show "only
  when it says something the name doesn't already".
- **Fix:** `fullName != client.displayName`.

### B7 — The day route's "today" check uses `DateTime.now()` · severity: low · confidence: high
- **Where:** `lib/features/calendar/screens/day_route_screen.dart:271`
- **Problem:** `final isToday = _day == DateTime.now().dateOnly;` — this screen
  has **zero** `currentDayProvider` references, unlike
  `main_calendar_screen.dart`, which watches it specifically so its today
  indicator rebuilds at midnight. `isToday` gates the jump-to-today control
  (`:313-318`), so in an app left open across midnight it silently goes stale.
  A documented anti-pattern (`CLAUDE.md`: *"never `DateTime.now()`, or the
  circle sticks on yesterday"*).
- **Fix:** `ref.watch(currentDayProvider)` for the comparison.

### B8 — A Wave failure on an unmounted section never reaches Crashlytics · severity: low · confidence: high
- **Where:** `lib/features/wave/widgets/wave_settings_section.dart:76-77`
- **Problem:** the inverse of B4 — `if (!mounted) return;` **precedes** the
  `ref.read(loggerProvider).warn('WAVE-$tag failed', ...)`, while the method's
  own docstring at `:65` promises *"Logs under `WAVE-<tag>` before showing the
  notice, so failures still reach Crashlytics."* A connect/sync/retry failure
  on an unmounted section is logged never. No crash risk — accidentally the
  *safe* ordering under Riverpod 3, and the only ordering violation of that
  rule in all of `lib/`.
- **Fix:** the same hoist as B4 fixes both properties at once.

### B9 — Three of six address fields overwrite hand-typed values, contradicting the docstring · severity: low · confidence: high
- **Where:** `lib/features/maps/address_field_filler.dart:6, 26, 32, 33`
- **Problem:** the docstring promises *"leaving manually-entered values
  intact."* `apt` fills only when empty, `street` only when different, and
  `country` only when non-Canada or empty — but **`postalCode`, `province` and
  `city` overwrite unconditionally**. A user's hand-typed city or province is
  clobbered when they pick an autocomplete suggestion. Either the doc or the
  code is wrong, and there is no test on this file (`AddressParser` beneath it
  has 59 hits — the parser is fine, the policy on top of it is untested).
- **Fix:** decide which contract is intended, then make the other match.

## 🔵 Areas to improve

### I1 — `todayRangeProvider` forks a permanent duplicate Firestore listener over a strict subset · impact: high · confidence: high
- **Where:** `lib/features/employees/application/employee_schedule_providers.dart:17`
- **Opportunity:** it returns `AppointmentDateRange.forDay(today)`, whose query
  result is a **strict subset** of `forMirrors(today)` (same `fetchStart`,
  narrower `end`). For an **admin**, `schedule_snapshot_provider.dart:36`
  already holds `appointmentsInRangeProvider(forMirrors)` open for the whole
  session via `AppSyncListeners` — the same provider family. So all three
  `todayRangeProvider` consumers (`employeeJobsTodayProvider` on every Team
  roster row, `employeeTodayJobsProvider` on the detail TODAY panel, and the
  drawer badge at `app_nav_drawer.dart:304`) attach a **second permanent
  listener** to documents the first is already streaming. The hub's
  `IndexedStack` keeps the Team tab mounted, so once visited it is permanent
  for the session.
  **This exact rule is already written down twice** — verbatim at
  `my_details_providers.dart:64-75` (*"Any other range here would fork a second
  permanent Firestore listener over overlapping documents"*) and again in
  `forMirrors`' own docstring.
- **Suggested improvement:** return `AppointmentDateRange.forMirrors(...)`. All
  three consumers already re-scope with `runsOn`, so the wider list feeds them
  unchanged. Keep `forDay` for the calendar's selected-day leg. One line.

### I2 — `runDailyDigest` is the last uncapped sweep query · impact: medium · confidence: high
- **Where:** `functions/notification_utils.js:635-640`
- **Opportunity:** no `.limit()`, no `orderBy`, while both siblings were capped
  on 2026-08-13 (`TRAVEL_SWEEP_MAX` 500, `OVERDUE_SWEEP_MAX` 500) each with a
  warn-at-cap. It reads every open appointment in a 15-day window,
  business-wide. Bounded in practice, unbounded in principle — a bulk import or
  a wide repeat series in that window is a full-collection fan-out that then
  issues one `fetchEmployeeWidgetWindow` + `sendToEmployee` per grouped
  employee against a 60 s timeout. `functions/CLAUDE.md` calls the travel sweep
  *"the only sweep in the repo with no ceiling"*, which is no longer accurate.
- **Suggested improvement:** `.orderBy("startTime").limit(DIGEST_SWEEP_MAX)` +
  warn at cap, same shape as the two siblings. Served by the existing
  `(status ASC, startTime ASC)` index — no new index.

### I3 — Client search recomputes `displayName` twice per comparison · impact: medium · confidence: high
- **Where:** `lib/features/clients/data/firebase_clients_repository.dart:423-429`
- **Opportunity:** `ClientRecord.displayName` (`client_record.dart:155`) is an
  **uncached getter** over `displayFor`, which runs `stripPhone` twice — each a
  trim, two `endsWith` checks, a regex `firstMatch` and a `replaceAll`. The
  comparator calls it on both sides of every comparison, over the full match
  set *before* `.take(resultDisplayLimit)`. A one-letter query matching ~600
  clients is ~6,000 comparisons ⇒ ~12,000 `displayFor` calls ⇒ ~48,000 regex
  passes per debounced keystroke. It runs in a `compute` isolate so it is not
  UI jank — it is directly the search-result latency.
  **The fix is already written twice in the same file**:
  `fetchClientsByType:244-247` and `fetchArchivedClients:221-224` precompute the
  key with the comment *"computed once per record rather than twice per
  comparison."*
- **Suggested improvement:** carry `displayName.toLowerCase()` into the scored
  tuple beside the score.

### I4 — `AppointmentImageUrlResolver` head-of-line-blocks the photo strip · impact: medium · confidence: high
- **Where:** `lib/core/images/appointment_image_url_resolver.dart:39, 64`;
  called from `photo_picker_section.dart:70`
- **Opportunity:** `getDownloadURL()` is a network round-trip fanned out per
  photo on every mount, with no memoization across opens. An 8-photo job is 8
  RPCs per sheet open, repeated verbatim on re-open — and `_existingUrls`
  deliberately serves `const []` until the **whole** list resolves, so the
  slowest RPC gates all of them. That is the observable "photo strip fills in
  late".
- **Suggested improvement:** resolve **lazily per visible tile** rather than
  the whole list up front. That fixes the blocking with no security tradeoff.
  A cache would also work but weakens the render-time rules re-evaluation the
  design deliberately bought — that one needs your sign-off, not just a patch.

### I5 — Test-coverage gaps, ranked by blast radius · impact: high · confidence: high
All verified by **symbol** grep across both test trees, not by filename.

**Highest value:**
- `hasWorkLeft` (`functions/time_utils.js:182`) — **0 tests, 7 call sites.**
  Four lines, pure, and its own docblock says it is "the ONE owner" created to
  kill a drift bug. The documented past failure is exactly what a test pins:
  gating on `startTime` rather than `endTime` meant cancelling a job mid-run
  pushed **nothing** to a crew already on site. Cheapest high-value test on
  this list.
- `deregisterThisDevice` (`lib/core/app/device_deregistration.dart:30`) —
  **0 tests, 3 call sites, order load-bearing.** Regression leaves a stale
  `fcmToken` pushing to a signed-out device and a stale `presence/location`
  rendering the person on the admin live map: a **privacy leak**. Its
  implementation `await`s sequentially with no `try`/`catch`, so a throw in
  step 1 silently skips 2 and 3 — contradicting its own "every step is
  best-effort" contract.
- **Three backfill scripts have no `module.exports` at all**, so every helper
  is trapped in a top-level run block while the script mutates prod
  irreversibly: `backfill-appointment-images.js` (193 lines — `imageDoc:65` and
  `backfillOne:95` carry the "drop `url` only when `storagePath` is present"
  rule its own header warns *"clearing here blanks every photo on every
  phone"*), `backfill-clients-archived.js` (which `CLAUDE.md` says **must** run
  against prod before the filtered query deploys), and `backfill.js`. The two
  scripts that *do* export both have test files, proving the pattern works.
- `assertFreshReauth` (`functions/security.js:254`) — 0 tests. The pure
  predicate `isReauthStale` is tested; the throwing wrapper is not, so the
  `auth_time` extraction and the `stale-auth` error string the Flutter client
  branches on are unpinned.
- `deliverRecipientOnce` (`functions/notification_utils.js:402`) — 0 tests, and
  it **writes**. Exported *for testing* and never imported by a test. It is the
  at-most-once primitive for the entire reminder system.
- `EventDetailsSavePipeline.applyPhotoChanges` / `applySeriesChange` /
  `deleteOrphanedImages` — 0 direct hits. The class doc says its reason for
  existing is *"deleting orphaned bytes only AFTER the doc stops pointing at
  them"*, and that ordering is untested on the **save** path. (The
  delete-appointment path *is* covered.)

**Medium:** `clampedLastWorkDayMs` (`day_slice_utils.js:177` — the one hole in
an otherwise fully-covered hand-mirrored module), `optionalString`
(`security.js:80` — guards 8+ callable fields; every sibling validator is
tested), `businessMinutesOfDay` (`time_utils.js:132` — decides overnight
detection, which drives the whole slice model), `firebaseMessagingBackgroundHandler`
/ `writeWidgetPayloadJson` (the `widgetPayload` data key is a cross-language
contract with **no test on either side of the wire**), `RoleUpgradeListener`,
`digitsOf` (`client_name_utils.js:47` — the freshest-risk gap given B1),
`widgetPayloadProvider` (a collapsed error **wipes the home-screen widget**),
`fillAddressControllersFromText` (see B9), `liftPhoneFromNameField`.

**Low, batchable:** `MAX_ID_LENGTH` equality across the doc-id mirror (both
suites assert `<= 304`, which catches drift **upward** only — either side
shrinking to 250 passes both while deriving different ids),
`torontoDayStartMs`/`WIDGET_LOOKAHEAD_DAYS`, `buildSelfEmailChangedMessage`,
`EventDetailsSavePipeline.resolveAssignees`, `SettingsSaveDebouncer`.

**Verified as covered — do not chase:** `AppointmentFormConcerns`,
`kDefaultStartingPassword` (pinned 17×), `TourSeenStore`, `RouteUrlBuilder`,
`DrawerCatalog`, `PlacesRepository`, all three repositories' write/delete
methods. Deliberately untested by documented decision:
`calendarDaysBetween`/`addCalendarDays` (a UTC runner would be a false green),
`WidgetSyncService.sync`/`.clear` (device-only).

### I6 — Neither suite measures coverage, and CI does not run on this branch · impact: medium · confidence: high
- **Where:** `functions/package.json` (no jest coverage config),
  `.github/workflows/ci.yml`
- **Opportunity:** CI triggers only on `push: branches: [main]` and on PRs, so
  the **54 commits currently on `redesgin` have no CI run behind them**. It
  does fire at PR time, so this is feedback latency rather than an absent gate
  — but every finding in I5 would have surfaced mechanically from a
  `--coverage` run.
- **Suggested improvement:** add `--coverage` to both suites; consider adding
  `redesgin` to the push triggers while it is the active branch.

### I7 — God files, with the seam the test suite has already drawn · impact: medium · confidence: high
- `firebase_appointments_repository.dart` (**804**) → extract the history/search
  family (`searchHistory`, `_historyScanWindow`, `fetchHistoryPage`,
  `fetchClientHistory`, the LRU block, the three private cache classes; ~200
  lines) and the images subcollection (`:280-410`; ~130 lines). **Six separate
  test files already partition this file along exactly these lines.**
- `functions/employee_accounts.js` (**781**) → extract the email-change family
  (`:334-610`, ~275 lines). `__tests__/employee_accounts_self_email.test.js`
  already exists as a separate file for precisely this family.
- `functions/wave/worker.js` (**1081**) → the pure retry/error classification
  (`:147-253`, zero deps, becomes trivially testable) and the queue admin ops
  (`:921-1081`).
- `functions/wave/customers.js` (**832**) → split the two sync directions; move
  import (`:602-798`, ~230 lines) out from the export direction.
- `functions/travel_utils.js` (**859**) → extract the Google Routes layer
  (~220 lines; clean because it already takes an injected `fetchImpl`).
- `main_calendar_screen.dart` (**775**) → the three layout builders
  (`:484-655`, 172 lines) and the two independent widgets.
- `day_route_screen.dart` (**654**) → `_StopTile`/`_StopRail`/`_NavigatePill`
  (`:490-654`, 165 lines, purely presentational). Lowest-risk split here.

**Checked and NOT worth splitting** (recorded so nobody does):
`photo_picker_section.dart` (578) and `appointment_card.dart` (560) are long
only because each holds 6-8 small cohesive private widgets;
`themes.dart`'s `_buildLightTheme` and `app_routes.dart`'s `onGenerateRoute`
are declarative single-source-of-truth blocks.

### I8 — Duplication at 3+ instances, or already drifted · impact: medium · confidence: high
- **Search debounce: 4 sites, two values, already drifted** — 300 ms at
  `add_appointment_sheet.dart:53` and `details_edit_body.dart:49`; 250 ms at
  `clients_list_view.dart:67` and `appointment_history_view.dart:89`. All four
  are Firestore-backed searches against the same cost dial, so this is not a
  per-surface choice. Add `searchDebounce` to `client_search_policy.dart`,
  which already owns `serverReadLimit`/`resultDisplayLimit`.
- **Three spellings of "parse a Firestore instant", and they disagree** — owner
  is `core/utils/firestore_parsing.dart:6`, whose docstring says it exists *"so
  domain models don't need to import cloud_firestore directly."*
  `appointment_image.dart:34` detects the type via
  `value.runtimeType.toString() == 'Timestamp'` — a **string comparison**,
  specifically to dodge the import the owner exists to remove; it breaks under
  any `Timestamp` subtype. `firebase_appointments_repository.dart:707-708`
  handles only `Timestamp`, and on null skips the `dailyWindowsOverlap`
  narrowing, i.e. falls through to reporting a **phantom booking clash**.
  Point both at `firestoreDateTime` (already used at 7 sites).
- **`presenceStaleAfter` ↔ `PRESENCE_STALE_MINUTES` is the one hand-mirrored
  pair with no test** — `live_map_aggregator.dart:10` and
  `travel_utils.js:55`, both 25, both carrying a pointer comment, **zero** test
  hits on either side while every other documented mirror is pinned. Drift
  fails in the worst direction: the admin map labels a tech "fresh" while
  `decideOrigin` has already discarded their fix. One assertion naming both.
- **`StatusPill` has one owner and five hand-rolled twins** —
  `employee_profile_card.dart:127`, `settings_profile_card.dart:173`,
  `settings_tile.dart:103`, `signed_in_chip.dart:24`, `wave_sync_badge.dart:38`.
  Vertical padding disagrees three ways, font weight two. Share the **container
  shape** only — the 1.3× text-scale cap is documented as `StatusChip`-specific
  and should not be imposed everywhere.
- **`DateTime(d.year, d.month, d.day)` hand-spelled 3×** —
  `calendar_month_grid.dart:292`, `calendar_week_strip.dart:128`,
  `dashboard_period.dart:43`, despite `date_utils_helper.dart:77 dateOnly`
  whose docstring says it *"centraliz[es] the day-floor."*
- **Callable timeout as a bare literal** — `20` 3× in `wave_service.dart`, `10`
  3× in `google_places_repository.dart`, while
  `firebase_employees_repository.dart:17` already hoists
  `const _callableTimeout`. Hoist a file-level const; **do not** build a shared
  `callWithTimeout` wrapper — each site's log tag and error mapper genuinely
  differ.

**Downgraded after verification** (reporting so nobody "fixes" it): the
`OPEN_LIKE` allowlist in `notification_policy.js:75` vs Dart's `isClosed`
denylist is **not** drift — `OPEN_STATUSES` feeds a `where("status","in",…)`
and Firestore cannot express "not terminal" as a query. Worth one docstring
line on the Dart side. Likewise the 14× inline callable auth guard:
`functions/security.js:268` carries a comment *forbidding* the helper because
it would break the guard-order mocks.

### I9 — `getSeries` is unbounded and read twice per series save · impact: low-medium · confidence: high
- **Where:** `lib/features/calendar/data/firebase_appointments_repository.dart:201-208`
- **Opportunity:** no `.limit()` — and the comment at `:143` claims
  `countFutureAssignments` "was the last unbounded query in the repository",
  which this contradicts. Bounded by `RepeatInterval.maxOccurrences` (120) only
  for app-written series; a console write bypasses that. Separately, one save
  reads it twice: `details_edit_body.dart:213` for the scope dialog's
  consequence line, then again inside `appointment_series_editor`.
- **Suggested improvement:** `.limit(maxOccurrences + 1)` with a warn at cap;
  thread the already-fetched list into the save path.

### I10 — Appointment photo uploads are sequential · impact: low-medium · confidence: high
- **Where:** `lib/features/calendar/data/appointment_image_upload_service.dart:125-148`
- **Opportunity:** `uploaded.add(await _storage.uploadImage(...))` inside a
  `for` loop. A 5-photo batch takes ~5× the wall clock of a bounded-parallel
  upload. Nobody is blocked (it is the background drain), but the queue entry
  stays live longer and is correspondingly more likely to be cut short by
  backgrounding.
- **Suggested improvement:** bounded concurrency (3-4), preserving the per-file
  `survivors`/`permanentFailures` partitioning exactly as-is.

## 🟡 Code-quality suggestions

- **Q1 — `functions/CLAUDE.md:187` and `ios/CLAUDE.md:49` directly contradict
  each other** on `NSLocationAlwaysAndWhenInUseUsageDescription`: one says
  "never re-add", the other says "declared on purpose — do NOT clean it up",
  with the ITMS-90683 rationale. The plist follows `ios/CLAUDE.md` and is
  correct. **This contradiction has already cost something measurable — it
  produced the one false finding in this audit's security pass**, and in a repo
  where CLAUDE.md *is* the spec it will eventually cause someone to "fix" the
  plist and reintroduce the warning emails. Narrow the `functions/CLAUDE.md`
  sentence to the `UIBackgroundModes` half and point at `ios/CLAUDE.md` for the
  purpose string.
- **Q2 — `CLAUDE.md:1110-1118` still describes the deleted 5-minute
  `waveSyncWorker` as live** ("the outbox worker flips it to `synced` up to
  five minutes later", "the 5-minute worker had already sent it"). The worker
  was deleted 2026-08-13 and the push is now inline and reaches Wave in
  seconds. `functions/CLAUDE.md` and `docs/CLOUD_FUNCTIONS.md` were both
  updated; only the root file lags.
- **Q3 — `functions/CLAUDE.md` says `waveSetImportSchedule` has "no rate
  limit"**; `wave/callables.js:350` does call `enforceDurableRateLimit`. Code
  is more protective than the doc claims.
- **Q4 — `waveRetryFailedJobs` is missing from the module map** in
  `functions/CLAUDE.md`, which still describes the Wave callable set without
  it.
- **Q5 — `functions/CLAUDE.md` calls the travel sweep "the only sweep in the
  repo with no ceiling"** — no longer true; see I2.
- **Q6 — one orphaned l10n key: `dashboard_newClientsTotal`
  (`lib/l10n/app_en.arb:2225`).** Zero references in `lib/`; orphaned by
  `bf316828`, which rewrote the new-clients caption. Flagged for a deliberate
  l10n pass rather than deleted, per the audit rules. This is the **only**
  orphaned key — EN/FR parity is otherwise exact.
- **Q7 — two stale docs.**
  `docs/audits/SECURITY_ASSESSMENT_2026-08-04.md` carries no superseded banner
  (unlike everything in `docs/archive/`) while F5, F1, CRYPTO-1, F7 and
  PLATFORM-1/2 all reference things deleted on 2026-08-05/08 (`android/`,
  `invites.js`, `signup_code_utils.js`, the two `allow delete` grants).
  `docs/plans/2026-07-29-redesign-program.md:26-40` still describes the
  withdrawn P4b invite-code design without pointing at P4c.
  Also worth a guard note: `functions/scripts/backfill-client-phone-from-name.js`
  ran against prod on 2026-08-08 and was **reversed** by
  `backfill-client-name-with-phone.js` on 2026-08-14. Re-running it would
  rename real Wave customers again, and nothing in the file says so.

## Notes / uncertainties

- **Nothing was auto-changed.** `CLAUDE.md` was already modified before this
  audit began (an owner edit to the testing-rules note) and remains the only
  entry in `git status`. `docs/audits/CODEBASE_AUDIT.md` (the 2026-08-11 second
  pass) was moved to `docs/archive/CODEBASE_AUDIT_2026-08-11-second-pass.md`
  to make room for this one, matching the convention the previous pass used.
- Generated files (`lib/l10n/.gen/**`, `*.freezed.dart`) were excluded
  throughout, per `analysis_options.yaml`.
- `docs/legal/*.html` byte-identity against the external `es-pro-legal` GitHub
  Pages repo was **not** re-verified — it needs the other repo, which is out of
  scope here. `CLAUDE.md` requires the four files stay byte-identical.
- B1's blast radius depends on how many client docs have `name` ≠
  `firstName + lastName` with no `type` set. The mechanism is verified; the
  count is not. Worth a read-only query before deciding urgency —
  `docs/audits/audit-client-phone-backfill-damage.js` is a close template.
- The B4 site list is ranked by likelihood, and two entries
  (`clients_list_view.dart:92`, `splash_screen.dart:54`) are medium confidence
  on *impact* — a `PagingController` may swallow the substituted `StateError`
  as it swallows the original. The throw itself is certain at all of them.
- No emulator was available, so `firestore.rules` findings (S3) are read from
  the rules text plus the existing rules-text-reading tests, not from live
  evaluation.

## What was not done, and why

Three findings were reconsidered against the code during implementation and
deliberately left alone. Each is a case where the fix I proposed from the
outside turned out to be worse than the finding.

- **I4 (photo-strip head-of-line blocking) — NOT implemented.** I proposed
  resolving lazily per visible tile. Reading `PhotoPickerSection` afterwards,
  the positional contract there is load-bearing and documented: `_existingUrls`
  serves `const []` until the WHOLE list resolves precisely because every
  consumer indexes it positionally beside `newImages`, and the partial-list bug
  class is already on record — removing photo 0 rendered the *deleted* photo,
  an untapped placeholder opened a new one, and the viewer's `initialIndex` ran
  past the end and threw a `RangeError` out of Save/Share. Per-tile resolution
  reintroduces exactly that shape. The alternative — a resolved-URL cache —
  weakens the render-time `storage.rules` re-evaluation the resolver exists to
  provide, which is an owner decision, not a patch. **This is latency on a
  background-resolving strip, not cost or correctness.** Left as-is.
- **I10 (sequential photo uploads) — NOT implemented.** Bounded concurrency is
  safe from a path-collision standpoint (staged names carry a per-file index,
  so same-millisecond uploads still differ), but it would land on the exact
  method S1 just changed, inside the pipeline whose invariants are "never
  orphan bytes" and "never upload twice", to speed up a background drain nobody
  is blocked on. The per-file `survivors` / `permanentFailures` /
  `tooLargeNames` partitioning is what makes that pipeline correct, and
  re-deriving it under concurrency in the same pass as another change to it is
  a poor trade. Left as-is.
- **I7 (god-file splits) — NOT implemented.** Seven pure-refactor moves across
  files this pass already edited for correctness (`firebase_appointments_
  repository.dart`, `settings_screen.dart`, `day_route_screen.dart`,
  `details_edit_body.dart` all carry behavioural fixes now). Mixing a large
  mechanical reshuffle into that diff makes every correctness change harder to
  review, which is the opposite of what a split is for. The seams identified —
  particularly the two the test suite has already drawn (the history/search
  family out of the appointments repository, the email-change family out of
  `employee_accounts.js`) — are still right, and are best done as their own
  reviewed change on a clean tree.

Everything else in this report was implemented.

## ⚠️ Still outstanding: the deploy

The pre-deploy item at the top is **not done and was not attempted** — it
deletes three live Cloud Functions from production, which is the owner's call
to make, not something to fold into an audit pass. The backend changes in this
diff (the `wave-connection` rate limit, `DIGEST_SWEEP_MAX`, the rules'
`hasValidAppointmentInstants` and `repeat` cap) are **in the tree but not
live**, on top of the three days of backend work that was already undeployed
when this audit started.

The runbook is `docs/DEPLOYMENT.md:257-315` — deletions first, then
`firebase deploy --only functions,firestore:rules,firestore:indexes,storage`,
never with `--force`.
