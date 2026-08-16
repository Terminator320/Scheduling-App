# Codebase Audit — 2026-08-15

> ## ✅ IMPLEMENTED 2026-08-15 — every finding below is CLOSED
>
> All 41 reported findings, all 8 code-quality suggestions and all 4 stale-doc
> items were implemented in one pass. **Read the findings below as a record of
> what was wrong, not as a work list.**
>
> **Verification at completion:** `flutter analyze` → *No issues found!* ·
> `flutter test` → **2328** passing (was 2192) · `cd functions && npx jest` →
> **1160** passing across 47 suites (was 1135) · `npm run lint` → clean,
> now including `functions/scripts/`, which `.eslintignore` had been excluding.
>
> **Owner decisions taken during implementation** (the audit deliberately left
> these open):
> - **🔴S1 → option (b).** `AppointmentImageUrlResolver` is now
>   `AppointmentImageLoader`: photos render from `Uint8List` bytes fetched with
>   `ref.getData()`, so `storage.rules` is evaluated on **every fetch** and no
>   shareable URL is ever produced. I3's session cache was kept but holds bytes
>   instead of URLs (24 MB budget, oldest-first eviction). `cached_network_image`
>   and `flutter_cache_manager` were dropped from `pubspec.yaml`. **Accepted
>   cost: no on-disk photo cache, so photos re-download per session and are
>   unavailable offline.** This cannot revoke a URL captured under an older
>   build — that still needs server-side token rotation.
> - **🔵I18 → marker-doc debounce.** Claim released *before* the `count()`
>   aggregate, so nothing suppressed can be missed and the replay self-heal
>   survives.
> - **🔵I25 → deleted.** `AppLanguageScope` removed; locale propagation verified
>   intact via the `ValueListenableBuilder` and three direct singleton readers.
> - **`CalendarWeekStrip.heightFor` → deleted (case b).** Investigated: P2 made
>   portrait two scroll areas, so there is no vacated extent for a spacer to
>   hold. No layout bug existed. Text-scale coverage kept by measuring the
>   painted height instead.
> - **`AuthErrorContext.reauthentication` → wired up**, not deleted. Its
>   `register` sibling is *not* statically false but its only failure is
>   runtime-unreachable since P4c — left alone, flagged below.
> - **EdgeInsets/`AppSpacing` → left alone**, per the audit's own reasoning.
>
> **Found during implementation, not in the audit** — un-ignoring
> `functions/scripts/` from ESLint immediately caught a live defect in
> `backfill-appointment-images.js`, the script with outstanding production work:
> it parsed `--dry-run` into a variable it never used, called `backfillOne`
> unconditionally (which commits its batch), then referenced an **undefined**
> `DRY_RUN`. A "dry run" would have written every document and then died with a
> `ReferenceError`. The dry-run machinery inside `backfillOne` was correct all
> along; `main()` simply never passed the flag. Fixed.
>
> Also fixed: `.claude/workflows/wave-ultra-review.mjs` could never load —
> raw backticks terminated its `REPO_CONTEXT` template literal at line 35.
>
> **DEPLOYED 2026-08-15 at `6d41dd3c`** — functions, rules and indexes, 25 → 25
> with no export change, so neither known abort fired. The rules changes (S2,
> S3, S4 and the `appointmentRecountClaims` deny block) and every functions
> change are live; `firestore.rules` was validated through the Firebase MCP
> rather than the emulator, which needs a JRE this box does not have. Two later
> Wave deploys the same day (`e84a66fd`, then `6b3fcf7c`) sit on top of it. The
> full record, including the ONE accepted risk — the new `clients.addressLine2`
> cap over docs the already-deployed import wrote uncapped — is in
> `docs/DEPLOYMENT.md`.


Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`, `docs/`). Baseline: `a30eb3ef`, working tree
clean at start.

## Summary

- **Scanned:** 383 `lib/` files (51k LOC) · 94 `functions/` JS files (13k LOC) ·
  262 Dart test files · 48 jest suites · 721 ARB keys · both rules files.
- **Auto-fixed (safe, in the diff): 2** — two provably-dead symbols. That number
  is small because the tree is genuinely clean, not because the sweep was
  shallow: `flutter analyze` reports *No issues found*, `dart fix` has nothing to
  apply, Functions ESLint is clean, there are **0** orphaned Dart files, **0**
  dead Riverpod providers of 103, **0** orphaned ARB keys of 721, **0** unused
  dependencies, **0** BOMs, and **0** commented-out code blocks.
- **Reported for your decision: 41** (⚠️ 0 pre-ship · 🔴 4 security · 🟠 11 bugs ·
  🔵 26 improvements).
- **Verification:** `flutter analyze` → No issues found (matches baseline) ·
  `flutter test` → 2106/2106 pass · `cd functions && npm test` → 1122/1122 pass
  across 48 suites · `npm run lint` → clean.

**Top 3 to look at first:** 🟠B1 (photos silently disappear from a job — live on
production data today), 🟠B2 (a backfill script can delete a live employee's
`usersByUid` bridge and lock them out), 🔴S1 (a former employee's captured photo
URLs keep working forever, which is the control `storage.rules` is documented as
providing).

## Auto-applied cleanups (review the diff)

| File:line | Change | Why |
|---|---|---|
| `lib/core/theme/design_tokens.dart:201` | Removed `AppMotion.drawer` | Motion token with zero call sites; every other `AppMotion` member has 1–6. Verified no references in `lib/` or `test/`. |
| `lib/core/utils/app_language.dart:25-29` | Removed `AppLanguageScope.of` | Dead static method — its only reference was itself. See 🔵I25 for the consequence. |

> Full detail is in `git diff`. Nothing below this line was auto-changed.

## ⚠️ Pre-ship checklist

**Empty — verified.** There are zero `TODO(pre-ship)` markers in the tree (the
last one, `kShowTestingDeleteClient`, went with the client archive/delete work).
The only code marker anywhere is one correctly-formatted
`TODO(gvogas)` at `lib/features/calendar/application/event_details_controller.dart:138`.
All 13 callables set `enforceAppCheck: true`; App Check activation is intact in
`main()`. Nothing is gated on store launch.

Operational items outstanding from the 2026-08-14 deploy are tracked in
Notes, below — they are ops, not code.

## 🔴 Security findings (review required)

### S1 — Storage download tokens are permanent, so the `status == 'active'` photo gate does not survive offboarding · severity: medium · confidence: high (mechanism) / medium (real-world exploitation)

- **Where:** `lib/core/images/appointment_image_url_resolver.dart:42`, with
  `storage.rules:45`
- **Risk:** `resolve()` calls `getDownloadURL()`, which returns a URL embedding
  the object's `firebaseStorageDownloadTokens` value. That token is **stable per
  object and never expires**, and fetching the URL serves the bytes over plain
  HTTPS with **no auth and no rules evaluation**. So the resolver does put a
  rules check in front of *obtaining* the URL — but hands back the same string
  every time. A technician renders a job's photos while active; those URLs are
  then in the image cache on disk and trivially copyable. `deactivateEmployee`
  disables the Auth account and revokes tokens, and the `status == 'active'`
  gate then denies *new* reads — but every previously-resolved URL keeps working
  indefinitely, for anyone holding it.
  Root `CLAUDE.md` asserts the resolver makes it so "every read re-evaluates the
  rules". That holds for the mint, not for the byte fetch. The 2026-08-08 change
  removed the *persisted* `url` as a render source, which is a real improvement
  — it just doesn't reach as far as the note claims.
- **Fix:** three options, in descending strength — (a) mint short-lived signed
  URLs server-side (`file.getSignedUrl({action:'read', expires})`) from an
  App-Check'd callable and render those; (b) fetch bytes with `ref.getData()`
  and render from memory; (c) rotate `firebaseStorageDownloadTokens` on that
  employee's appointment images during deactivation (`functions/bridge.js`'s
  `purgeDeliveryState` is the natural hook, though it has to walk their
  `employeeIds` jobs). **At minimum**, correct the claim in the class doc and in
  root `CLAUDE.md` so the control isn't relied on as stronger than it is — that
  part costs nothing and is the thing most likely to mislead a future change.
- **Interacts with 🔵I3:** the perf reviewer independently reached the same
  conclusion about token stability and proposed caching resolved URLs. Both are
  correct. A session-scoped cache is compatible with any fix above *provided*
  the `''` permission-denied refusal stays uncached; if you adopt (a), the cache
  must respect the signed-URL expiry instead.

### S2 — Rules let an assignee flip a `cancelled` appointment to `done` · severity: low · confidence: high

- **Where:** `firestore.rules:601-605` (verified directly)
- **Risk:** the employee branch of `allow update` tests
  `isAssignedEmployee(resource.data)`, `affectedKeys().hasOnly(['status','updatedAt'])`
  and `request.resource.data.status == 'done'` — it never inspects the **stored**
  `resource.data.status`. Any assignee can therefore write `done` over
  `cancelled`, resurrecting a cancelled visit as completed in history, in the
  dashboard tallies and in `purgeExpiredHistory` accounting, and re-firing
  `notifyAppointmentChanges` / `endCardOnTerminal`. The UI hides it
  (`DetailsActionBar` gates on `hasStarted && !isDone && !isCancelled`), so rules
  are the only real gate here, and reaching it needs only a modified client.
- **Fix:** add `&& resource.data.status != 'cancelled'` to that branch (or
  `resource.data.status in ['pending','in_progress']`). Needs a rules deploy.
  **Do not** tighten the other half — the absence of a *date* restriction on this
  branch is deliberate and documented (an employee on day 2+ of a multi-day run
  must still be able to close it).

### S3 — Wave import writes `addressLine2` uncapped, and the field has no rules clause · severity: low · confidence: high

- **Where:** `functions/wave/mappers.js:353` (the one returned field that skips
  `capped(...)`), against `IMPORT_FIELD_CAPS` at `:61-73`; `firestore.rules:665-702`
- **Risk:** the comment at `mappers.js:343` says "Every mapped field is
  length-capped on the way in" — `addressLine2` is not. The import writes with
  the Admin SDK, which bypasses rules, so an oversized value lands silently. Not
  client-exploitable (`ClientRecord` neither reads nor emits `addressLine2`), so
  the failure is doc-size growth rather than a rules rejection — but it defeats
  the guarantee the caps exist for. `text_limits_test.dart` iterates
  `IMPORT_FIELD_CAPS`, so it structurally cannot catch a field absent from the map.
- **Fix:** add `addressLine2` to `IMPORT_FIELD_CAPS` (500 matching `address`, or
  64 matching `apt`) and add the matching clause to `isValidClientData`.

### S4 — `fileName` has a 300-char rules cap and no client-side cap · severity: low · confidence: high (mismatch) / low (reachable today)

- **Where:** `firestore.rules:652-653` vs `lib/core/images/image_storage_service.dart:41`
- **Risk:** `fileName` is built as `'<millis>_<originalName>'` with no bound while
  the images-subcollection rule caps it at 300 — the "client cap must not be
  looser than the rules cap" rule applied to a field with no `TextLimits`
  constant at all. A >287-char basename fails the whole
  `appendAppointmentPictures` batch with an opaque `permission-denied`, taking
  the valid photos in that batch down with it. Practically unreachable through
  `image_picker`'s generated temp names, so this is a robustness gap.
- **Fix:** add `TextLimits.imageFileName = 300`, truncate client-side, and add it
  to the `text_limits_test.dart` rules-readback.

### Verified intentional (looks wrong, confirmed correct — do not "fix")

`DEFAULT_PASSWORD` in source · `changeEmployeeEmail` skipping `assertFreshReauth`
for admins (keyed on `isAdmin`, not `isSelf`, deliberately) ·
`resetProvisionedPassword`'s narrowed-not-closed window · the
`emergencyFieldNotSet` / `appointmentSpanNotWidened` / `hasValidAppointmentInstants`
create-vs-update asymmetries · `/users` read clause 2 exposing peer email/phone ·
the `+2h` DST allowance in `isValidAppointmentSpan` · `allow write` on Storage
images not covering delete · `travelAlertsEnabled` absent ⇒ ON.

Also verified clean: guard order (auth → identity → payload → re-auth → rate
limit → work) holds in **all 13** callables; no hardcoded keys or tokens in
`lib/` or `functions/`; no PII in any `logger.*` call on either side; role never
read from SharedPreferences; no `FirebaseFirestore.instance` in UI;
`enableIMEPersonalizedLearning: false` set unconditionally on all three
credential fields; magic-byte validation agrees across `image_magic.dart` ↔
`image_magic.js`; Keychain is `first_unlock_this_device` with `_ensureMigrated`
first in every public method.

## 🟠 Bug findings (review required)

### B1 — Subcollection photo read **replaces** the array-seeded list instead of merging it, so photos vanish from a job · severity: high · confidence: high

- **Where:** `lib/features/calendar/application/event_details_controller.dart:194-206`
  (adopted at `:175-177`) — **I verified this directly**
- **Problem:** `_mergeStoredPictures` builds its result by iterating **`stored`
  only** (the subcollection read), so any photo present in the `pictures` array
  but *not* in `appointments/{id}/images` is dropped. The docstring immediately
  above it (`:180`) promises the opposite — "**Combines** the subcollection read
  with the array `build` seeded" — and `_loadStoredPictures`' own comment says
  "Empty therefore means *nothing to add*". Both describe a union; the code is a
  replace. The all-or-nothing reasoning those comments rest on held only while
  the two stores were all-or-nothing, and **photo phase 1 makes partial the
  normal state**.
- **This is live on production data now.** The images backfill has not been run
  and shipped build 1.45.0+72 writes the array only. I confirmed
  `appendAppointmentPictures` writes only the *new* photos to the subcollection
  while `arrayUnion`-ing those same photos onto the array — so: job A has 3
  legacy photos (array only, subcollection empty); an admin on the current build
  adds a 4th; array now 4, subcollection 1. Reopen the sheet → `hasPictures` is
  true → `fetchAppointmentPictures` returns 1 → `stored.isEmpty` is false → the
  seed check passes → `existingImages` becomes `[photo4]`. Both the read-only
  carousel and the edit strip render **1 photo instead of 4**. The 3 hidden
  photos also become unremovable (`removeExistingImage` indexes the truncated
  list) and stop counting toward the 10-photo cap. Nothing errors, nothing logs.
- **Fix:** make it a real union keyed on `appointmentImageDocId`, preserving the
  array's ordering *and* its instance (the `arrayRemove` deep-equality reason the
  array instance must win still applies):

  ```dart
  final byId = {for (final i in stored) appointmentImageDocId(i): i};
  final seenIds = <String>{};
  return [
    for (final image in seeded)
      if (seenIds.add(appointmentImageDocId(image))) image,
    for (final image in stored)
      if (seenIds.add(appointmentImageDocId(image))) image,
  ];
  ```

  No test covers `_loadStoredPictures` today — see 🔵I4.

### B2 — `backfill.js` deletes a live employee's `usersByUid` bridge, and has no `--dry-run` · severity: high · confidence: high

- **Where:** `functions/scripts/backfill.js:89` and `:109-110`
- **Problem:** it is the **only** script in `functions/scripts/` with a
  `.delete()` and the **only one with zero `--dry-run` support** (every other
  backfill has 3–16 references to it). Line 89 `continue`s on
  `!shouldHaveBridge(data)`, so that doc never enters `expectedUids`; line
  109-110 then deletes that person's bridge row as an "orphan".
  `functions/bridge.js:159-165` handles identical input the **opposite** way —
  logs and returns without touching the bridge, noting such a doc is only
  reachable via a console/Admin-SDK write. So one console-edited `users` doc
  makes this script delete a live employee's bridge row, and root `CLAUDE.md`
  names that exact outcome: *"`syncUsersByUid` then DELETED their `usersByUid`
  bridge, locking them out of everything."* Every rules gate resolves a role
  through that collection. The `skippedInvited` and `skippedNoUid` branches at
  `:81`/`:86` have the same shape.
- **Fix:** add `--dry-run`; gate the orphan sweep behind an explicit
  `--prune-orphans`; make the invalid branch match `bridge.js:164` (skip, don't
  delete).

### B3 — Four backfill scripts run LIVE on a typo'd `--dry-run` · severity: medium · confidence: high

- **Where:** missing `assertKnownFlags` in `backfill-appointment-images.js`,
  `backfill-client-phone-from-name.js`, `backfill-clients-archived.js`,
  `backfill.js` (present in the other three)
- **Problem:** all four read `process.argv.includes("--dry-run")`, so
  `--dryrun` / `--dry_run` / `--dryRun` is a **live production run** against
  `/clients` or `/appointments` with no warning and no confirmation.
  `backfill-appointment-images.js` is the one with outstanding work, which makes
  it the live risk right now.
- **Fix:** six call sites now clears the 3+ bar for a shared `scripts/_flags.js`.
  Only the reject-unknown rule must agree — the flag *lists* legitimately differ
  per script, so keep those local.

### B4 — `retryAsync` has no `retryWhen`, so it retries genuine rules rejections · severity: medium · confidence: high

- **Where:** `lib/core/utils/retry.dart:18-33` — **I verified this directly**
- **Problem:** `retryStream` (immediately below, `:36`) correctly takes a
  `retryWhen` predicate. `retryAsync` takes none — its `catch (e, st)` retries
  **everything**. So the four one-shot call sites retry a genuine
  `permission-denied` three times before surfacing it, adding ~4.2s of latency to
  a failure that will never succeed. Same race, opposite behaviours, in the same
  file. Separately, `.claude/rules/error-handling.md` names
  `sign_in_controller.dart`'s `_retryOnAuthPropagation` as a "reference use" of
  the shared predicate — it is not; `:221-230` re-declares the predicate inline
  and uses neither shared helper, which the same rule forbids ("Never re-declare
  it locally"). Delay budgets have four different answers across
  `retry.dart:40-44`, `splash_controller.dart:55`,
  `active_user_identity_provider.dart:36`,
  `firebase_appointments_repository.dart:555`, `main.dart:278` and
  `sign_in_controller.dart:227`.
- **Fix:** add `retryWhen` to `retryAsync` defaulting to
  `isAuthPropagationDenied`; add a `const kAuthPropagationDelays` beside it;
  delete `_retryOnAuthPropagation`. One parameter, one constant, one deletion.
  Pairs with 🔵I7 (the predicate itself is never evaluated by any test).

### B5 — `isAllDay` is read from live state *after* the awaits its own instants were derived from · severity: medium · confidence: high

- **Where:** `lib/features/calendar/application/add_event_controller.dart:303`
  (span computed `:248-254`, snapshots `:261-266`); same shape at
  `event_details_controller.dart:544-548`
- **Problem:** `start`/`end` come from `appointmentSpan(... isAllDay: state.isAllDay ...)`
  **before** `await repo.findBusyEmployees`. Every other field is explicitly
  snapshotted at `:261-266` under the comment *"Snapshot the state before the
  awaits, so it survives if the sheet gets dismissed mid-submit"* — but
  `isAllDay:` at `:303` reads `state.isAllDay` live, after the round trip. The
  switch is not disabled during submit (`add_appointment_sheet.dart:279` wires
  `onAllDayChanged` unconditionally; only the button takes `isBusy`). Toggling
  All day while the conflict check is in flight writes `isAllDay: true` with a
  09:00–17:00 window: the card says "All day" over a 9–5 job,
  `selectTravelCandidates` skips it so **the crew gets no "time to leave" push**,
  and the widget's `stillAhead` switches branch. Secondary: reading `state` on a
  disposed Notifier throws under Riverpod 3, so a sheet dismissed mid-submit
  aborts the write inside the catch — the opposite of what the snapshot comment
  promises.
- **Fix:** snapshot `final isAllDay = state.isAllDay;` beside `isPersonal` at
  `:264` and feed the *same* value to both `appointmentSpan` and the record. Same
  for the three reads in `event_details_controller.save`.

### B6 — Overdue sweep re-scans a 24-hour window 288×/day after the cadence merge · severity: medium · confidence: high

- **Where:** `functions/notification_utils.js:587` (query),
  `functions/notification_policy.js:42` (`OVERDUE_LOOKBACK_MS = 24h`)
- **Problem:** `runOverduePromptSweep` was folded into `sendUpcomingJobReminders`
  (`every 5 minutes`) on 2026-08-13, tripling its cadence from 96 to 288 runs/day
  — but the lookback stayed at 24h. A job that ends and stays open remains a
  candidate for the full 24h, so it is re-read and its ledger `create()`
  re-attempted on **287 subsequent sweeps** after the one that actually prompted.
  The in-code comment at `:574` still reads *"This runs 96x a day"* — written for
  the old cadence and not revisited by the merge. With ~15 jobs sitting past
  `endTime` and still open at any moment (normal for a crew that closes jobs at
  day's end): ~4,300 wasted reads/day plus ~6,500 no-op `create()` round-trips/day,
  every one guaranteed to fail `ALREADY_EXISTS`.
- **Fix:** narrow `OVERDUE_LOOKBACK_MS` to ~2h now that the sweep runs 12×/hour
  (still 24 sweeps of outage slack instead of 288 examinations). Correct the
  "96x a day" comment either way. If the 24h reach must stay for outage recovery,
  gate the ledger attempt on `endTime > now - 2 * SWEEP_INTERVAL` and let the
  wider pass run on the daily digest.

### B7 — Widget-window query runs *before* the recipient-eligibility gate · severity: medium-low · confidence: high

- **Where:** `functions/notification_utils.js:385-404`
- **Problem:** `handleAppointmentWrite` calls `fetchEmployeeWidgetWindow(...)` (a
  real Firestore query) for every event's `employeeDocId`, and only *then* calls
  `sendToEmployee`, which returns 0 at the role gate — `CHANGE_RECIPIENT_ROLES`
  is `{"employee"}`. An **admin assigned to a job** therefore pays a full
  widget-window query, a users read, an `fcmTokens` read and (in a series) a
  claim-ledger *write* for a push that can never be sent. Same waste for any
  assignee with zero tokens. `sendToEmployee` is also called with
  `cache = undefined`, so two events for the same employee in one write read that
  user twice.
- **Fix:** hoist the user-doc read into a `cache` `Map` shared across the loop
  (the pattern `runOverduePromptSweep` and `runTravelAwareReminderSweep` already
  use), check `allowed.has(user.role) && user.status === 'active' && tokens.length > 0`
  first, then populate `windows`. Pure reordering, no behaviour change.

### B8 — `deleteAppointment` has no reentrancy guard, and neither does its confirm dialog · severity: low · confidence: high

- **Where:** `lib/features/calendar/application/event_details_controller.dart:623-631`;
  caller `lib/features/calendar/widgets/views/details_edit_body.dart:378-390`
- **Problem:** it sets `isSaving: true` but never tests it first — unlike its
  siblings `save` (`:467`) and `_setStatusOnRepo` (`:414`), and unlike the
  project convention. `_confirmDelete` also opens the dialog with no in-flight
  flag, whereas the neighbouring `_resolveSeriesScope` (`:301`) explicitly sets
  `setSaving(busy: true)` *before* its dialog "so a second tap can't stack a
  duplicate". A fast double-tap stacks two dialogs; confirming both runs two
  deletes — idempotent in Firestore, but two "deleted" notices,
  `deleteOrphanedImages` twice, and for a series the `getSeries` + batch delete
  paid twice.
- **Fix:** `if (state.isSaving) return null;` at the top of `deleteAppointment`,
  and mirror `_resolveSeriesScope`'s `setSaving(busy: true)` around the dialog.

### B9 — A mid-loop staging failure orphans already-moved photo files with no queue entry · severity: low · confidence: high

- **Where:** `lib/features/calendar/data/appointment_image_upload_service.dart:74-95`
- **Problem:** `_stage` **moves** each picked file into the staging dir one at a
  time, and `await _store.add(entry)` only runs after the whole loop. If `_stage`
  throws on file *k*, files `0..k-1` have been moved and their originals deleted,
  but no queue entry exists — so `prune` (which walks queue entries) never reaches
  them and `drainPending` never sees them. Picking 3 photos with a disk-full error
  on the third: all 3 reported failed (correct), 2 files sit in `pending_uploads/`
  forever. Grows unboundedly across occurrences.
- **Fix:** stage into a local list and, in the `catch`, `_deleteQuietly` everything
  already staged before reporting.

### B10 — `findBusyEmployees` is unbounded, contradicting the file's own invariant · severity: low · confidence: high

- **Where:** `lib/features/calendar/data/firebase_appointments_repository.dart:728-737`
  vs the comment at `:152-154` *(found independently by two reviewers)*
- **Problem:** the comment claims *"Every query in this repository now names a
  ceiling — `getSeries` was the last one without."* That is false: the
  `arrayContainsAny` chunk queries have no `.limit()` and no warn-at-cap, unlike
  `_rangeQuery`, `getSeries`, `countFutureAssignments`, `_historyScanWindow` and
  `fetchAppointmentPictures`. Bounded in practice by the two inequalities, so
  this is tail risk, not steady state — a 14-day booking across a large roster
  reads every overlapping job for up to 30 assignees per chunk, on every Save.
  (Index is fine: `(employeeIds CONTAINS, endTime ASC, startTime ASC, __name__)`
  covers both inequality fields.)
- **Fix:** add `.limit(_conflictScanLimit)` per chunk with the same warn posture
  as `_mapRangeSnapshot` — understating a conflict is the dangerous direction, so
  warn loudly. Or correct the comment.

### B11 — Two `ref.read`-after-`await` convention breaks, one of which swallows a log · severity: low-medium · confidence: high

- **Where:** `lib/features/auth/screens/login_screen.dart:53` (the real one), plus
  9 further `ref.read`-inside-`catch` sites: `main.dart:217,229,261`,
  `tour_seen_store.dart:34,56`, `live_activity_preference.dart:32,42`,
  `app_lock_provider.dart:47,49`
- **Problem:** `login_screen.dart:53` breaks the rule in **both** directions at
  once — `if (mounted) ref.read(loggerProvider).warn('login.prefill_email', e, st);`
  puts the log *inside* a mounted guard (the rule requires `warn` **before** any
  such guard, so it survives unmount) while the guard is what prevents the
  Riverpod-3 throw. Result: every prefill failure that lands after the user
  navigates away is silently swallowed — and a secure-storage read failing is
  exactly the pre-first-unlock `-25308` case the keychain work exists to surface.
  The other 9 sites are currently **unreachable** (non-`autoDispose` app-scope
  notifiers and the root widget), so they are convention debt, not live bugs.
- **Fix:** hoist `final logger = ref.read(loggerProvider);` above the `try` in
  each, then log unguarded. Mechanical; turns a rule with 10 standing exceptions
  into a real greppable invariant.

## 🔵 Areas to improve (review required)

Ordered by payoff. Test-coverage items dominate the top because this repo's
documented failure mode is a load-bearing rule regressing silently.

### I1 — `timeZone: "America/Toronto"` bypasses `BUSINESS_TIME_ZONE` in all three schedulers · impact: high · confidence: high

- **Where:** `functions/notifications.js:137`, `:197`, `functions/maintenance.js:84`
  — **I verified this directly**
- **Opportunity:** `functions/time_utils.js:15` owns `BUSINESS_TIME_ZONE`, and
  `functions/CLAUDE.md:131` forbids this verbatim: *"Never re-inline a local
  `toMillis` or a bare `timeZone: "America/Toronto"`."* These are the **only
  three** remaining Cloud Scheduler jobs, so a timezone move would silently split
  every scheduler from every time the app renders. Values are identical today, so
  this is drift prevention, not a live bug.
- **Suggested improvement:** import `BUSINESS_TIME_ZONE` in both modules and swap
  the three literals. Best value-per-effort item in the audit. Neither module
  currently requires `time_utils.js`, so this adds one `require` each — which is
  why I reported it rather than auto-applying it (it needs a functions deploy).

### I2 — `PhotoPickerSection`'s positional resolution and `buildImageProviders` have no real tests · impact: high · confidence: high

- **Where:** `lib/features/calendar/widgets/sections/photo_picker_section.dart:55,63,87,100,253,315`;
  `lib/features/calendar/widgets/dialogs/image_viewer.dart:401`, `:30`
  *(found independently by three reviewers)*
- **Opportunity:** grep for `_resolvedFor|buildImageProviders|initialIndex|existingUrls`
  across all of `test/` returns **zero matches**. The existing
  `photo_picker_section_test.dart` is 69 lines with **two** assertions, both
  "does this widget exist". `image_viewer_test.dart` has four gesture tests all
  asserting only `find.byType(ImageViewer)`, over a single-element list — so the
  `initialIndex.clamp` is never exercised. Root `CLAUDE.md` devotes a full
  paragraph to this code and lists the shipped symptoms verbatim: *"removing
  photo 0 rendered the deleted photo, an untapped placeholder opened a NEW photo,
  and the viewer's `initialIndex` ran past the end of the provider list and threw
  a `RangeError` out of Save/Share."* Past production bugs with no regression pin.
  `AppointmentImageUrlResolver` itself is well tested, which is exactly why the
  consumer-side gap is invisible.
- **Suggested improvement:** assert `buildImageProviders(urls: ['a','','c'], files: [])`
  → length 3 with index 1 substituted (never dropped); `urls: ['a'], files: [f1,f2]`
  → length 3 with files at indices 1–2 in order (this ordering is what makes
  `existingUrls.length + i` a correct offset); `ImageViewer.open` past the end
  clamps; the `_resolvedFor` gate serves `const []` until the resolved list
  matches, and an empty resolved URL renders the error tile untappable.

### I3 — Storage download URLs are re-resolved from scratch on every sheet open · impact: high · confidence: high

- **Where:** `lib/core/images/appointment_image_url_resolver.dart:39`, `:64`;
  consumers `photo_picker_section.dart:81`, `details_view_leaf_widgets.dart:256`,
  `details_edit_body.dart:443`
- **Opportunity:** `resolve()` does a live HTTPS round-trip with **no memoization
  at any layer**, and `resolveAll` fires all N concurrently with no cap. Resolution
  happens in `initState`, so the cost is per *widget State* — and there are two
  separate mount points, so **toggling a sheet from View to Edit re-resolves every
  photo**, as does every reopen of the same job. A job with 8 photos = 8 requests
  per open, ~16 per view→edit round trip. The detail sheet is the app's
  most-opened surface. The resolver's own docstring notes the resolved URL is
  stable by construction — i.e. cacheable, and simply not cached.
  `CachedNetworkImage` caches the *bytes*, not the URL lookup, so the placeholder
  window `CLAUDE.md` calls "a real window, not a frame or two" is re-paid every time.
- **Suggested improvement:** a session-scoped `Map<String storagePath, Future<String>>`
  inside the resolver (already a singleton `Provider`). Cache successes and
  non-`permission-denied` failures; **do not** cache the `''` refusal — entitlement
  can change mid-session. Optionally bound `resolveAll` concurrency to ~4.
  **See 🔴S1** — if you adopt signed URLs, the cache must respect their expiry.

### I4 — `_loadStoredPictures` / `_mergeStoredPictures` have zero coverage · impact: high · confidence: high

- **Where:** `lib/features/calendar/application/event_details_controller.dart:132`, `:194`
- **Opportunity:** zero symbol hits in `test/`; neither
  `event_details_controller_test.dart` nor `..._image_cap_test.dart` references
  `fetchAppointmentPictures`. This code already regressed once (an `identical`
  check against a freezed collection getter was *always* false, so the read ran
  every open and was thrown away). **This is the gap that let 🟠B1 through.**
- **Suggested improvement:** assert adopt-when-untouched; **discard** when the
  user removed a photo mid-round-trip; compare by value not identity; a photo in
  both stores keeps the **array's** instance (so `arrayRemove`'s deep-equality
  match keeps working); a throw leaves the seeded list intact; and — post-fix —
  a partial subcollection unions rather than replaces.

### I5 — `myUpcomingAppointmentsProvider`'s body has never executed in a test · impact: high · confidence: high

- **Where:** `lib/features/settings/application/my_details_providers.dart:85`
  (role branch `:92`, re-filter `:101`)
- **Opportunity:** both references in `test/` are `overrideWith` — the body never
  runs. Root `CLAUDE.md` documents this as a **shipped bug**: a technician's query
  was rejected by `isAssignedEmployee` (rules evaluate LIST queries against
  constraints), swallowed by `?? const []`, so the availability-conflict warning
  *"silently never fired for the only role that screen exists to serve"* while a
  permanently-failing listener stayed open. It can reintroduce itself with every
  test still green.
- **Suggested improvement:** assert admin reads `appointmentsInRangeProvider`;
  `'employee'` reads `myAppointmentsProvider` and **never** the range provider;
  null identity → `const []`; a job not containing `docId` is filtered out; a
  stream error yields `[]` **and** logs once under `MYDET`.

### I6 — `AppSyncListeners` mirror listeners are structurally untestable · impact: high · confidence: high

- **Where:** `lib/core/app/app_sync_listeners.dart:78` (`_isUnsettled`), `:81`, `:100`;
  producers `widget_sync_service.dart:205`, `schedule_snapshot_provider.dart:11`
- **Opportunity:** both `_widgetSync` and `_snapshotSync` `return` on
  `!Platform.isIOS` **before** any injectable seam, and `flutter test` runs on the
  host — so these listeners never register and the code is unreachable from the
  harness. The existing `app_sync_listeners_test.dart` covers 4 of 6 listeners and
  *reads as if the class were covered*. The docstring records the exact past
  failure: an `AsyncError` carries a null value, and `null` means "signed out,
  clear the App Group" — so a failed Firestore read blanked the home-screen widget
  and had Siri answer "no appointments" to someone with jobs. Both surfaces are
  off-screen; nothing reports it.
- **Suggested improvement:** lift the platform gate to an injected predicate and
  mark `_isUnsettled` `@visibleForTesting`. Then assert: `AsyncError` calls
  **neither** `sync()` nor `clear()`; settled `null` calls `clear()` once; settled
  data calls `sync(payload)`; `role == 'admin'` picks the range provider.

### I7 — `isAuthPropagationDenied` is never evaluated by any test · impact: high · confidence: high

- **Where:** `lib/core/utils/retry.dart:15`
- **Opportunity:** `retry_test.dart` passes a locally-declared
  `retryWhen: (e) => e is StateError` at `:110`, `:133`, `:153` — the shipped
  predicate is never called. It exists *because* it had drifted across three
  byte-identical copies. Narrow it and the first post-sign-in query fails
  intermittently on slow devices only; broaden it and a genuine rules rejection is
  retried before surfacing. Both are timing-dependent and neither logs anything
  distinguishable. Pairs directly with 🟠B4.
- **Suggested improvement:** assert `FirebaseException(plugin:'cloud_firestore',
  code:'permission-denied')` → true; `code:'unavailable'` → false;
  `FirebaseAuthException` → false; bare `Exception` → false. Plus one `retryStream`
  case using the real predicate.

### I8 — `liveActivityPushToStartTtl` is the only Dart↔CEL hand-mirror with no rules-reading test · impact: high · confidence: high

- **Where:** `lib/features/live_activity/domain/live_activity_token.dart:19`
  (`Duration(days: 30)`) ↔ `firestore.rules:392` (`< request.time + duration.value(31,'d')`)
- **Opportunity:** one day of headroom. `TextLimits`, `kSelfServiceUserFields`,
  `emergencyFieldNotSet`, the span bound and the status allowlist **all** have a
  test that reads `firestore.rules` back, precisely because Dart and CEL cannot
  share a constant. This pair does not. Bump the Dart TTL to 45 days and every
  push-to-start token write is rejected — and the registration controller
  catches-and-logs with no user-facing signal, so the symptom is "Live Activities
  quietly stopped appearing on new devices."
  Note the existing `live_activity_token_test.dart:45-59` restates the
  implementation with the same constant, so it holds for 30, 45 or 400 days and
  cannot catch this.
- **Suggested improvement:** parse `duration.value(N,'d')` out of the rules and
  assert `liveActivityPushToStartTtl < Duration(days: N)`; same for
  `liveActivityUpdateTtl`. Same shape as `text_limits_test.dart`.

### I9 — Search-cache invalidation has 8 call sites and no test can catch a missing one · impact: high · confidence: high

- **Where:** `lib/features/calendar/data/firebase_appointments_repository.dart:73`,
  called at `:208,261,274,301,354,384,472,485`
- **Opportunity:** `firebase_appointments_repository_search_test.dart` is the only
  file calling `searchHistory` and contains **zero** write calls; every test builds
  a fresh repository, so no test ever performs write-then-search. The repository is
  a long-lived singleton, so a new write method added without the call makes
  history search serve a **deleted** appointment — tapping it opens a detail view
  for a doc that no longer exists.
- **Suggested improvement:** a table-driven test walking the public write methods
  (search → write → search re-queries, `verify(query.get()).called(2)`), so a *new*
  method fails loudly.

### I10 — `neverSetUpAccountsProvider`: a one-word change makes the only security warning permanently empty · impact: high · confidence: high

- **Where:** `lib/features/dashboard/application/dashboard_providers.dart:199`
- **Opportunity:** zero test references; sole consumer is `dashboard_screen.dart:222`.
  It lists accounts still on the shared `Welcome123!`, read from
  `allUsersStreamProvider` — **never** `employeesStreamProvider`, which filters
  `status == 'active'`. Every never-set-up account is `invited`, so that
  substitution makes the list permanently empty and the dashboard's only
  operational-security warning silently never fires.
- **Suggested improvement:** assert an `invited` user is listed and an `active` one
  is not (substituting `employeesStreamProvider` must break the test); ordering is
  oldest-first with null `createdAt` **last, not dropped**.

### I11 — One `user_vocabulary_rules_test.dart` closes five Dart↔CEL gaps at once · impact: medium-high · confidence: high

- **Where:** `firestore.rules:161` `isValidRole`, `:164` `isValidUserStatus`,
  `:174` `isValidJobTitle`; also unpinned: `isValidWorkingDays`, `isMinuteOfDay`,
  `isValidColorValue`, `isValidDocIdField`, `isValidAppointmentData`
- **Opportunity:** each is a hand-mirror of a Dart enum (`JobTitle`, `UserStatus`),
  and grepping each rules-function name across `test/` returns **0**. Contrast
  `isValidAppointmentStatus`, which *is* pinned. Add a sixth `JobTitle` in Dart,
  the chips offer it, and every save of a person with that title dies as an opaque
  `permission-denied`.
- **Suggested improvement:** one test file reusing the regex-extraction helper
  already in `appointment_status_rules_test.dart:29-46`. Cheap; closes five gaps.

### I12 — `storage.rules` is the least-observed of four admin-gate copies and the only one with no test · impact: medium-high if it drifts · confidence: medium

- **Where:** `firestore.rules:26-30` · `storage.rules:12-20` ·
  `functions/security.js:214-218` · `functions/employee_accounts.js:386-392`
- **Opportunity:** "active admin via the `usersByUid` bridge" has four independent
  implementations. `CLAUDE.md` pins the *sibling* pair (`isAssignedEmployee` ↔
  `isAssignedToAppointment`) but says nothing about the admin gate, which has twice
  as many copies — and the documented historical bug was precisely a missing
  `status == 'active'` in a bridge gate. The actionable asymmetry: `firestore.rules`
  is read back by **six** tests; `storage.rules` by **none**.
- **Suggested improvement:** one test asserting both admin-gate bodies contain the
  `role == 'admin'` **and** `status == 'active'` clauses, in the
  `self_service_fields_test.dart` idiom.

### I13 — The `maxJobsPerDay == 0` → "No cap" label rule has 4 copies, and one has already diverged · impact: medium · confidence: high

- **Where:** `work_schedule_policy.dart:140` (inside the shared picker) ·
  `edit_person_sheet.dart:468` · `my_scheduling_section.dart:47-49` ·
  `employee_details_view.dart:111-114`
- **Opportunity:** root `CLAUDE.md` says the picker *and* the "`noCap` label rule"
  were extracted together. The **option list** was; the **label rule** was not —
  and `employee_details_view.dart` has already diverged, omitting the row entirely
  rather than saying "No cap". This is the most valuable finding shape in this repo:
  the doc records a rule as owned when it is not.
- **Suggested improvement:** `String maxJobsLabel(AppLocalizations l10n, int value)`
  beside `showMaxJobsPicker`; route the three; make the detail view's omission
  deliberate and commented, or fold it in.

### I14 — `functions/CLAUDE.md:117`'s "re-exports every one of them" is false for 10 of 21 symbols · impact: medium · confidence: high

- **Where:** `functions/notification_policy.js` exports 21;
  `functions/notification_utils.js` re-exports 11. Missing: `DAY_MS`,
  `OVERDUE_LOOKBACK_MS`, `OVERDUE_SWEEP_MAX`, `DIGEST_SWEEP_MAX`,
  `WIDGET_PAYLOAD_MAX_BYTES`, `CHANGE_RECIPIENT_ROLES`, `ledgerBody`,
  `isAlreadyExists`, `recordOf`, `contextFor`
- **Opportunity:** the implicit invariant is **already broken** —
  `functions/__tests__/live_activity_ctx.test.js:20` requires `notification_policy`
  directly. This is the "a long comment is a spec" failure shape, on the entry-point
  doc for anyone working in `functions/`.
- **Suggested improvement:** correct the sentence, or add the ten re-exports.
  Either, but they must agree.

### I15 — `functions/wave/callables.js` holds a Firestore trigger and a scheduled rider · impact: medium · confidence: high

- **Where:** `functions/wave/callables.js:727` (`waveUpsertCustomer`, a 144-line
  `onDocumentWritten`) and `:871` (`runWaveDaily`, a 96-line scheduled rider), in a
  965-line file named for callables
- **Opportunity:** neither is a callable; both live here only because they share
  `importWithWatermark:409` and `drainForSync:519`. Anyone looking for "the Wave
  trigger" has no reason to open this file.
- **Suggested improvement:** move `importWithWatermark` + `drainForSync` +
  `readWaveBusinessIdCached:96` → `functions/wave/sync_run.js` (`CLAUDE.md` already
  calls that pair "ONE owner", so it earns a file by the repo's own reasoning);
  move the two triggers → `functions/wave/triggers.js`. `index.js` export *names*
  are unchanged; only `require` targets move. Result: 460 / 210 / 250 lines.

### I16 — `functions/wave/worker.js`'s retry taxonomy has no `*_policy.js` sibling · impact: medium · confidence: high

- **Where:** `functions/wave/worker.js:82-252` — nine dependency-free symbols
  (`DEFAULT_MAX_ATTEMPTS`, `RATE_LIMITED_MAX_ATTEMPTS`, `BASE_BACKOFF_MS`,
  `MAX_BACKOFF_MS`, `defaultBackoffMs`, `isTransientGraphqlError`, `isRetryable`,
  `attemptBudgetFor`, `sanitizeError`)
- **Opportunity:** these decide whether a real client edit is dead-lettered forever,
  and are reachable only through a 2218-line Firestore-mock harness. This is exactly
  the split `CLAUDE.md` blesses twice (`notification_policy` ↔ `notification_utils`,
  `maintenance_policy` ↔ `maintenance`) — none of them takes `deps`.
- **Suggested improvement:** `functions/wave/retry_policy.js`; `worker.js`
  re-exports `RATE_LIMITED_MAX_ATTEMPTS` so nothing downstream changes.

### I17 — An admin holds two permanent appointment listeners for the two off-screen mirrors · impact: medium-low · confidence: medium-high

- **Where:** `lib/features/home_widget/application/widget_sync_service.dart:233` vs
  `lib/features/siri/application/schedule_snapshot_provider.dart:37`
- **Opportunity:** `AppointmentDateRange.forMirrors`' own docstring
  (`appointment_record.dart:238`) states the invariant — *"both ask the same
  `myAppointmentsProvider` family … two different ranges meant two permanent
  Firestore listeners per signed-in user."* That holds for employees. For an
  **admin** it does not: the Siri snapshot branches to `appointmentsInRangeProvider`
  while the widget payload unconditionally uses `myAppointmentsProvider`. Both are
  held open for the session, and the admin's own jobs are a strict subset of the
  business-wide list the first listener already streams.
- **Suggested improvement:** role-branch `widgetPayloadProvider` the same way the
  snapshot does, filtering to `employeeIds.contains(empId)` in Dart (which
  `buildWidgetPayload` already re-scopes anyway).

### I18 — One photo batch fans out into N recounts, N parent writes and N+1 notification invocations · impact: medium · confidence: medium-high

- **Where:** `functions/appointment_images.js:121` (`recountAppointmentPictures`)
- **Opportunity:** `appendAppointmentPictures` writes N image docs in one batch;
  each fires the recount, which runs a `count()` aggregate and an `update()` on the
  **same parent**. The file documents the ~1 write/sec/document contention but not
  the second-order fan-out: each parent write re-fires `notifyAppointmentChanges`
  (`notifications.js:87`). Uploading 10 photos to one job ⇒ 10 recount invocations
  **+ 11 `notifyAppointmentChanges` invocations** for one user action, multiplied
  further by `retry: true` contention retries.
- **Suggested improvement:** debounce the recount per parent (short-TTL marker doc,
  or derive at write time with a periodic absolute reconcile). **Do not** add the
  `before.exists && after.exists` guard — the file explains why that's wrong.

### I19 — `ImageStorageService` is untestable because of one field initializer, and the documented reason is stale · impact: medium · confidence: high

- **Where:** `lib/core/images/image_storage_service.dart:15` —
  `final FirebaseStorage _storage = FirebaseStorage.instance;`
- **Opportunity:** this is the **only** hard `.instance` field initializer in all of
  `lib/`. All 5 test files naming this class only mock or fake it — the real class
  is never constructed, because that field throws without a Firebase app. The class
  already accepts an injected `AppLogger`, so it follows the convention for one dep
  and not the other. `.claude/rules/testing.md:46` excuses it alongside
  `ImagePickerService` as "method-channel plugins" — accurate for the picker (a thin
  wrapper with no logic), **wrong for this class**, which has magic-byte rejection
  (`:31`), the 8 MB cap (`:36`), `_pathFromUrl`'s legacy fallback (`:96`) and the
  `object-not-found` swallow (`:67`). The lumping is what has kept it untested.
- **Suggested improvement:** `ImageStorageService({FirebaseStorage? storage, AppLogger? logger})`
  — one line. Then test the four behaviours above. Also correct the `testing.md`
  line so the two classes stop sharing an excuse.

### I20 — `syncUsersByUid` rewrites the bridge doc on every `users` write · impact: low · confidence: medium-high

- **Where:** `functions/bridge.js:127` (trigger), `:170` (unconditional `batch.set`)
- **Opportunity:** fires on any `users/{id}` write and re-writes `usersByUid/{uid}`
  even when none of `role`/`status`/`uid` changed. Compare `recountClientJobs`,
  which explicitly fires only when `clientId` actually changed. The hot writer is
  `MyDetailsScreen`'s availability panel, which by design commits immediately per
  switch with no debounce — so flipping five working days is five function
  invocations and five identical bridge writes.
- **Suggested improvement:** early-return when `before.role === after.role &&
  before.status === after.status && before.uid === after.uid`, after the existing
  validity checks. Keep the presence-purge and auth-access paths on their own
  predicates, which already diff correctly.

### I21 — `_attempt` threads six interacting flags through a 132-line method · impact: medium · confidence: high

- **Where:** `lib/features/calendar/data/appointment_image_upload_service.dart:143`,
  decision at `:231-270`
- **Opportunity:** the only genuine complexity hotspot in the codebase (measured by
  nesting depth, method length and branch density — max control nesting anywhere in
  `lib/` is three levels). It threads `permanentFailures`, `tooLargeNames`,
  `transientFailure`, `survivors`, `resolveFailed`, `appendFailed` through an upload
  loop, then makes the requeue/report decision from them — encoding the rule
  `CLAUDE.md` is most emphatic about (carried-forward uploads must be re-linked,
  never re-uploaded, never dropped, or Storage bytes orphan invisibly).
- **Suggested improvement:** extract `_AttemptOutcome.from({...})` returning
  `(requeue, uploadedToCarry, failedCount)` — makes the six-flag interaction
  unit-testable without the mock harness. **Do not** restructure the upload loop.

### I22 — Four more rules mirrored 3+ times without an owner · impact: medium · confidence: high

- `enableIMEPersonalizedLearning: false` — 4 sites
  (`auth_form_widgets.dart:450-454`, `change_email_dialog.dart:219-224`,
  `delete_account_dialog.dart:69-73`, `:126-127`), three carrying their own
  restatement of the reasoning. All agree today; `.claude/rules/security.md` records
  that this exact rule **shipped violated** once. A new credential field is one raw
  `TextField` away from repeating it. → one `credentialInputDefaults`.
- Business-local day-start composition — `day_slice_utils.js:33-36`, `:44-47`,
  `widget_payload_utils.js:97-102`, `notification_policy.js:311-319`, all
  `businessMidnight(...businessYmd(x), d + n)`. All three modules already require
  `time_utils.js`, which owns both halves but stops one level short. Same shape that
  produced the documented DST bug. → export `businessDayStartMs(instant, offsetDays)`.
- Firestore doc-id validation (≤128, no `/`) — `firestore.rules:445-447` is the CEL
  owner; `clients.js:73-79`, `employee_accounts.js:417-422` and `:728-733` (the last
  two **byte-identical including the comment**), `notification_policy.js:118-126`.
  No callable is currently missing the guard, so this is duplication, not a hole.
  → `requireDocId(data, key)` in `functions/security.js`.
- Email normalization — 9 sites, no owner, plus a local `_norm` in
  `change_email_dialog.dart:135`. **Concrete part:**
  `employee_record.dart:99` emits `'email': email` **raw** in `toMap()`, and that is
  the uniqueness key `firebase_employees_repository.dart:187` queries against to
  refuse a duplicate account. Latent, not live (no production write caller today —
  `updateEmployee` hand-builds its patch). → `normalizeEmail()` in `core/validators/`,
  and either normalize or delete `toMap()`'s `email` key.

### I23 — Tests that exist but assert too little · impact: medium · confidence: high

The highest-stakes one first:

- **`test/features/clients/widgets/clients_list_swipe_test.dart`** — 9 assertions,
  all about which action *labels* appear. The **destructive half is unasserted**:
  `clients_list_view.dart:186` is `DismissiblePane(onDismissed: () => archiveClient(client))`,
  and `CLAUDE.md` states *"A full swipe commits Archive only; delete is never
  gesture-committed."* Change that to `deleteClient` and all three tests still pass
  while a full swipe **irreversibly deletes a client**. Also unasserted: that
  `ClientTile` inside the booking picker has no `Slidable`.
- `appointment_image_upload_service_test.dart:279` ("is reentrancy-safe") asserts
  only the *guard*, never the **coalesce**. Simplify `drainPending` to
  `if (_draining) return;` and it still passes while a batch staged mid-drain sits
  queued until the next connectivity flip. `CLAUDE.md`: *"coalesce, never drop."*
- `firebase_employees_repository_test.dart:470` asserts the callable's payload but
  not the **ordering** `CLAUDE.md` calls "the whole fix" (callable **before** the
  Firestore write). No `verifyInOrder` in the file, unlike `auth_service_test.dart:46`
  which pins the analogous password-then-activate order.
- `main_calendar_screen_test.dart:221`, `:256` are tautologies — the expected string
  is produced by the function under test, so they pass for any output including the
  wrong French word order.
- The four bounded-read **cap warnings** (`firebase_appointments_repository.dart:170,495,680`;
  `firebase_clients_repository.dart:315`) are asserted nowhere. That warn is the
  entire mitigation: at the clients cap the window is the alphabetically *first*
  1000, so search, the type chips and the Archived chip all go blind past that point
  at once, gradually, as the roster grows.
- `themes_test.dart:7` asserts the four `ThemeExtension`s register, but not the **12
  sub-theme keys** — identical in both themes today, enforced by nothing, across two
  180-line builders. Asserting the key sets match is the proportionate answer here,
  not an abstraction over the two builders.
- `widget_signature_test.dart` covers `signatureForTesting` but not `sync`/`clear`
  themselves. If `_lastState` is set *before* the write succeeds, a failed write
  permanently skips the retry and freezes the widget on stale jobs.

### I24 — Further verified coverage gaps · impact: medium-low · confidence: high

`AppointmentRecord.hasPictures` + `_parseCount` (zero hits; tests **both** stores
because during migration a doc legitimately has either) · `dashboardRecordsProvider`
(merge-by-id is unit-tested, the wiring is not — replace it with `[...live, ...history]`
and every KPI double-counts a fortnight while the aggregator's tests still pass) ·
`AuthFailureLogging.authFailure` (Crashlytics severity routing **and** the
never-log-PII rule, on an untested line) · `AuthErrorContext`'s `reauthentication`
and `register` legs · `isKeychainLockedError` (a substring match on an exception
message — the most fragile predicate shape there is; assert null message → false
without throwing) · `client_name_utils.js:124-159 looksLikeBusinessName` (positives
covered via `composeStored`, the word-boundary negatives two files away; `CLAUDE.md`
says *"Expect to ADD tokens"*, and every such edit changes an untested regex whose
false negatives rename real companies on live Wave invoices) ·
`role_upgrade_listener.dart:44`'s eager read · `photo_upload_failure_listener.dart:61` ·
`appointmentsOrEmpty` and `keepWarmWithGrace` in `appointments_providers.dart` ·
`presence_sync_controller.dart:219` (`denied` must `_stop()`, or a **disabled**
employee's phone streams location and hammers Firestore with rejected writes
indefinitely) · `live_map_providers.dart:30` (regress the error branch to `.value ?? []`
and a rules rejection renders an **empty live map**, which an admin reads as "nobody
is in the field") · `date_utils_helper.dart:34 formatDayHeader` (English-only tests
pass; the documented past bug was French rendering as *"mercredi, août 5"*) ·
`employee_picker.dart:28` ("only active staff are offered" is the premise of the
whole `mergeRetainedAssignees` invariant) · `jobTitleLabel`.

### I25 — `AppLanguageScope` is now an inert wrapper · impact: low · confidence: high

- **Where:** `lib/core/utils/app_language.dart:18`, mounted at `lib/main.dart:391`
- **Opportunity:** I removed its dead `of` accessor (see auto-fixes). That accessor
  was the **only** thing that would ever call
  `dependOnInheritedWidgetOfExactType<AppLanguageScope>()`, so nothing in the tree
  registers a dependency on this scope and it rebuilds nothing. Locale actually
  propagates via the `ValueListenableBuilder` at `main.dart:399` and via off-screen
  consumers reading the singleton directly.
- **Suggested improvement:** your call — remove the widget entirely, or keep it as
  the seam that would make a future `of(context)` cheap to add. I left it in place
  deliberately; deleting a widget from `main.dart`'s tree is not an auto-fix.

### I26 — Two more small ones · impact: low · confidence: high

- `lib/shared/widgets/fields/app_search_bar.dart:23` — `preferredHeight` is a second
  owner of a number `preferredSize` (`:36`) recomputes, and **recomputes
  differently**: `preferredSize` scales by `textScaler`, the constant does not. Used
  only by `app_search_bar_test.dart:62`, so deleting it needs a test edit.
- `lib/features/employees/domain/models/employee_record.dart:21` — the default crew
  colour `Color(0xFF2196F3)` (Material Blue 500) is **not** in `AppColors.crewPalette`,
  so an employee whose colour was never picked renders a hue outside the pool and
  outside the `_darkCrewOverride` map (no dark lift).

## 🟡 Code-quality suggestions (optional)

- `lib/features/calendar/screens/day_route_screen.dart:320` — the jump-to-today
  button uses `DateTime.now().dateOnly` while its own visibility gate two lines
  above (`:272`) carries the comment explaining why it must use `currentDayProvider`.
  Divergence window is only between the midnight timer firing and executing, so
  impact is near-zero — but it is the exact comment-vs-predicate drift shape that
  produced two release bugs. → `ref.read(currentDayProvider)` in the `onPressed`.
- `lib/features/wave/widgets/wave_settings_section.dart:56-62` — `_blockedOffline()`
  is a hand-rolled `guardedOffline` (same shape, surfaces `WaveNetwork().toLocalizedMessage`
  instead of `composeErrorNotice`). Defensible under the typed-Failure-branch-first
  rule — but `guardedOffline`'s docstring (`error_cause.dart:78-81`) asserts there is
  exactly **one** carve-out, and was tightened on 2026-08-11 precisely because a
  stale second carve-out "read as drift". → route it through, or name it in that docstring.
- `lib/features/calendar/widgets/views/calendar_week_strip.dart:49` —
  `CalendarWeekStrip.heightFor`'s docstring claims it exists "so the collapse can
  size its spacer against the grid it replaces", but no collapse path calls it (only
  its test). Its sibling `CalendarMonthGrid.heightFor` *is* consumed. Either the
  collapse spacer should be using it (**possible layout bug at large text scale**) or
  the method and its comment should go. Worth a decision, not a blind deletion.
- `lib/features/auth/domain/auth_failure.dart:11` — `AuthErrorContext.reauthentication`
  is never passed by any of the 5 call sites, so the guards at `:96` and `:107` are
  **statically false** and `AuthFailureUserNotFound` / `AuthFailureWrongCredentials`
  can never take their re-auth branch. Dead code masquerading as a handled case. I did
  **not** auto-remove it: 🔵I24 argues the branches should be *reached* (a user
  re-authenticating to delete their account currently sees "No account found with this
  email" instead of "Please log in again and retry"). Decide which way before editing.
  The ARB key behind them, `auth_pleaseLogInAgainAndRetry`, is still live at `:155`.
- `lib/features/auth/widgets/auth_form_widgets.dart` — 533 lines, 8 public widgets;
  the only real violation of "one class or widget per file", with 3 consumers.
  → split into `auth_scaffold.dart` / `auth_fields.dart` / `auth_text.dart`.
- `lib/features/settings/screens/settings_screen.dart:376-478` — one `State` carries
  app-lock lifecycle, the notification toggles, and a ~100-line account-deletion flow.
  → the deletion trio to a `DeleteAccountFlow` mixin.
- Raw `EdgeInsets` numbers: 31 sites, **mostly not actionable** — ~9 are the documented
  sub-4px "intentionally raw" nudges and ~22 use off-scale values (7, 9, 10, 11, 13, 14,
  15, 18, 20, 25, 48) with no token at all. The only genuine mixing is
  `app_nav_drawer.dart:68,73,130,345`, which uses `AppSpacing` elsewhere in the same
  file. Honest options: leave it, or extend `AppSpacing` to the redesign's real scale.
  Piecemeal token-swapping half a `fromLTRB` would make it worse.
- Two redundant jest suites: `wave_import_schedule.test.js` (43 lines) is a **strict
  subset** of `import_schedule.test.js` (196) — safe to delete. `mappers.test.js` (389)
  vs `wave_mappers.test.js` (715) overlap heavily but are **not** strict-subset —
  merge, don't delete blind.
- `functions/__tests__/import_schedule.test.js:6-7` redefines its own local copies of
  `WEEK_MS`/`MONTH_MS` instead of importing them, so changing
  `import_schedule.js:11-12` would **not** fail the suite that exists to pin them.
  Same shape (lower stakes) for `MAX_ID_LENGTH` in `appointment_image_ids.js:67`.
- `.eslintignore` excludes `scripts/`, so the backfill scripts — including the one in
  🟠B2 — are **not linted**.

### Stale documentation (4 would mislead someone acting on them)

- `docs/CLOUD_FUNCTIONS.md:166-176` says *"All three still run in prod until the
  pending deploy"* of `sendOverdueJobPrompts` / `waveScheduledImport` /
  `waveSyncWorker`. That deploy ran 2026-08-14 at `d3e22377` — **and this same file
  says so at `:37`**. A reader concludes 6 scheduler jobs are live. Its cross-ref
  title is also wrong (`docs/DEPLOYMENT.md:259` now reads `## DONE 2026-08-14: …`).
  The orphaned Cloud Scheduler entries *are* still outstanding — only the tense and
  pointer are wrong.
