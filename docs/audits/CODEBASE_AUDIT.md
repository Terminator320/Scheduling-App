# Codebase Audit — 2026-08-19

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`, `lib/l10n/*.arb`, `docs/`).
Baseline: `db99d889` on `redesgin`.

> **Doc references use the NEW rule layout.** The CLAUDE.md → `.claude/rules/`
> lazy-loading split landed on disk *during* this audit (root CLAUDE.md 2100 →
> 449 lines; new `appointments.md`, `clients.md`, `employees.md`, `images.md`,
> `wave.md`, `notifications.md`, `firestore-indexes.md`, plus
> `lib/core/navigation/CLAUDE.md`). Every citation below was re-located against
> that new layout and re-verified — none point at the pre-split file.
>
> **This audit changed no files.** The only working-tree changes are yours (the
> split itself), so nothing here collides with it.

## Resolution — all 38 findings closed, 2026-08-19

Every finding below was implemented in the working tree the same day. Read the
findings as the record of what was wrong, not as outstanding work.

**Verified after the fixes (observed, not assumed):**

- `flutter analyze` → **No issues found!**
- `flutter test` → **2599 passing / 0 failing** (from 2445/41 at the baseline)
- `functions` ESLint → clean · `functions` jest → **1327/1327 across 56 suites**
  (from 1308/54)
- `lib/l10n/.gen/untranslated.json` → `{}` · zero BOMs across every changed file

**The two decisions worth carrying forward:**

- **S1 was resolved as *bounded paging*, not by picking one of the two states
  the finding described.** Paging and a ceiling are not alternatives: page so a
  single snapshot cannot truncate the answer, cap so the loop cannot walk the
  collection, warn so a truncation is visible in Crashlytics. The constants were
  raised rather than restored — `_rangeStreamLimit` 3000, `_userStreamLimit`
  1000, `_presenceStreamLimit` 1000, `_historySearchScanLimit` 5000,
  `_clientScanLimit` 5000, `_clientHistoryScanLimit` 1000 — and every doc claim
  the finding listed was rewritten to that shape rather than deleted.
- **B6's prescribed fix was insufficient as written.** Hoisting the provider
  reads to the top of `_restoreDeviceRegistrations` does not help, because the
  whole function runs after its caller's three awaits. The deps are now passed
  in from the caller, which makes a restore-without-deps unrepresentable.

**Where the audit was wrong, corrected during the work:**

- I12 undercounts: **78** log tags in `lib/`, not 63 — the extraction missed
  tags passed as a named `tag:`, built by interpolation, or spelled in a ternary.
- I11: `functions/build/` was **already** gitignored (`.gitignore:64`, a bare
  `build/`, which matches at every depth). Only the `__tests__` entry was needed.
- I1: `functions/index.js` is **not** requireable outside the emulator as-is —
  it needs `FIREBASE_CONFIG`, for exactly the reason I12 corrects about
  `maintenance.js`.
- I6: `AppointmentCard._body` is 59 lines, not 94. Only `build()` was over 60.
- I2's Personal/all-day claim is half right: the two controllers are
  deliberately asymmetric, so the doc was rewritten per-controller rather than
  deleted.
- D3: **both** new collections carry a TTL `fieldOverride`, not one.

**Found while closing the audit, not in it:** `login_screen.dart` carried the
same dead `_bannerSuccess` state as **B7** — assigned `null` at all four sites
and nothing else, so its success banner was unreachable. Removed.

**Still outstanding, and deliberately not done here** (both are operational, not
code):

- `docs/legal/privacy-policy.html` is now internally consistent but must be
  **republished to `gvogas/es-pro-legal`** — `termsAcceptedAt` is stamped against
  the *published* text, so the live page is the one that matters.
- `functions/scripts/restore-client-name-halves.js` — **prod dry run DONE
  2026-08-21, and the repair set is EMPTY**: 703 clients examined, 0 to
  restore, 0 for the business repair, 507 already carrying halves, 193 never
  renamed. The live run was never needed. Three docs remain, and none of them
  is what this script repairs — see the note under **Notes / uncertainties**.

## Summary

- **Scanned:** 389 Dart files / 56k lines in `lib/`, 294 test files, 110 JS files
  in `functions/`, 722 ARB keys × 2 locales, rules + indexes, `docs/`.
- **Auto-fixed (safe, in the diff): 0.** The static layer is completely clean and
  every finding this round is semantic, security-sensitive, or a judgment call —
  report-only by the skill's own rule. There was nothing safe left to apply.
- **Reported for your decision: 38**
  (⚠️ 3 pre-ship · 🔴 7 security · 🟠 9 bugs · 🔵 12 improvements · 🟡 7 code-quality)
- **Verification (observed, not assumed):**
  - `flutter analyze` → **No issues found!**
  - `dart fix --dry-run` → **Nothing to fix!**
  - `functions` ESLint → clean
  - `functions` jest → **1308/1308 pass across 54 suites**
  - `flutter test` → **RED: 2445 pass / 41 fail** (a second run gave 2444/42, so
    at least one test is also flaky). See **B1** — this is a finding, not a note.

### The one-paragraph version

The static, dead-code and convention layers are **exceptionally clean**: zero
unused files (verified two ways, including a reachability BFS from `main.dart` —
0 of 380 unreachable), zero dead public symbols, zero unused dependencies, zero
BOMs, zero import-order violations, zero unsanctioned SnackBars, zero raw
`Exception` throws, zero `FirebaseFirestore.instance` in the widget layer, and
zero widget-disposal leaks across all 123 controller sites. All eight documented
Dart↔JS hand-mirrors were diffed and **none has drifted**.

The findings concentrate in one place: **the last two commits** (`a06c8e4a`
"clean up and review of code", `db99d889` "more clean up"). Between them they
removed every named query ceiling in the data layer and shipped 41 failing
tests. Nearly everything above 🔵 traces to those two commits or to the new
image/account-exit code they landed alongside.

---

## ⚠️ Pre-ship checklist (act before release)

There are **zero `TODO(pre-ship)` markers** in the tree — that scaffolding is
genuinely gone. These are the launch-gated items that remain:

- [ ] **`flutter test` is red — 41 failures.** Do not cut a build against this.
  See **B1**; several failures are ambiguous between "test needs updating" and
  "product regression" and need individual triage.
- [ ] **`docs/plans/APP_STORE_SUBMISSION.md:607, :741`** — EN and FR "What's New"
  copy still pinned at **v1.45.0+72 (2026-08-11)** while `pubspec.yaml` is
  **1.46.2+75**. This is the text pasted into App Store Connect; the failure mode
  is publishing last release's notes. The doc's own header warns about this.
- [ ] **`docs/legal/privacy-policy.html:45` vs `:580-581`** — header says
  *Last updated: August 14, 2026*, footer still says *August 8, 2026*. This is a
  **consent artefact**: `termsAcceptedAt` is stamped against the published text
  and §11 makes the date the change-announcement mechanism. Fixing it also
  requires republishing to `gvogas/es-pro-legal`, or the live site keeps the split.

---

## 🔴 Security findings (review required)

### S1 — Every named query ceiling and warn-at-cap was removed from the data layer · severity: high · confidence: high

**Where (code):**
- `lib/features/calendar/data/firebase_appointments_repository.dart:291-311` (`_rangeQuery`), `:343-361` (`fetchClientHistory`), `:391-417` (`_historyScanWindow`)
- `lib/features/clients/data/firebase_clients_repository.dart:129-142` (`fetchClientsCreatedSince`), `:251-281` (`_clientScanWindow`)
- `lib/features/employees/data/firebase_employees_repository.dart:28-56` (all three `users` streams)
- `lib/features/presence/data/presence_repository.dart:70-82` (`watchAllPresence`)

**What.** `_rangeStreamLimit`, `_userStreamLimit`, `_presenceStreamLimit` and
`_historySearchScanLimit` no longer exist anywhere in `lib/`.
`ClientSearchPolicy.serverReadLimit` survives as a declaration with **no call
site**. Four bounded `.limit(N).get()` reads became `while(true) { … startAfterDocument … }`
loops that walk the entire result set; three live `snapshots()` listeners lost
their ceiling outright. Every warn-at-cap went with them.

**This was deliberate, not an accident** — the guard test was inverted in the
same commit. `test/features/calendar/data/firebase_appointments_repository_cap_warning_test.dart`
now contains `test('fetchInRange no longer truncates through a hard query limit')`
asserting `verifyNever(() => query.limit(1000))`, and
`test('history search walks additional pages instead of warning at a cap')`
asserting `expect(logger.warnings, isEmpty)`. Notably `countFutureAssignments`
**kept** its cap and its warn, so the change was selective and considered.

**The reasoning is defensible.** Silent truncation is a genuinely bad failure
mode, and the rules docs argue that case themselves. Paging fixes correctness.
**The concern is that it went from *bounded* to *unbounded* rather than
*bounded higher*, and left three things behind:**

1. **Five doc claims now assert protections the code does not have** — and the
   split preserved every one of them:
   - `.claude/rules/employees.md:287` — *"All three `users` streams are bounded by the shared `_userStreamLimit` (500)…"*
   - `.claude/rules/employees.md:290` — *"The appointment range streams are bounded too (`_rangeStreamLimit`, 1000) and WARN when a snapshot comes back at the cap."*
   - `.claude/rules/appointments.md:344` — *"Every query in every repository now names a ceiling."*
   - `CLAUDE.md:275` — *"Both scan windows WARN at their cap."*
   - `CLAUDE.md:282` — *"Never add a bounded read here without the warn."*

   Plus three inline comments: `lib/features/settings/screens/my_details_screen.dart:409`
   (asserts the `_userStreamLimit` bound), and `firebase_employees_repository.dart:42`
   / `employee_name_policy.dart:1-5`, both of which rest on a removed
   `orderBy('name')` that `watchAllUsers` no longer has.
2. **The live listeners are a different risk class from the one-shot scans.** An
   unbounded `snapshots()` over a business-wide range — re-established per month
   page and held open by the calendar, day route, drawer badge, roster reducer
   and dashboard — is not the same trade as an unbounded one-shot `.get()` behind
   a 2-minute TTL cache.
3. **Cost is now unbounded in business size and grows forever.** History search
   pages the *entire* terminal-appointment archive (2-year retention) on the
   first committed keystroke, once per TTL, per user — then copies every raw doc
   map across the `compute` isolate boundary. Clients search does the same over
   the whole roster (archived clients are never deleted).
   `fetchClientHistory(limit: 50)` now returns a client's *whole* history, and
   `client_job_history_section.dart:62-90` renders it in a **non-lazy `Column`**.

**Risk:** unbounded, client-triggered Firestore read billing; an on-device OOM
path on large datasets; and — because the warns are gone too — a blow-up or a
truncation is now invisible in Crashlytics either way.

**Fix (your call — a product decision, not a mechanical one):** either restore a
named ceiling + warn on each of the seven queries (raising the constants if
1000/500 were too low), **or** keep the paging and rewrite the five doc claims
plus three inline comments so they stop describing a control that no longer
exists. Right now code and spec disagree, which is the worst of the three
states. At minimum, put a hard ceiling on the loops so they cannot walk a
collection without bound, and delete the now-dead `serverReadLimit`.

### S2 — The image disk-cache generation guard is a no-op for the exact case it documents · severity: medium-high (privacy) · confidence: high

**Where:** `lib/core/images/appointment_image_disk_cache.dart:130` +
`lib/core/images/appointment_image_loader.dart:144`
**Doc:** `.claude/rules/images.md:121` — *"A disk write whose session ended
mid-flight is dropped (the cache carries a generation counter): the loader's
write-back is unawaited, so a fetch resolving just after sign-out would
otherwise re-seed the cache that was just emptied."*

**Risk.** `write()` captures `final generation = _generation` at **call** time,
but the loader calls `_disk.write(key, bytes)` only *after* the Storage fetch
resolves. `clear()` bumps `_generation` synchronously — so by the time `write`
runs, the captured value already **equals** the current one and the write
proceeds. The guard only fires for a write queued *before* `clear()`, which the
`_mutations` chain already orders anyway — the harmless direction.

**Concretely:** an employee opens a job sheet with photos still loading, signs
out (or is kicked out by the account-deleted listener), `deregisterThisDevice`
wipes the cache — and the fetch resolves milliseconds later and writes those
bytes back to disk, where they **survive the process**. On a shared handset the
next person's session has the previous user's job photos cached. The in-memory
half *is* protected (by the `identical(_cache[path], pending)` test in `_settle`);
only the disk half — the half that outlives the process — is exposed.

**Its test asserts the opposite ordering.**
`test/core/images/appointment_image_disk_cache_test.dart:103` does
`final write = cache.write(...)` *then* `final cleared = cache.clear()`. Swap
those two lines and it fails today.

**Fix:** capture the generation where the fetch *starts* and thread it through —
`_disk.write(key, bytes, generation: g)` with `g` read in the loader before
`await _fetch` — and reverse the two lines in the test.

### S3 — `AppLock` permanently disables the user's biometric setting on a transient plugin error · severity: medium · confidence: high

**Where:** `lib/core/security/app_lock.dart:136-153` (added in `a06c8e4a`)
**Doc:** `CLAUDE.md:175` — *"a persistent read failure still degrades to
unlocked, on purpose."*

**Risk.** `_authenticate()` now calls `service.isAvailable()` and, on `false`,
**writes `setEnabled(value: false)`** to the persisted Keychain flag, then
unlocks. But `BiometricAuthService.isAvailable()` (`biometric_auth_service.dart:15-22`)
is `try { isDeviceSupported() } catch { return false; }` — it returns `false` on
*any* thrown `PlatformException`, including the pre-first-unlock `local_auth`
channel window this whole subsystem exists to handle. One hiccup on resume
silently turns the user's app lock off, **forever**, with no notice.

The doc sanctions degrading to *unlocked for the session*; nothing licenses
**persisting** that decision over a preference the user explicitly set. The
`_LockOverlay` "Unlock" button routes to the same `_authenticate`, so a user
tapping Unlock in that window is the trigger.

**Fix:** unlock for this session only and surface a notice; don't write the flag.
If a persistent disable is genuinely wanted, gate it on a distinguishable
"device does not support auth" result rather than the catch-all `false`.

### S4 — `PresenceSyncController.unregister()` deletes nothing when this session never started · severity: medium-high · confidence: high

**Where:** `lib/features/presence/application/presence_sync_controller.dart:291-294`

**Risk.** `_docId` is set only inside `_start()`, which requires `firebaseReady`
**and** a granted location permission **and** a successful `findUserByUid`. If
any fails this session, `unregister()` hits `if (docId == null) return;` and
deletes nothing — leaving a `presence/location` doc from a **previous** launch
live in Firestore.

**What the user sees:** an employee revokes Location in iOS Settings, opens the
app (sync bails at the permission gate), signs out — and their last pin stays on
the admin live map indefinitely. `LiveMapAggregator.join` filters on
missing/inactive user, never on freshness, and `staff_marker_icon.dart` has no
staleness branch, so that stale pin is **visually identical to a live one**.
`docs/legal/privacy-policy.html` §6/§8 promise sign-out clears it.

Its sibling gets this right and says why — `live_activity_registration_controller.dart:309`:
*"Resolve docId in case `_docId` was never set."*

**Fix:** mirror it — `final docId = _docId ?? await _resolveUserDocId();`

### S5 — `unregister()` races an in-flight `sync()` in all three device-registration controllers · severity: medium-high · confidence: high

**Where:** `lib/core/utils/reentrant_sync.dart:9` · `presence_sync_controller.dart:291` ·
`push_registration_controller.dart:161` · `live_activity_registration_controller.dart:302`

**Risk.** `ReentrantSync.runCoalesced` guards `sync` against `sync`. It does not
guard `sync` against `unregister`, and `unregister` doesn't go through it.
`deregisterThisDevice` runs *before* `signOut()` by design, so a `_syncGuarded`
resuming mid-teardown still holds a valid credential and **writes successfully**:

- **Presence:** `_start()` re-opens the position stream and re-creates
  `presence/location` for a user who just signed out, and keeps uploading until
  the process dies.
- **Push:** `push_registration_controller.dart:116-124` — if the resumption lands
  before `service.currentToken()`, FCM mints a *fresh* token (the old one just
  invalidated by `deleteToken()`) and upserts it. The signed-out device is now
  registered with a live token and keeps receiving that account's job pushes.

Both writes succeed, so **nothing logs an error**.

**Fix:** route `unregister()` through the same guard, or set an `_unregistering`
flag that `_syncGuarded` re-checks after each await.

### S6 — The `IMPORT_FIELD_CAPS` mirror test silently skips half the fields it claims to check · severity: medium · confidence: high

**Where:** `test/core/validators/text_limits_test.dart:243-251` vs
`functions/wave/mappers.js:112-132`
**Doc:** `.claude/rules/employees.md:380` — *"It reads `functions/wave/mappers.js`
back too, for `IMPORT_FIELD_CAPS` … Add a new capped import field to that map and
the test picks it up automatically."*

**Risk.** It does not. The test parses the map dynamically (`:226-238`) and then
discards most of it through a **hardcoded allowlist of 6 names**, while
`mappers.js` defines **12**. A new field lands in `caps`, fails
`checked.contains`, and is silently skipped.

This is the cap mirror where failure is quietest: the Wave import writes with the
**Admin SDK, which bypasses rules**, so a cap above the rules cap does not fail
the import — it writes a client doc the app can **never update again**, every
later save landing as `permission-denied` on a field nobody typed.

**Fix:** iterate `caps.entries` unfiltered with a deny-by-default `switch` that
`fail()`s on an unrecognised key. Note `rulesCapFor` returns the *minimum* across
collections, so `address` needs a client-scoped lookup (the appointments
validator also caps `address`, at 500).

### S7 — `functions/` carries 5 moderate transitive advisories · severity: low · confidence: high

**Where:** `functions/package.json` (`firebase-admin ^13.6.0`)

`npm audit` reports moderate findings in `@google-cloud/firestore`,
`@google-cloud/storage`, `gaxios`, `google-gax` and `firebase-admin`, all with
`fixAvailable: firebase-admin@14.3.0 (isSemVerMajor: true)`. Your own notes
record that admin@14 is incompatible with `firebase-functions` 7.x. **No action
recommended** — logged for the dependency ledger only.

---

## 🟠 Bug findings (review required)

### B1 — 41 tests fail at HEAD; the tests added by the last two commits were never run · severity: high · confidence: high

`flutter test` → **2445 pass / 41 fail** across 15 files. A second run gave
2444/42, so at least one test is **also flaky**. The last audit closed at
2352/2352 green.

The largest single cause is mechanical and unambiguous: the cleanup commits added
`when(() => repo.watchInRange(any()))` blocks inside `setUp()` **without a
`setUpAll(() => registerFallbackValue(...))`** for the custom argument types
(`AppointmentDateRange`, `DocumentSnapshot<Object?>`). mocktail throws
immediately, and because the throw is in `setUp` it poisons **every test in the
file** — including previously-passing ones. That is why 41 failures span 15
files. `git diff 8ddae0f7..db99d889 -- test/features/calendar/application/appointments_providers_test.dart`
shows the block added with no fallback registration. **These tests cannot ever
have been executed.**

**The rest are not all mechanical and need individual triage:**

| File | Symptom | Reads as |
|---|---|---|
| `test/core/animations/tap_scale_test.dart` (2) | `Bad state: Too many elements` | Helper does `tester.widget(find.byType(Transform))`; a widget change added a second `Transform` and the finder was never narrowed |
| `test/core/images/image_storage_service_test.dart` (8) | `Bad state: Cannot call …` | Harness/stub drift |
| `test/core/images/appointment_image_loader_test.dart` | `Expected: <4> Actual: <3>` | The **documented** `loadAll` concurrency bound of 4. Possibly a real throughput change from the new disk-read-before-network step |
| `test/features/auth/account_status_provider_test.dart` (2) | `Expected: 'Theo Roy' Actual: ''` | Real assertion failure in the name/email fallback |
| `test/features/employees/employee_map_memo_test.dart` | `Expected: {'e1': 'Amy Adams'} Actual: {}` + 30 s timeout | Real |
| `test/features/settings/data/shared_prefs_settings_repository_test.dart` | `Expected: 'es' Actual: 'en'` | Real |
| `test/core/security/app_lock_test.dart` | `Expected: true Actual: <false>` | Plausibly **S3**'s new branch |
| `test/features/auth/application/active_user_identity_provider_test.dart` (3) | `Expected: <1>` | Plausibly the new auth-uid bootstrap gate |
| `test/features/clients/data/firebase_clients_repository_test.dart` | — | Tests the **new** paging behaviour from **S1**, and fails |

Several are genuinely ambiguous between "the test needs updating" and "this is a
product regression the test correctly caught" — which is exactly why none of it
was auto-fixed. **Suggested order:** register the missing fallbacks first (that
alone should clear the bulk and reveal what is actually broken underneath), then
triage the remainder one by one.

### B2 — `Debouncer` now swallows the debounced action's errors at 5 of 6 call sites · severity: medium · confidence: high

**Where:** `lib/core/utils/debouncer.dart:26-33`

`run` wraps the action in `Future.sync(...).catchError((e, st) { onError?.call(e, st); })`.
`onError` is **optional**, and only `address_autocomplete_field.dart:48` passes
one. The other five — `add_appointment_sheet.dart:53`, `details_edit_body.dart:49`,
`appointment_history_view.dart:89`, `clients_list_view.dart:67` — construct
`Debouncer(kSearchDebounce)` bare, so a throw inside a debounced search callback
now **vanishes entirely**: nothing logged, nothing in Crashlytics, search
silently returns nothing. Previously the error escaped to the zone handler and
was recorded. Directly contradicts `.claude/rules/error-handling.md`: *"Never
swallow errors silently."*

**Fix:** make `onError` required, or default it to
`AppLogger().warn('DEBOUNCE action failed', e, st)`, and pass a tagged handler at
the five sites.

### B3 — A reentrancy-skipped delete is reported to the user as a successful delete · severity: medium · confidence: high (latent today)

**Where:** `lib/features/calendar/application/event_details_controller.dart:669`

`deleteAppointment` returns `Object?` where `null` means success — and the guard
`if (state.isSaving) return null;` returns that same `null`. The caller
(`details_edit_body.dart:395-404`) treats `error == null` as "deleted", shows
`common_appointmentDeleted` and calls `widget.onClose()`.

This is the **exact shape** `.claude/rules/error-handling.md` records as already
fixed for the status setters: *"a write skipped by the reentrancy guard was
indistinguishable from one that committed — the sheet announced 'marked as
complete' and closed without having written anything."* The rule mandates a
sealed outcome for any action with more than two states; this one was missed.

Reachability today is narrow (`_DeleteButton` is disabled while `isSaving`, and
`_confirmDelete` clears the flag synchronously), so it is latent — but one
refactor from being real.

**Fix:** return `EventDetailsActionOutcome` (`Ok`/`Busy`/`Failed`) like
`_setStatusOnRepo` already does; surface nothing on `Busy`.

### B4 — `TopRouteObserver` gained the `didRemove` override its spec explicitly forbids · severity: low · confidence: medium

**Where:** `lib/core/navigation/top_route_observer.dart:36-41`
**Doc:** `.claude/rules/employees.md:210-212` — *"`TopRouteObserver` is still
registered … and still deliberately has no `didRemove` override —
`pushNamedAndRemoveUntil` (the account-disabled path) pushes *before* it removes,
so overriding it would overwrite the just-pushed name with a route no longer on
the stack."*

The new override guards with `route.settings.name != _currentRouteName` —
**name-based, not identity-based** — so removing an older route that happens to
share a name passes the guard and overwrites the current one. Impact today is nil
(`_topRouteObserver` has no reader), which is why this is low.

**Fix:** compare by identity, or revert the override and restore the comment.

### B5 — `PendingUploadStore` remove-then-add is not atomic; a failure strands photo bytes permanently · severity: medium · confidence: medium-high

**Where:** `lib/features/calendar/data/appointment_image_upload_service.dart:241-254`

```dart
await _store.remove(entry.id);
if (outcome.requeue) { await _store.add(PendingUpload(... survivors ...)); }
```

`_serialized` makes each mutation safe individually, but **the pair is two
separate read-modify-writes**. If `add` throws, the entry is gone while the
staged files remain on disk — and both `prune` and `drainPending` walk *queue
entries*, so nothing can ever reach those files again. The throw is caught at
`:293`, so it logs but **the user is told nothing**: photos attached to a job
silently never appear, and the staging directory grows permanently.

**Fix:** add `PendingUploadStore.replace(id, entry)` doing both inside one
`_serialized` mutation.

### B6 — `ref.read` after three awaits in the account-deletion catch path · severity: medium · confidence: high

**Where:** `lib/features/settings/widgets/views/delete_account_flow.dart:199, 209, 210, 213`

`_restoreDeviceRegistrations()` is called from both `catch` arms (`:150`, `:168`)
**before** their `if (!mounted) return;` guards, and only after
`reauthenticateWithPassword` + `deregisterThisDevice` + `deleteAccount` have run.
Under Riverpod 3 `ref.read` on a disposed consumer **throws a `StateError`** — so
if Settings unmounted during those round trips, the throw replaces the real
failure, skips the notice *and* the `_isDeletingAccount = false` reset, and
escapes to the zone handler.

**What the user sees:** a failed account deletion with a spinner stuck on, no
error message, and a `StateError` in Crashlytics masking the actual cause. Same
shape that was a **FATAL** in `address_autocomplete_field.dart`.

**Fix:** hoist the three provider reads into locals at `:199`, above the awaits.

### B7 — `_bannerSuccess` is now unreachable state, orphaning an ARB key · severity: low · confidence: high

**Where:** `lib/features/auth/screens/account_setup_screen.dart:97, 573`

`_recoverToLoginAfterSetup` replaced the only assignment. The field is still read
at `:573` but can only ever be `null`, so the success-banner branch is dead — and
`auth_accountReadySignInAgain` (`app_en.arb:67`, `app_fr.arb:19`) is now the
tree's **only** orphaned ARB key.

**Fix:** delete the field and the branch; retire the key in both locales in a
deliberate l10n pass.

### B8 — `unregisterCurrentDevice` skips the Firestore delete when this session never registered · severity: medium · confidence: high

**Where:** `lib/features/notifications/application/push_registration_controller.dart:163-169`

Same shape as **S4**: `if (docId != null && token != null)` where both are set
only on a fully-successful `_syncGuarded`. Milder, because the unconditional
`service.deleteToken()` invalidates the token at FCM — so the residue is a stale
`fcmTokens` row the server keeps trying to push to, not a live delivery. But it
accumulates one row per device per incomplete session, and `syncUsersByUid`
purges these only on *disable*, not on sign-out.

**Fix:** resolve `docId` via `findUserByUid` and delete by uid/kind, the way
`deleteTokensOfKind` already does for Live Activity.

### B9 — A push tap on a slow cold start is discarded with nothing recording it · severity: low-medium · confidence: high

**Where:** `lib/main.dart:342-350` (`_awaitLiveHub`)

It polls for 10 s then `return null`, and the caller returns silently — **no
`logger.warn`, no notice**. The user taps a notification, the app opens, and
nothing happens, with no trace anywhere.

**Fix:** one `logger.warn('PUSH-TAP hub never appeared')` on the null branch.

---

## 🔵 Areas to improve (review required)

### I1 — Test-coverage gaps on high-blast-radius logic · impact: high · confidence: high

Each verified by grepping the **symbol** across `test/`, not the filename (that
caught ~15 false positives where coverage lives under a caller's file name):

| Where | Gap | Why it matters |
|---|---|---|
| `lib/features/calendar/domain/models/repeat_interval.dart:62` (`occurrenceEnd`) | **zero** hits | Writes `endTime` on up to **120 documents atomically** (`add_event_controller.dart:324`, `appointment_series_editor.dart:43,101`). Its whole reason for existing is UTC-midnight arithmetic preserving a multi-day span across DST — neither the multi-day nor the DST branch is asserted. The series test checks `startTime`, `status`, `isAllDay`, `isPersonal`, `seriesId` — never `endTime`. ~6 plain `test()` cases fixes it. |
| `functions/index.js` (25 exports) | no test requires it | Your own notes record the exact failure this permits: *"export SET changed by 6 at an unchanged count of 25."* A count check cannot catch a rename or a swap. `index.js` **is** requireable outside the emulator — ~15 lines asserting the sorted key list. **Cheapest high-value item here.** |
| `lib/core/app/account_exit_listeners.dart` | its test imports `account_exit_controller.dart`, not this file | The only runtime session-kill path. The admin-demotion rule (with its empty-string carve-out) exists **only here** and is untested. A regression either leaves a demoted admin holding an admin session, or signs out an invited employee mid-activation. |
| `lib/core/adaptive/cupertino_time_picker.dart` + `adaptive_pickers.dart` | neither imported by any test | On an iOS-only app this is the **sole** path by which anyone picks an appointment start time, end time, date, or an employee's working hours (5 call sites). Real logic: `firstDate`/`lastDate` clamping, a mutable `tempPicked`, Cancel→`null` vs Done→`onDone()`. |
| `lib/core/utils/firestore_parsing.dart:22` (`firestoreInt`) | its 26-line sibling has 5 tests, this has 0 | Parses `workStartMinutes`/`workEndMinutes`/`maxJobsPerDay` on every `EmployeeRecord` and `jobCount` on every `ClientRecord`, and exists so one console-written field can't throw **inside `snapshots().map`** and blank a whole snapshot. |
| `functions/client_job_count.js:68-84` (`recountOne`) | unexported, untested | Two documented decisions, both silent when wrong: `update()` not `set({merge:true})`, and the `NOT_FOUND` swallow with everything else rethrown so `retry: true` means something. |
| `lib/features/auth/domain/auth_failure.dart` (`toForgotPasswordMessage`) | zero hits | Its `=> null` branch is a **deliberate silence** so the reset screen isn't an account-existence oracle. A well-meaning "improve the error message" change turns it into an email-enumeration endpoint with nothing failing. |
| `lib/core/security/credential_input.dart` (`kCredentialImePersonalizedLearning`) | zero hits | Nothing asserts the 4 production sites set it, and nothing stops a *new* credential field omitting it — exactly how `AuthPasswordField` and both `DeleteAccountReauthDialog` variants shipped broken before. The repo already has the right pattern: a source-reading test, like `text_limits_test.dart` reading `firestore.rules` back. |

### I2 — Four "pinned by a test" claims are weaker than written · impact: medium · confidence: high

38 such claims were checked across the new rule files; **29 hold, 0 name a
nonexistent test, 9 are weaker than stated.** The four that matter:

- **The disk-cache generation test** exercises the harmless ordering — see **S2**
  (`.claude/rules/images.md:121`).
- **`lib/core/navigation/CLAUDE.md:30-31`** — *"`_hubRoute` + `HubTabRedirectRoute`
  survive at three tab routes — they look dead but remain the cold-start fallback
  and are pinned by `hub_shell_test`."* `test/routes/hub_shell_test.dart:157-185`
  mounts a live `HubShell` as `home:` *before* pushing, so only the redirect
  branch runs. `grep -rn "initialTab" test/` → **zero hits**; the cold-start
  fallback at `app_routes.dart:177-186` is never reached. The pair is pinned; the
  *reason given for its survival* is not.
- **`CLAUDE.md:175`** — *"a persistent read failure still degrades to unlocked …
  Pinned by `app_lock_test.dart`."* The nearest test has the retry **succeed** on
  the second call. No test leaves `readFlag` throwing every time. The natural
  "fix" of holding the lock while unresolved would pass all four existing tests
  and trap a non-biometric user behind a prompt they cannot satisfy.
- **Emergency-contact caps "are not dead."** Nothing reads back
  `isBoundedString(d.emergencyContact, 200)` / `d.emergencyPhone, 40`
  (`firestore.rules:217-220`). Deleting those caps as "unreachable" — the exact
  mistake the rules comment warns against — passes the whole suite. Two
  sub-weaknesses: the assertions check only that the field names *appear* (a
  `hasAny`→`hasAll` flip still passes), and the extraction regex is **unscoped**,
  hitting `/users` only by accident of file order —
  `appointment_span_rules_test.dart:80-83` documents this exact trap and scopes
  its own search.

**Two further doc claims, both verified false against the new files:**

- `.claude/rules/clients.md:280-284` says `splitPersonName` is hand-mirrored by
  `splitName` in **both** `backfill-client-name-with-phone.js` **and**
  `restore-client-name-halves.js`, "the three share worked examples". But
  `restore-client-name-halves.js:112` does
  `const {splitName} = require("./backfill-client-name-with-phone");` — it
  **imports** it. There are **two** implementations, not three.
- `.claude/rules/appointments.md:171` says turning Personal **on** "still defaults
  an untimed block to all-day", but
  `test/features/calendar/event_details_controller_test.dart:324` asserts
  `test('turning Personal on again does not resurrect all-day')` —
  `setPersonal(value: true)` then `expect(readState().isAllDay, isFalse)`. The
  source agrees with the test.

### I3 — The auth-uid tri-state unwrap is spelled out six times · impact: medium · confidence: high

Identical ~15-line `hasError → Stream.error / isLoading → fromFuture().asyncExpand / else build(value)`
blocks at `appointments_providers.dart:41` and `:68`, `employees_providers.dart:27`
and `:126`, `account_status_provider.dart:27`, `active_user_identity_provider.dart:31`.

Six instances clears the 3+ bar comfortably. **Owner:** one helper beside
`authUidProvider` in `lib/core/providers/firebase_providers.dart` —
`Stream<T> streamForUid<T>(Ref ref, Stream<T> Function(String? uid) build)`. Each
site's per-null-uid behaviour stays inside its own closure, so nothing is
flattened away.

*Explicitly not findings* (below the bar, listed so they aren't re-raised): the
`_scheduleSearch` debounce block (2 sites), the `_skeleton`/`_errorState`/`_emptyState`
triad (2 sites), the chunked-concurrency loop in `functions/` (5 sites but 4 lines
each, and `live_activity_registry.js` already has a local `_chunk`).

### I4 — `main.dart` holds an untestable external-entry-point router · impact: high · confidence: high

**Where:** `lib/main.dart:220-352` (~132 lines)

`_setupWidgetTapHandling`, `_setupPushTapHandling`, `_handleWidgetTap`,
`_handlePushTap`, `_openAppointmentDeepLink` and `_awaitLiveHub` live inside
`_PaulAppState`. Verified zero test hits for any of them. The `app_links` third
of this **was already extracted** to `core/deep_links/` and *is* tested — the
other two thirds were left behind.

**Change:** extract into `lib/core/app/appointment_link_opener.dart`, matching the
four classes already in `core/app/` that `main.dart` registers. Not a new
abstraction — the move already made once for deep links. Pairs naturally with **B9**.

### I5 — Live-map marker assembly is an engine buried in a `State` · impact: medium · confidence: high

**Where:** `lib/features/presence/screens/live_map_screen.dart:233-346`

`_assembleMarkers` takes **7 positional parameters**; `_signatureOf` takes 5.
`_signatureOf` is a pure function that decides *whether the map updates at all* —
if it ever omits a field, staff markers silently stop moving with no error. It
cannot be tested where it is, because the surrounding `State` needs a live
`GoogleMap`.

**Change:** move both into `lib/features/presence/domain/staff_marker_assembly.dart`
taking a small params record.

### I6 — `AppointmentCard` — the one card on six surfaces — is 182 lines across two methods · impact: medium · confidence: high

**Where:** `lib/features/calendar/widgets/cards/appointment_card.dart:108` (build,
88 lines) and `:231` (`_body`, 94 lines, **8 named params**)

`build()` derives eight values before it builds anything, then hands most of them
to `_body` one at a time; the 8-param signature is the symptom.

**Change:** a private `_CardModel.from(context, ...)` value class; `_body` then
takes `(theme, model)`. Drops both under 60 lines and makes the three variants
(normal/collapsed/cancelled) readable side by side.

### I7 — 68 of 313 `build()` methods exceed 60 lines; 17 exceed 90 · impact: medium · confidence: high

A tail, not a crisis — most are flat declarative trees. The five with a genuinely
clean extraction:

| File:line | Lines | What extracts |
|---|---|---|
| `dashboard/widgets/charts/weekly_bar_chart.dart:38` | **124** | ~100 lines are one `BarChartData` literal + a legend → `_chartData(...)` + a `_SeriesLegend`. **Also has no test at all.** |
| `employees/widgets/views/employee_details_view.dart:43` | **123** | Builds `infoRows`/`emergencyRows` inline → two methods, build drops to ~50. **This is where the emergency-contact entitlement branch lives.** |
| `clients/widgets/fields/client_search_field.dart:40` | **123** | A 60-line result `ListTile` inside a `.map()` → `_ClientResultTile` |
| `calendar/widgets/fields/employee_picker.dart:28` | **107** | Same shape → `_EmployeeChip` (also lets it be `const`) |
| `calendar/widgets/views/details_action_bar.dart:33` | **107** | Three conditional buttons with inline `styleFrom` → one builder each |

The top two are worth doing for the reasons noted; treat the rest as background.

**Explicitly cohesive, leave alone:** `appointment_form_fields.dart` (631 —
`build()` is 12 lines delegating to 4 section builders), `photo_picker_section.dart`
(592), `edit_person_sheet.dart` (613), `edit_client_sheet.dart` (502),
`firebase_appointments_repository.dart` (553), `event_details_controller.dart`
(717), and the four large `functions/` modules.

### I8 — `wave/customers.js` is two things that share nothing · impact: medium · confidence: high

**Where:** `functions/wave/customers.js:669-926`

The file's own banners mark the seam (`:305` upsert, `:669` import). Across the
whole 257-line import half, the only push-side symbols referenced are
`adminFirestore`, `readBusinessId`, `sanitizeInputErrors`, `WaveValidationError`,
`LIST_CUSTOMERS` and the mappers. **Neither half calls the other**, and the jest
suite already separates its describes along the same line.

**Change:** move to `wave/customers_import.js` and re-export, so no call site
changes. *Counter-argument worth weighing:* `importOneCustomer:721-733` reasons
explicitly about the `lastSyncedHash` the push half writes — a comment-level
dependency.

### I9 — `day_route_screen._prepareBuild` re-derives the day's slices on every rebuild · impact: low-medium · confidence: high

**Where:** `lib/features/calendar/screens/day_route_screen.dart:186-227`

`where` + `map(sliceFor)` + `sort` + a second `where` + a `Map` build over the
whole ~21-day range-stream superset, on every `setState` (day switch, employee
pick), every `currentDayProvider` tick and every `employeeNameMapProvider`
emission. Its twin on the calendar screen (`_refreshDayIndex`,
`main_calendar_screen.dart:155`) **is** memoized on list identity; this one is
not. (N ≈ 100–400 records for a busy shop — noticeable on the ◀/▶ tap, not per
frame.)

**Change:** memoize the same way.

### I10 — Ten stale documentation items · impact: medium · confidence: high

`docs/CLOUD_FUNCTIONS.md` is otherwise accurate (25 exports, 25 documented rows,
no ghosts). The ones with real consequences:

| # | Where | Stale claim |
|---|---|---|
| D1 | `docs/CLOUD_FUNCTIONS.md:885` + row `:213` | Says `waveGetConnection` has *"No secret, no rate limit."* It **is** durably rate-limited — `wave-connection`, 60/hr (`functions/wave/callables.js:194-199`). This is the per-function security reference; it under-reports a guard, inviting someone to "fix" the gap by adding a second limiter. |
| D2 | `docs/ARCHITECTURE.md:1049-1051` | `rateLimits.route` presented as a closed union of **4** ids; there are **13**. A reader concludes Places and Wave callables are unlimited. |
| D3 | `docs/ARCHITECTURE.md:1042` | `appointmentSeriesNotices` and `appointmentRecountClaims` absent from the data model, though both are in `firestore.rules` and one carries a TTL `fieldOverride`. A collection in rules + TTL but not the schema doc is what gets deleted as "unknown" in a cleanup. |
| D4 | `docs/ARCHITECTURE.md:1134-1136` | A live pre-deploy gate telling you to hold the App Check enforcement deploy for App Distribution testers — contradicted six lines above and by `grep enforceAppCheck: false functions` → 0. Retired ~20 releases ago. |
| D6 | `docs/cost-breakdown.html:369, :661, :416-417` | Headline still says **six** Cloud Scheduler jobs / ~$0.30 recurring; the doc's own table at `:760` says three / $0. `:416` also mis-reads *"The three schedules were merged down to three."* |
| D8/D9/D10 | `docs/ARCHITECTURE.md:67, :41, :45, :223`; `docs/archive/2026-07-20-session-handoff.md:38` | `features/navigation/` missing from the Directory Map; `SkeletonLoader` and `SheetHandle` don't exist under those names and `SheetFocusScroll` is omitted; `waveRetryFailedJobs` guard cell says `durable` with no number (actual 10/hr); one broken relative link. |

**The legal pages check out clean** — the repo's known failure mode did *not*
recur. `support.html` and `terms-of-service.html` both describe the **current**
admin-provisions flow with no signup-code residue, zero Android/Play hits across
all four files, and privacy §6/§8 correctly state that revoking location
permission does not delete the stored reading. (D5, the date mismatch, is in the
pre-ship list above.)

### I11 — `functions/__tests__/**` is deployed to Cloud Functions · impact: low · confidence: high

`firebase.json:14-22` does not ignore it — ~785 KB of the 1.9 MB source bundle
uploaded on every deploy. No functional risk. Also `functions/build/.last_build_id`
is a stray Flutter artifact covered by neither `.gitignore` nor the deploy ignore
list.

### I12 — The log-tag registry documents 25 of 63 tags in use · impact: low-medium · confidence: high

`.claude/rules/error-handling.md` lists ~25; `lib/` uses **63**. Undocumented:
`APPT-BUSY`, `LIVEMAP-MARKERS`, `LIVEMAP-LOAD`, `IMG-DISK`, `IMG-DEL`, `IMG-URL`,
`AUTH-SETUP`, `DASH-LOAD`, `EMP-EMERGENCY`, `ONBOARD-GATE`, `PERM-LOCATION`,
`PERM-MEDIA`, `PRESENCE`, `SIRI`, `TOUR`, `WIDGET-TAP`, and the whole `WAVE-*`
family. Since notices stopped carrying support codes (2026-08-04) the registry is
the **only** place a tag lives, so a stale list makes Crashlytics triage
guesswork.

**Related, and CORRECTED from an earlier draft of this audit.** `CLAUDE.md:399-401`
and `functions/CLAUDE.md:199` say `maintenance.js` *"resolves a Storage bucket at
load and therefore throws on `require()` outside the emulator."* I verified this
by actually requiring it: **it does still throw**, so the conclusion and the
`*_policy.js` split rule are correct and load-bearing — but the stated
**mechanism is wrong**. The throw comes from `onObjectFinalized`'s bucket-name
resolution at *trigger registration* (`firebase-functions/lib/v2/providers/storage.js:169`,
"Missing bucket name"), not from an admin `getStorage()` handle:
`maintenance.js:40` and `:69` both resolve **lazily** inside functions. Worth one
sentence of precision so nobody goes looking for a load-time `getStorage()` that
isn't there.

---

## 🟡 Code-quality suggestions (optional)

- `functions/appointment_images.js:312,313,316` — `claimRecount`, `releaseRecount`,
  `RECOUNT_SETTLE_MS` exported with no external reader (siblings
  `RECOUNT_CLAIM_STALE_MS`/`_TTL_MS` *are* test-driven, so this trio is the odd
  one out).
- `functions/appointment_image_tokens.js:375` — `defaultBucket` exported, internal
  fallback only.
- `functions/bridge_policy.js:105` — `VALID_BRIDGE_STATUS` exported with no reader
  (sibling `VALID_ROLES` *is* consumed by `bridge.js:136`).
- `functions/wave/customers.js:924-925` — `isStaleCustomerLink`,
  `hasNotFoundInputError`. The comment says they are *"exported so the unlink
  decision can be driven directly"* — but nothing drives them. **The suggested
  action here is a test, not deletion:** this is the path that rewrites a client's
  Wave identity (the 2026-08-15 dead-letter fix).
- `lib/features/calendar/application/event_details_controller.dart:138` — the
  tree's only marker, `TODO(gvogas): revisit at the photo-subcollection CONTRACT
  step.` Follows the convention but omits the `(#issue)` suffix. Content is
  legitimate and load-bearing.
- `pubspec.yaml:87-90` — `google_maps_flutter_ios_sdk9` sits in `dependencies`,
  not `dependency_overrides`, and there is no `dependency_overrides` section or
  `pubspec_overrides.yaml`. Worth a sanity check that the SPM swap actually takes
  effect — a build question, not dead code.
- `lib/l10n/app_en.arb:67` / `app_fr.arb:19` — `auth_accountReadySignInAgain`, the
  tree's only orphaned ARB key (see **B7**). Retire in a deliberate l10n pass, not
  a code sweep.

---

## Notes / uncertainties

**Verified clean — stated explicitly so it isn't re-audited:**

- **Static layer:** `flutter analyze` "No issues found!", `dart fix` "Nothing to
  fix!", `functions` ESLint clean.
- **Dead code:** zero unused files in `lib/` — verified two independent ways
  (inbound-import scan across all 674 files, **and** a reachability BFS from
  `main.dart`: 0 of 380 unreachable). Zero dead public symbols across 532 types,
  166 top-level functions, 180 top-level constants. Zero unused dependencies (all
  4 heuristic hits confirmed false positives). Zero commented-out code, zero bare
  `TODO`/`FIXME`/`HACK`/`XXX`, zero `TODO(pre-ship)`.
- **Conventions — all eleven axes clean:** exactly 3 SnackBar sites and all 3 are
  the sanctioned ones; zero raw `Exception` throws; zero `FirebaseFirestore.instance`
  in the widget layer; hardcoded colors confined to the token layer (one documented
  decorative exception); zero `isDark` styling branches; zero hand-spelled email
  normalization; zero raw debounce `Timer`s; zero `DateFormat` in a builder; zero
  hand-spelled `weekday % 7`; **zero BOMs across all 674 files**; zero import-order
  violations.
- **Hand-mirrors:** all eight Dart↔JS/CEL pairs diffed line-by-line — **no
  divergence**, including the 35-token `looksLikeBusinessName` list byte-identical
  on both sides.
- **Security:** all 14 callables set `enforceAppCheck: true` with correct guard
  order; `completeEmployeeSetup` fails **closed** on the token;
  `changeEmployeeEmail`'s freshness gate is keyed on `isAdmin` not `isSelf` (the
  past drift stayed fixed); `/users` read has exactly three clauses; the two-branch
  `allow update` keeps its load-bearing outer parentheses; cap alignment walked
  field-by-field with no violation; **no hardcoded secrets**; **no PII in any log
  site**, Dart or JS; the image render path has **no URL-shaped fallback anywhere**.
- **Resource safety:** zero widget-disposal gaps across 123 construction sites in
  44 files; zero bare `Stream.listen` (all 10 pass `onError`); zero
  silently-swallowed catches across 165 sites beyond the three sanctioned ones.

**Not verified / assumptions:**

- The 41 test failures were not individually root-caused — the mocktail
  `registerFallbackValue` cause is confirmed for the bulk, but ~10 assertion
  failures need per-test triage to decide test-vs-product. **B1 says which.**
- `docs/ARCHITECTURE.md:1151-1153` claims 2352 flutter / 1274 jest tests; observed
  figures are 2445+41 flutter / **1308** jest. Re-count at next release.
- `functions/scripts/restore-client-name-halves.js` — **dry run RAN against prod
  2026-08-21 and found nothing to restore** (0 of 703). The 2026-08-14 damage
  set the script was written for no longer exists in a recoverable form: every
  renamed client that has a name has its halves. Its three residual docs each
  fail a DIFFERENT rule, and the script is right about all three:
  - `o0KcOnJSgjvMHYpmcZ44` — **never had a name to lose.** Its one settled
    appointment (2026-08-11, `done`) already carries `clientName: "5144586186"`,
    written before the rename, so the client was created number-only.
  - `owhMXiJWzDC6CkizVAHH` — a **business** the heuristics cannot see: no
    `type`, no `businessName`, no appointment. `email:
    info@garderie123onyva.com` names it. Belongs to
    `restore-business-client-names.js`, whose `RESTORE` table is HARDCODED, so
    it gets nothing until the id is added there.
  - `tNjpCc9DFJtgnzBbwv5Z` — a person, recoverable only from
    `email: Ismaelandresabarca@gmail.com`.

  **The email is evidence this script deliberately does not read** — rule 4 is
  a settled appointment's `clientName`, and widening it to parse a local-part
  would be a guess written into client identity, which then pushes to Wave.
  Both remaining names are a one-line manual edit in the app, not a script.
- The CLAUDE.md → `.claude/rules/` split was still landing during this audit
  (`functions/CLAUDE.md`, `wave.md`, `notifications.md`, `firestore-indexes.md`
  appeared mid-run). Citations were re-verified against the layout as of the end
  of the audit; line numbers may shift as the split finishes.