- `docs/DEPLOYMENT.md:213` says *"Phase 1 is written and un-deployed"*, contradicted
  by its own block quote three lines above. Heading `:204` still reads `## Pending:`;
  only steps 2–3 are pending.
- `docs/plans/README.md:158-161` says `docs/audits/audit-client-phone-backfill-damage.js`
  has a stale `require` path. It doesn't — `:59` is correct, with a repair comment at
  `:55-56`. The note discourages the only tool for assessing the 2026-08-08 Wave
  rename damage, and invites someone to "fix" a correct path into a broken one.
- `docs/audits/AUDIT_FOLLOWUPS.md:10-30` carries an open follow-up for Inter /
  `google_fonts`, both removed by P1 on 2026-07-30. `docs/plans/README.md:165-167`
  correctly says only §2 is open — the two disagree.

Cosmetic: `docs/CLOUD_FUNCTIONS.md:827` cites a deleted script;
`docs/ARCHITECTURE.md:177` has the one Android sentence not covered by the blanket
disclaimer; `docs/CLOUD_FUNCTIONS.md:179-180` justifies `deleteAccount` by "Google
Play account-deletion policy" (Play is moot — Apple 5.1.1(v) alone carries it);
`docs/archive/README.md:22-25` claims `INVITED_SIGNUP_REDESIGN.md` is still cited as
authoritative by CLAUDE.md and `CLOUD_FUNCTIONS.md` — neither cites it any more;
`docs/plans/2026-07-29-redesign-program.md` describes the deleted signup-code flow
with no withdrawal banner on the affected sections (the P4b **sub-docs** are
exemplary by contrast); `.claude/workflows/wave-ultra-review.mjs:66-68` still
describes a Wave "outbox worker / lease-based reaper", deleted 2026-08-14.

## Notes / uncertainties

- **Method note for future sweeps:** a naive `package:scheduling/` importer scan
  reports 4 false orphans under `settings/widgets/cards/` — they are re-exported by
  the barrel `settings_tiles.dart:4-7` using **relative** `export` directives. Any
  scan must follow those. Likewise, a naive per-directory test scan reported
  `presence`, `maps`, `siri`, `settings` and `wave` domain layers as untested; all
  five were false (coverage lives under the **caller's** filename). Every "no test"
  claim in this report was verified by grepping the **symbol** across all of `test/`.
- **Corrections to reviewer claims I did not accept:** `AppointmentRecord.toMap()`'s
  omission of `pictureCount` **is** pinned (`appointment_images_rules_test.dart:90-99`).
  A claimed security finding that "none of 13 `role == 'admin'` checks tests
  `status == 'active'`" over-reads — `active_user_identity_provider.dart:19` *is* the
  active gate and consumers inherit it; downgraded to a non-actionable style note.
  `day_route_screen`'s stop-numbering, `buildWidgetPayload`, `LiveMapAggregator`,
  `AddressParser.canonicalFrom`, `WaveErrorMapper`, `joinWeekdayNames`,
  `sundayIndexOf`, `ClientSearchPolicy.index` and every declared Dart↔JS hand-mirror
  are all properly covered.
- **All declared hand-mirrors were checked and agree:** `appointment_day_slice.dart` ↔
  `day_slice_utils.js` (including the overnight `<=`, the 14-day clamp and the
  wall-clock window rebuild), `ClientNamePolicy` ↔ `client_name_utils.js`,
  `appointmentImageDocId` ↔ `appointment_image_ids.js` (a line-for-line mirror of 12
  test names — the strongest discipline in the repo, and the model for the others),
  `widget_sync_service.dart` ↔ `widget_payload_utils.js`, `_who` in
  `notification_messages.js` ↔ `live_activity_utils.js`. Every range-stream consumer
  re-scopes through `runsOn`/`sliceFor`/`runsInRange`/`expandToDays`.
- **Dependency heuristic false positives, all verified:** `google_maps_flutter_ios_sdk9`
  is the deliberate SPM-compatible iOS implementation swap (pubspec:85-88);
  `freezed`/`build_runner` back the `part '*.freezed.dart'` codegen; `flutter_launcher_icons`
  has its config block at pubspec:166. **Zero unused dependencies.**
- **`android/` is back on disk** — correctly untracked and covered by `.gitignore:78`,
  so the load-bearing entry is doing its job; a Flutter command regenerated it exactly
  as `CLAUDE.md` predicts. I checked the known secret risk: `android/local.properties`
  exists but contains **no `MAPS_API_KEY` line**. No action needed; flagged only so it
  isn't mistaken for a resurrection.
- **Operational items outstanding** (ops, not code — from the 2026-08-14 deploy):
  **as written, this listed the orphaned Cloud Scheduler entries, the
  appointment-images backfill and the app build. Two of the three have since
  closed** — the backfill ran on 2026-08-15 (13 photos across 10 appointments)
  once 🟠B3 had repaired its fake `--dry-run`, which is exactly the ordering this
  note asked for, and both gating indexes are `READY`. What is left is the three
  orphaned Cloud Scheduler entries and the app build. 🟠B1 was materially worse
  until that backfill ran.
- `functions/appointment_image_ids.js` has **zero production inbound requires** (only
  the backfill script and its jest suite). Consistent with the design, but it means
  the hand-mirror invariant is pinned by tests alone and never exercised by a deployed
  path. Worth knowing, not a finding.
- I did not run the Firestore emulator, so rules findings are by inspection of the
  CEL plus the existing rules-readback tests. 🔴S2's fix should be emulator-verified
  before deploy.
