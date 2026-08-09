# Codebase Audit — 2026-08-08

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`, `assets/`, `pubspec.yaml`).
Baseline: `49f38fbc` on `redesgin`, clean working tree.

> ## ✅ IMPLEMENTED — 2026-08-08, same day
>
> **Every finding below is now fixed except the four deploy-gated checklist
> items** (which are prod operations, not code) **and I8** (which the audit
> itself recommends against). The report is preserved as written so the
> reasoning survives; per-finding status is in the
> **[Implementation record](#implementation-record)** at the bottom.
>
> Two owner decisions shaped it:
> - **S1 took the FULL fix, not the cheap one.** `completeEmployeeSetup` now
>   requires `email_verified`, and `AccountSetupScreen` sends Firebase's own
>   verification email and gates its CTA on a forced ID-token refresh. Creating
>   an admin at invite time is still allowed — the mailbox check is what closes
>   the race, so it no longer matters that the row is admin.
> - **S2 keeps a legacy fallback.** Photos render from `storagePath`, falling
>   back to the stored `url` only when a doc has none. `ImageStorageService`
>   still WRITES `url`, so builds that predate the resolver keep working;
>   retiring the write is a follow-up for once the fleet has moved.
>
> Verification: `flutter analyze` clean · **flutter test 1713/1713** ·
> **jest 818/818** · `functions npm run lint` clean.

Method: deterministic static scan, then five parallel deep reviewers
(security · bugs · dead-code/conventions · performance · maintainability).
**Every finding below was re-verified against source by the coordinator before
being written down.** Two reviewer findings did not survive that check and were
demoted — they are recorded in "Demoted" rather than silently dropped, because
knowing what was checked-and-cleared is worth as much as the findings.

> Supersedes `CODEBASE_AUDIT_2026-08-04-second-pass.md` (preserved alongside).
> That pass ran against `46154b1`. This one is a fresh sweep over the shipped
> result plus the 1.37.1 shim retirement and the closed-jobs agenda work.

## Summary

- **Scanned:** 339 Dart files in `lib/` (~56k LOC), 74 JS files in `functions/`,
  220 Dart test files, 35 jest suites, both rules files.
- **Auto-fixed (safe): 0.** `flutter analyze` reports no errors or warnings,
  `dart fix --dry-run` says "Nothing to fix", ESLint is clean, and the
  unused-file heuristic found nothing. **The safe bucket was empty before I
  started** — every remaining finding changes behavior, output, or shape, so it
  is report-only by the audit's own rule. The working tree is unchanged apart
  from this document and the archive rename.
- **Reported for your decision: 28**
  (⚠️ 3 deploy-gated · 🔴 5 security · 🟠 8 bugs · 🔵 12 improvements, plus 🟡 notes)
- **Verification:** `flutter analyze` clean · **flutter test 1663/1663** ·
  **jest 815/815** · `functions npm run lint` clean.

### The headline finding

The sharpest thing this pass found is **not code drift — it is that the
project's own written risk assessment understates a risk the owner signed off
on.** `CLAUDE.md` prices the shared-`Welcome123!` onboarding window as:

> the window is "can reach the setup screen as this person", not "can read the
> business"

That is inaccurate. Whoever wins that race calls `completeEmployeeSetup`, which
flips the doc to `active` with no `email_verified` check — leaving the invited
state entirely. And because `createEmployeeAccount` accepts `isAdmin: true` at
creation time, an account provisioned as an admin means the race ends in **full
admin access to the whole `/clients` PII collection**. The code has not drifted
from what the docs describe; the *characterization* has. An accepted risk that
is written down smaller than it is will not get re-examined. See **S1**.

### The second theme: five "one outlier of N siblings" defects

Five separate findings share a shape worth naming, because it is the shape a
systematic sweep catches and a diff review does not — a rule this codebase
applies correctly in every place but one:

- `delete_account_dialog.dart:155` is the **only** destructive filled button
  using `scheme.error` instead of `palette.dangerFill`; the three siblings are
  correct and one carries an inline comment warning against exactly this
  mistake (**B3**).
- `_historyStatuses` is the **only** one of four terminal-status owners that
  omits `'completed'` — and its correct twin sits 150 lines below it *in the
  same file*, commented (**B4**).
- `runDailyDigest` is the **only** one of three backend fan-outs without
  per-item error isolation; both siblings carry comments explaining why they
  need it (**B7**).
- `sendOverdueJobPrompts` is the **only** one of three schedulers with no
  top-level try/catch; both siblings wrap and log (**S3**).
- `image_viewer.dart`'s `_share` is the **only** catch site in its own file
  passing the generic error string; its neighbour `_saveToPhotos` composes a
  specific intro (🟡).

Two more are near-misses of the same kind: **B5**'s correct pattern sits two
files away in `OnboardingGate._finish`, and **B8**'s two missing `mounted`
guards are the only unguarded awaits in files that guard eight others.

---

## ⚠️ Deploy-gated checklist

No `TODO(pre-ship)`, `FIXME`, `HACK`, `XXX`, `TEMP` or `REMOVEME` markers exist
anywhere in `lib/`, `functions/` or `test/` — verified by grep. The pre-ship
scaffolding really is gone. What remains is deploy/prod-state gated.

- [x] **`#compat-1.37.1` shim — CLOSED.** Verified fully retired: the only two
  surviving matches are comments in `functions/wave/callables.js:449` and
  `lib/features/wave/data/wave_service.dart:79` explaining that
  `waveImportCustomers`' inaccurate name outlived the tag and stays deliberately.
  No `signupCodes` rules block, no `invites.js`, no unauthenticated callable.
  **The `/clients` `allow delete` grant the last two audits flagged as the
  highest-value one to withdraw is withdrawn.**
- [ ] **The shim retirement is not deployed.** It is deleted in code only. This
  is the repo's first *deletion* deploy (functions go 27 → 25), so
  `docs/DEPLOYMENT.md`'s old-build-compatibility check matters more than usual.
- [x] **`functions/scripts/backfill-clients-archived.js` — RUN against prod**
  (owner confirmed 2026-08-08). Every client doc now carries `archived`, so the
  `where('archived', isEqualTo: false)` filtered query is safe to deploy.
- [x] **`functions/scripts/backfill-client-phone-from-name.js` — RUN against
  prod** (owner confirmed 2026-08-08) — **on the buggy joined-field version,
  and it destroyed business names.** It searched `name` + `businessName`
  concatenated and then renamed `name` from first+last whichever field the
  number came from, so a client with a clean business in `name` and a polluted
  legacy `businessName` became its contact person. Fixed the same day (extract
  per field; rename gated on the number being in `name`), but the prod writes
  had already landed.
- [x] **Damage audit run — NOTHING to repair** (2026-08-08).
  `functions/scripts/audit-client-phone-backfill-damage.js` (read-only)
  reported "No client matches the damaged shape." The bug could only fire when
  the number lived in `businessName` and not in `name`; `businessName` is never
  written by the backfill, so its text is intact and the signature is exact —
  no doc matching it now means no doc matched it then. In practice every
  polluted client carried its number in `name`, which is the case the script
  was written for and handles correctly.
  **One narrow blind spot, left open deliberately:** a number synthesised
  ACROSS the field boundary (trailing digits in `name` meeting leading digits
  in `businessName`, e.g. `"Atelier 514"` + `"5551234 Quebec Inc"`) leaves a
  10-digit number in neither field, so the detector cannot see it afterwards.
  It needs a very specific coincidence and none is known to exist. The broad
  net if it ever matters: any client whose *settled* appointments carry a
  `clientName` different from the current one.

---

## 🔴 Security findings

### S1 — The invited-account window ends in full access, not "the setup screen" · medium · confidence high

- **Where:** `functions/employee_accounts.js:504-521` (`completeEmployeeSetup`,
  guards are auth → payload → rate limit, **no `email_verified`**), with
  `:40` (`DEFAULT_PASSWORD`), `:76-78` (`emailVerified: false`, no verification
  mail), and `:133`/`:207` (`const role = isAdmin ? "admin" : "employee"` while
  `status` is `invited`).
- **Risk:** Between `createEmployeeAccount` and the employee's first sign-in,
  anyone who knows the email can sign in on the shared default and call
  `completeEmployeeSetup`. Nothing proves control of the mailbox. They land
  `active` — reading every active peer's full doc (`firestore.rules:120`),
  assigned appointments and job photos — and if the row was created with
  `isAdmin: true`, they land **admin**, which reaches the entire `/clients` PII
  collection (`firestore.rules:510`). They also lock the real employee out by
  choosing the new password. Recovery is disable-only: `deleteEmployeeAccount`
  refuses once `status !== 'invited'` (`:574`).
- **Why report a signed-off risk:** the code has not drifted — the *written
  mitigation* has. `CLAUDE.md` says the window is "can reach the setup screen",
  which is not what the callable allows. The operational mitigation (create the
  account when you hand the credentials over) is sound but is doing more work
  than the docs credit it with.
- **Fix:** cheapest real fix is **stop accepting `isAdmin: true` at creation**
  — require a separate post-activation promotion — so a lost race can never
  yield an admin. Fuller fix: have `createEmployeeAccount` generate an
  `auth.generateEmailVerificationLink` and have `completeEmployeeSetup` require
  `req.auth.token.email_verified === true`. Either way, correct the `CLAUDE.md`
  sentence so the next reader prices it right.

### S2 — Appointment photos are served by permanent tokenized URLs that bypass `storage.rules` · low · confidence high

- **Where:** `lib/core/images/image_storage_service.dart:51-55`
  (`getDownloadURL()` → persisted as `url`), stored by
  `firebase_appointments_repository.dart:544`, rendered from `url` in
  `photo_picker_section.dart:184` and `image_viewer.dart:122`.
- **Risk:** `getDownloadURL()` mints a permanent `?alt=media&token=…` URL that
  is readable by anyone holding it, with **no auth and no rules evaluation**.
  `storage.rules:32-38` gates photo reads on `status == 'active'` with an
  explicit comment that this exists so a disabled employee stops reading job
  photos. Any URL captured while active keeps working after `deactivateEmployee`
  → `syncUsersByUid` disables the Auth account and revokes tokens. The
  revocation path is otherwise thorough, which makes this its one gap.
  `cacheControl: 'public, max-age=31536000'` (`:47`) compounds it slightly.
- **Honest severity:** low. The delta over "they already had the photos cached
  on-device" is modest, and they cannot obtain *new* URLs after deactivation.
- **Fix:** the doc already stores `storagePath`. Render through
  `FirebaseStorage.ref(storagePath)` so each read re-evaluates rules, and stop
  persisting `url`. Rotating the download token on deactivation is the weaker
  alternative.

### S3 — A `/` in an `employeeIds` element permanently kills the overdue-prompt sweep · low · confidence high

- **Where:** `functions/notifications.js:178-180` (bare
  `await runOverduePromptSweep(liveDeps())`, **no try/catch**) and
  `functions/notification_utils.js:376` (`const ledgerRef = db.collection(…).doc(ledgerId)`
  built **outside** the `try` on `:377`).
- **Risk:** `firestore.rules:426-430` applies the no-slash `isValidDocIdField`
  guard to `clientId`, `seriesId` and `seriesOpId` but only length-checks
  `employeeIds` — rules cannot iterate a list. `overduePromptLedgerId` then
  interpolates an element into a doc id, and `.doc()` throws *synchronously* on
  a `/`. That throw escapes `_deliverRecipientOnce`, rejects the `Promise.all`,
  and — with no catch on the scheduler — fails the entire 15-minute run, every
  run, until the poisoned doc is fixed. All "job finished?" prompts stop.
- **Two separate deviations from the codebase's own stated rules.** `CLAUDE.md`
  mandates "Build the claim's `.doc()` ref INSIDE the try — `.doc()` throws
  synchronously on an id containing `/`" for the sibling series-claim; this site
  does the opposite. And both `sendUpcomingJobReminders` (`:116-125`) and
  `sendDailyJobDigest` (`:139-148`) wrap-and-log with comments explaining why;
  this is the one that does not.
- **Exploitability:** writing `employeeIds` requires an admin session, so this
  is defense-in-depth, not a reachable hole.
- **Fix:** move `ledgerRef` inside the `try`, and wrap `runOverduePromptSweep`
  the way its two siblings are wrapped.

### S4 — The password policy is checked untrimmed but the trimmed value is stored · low · confidence high

- **Where:** `lib/features/auth/screens/account_setup_screen.dart:124-127`
  (`AuthValidators.newPassword(context, _passwordController.text)`) vs
  `lib/features/auth/services/auth_service.dart:82`
  (`user.updatePassword(newPassword.trim())`).
- **Risk:** `"Aa1!bcd "` passes the 8-character requirement as typed; `"Aa1!bcd"`
  (7) is what is set on the account. Not attacker-driven — a user can only
  weaken their own credential — but it silently undercuts the stated policy.
  Note the `kDefaultStartingPassword` rejection **on the very next line** *does*
  compare trimmed, so the two checks on one field disagree about what the
  password is.
- **Fix:** validate `_passwordController.text.trim()`, and feed
  `PasswordStrengthMeter` / `PasswordRequirementsChecklist` the same value.

### S5 — `npm audit`: 1 critical in `websocket-driver@0.7.4`, unreachable · low · confidence high · **carried forward (was S5)**

- **Where:** `functions/package.json:20` →
  `firebase-admin@13.10.0 → @firebase/database-compat → @firebase/database → faye-websocket → websocket-driver@0.7.4`.
- **Risk:** GHSA-mp7j-qc5w-4988 / GHSA-xv26-6w52-cph6. It arrives only through
  the Realtime Database client, which this project does not use (no RTDB rules,
  no `getDatabase()` anywhere), so no attacker-controlled WebSocket frames reach
  that parser. **Not exploitable here.**
- **Fix:** none required. `npm audit fix` resolves `websocket-driver` alone if
  you want a clean report. **Do not bump to `firebase-admin@14`** — that break
  is already recorded in project memory.

---

## 🟠 Bug findings

### B1 — `sliceFor`/`runsOn` are unclamped while `expandToDays` and `dailyWindowsOverlap` are clamped · low · confidence high

- **Where:** `lib/features/calendar/domain/appointment_day_slice.dart:131-137`
  (`sliceFor`, no clamp) vs `:222-224` (`expandToDays` clamps to
  `maxAppointmentSpanDays`) and `:189` (`_windowsOf` clamps).
- **Problem:** the 14-day cap is **client-side only** — `firestore.rules`
  constrains neither instant — so a doc written by the console, the Admin SDK,
  or a future/older build can exceed it. When that happens the one owner of
  day-scoping disagrees with itself: the calendar agenda renders 14 slices and
  logs the cap warning, while every `runsOn` consumer (`app_nav_drawer.dart:318`,
  `employee_schedule_providers.dart:35,82`, `dashboard_aggregator.dart:62,101`,
  `day_route_screen.dart:192`) counts and renders the full corrupt length — a
  drawer badge reading "1 job today" every day for a year, a card counter
  reading "Day 400 of 900". Conversely `dailyWindowsOverlap` compares only the
  first 14 windows, so a conflict check silently misses clashes past day 14.
- **Reachability:** needs out-of-band data, hence low. The asymmetry itself is
  unambiguous in the code.
- **Fix:** clamp `_dayCountOfWindow`'s result inside `sliceFor` the way
  `expandToDays` and `_windowsOf` already do, so all three answers come from one
  clamped count.

### B2 — A mixed transient + permanent photo failure discards the "too large" filenames · low · confidence high

- **Where:** `lib/features/calendar/data/appointment_image_upload_service.dart:173-202`.
- **Problem:** when `transientFailure || appendFailed`, the branch reports
  `failedCount: survivors.length + (appendFailed ? uploaded.length : 0)` and
  never passes `tooLargeNames`. The `permanentFailures`/`tooLargeNames`
  accumulated in the same pass (`:129-139`) are dropped. Concretely: a batch
  with one oversized photo and one network blip deletes the oversized file from
  staging at `:139` — so it can **never** retry — but tells the user only
  "N photos failed", counting the retryable ones, with the one actionable
  detail ("this file is too large") withheld. They wait for a retry that cannot
  happen.
- **Fix:** fold `permanentFailures`/`tooLargeNames` into the re-queue branch's
  `reportFailure` call, not only into the `else`.

### B3 — The account-deletion confirm button uses the wrong destructive token in dark mode · low · confidence high

- **Where:** `lib/features/settings/widgets/dialogs/delete_account_dialog.dart:153-157`
  — `FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError)`.
- **Problem:** `.claude/rules/frontend.md` states the rule by name: *"a
  destructive filled button must read `palette.dangerFill`, never
  `scheme.error`"*. In **light** the two coincide (`themes.dart:67`,
  `error: AppColors.red`; `design_tokens.dart:663`, `dangerFill: AppColors.red`),
  so this is invisible in light mode. In **dark**, `scheme.error` is
  `AppColors.darkRed` = `#FF6076` — explicitly commented at `themes.dart:245` as
  *"lifted — Material reads this as foreground"* — paired with
  `onError: #1C060A`. So the button renders **pale pink with near-black text**.
- **Be precise about the failure:** contrast is fine (dark-on-light). The defect
  is **severity signaling and consistency** — the app's single most destructive
  action renders as a light/secondary button, and differs from every other
  destructive button in the app. It is not the unreadability the rule's wording
  suggests.
- **The one outlier of four:** `series_scope_dialog.dart:122-125` (which carries
  an inline comment warning against this exact mistake),
  `clients_list_view.dart:190` and `confirm_dialog.dart:62` all do it correctly.
- **Fix:** one line — `palette.dangerFill` / `palette.onDangerFill`. Not
  auto-applied because it changes rendered output in dark.

### B4 — `_historyStatuses` omits `'completed'`, so a legacy doc is permanently invisible in History · medium · confidence high

- **Where:** `lib/features/calendar/data/firebase_appointments_repository.dart:369`
  — `static const List<String> _historyStatuses = ['done', 'cancelled'];`, used
  as `.where('status', whereIn: _historyStatuses)` at `:338` and `:419`.
- **Problem:** "terminal appointment status" has **four owners**, and this is the
  one that drifted. The *same file*, 150 lines down at `:517-523`, declares
  `static const Set<String> _terminalStatuses = {'done', 'completed',
  'cancelled'}` with the comment *"'completed' is a legacy alias for 'done'"*.
  `AppointmentRecord.isClosed` (`appointment_record.dart:101-104`) includes it.
  `AppointmentStatus.fromRaw` (`status_chip.dart:16-22`) maps it to `done`.
  Only the History query forgets it. So a legacy `'completed'` doc renders as
  **Done** on its card, is correctly skipped by the conflict check, and is
  **absent from the History screen and history search** — it self-heals only if
  someone edits it (`storedRaw` maps it to `pending`… then a save writes a valid
  status).
- **How reachable:** `firestore.rules:399-401` allows only
  `pending|in_progress|done|cancelled`, so any `'completed'` doc must predate
  the rules. Whether prod holds any is not verifiable from the repo — **but
  three of the four owners believe such docs exist**, so either they do and
  History is lying, or they don't and three constants are carrying dead
  legacy handling. Both are worth resolving.
- **Fix:** give the rule one owner. Add
  `AppointmentStatus.terminalRawValues` for the `whereIn`, and make `isClosed`
  and `_terminalStatuses` delegate to `fromRaw(...).isTerminal`. Consider
  lifting the enum out of `shared/widgets/feedback/` into
  `features/calendar/domain/` — a data repository importing a *widgets* file is
  the smell that let this fork in the first place.

### B5 — Toggling App Lock drops its `Future`, so a keychain failure is a FATAL crash with a silently reverting switch · medium-high · confidence high

- **Where:** three facts compose —
  `lib/features/settings/widgets/cards/security_settings_card.dart:13` declares
  `final void Function({required bool value}) onToggleAppLock;` and calls it at
  `:27`; the handler at
  `lib/features/settings/screens/settings_screen.dart:139` is
  `await ref.read(appLockEnabledProvider.notifier).setEnabled(value: value);`
  with **no try/catch**; and `setEnabled`
  (`app_lock_provider.dart:54-61`) delegates straight to
  `SecureStorageService.writeFlag` without catching either.
- **Problem:** assigning a `Future<void>`-returning handler to a
  `void Function` **silently drops the future**. `flutter_secure_storage` throws
  on an iOS keychain fault — including the pre-first-unlock `-25308` window that
  `AppLockController._load()` documents by name, two methods above. So toggling
  App Lock in that window throws into the zone handler, is filed as a **fatal**
  Crashlytics record, and the Switch snaps back with no message at all.
- **The correct pattern already exists two files away:**
  `OnboardingGate._finish` (`onboarding_gate.dart:48-56`) wraps the identical
  `writeFlag` call in a try/catch with a comment about this exact failure. The
  sibling `_toggleLiveActivity` (`settings_screen.dart:188`) is also safe —
  `LiveActivityPreferenceController.setEnabled` catches internally.
- **Fix:** catch around `setEnabled`, surface a notice, and change the callback
  type to `Future<void> Function({required bool value})` so the dropped-future
  shape is not re-introducible.

### B6 — A `default` clause on a sealed `AuthFailure` makes a failed password reset render as success · medium · confidence high

- **Where:** `lib/features/auth/domain/auth_failure.dart:218` — `_ => null,`
  closing a `switch` that handles 3 of the sealed family's **16** members.
- **Problem:** the single call site,
  `forgot_password_screen.dart:81`, assigns the result to `systemError` and then
  `if (systemError != null) { show error } else { show "we sent you an email" }`.
  So every unhandled member — `operation-not-allowed` (email/password provider
  disabled), `permission-denied`, `session-expired`, `not-authorized` — tells
  the user mail is on the way that will never arrive.
- **Why the `_` is the defect and not the `null`:** the null-means-success
  bucket is presumably deliberate for `AuthFailureUserNotFound` (account
  enumeration protection). But `_` makes **every** unnamed member inherit that
  privacy behavior, and a 17th member joins it silently with no compile error —
  which is the entire reason the family is sealed.
- **Fix:** replace `_` with explicit cases, including
  `AuthFailureUserNotFound() => null` carrying the enumeration-protection
  comment, so the compiler forces a decision on each future member.

### B7 — The nightly digest drops the remaining employees when one read fails · medium · confidence high

- **Where:** `functions/notification_utils.js:606-629` (`runDailyDigest`) —
  `.map(async (employeeDocId) => { … return sendToEmployee(…); })` awaited by a
  bare `Promise.all` at `:629`, with **no per-item try/catch**.
  `sendToEmployee`'s `userRef.get()` (`:87`) and `fcmTokens.get()` (`:90`) are
  unguarded.
- **Problem:** one transient Firestore read rejects the whole `Promise.all`,
  `runDailyDigest` throws, and `sendDailyJobDigest` (`notifications.js:141`)
  catches and moves on — with the other sends possibly still in flight when the
  instance freezes. **The digest has no ledger and runs once daily**, so those
  employees lose tomorrow's schedule entirely; there is no retry.
- **Both sibling fan-outs get this right:** `_deliverRecipientOnce`
  (`notification_utils.js:397`) wraps `sendToEmployee` with the comment *"A
  transient send failure must not abort the sweep for the remaining
  recipients"*, and `travel_utils.js:621` does the same. This is the third
  "one outlier of N siblings" instance in this audit.
- **Fix:** `Promise.allSettled`, or a per-item `.catch(() => 0)`.

### B8 — Two missing `mounted` guards on the longest async gap in the app · low-medium · confidence high

- **Where:**
  `lib/features/calendar/widgets/sheets/add_appointment_sheet.dart:194-196` and
  `lib/features/calendar/widgets/views/details_edit_body.dart:427-429` — both
  `await pickAppointmentImages(context, ref)` then call
  `notifier.addImages(picked)` with no guard.
- **Problem:** the notifier is a `NotifierProvider.autoDispose.family`, and
  `pickAppointmentImages` opens an OS action sheet *then* the camera/Photos
  picker — the longest await in the app. If the sheet is torn down while the
  picker is up (backgrounding plus iOS memory pressure), `addImages` on a
  disposed notifier throws `StateError` out of an unawaited callback, which is
  filed as **fatal**.
- **These are misses against the files' own rule:** both files guard every
  *other* await (`add_appointment_sheet.dart:216,226,228`;
  `details_edit_body.dart:261,288,312,316,322`), and
  `add_event_controller.dart:258` carries the comment *"Resolve these before any
  awaits, so we don't crash if the notifier gets disposed mid-await
  (Riverpod 3)"*.
- **Fix:** a `mounted` check before `addImages` at both sites.

---

## Demoted — reviewer findings that did not survive verification

Recorded so they are not re-raised next pass.

- **"Travel reminders and Live Activity cards never fire on days 2+ of a
  multi-day run."** Real behavior (`travel_utils.js:511-516` floors at
  `startTime > now`; `selectTravelCandidates:237-246` keys on the stored start),
  but **deliberate and documented**.
  `docs/plans/2026-08-02-multi-day-appointments.md` §8 records: *"Travel 'leave
  now' — **Day 1 only.** … Documented, not accidental"* and *"**Multi-day jobs
  skip Live Activities in this pass.**"* The reviewer also claimed `CLAUDE.md`
  overclaims by saying `travel_utils.js` was closed by the 2026-08-04 audit —
  it does not overclaim; §8 makes day-1-only the intended end state.
  **One genuine question survives, as a product question not a bug:** the stated
  rationale is *"the crew is already on site"*, which is not true under the
  daily-window model — a crew on day 3 of a five-day job drove home last night
  and drives back this morning. Worth an owner decision; the code matches the
  plan either way.
- **"Siri snapshot and home widget drop multi-day runs."** Real
  (`schedule_snapshot.dart:60` buckets on the stored start;
  `widget_sync_service.dart:55-56` and `widget_payload_utils.js:129-132` test
  `startTime` in range), but this is **already-logged Plan 2 §8 debt**, called
  out in `CLAUDE.md`'s "NOT YET MIRRORED" bullet and in the previous audit's
  Notes. Carried forward as known open debt, not re-reported as a discovery.

---

## 🔵 Areas to improve

### I1 — The Dashboard opens a 70-day, business-wide, live listener capped at 1000 docs · high · confidence high · **sharpened from prior I10**

- **Where:** `dashboard_aggregator.dart:23-36` (`rangeAround` = 8 weeks back
  through next Monday = **56 days**, `weekCount = 8` at `:13`) →
  `appointment_record.dart:223` (`fetchStart` widens every range back another 14
  days → **70 days**) → `dashboard_providers.dart:39` →
  `firebase_appointments_repository.dart:314-328`, a **`.snapshots()` listener**
  `.limit(_rangeStreamLimit)` = 1000.
- **Opportunity:** every Dashboard open outside the 3-minute keep-warm window
  reads every appointment starting in the last 70 days — at ~10 jobs/day, ~700
  docs, by a wide margin the largest single Firestore read in the app, held as a
  **live** listener the whole time the screen is up. **Past ~14.3 jobs/day it
  hits the 1000 cap**, and the 8-week trends, busiest-weekday and Attention list
  are then computed over a *prefix* — silently under-reporting the oldest work,
  which is precisely what the Attention list exists to surface
  (`dashboard_aggregator.dart:186-216` deliberately has no range predicate).
  Seven of the eight week-buckets are closed, immutable history that has no
  reason to be live.
- **Suggested improvement:** split the range — one live provider over the
  current week ± the pending horizon, plus a one-shot `.get()` (or a per-week
  `count()`) for the seven historical weeks. Drops the live doc set ~85% and
  removes the cap risk from the charts. If it stays one query, at minimum
  surface the cap rather than only `logger.warn`-ing it.

### I2 — Two permanently-alive mirror listeners over nested ranges · medium · confidence high

- **Where:** `siri/application/schedule_snapshot_provider.dart:22-37` (range
  `[today, today+8)`; 22 days with `fetchStart`) and
  `home_widget/application/widget_sync_service.dart:200-208` (range
  `[today, today+3)`; 17 days). Both held open for the whole session by
  `ref.listen` in `core/app/app_sync_listeners.dart:73,90`, gated on no screen.
- **Opportunity:** for an **employee** both call the *same*
  `myAppointmentsProvider` family with different range values, and the widget's
  window is a **strict subset** of the snapshot's. Because the family is keyed
  by range value — which is the entire point of the `fetchStart`-is-a-getter
  rule — these are two separate Firestore listeners streaming overlapping
  documents forever. One is pure waste: `buildWidgetPayload` already re-scopes
  to today/tomorrow in Dart, so it can be fed from the 8-day list unchanged.
  For an **admin** the snapshot additionally opens a business-wide 22-day
  listener on top of the always-mounted calendar stream, whose range is usually
  a superset of it.
- **Suggested improvement:** give both mirrors ONE range — a shared
  `AppointmentDateRange.forMirrors(today)` factory beside `forWeekBucketOf`,
  which exists for exactly this "two surfaces must produce equal ranges" reason.
  Removes one permanent listener per signed-in user with no behavior change.

### I3 — `employeesStreamProvider` is not `autoDispose` · low · confidence high

- **Where:** `lib/features/employees/application/employees_providers.dart:59-62`.
- **Opportunity:** its consumers are transient sheets
  (`add_appointment_sheet.dart:259`, `details_edit_body.dart:83`) plus the
  Dashboard. Opening the add-appointment sheet **once** attaches a second live
  `users` listener (alongside the always-on `watchAllUsers()`) for the rest of
  the session. `employees_screen.dart:179-185,284-291` already carry comments
  describing this exact bug being fixed *on that screen* — the sheets are the
  half left behind.
- **Suggested improvement:** make it `.autoDispose`. Keep the invariant that it
  is **not** derived from `allUsersStreamProvider` — that part is load-bearing.

### I4 — `EmployeeCard` watches the whole jobs-today map instead of its own entry · low · confidence high

- **Where:** `lib/features/employees/widgets/cards/employee_card.dart:29` —
  `ref.watch(employeeJobsTodayProvider)[employee.id] ?? 0`.
- **Opportunity:** the provider rebuilds a fresh `Map` on every emission of the
  today-range stream, so **every** roster row rebuilds when *any* appointment in
  today's range changes, including rows whose count did not move (~15–25 rebuilds
  per write while the Team tab is visible). `CLAUDE.md` mandates the opposite
  discipline one layer over, for `EmployeeFormActivity`: *"A row asks
  `isSavingId(id)` … through a Riverpod `select`, so it rebuilds only when its
  OWN state flips."* Note the comment directly above line 29 correctly claims
  one shared *listener* — that is about query count, not rebuild fan-out.
- **Suggested improvement:**
  `ref.watch(employeeJobsTodayProvider.select((m) => m[employee.id] ?? 0))`.

### I5 — The two repository scan windows are never released · low · confidence high

- **Where:** `firebase_clients_repository.dart:41,292-299` (up to 1000 client
  maps) and `firebase_appointments_repository.dart:47,428-435` (up to 1000
  appointment maps). Both repositories are non-`autoDispose` singletons.
- **Opportunity:** `_isFresh` decides only whether a window may be *used*; an
  expired window is not dropped, so after one client search plus one history
  search roughly 2–4 MB of raw doc maps stay pinned for the session even if the
  user never searches again. Memory only — no extra reads.
- **Suggested improvement:** null the window in the `_isFresh`-false branch that
  already detects staleness. Zero behavioral change; the next search re-reads
  regardless.

### I6 — `activeUserIdentityProvider` re-queries for a doc id the stream already held · low · confidence high

- **Where:** `lib/features/auth/application/active_user_identity_provider.dart:16-35`
  issues `repo.findUserByUid(uid)` (`firebase_employees_repository.dart:308-313`,
  a fresh `where('uid').limit(1).get()`) purely to learn the doc id — which
  `watchUserDoc` (`:332-352`) already had and discarded at
  `snapshot.docs.first.id`.
- **Suggested improvement:** have `watchUserDoc` emit `(id, data)` and drop the
  extra round-trip. One document read per user-doc emission plus one per cold
  start. `retryStream` on the listener already covers post-sign-in token lag.

### I7 — ~2.1 MB of dead tracked image assets, now three files · low · confidence high

- **Where:** `assets/images/paul2.png` (1.07 MB), `logo_splash.png` (610 KB),
  and — **new this pass** — `icon_foreground.png` (429 KB).
- **Opportunity:** all three are `git ls-files`-tracked, declared in no pubspec
  `assets:` block (only `icon.png` is), and ship in no binary.
  `icon_foreground.png` was the Android adaptive-icon foreground; it went dead
  when `android/` was deleted, and `pubspec.yaml`'s `flutter_launcher_icons`
  block is now `android: false` with `image_path: assets/images/icon.png`. Its
  only surviving reference is inside `.claude/worktrees/…`, which is gitignored
  scaffolding, not the live tree.
- **Suggested improvement:** delete all three. Repo weight only.

### I8 — `purgeExpiredHistory` issues a Storage list+delete per purged doc, including image-less ones · low · confidence medium

- **Where:** `functions/maintenance_policy.js:89-91` maps `deleteImages(doc.id)`
  over all 200 docs in a page; `functions/maintenance.js:76-88` implements it as
  `bucket().deleteFiles({prefix})`. `snap.docs` already carries `doc.data()`, so
  `pictures` is in hand for free.
- **The tradeoff is real and argues against the fix:** `CLAUDE.md`'s
  offline-upload invariant explicitly worries about Storage bytes orphaning when
  the `arrayUnion` doc-link append fails. Skipping the prefix delete on an empty
  `pictures` array leaves exactly those orphans unreclaimed forever. The job is
  quarterly with an 1800 s budget, so this is headroom, not a bottleneck.
- **Suggested improvement:** only worth doing paired with a separate orphan
  sweep. Listed for visibility, not recommended as-is.

### I9 — Three CLAUDE.md-named single-owner rules have no test at all · high · confidence high

The test baseline is strong (220 Dart files against 336 in `lib/`; 35 jest files
against 39 backend sources), so these stand out precisely because everything
around them is covered.

- **`AddressParser.canonicalFrom`** (`features/maps/domain/address_parser.dart:106`)
  — the explicit-apt-beats-embedded-apt precedence rule that `CLAUDE.md` names
  as having exactly ONE owner. **Every sibling in that file is tested**
  (`splitApt`, `combineAptAndStreet`, `formatForDisplay`, `canonicalToDisplay`,
  `toCanonical`, plus a round-trip group) — the one an invariant is written
  about is not. Pure function, ~6 cases, no harness.
- **`launchExternalUri`** (`core/launchers/external_uri_launcher.dart`) — pin
  that a *throwing* `launchUrl` yields `logger.warn` + a notice + `false`
  instead of escaping. This function **exists because** a hand-rolled copy had
  lost its `try`/`catch` and a thrown `launchUrl` was recorded as a FATAL. It is
  the single owner behind `launchPhoneCall`, `AddressMapLauncher`,
  `EmailComposeLauncher` and `launchGoogleMapsRoute`.
- **`TourSteps`** (`feature_tour/domain/tour_steps.dart`) — pin that `stepIf`
  returns the child untouched for an id outside the catalog (where `step` force-
  unwraps `keys[id]!` and throws). It is the class that exists to stop a
  documented crash-on-`!`, and I10 below shows three screens still bypassing it.

Lower-value but real: `fillAddressControllersFromText`
(`maps/address_field_filler.dart`, four different precedence rules in one
function, none pinned), `EmailComposeLauncher`, and
`AppointmentDraftDefaults.defaultEndTime` (an 11:30 PM start must yield
12:30 AM, not hour 24).

### I10 — Four hand-copied derivations that have already drifted · medium-high · confidence high

Same shape as the `displayStatusAt` ladder and `_who` before they were given one
owner. Reported at 3+ instances only, per the anti-defaults.

- **Tour search-bar wiring, 3 screens** (`clients_screen.dart:96,115`;
  `history_screen.dart:61,81`; `employees_screen.dart:150,165`) — all three
  re-spell the `has(id) ? TourShowcaseBar(...) : bar` block verbatim.
  `tour_steps.dart:39-44` explicitly says *"Prefer this over
  `has(id) ? step(id, child: c) : c`, which was being re-spelled per screen"* —
  but `TourSteps` has no `PreferredSizeWidget` variant, so the app-bar `bottom:`
  slot escapes its own owner. **Fix:** add `stepBarIf` beside `stepIf`.
- **`_isAuthPropagationDenied` copied byte-identically into 3 repositories**
  (`firebase_appointments_repository.dart:606`,
  `firebase_employees_repository.dart:360`, `presence_repository.dart:110`).
  Two carry a "keep in sync" comment naming only **one** twin — so neither
  author knew there were three. **Fix:** move it to `core/utils/retry.dart`,
  beside the `retryStream`/`retryAsync` it exists to serve.
- **Positional `employeeIds ↔ employeeNames` pairing, 5 sites, 4 different
  missing-name fallbacks** (`appointment_crew.dart:33`,
  `event_details_controller.dart:110`, `day_route_screen.dart:243`,
  `appointment_history_view.dart:183`, `assignee_resolver.dart:18`). The
  *differing fallbacks* are arguably intentional per surface; the **lookup
  half** (`i < employeeNames.length ? …`) is one rule with five owners. The
  edit-sheet copy is the dangerous one — a blank name flows into
  `mergeRetainedAssignees` and is written back. **Fix:** export
  `assigneeNameAt(...)` returning `null`, and let each surface keep its own
  fallback.
- **Multi-day run-length `+1`, 3 sites** (`appointment_form_validator.dart:82`,
  `add_appointment_sheet.dart:183`, `details_edit_body.dart:87` — the last two
  sharing the same copied five-line comment, which is the tell). **Fix:**
  `runLengthDays(...)` in the validator that already owns `appointmentSpan`.
- Also: **hand-built skeleton lists in 5 places**, already visibly drifted
  (`employees_screen.dart:187` uses gap `sp12` where the other four use `sp8`).
  **Fix:** a `SkeletonList({rows, padding})` generalizing the private
  `_skeletonRows` in `clients_list_view.dart:238-249`.

### I11 — Four complexity hotspots worth extract-only refactors · medium · confidence high

Ranked by how likely they are to harbor a future bug. **Good news first:**
`functions/` has **no god file** — its largest is 459 *code* lines
(`wave/callables.js`); `wave/worker.js` is 888 raw lines but 45% comments — and
zero functions nested more than 5 levels deep.

- **`details_edit_body.dart:240` `_save()` (118 lines) — the highest-risk
  function in the UI layer.** Four sequential async phases in one body:
  reentrancy check → series-scope dialog (with its own busy-flag handoff around
  an extra Firestore read and a `context.mounted` bail that must reset the flag)
  → save attempt → busy-conflict dialog + forced retry → a 4-case outcome switch
  with a nested ternary picking one of four success messages. **Six**
  `context.mounted` guards and **two** independent busy-flag owners. Each guard
  is individually correct and commented; the risk is the *next* edit adding a
  seventh in the wrong place. **Seams:** `_resolveSeriesScope(...)` (lines
  253-291, `null` = cancelled) and `_announce(outcome)` (324-356), leaving
  `_save` at ~40 linear lines.
- **`wave/worker.js:545` `dispatchQueuedJobs` (169 lines)** — the money-adjacent
  path: query → transactional claim (with a `claimed` flag reset *inside* the
  callback because Firestore may re-run it) → dispatch → two divergent outcome
  paths. Mitigating: `wave_worker.test.js` is 1,930 lines, the largest test file
  in the repo — well-tested complexity, which lowers urgency but not reading
  cost. **Seams:** `claimJob` / `dispatchJob` / `resolveOutcome`.
- **`travel_utils.js:505` `runTravelAwareReminderSweep` (146 lines)** — the
  most-branched backend sweep, with a 99-line `resolveOrigin` 3-prong fallback
  beneath it, and four separate historical bugs documented in `CLAUDE.md`.
  **Seam:** `decideReminderForPair(...)`.
- **`wave/customers.js:607` `importCustomers` (146 lines)** — five counters that
  the watermark logic then reads, where `CLAUDE.md` documents that a single
  miscounted `skippedPending` silently loses Wave-side data. **Seam:**
  `importOneCustomer(node, ctx)`.

### I12 — `design_tokens.dart` is 865 code lines and is really four files · medium · confidence high

- **Where:** `lib/core/theme/design_tokens.dart` — five small token classes
  (through line ~180) followed by **four independent `ThemeExtension`s**, each
  with its own ~40-field `copyWith` + `lerp` boilerplate: `AppCardStyle`
  (235-394), `AppStatusColors` (395-605, whose `lerp` alone is 74 lines),
  `AppPalette` (606-794), `AppMonoType` (795-965).
- **Opportunity:** adding one token means editing a 965-line file in three
  places, and the `lerp` bodies are where a missed field silently degrades a
  theme fade into a snap. The extensions never reference each other, so the
  split is a pure move.
- **Suggested improvement:** move each to
  `core/theme/extensions/{app_card_style,app_status_colors,app_palette,app_mono_type}.dart`
  and keep `design_tokens.dart` as the raw tokens **plus a barrel export**.
  `CLAUDE.md` names this file as *the* token file, so **the single import path
  surviving is a precondition, not a nicety** — don't do the split without it.
- **Also:** 53 `build()` methods exceed the project's ~60-line rule — the
  largest systematic deviation from `code-quality.md` in the repo. Most sit at
  60-75 and are not worth churn. **Don't sweep**; apply opportunistically. The
  one worth doing deliberately is `appointment_card.dart:108` (94 lines): that
  file already extracts `_TitleRow`/`_ClosedMetaRow`/`_CrewAvatars`/`_CrewRow`,
  so its `build()` is inconsistent with its own file, and it is the most-read
  widget in the app.

---

## 🟡 Code-quality suggestions

- **`destinationByName`** (`lib/core/navigation/app_destination.dart:31`) —
  zero production callers; referenced only by its own test. Its doc comment
  claims the tour-seen store uses it, but `TourSeenController._load()` resolves
  via `tourScopeByKey` — a leftover from the 2026-08-04 `TourScope` refactor.
  Its siblings `allDestinations`/`destinationRoute` are live. Delete it and the
  stale comment, or pin it. **Owner call.**
- **`EventDetailsController.exitEditing()`** (`event_details_controller.dart:176`)
  — carried forward. Still zero production callers, test-only.
- **`EmployeeFormActivity.isDeletingAccount`** (`employee_form_controller.dart:110`)
  — carried forward. Still zero `lib/` callers, 4 test refs. `CLAUDE.md` says it
  and `isSaving` both "survive … for the two person sheets"; `isSaving` really is
  used, this never is. Delete it and amend the sentence, or leave and note the
  asymmetry. **Do not touch the id-keyed pair** — that is the load-bearing half.
- **`AppointmentDaySlice.isFirstDay` — CLOSED.** Flagged last pass as the
  clearest "just delete it"; it is gone. Recorded so it is not re-raised.
- **`calendar_date`** (`app_en.arb:568` / `app_fr.arb:125`) — carried forward.
  Still zero references; superseded by `calendar_startDate`/`calendar_endDate`/
  `calendar_selectDate` when the date field became a range. Prune in a
  deliberate l10n pass.
- **`nav_myDetails`** — unreferenced but **forward-provisioned for P5**
  (`drawer_catalog.dart` carries `// PushedDestination.myDetails joins here in
  P5.`). **Keep.** Recorded so it is not mistaken for drift.
- **`image_viewer.dart:188-190`** — `_share` passes
  `error_somethingWentWrongPleaseTryAgain` straight into the notice, which
  `.claude/rules/error-handling.md` forbids at new catch sites. Its neighbour
  `_saveToPhotos` (`:148-150`) does it correctly with a specific intro
  (`calendar_couldNotSavePhoto`). The `IMG-SHARE` log tag is present and correct
  — only the intro key is missing. Add `calendar_couldNotSharePhoto` to both ARBs.
- **`functions/scripts/backfill.js`** (usersByUid bridge backfill) — not
  exported, not required by any test, no doc records whether it ran. `usersByUid`
  is now long-deployed and foundational, which strongly implies it did its job.
  Unlike the two backfills in the checklist above, nothing tracks this one.
  Confirm and delete, or add a "ran on <date>" header. **Owner call — medium
  confidence, prod state is not verifiable from the repo.**
- **Raw `Colors.white`** at `form_helpers.dart:69` (scrim-circle icon) and
  `image_viewer.dart:209,307` (lightbox foreground over a dark scrim) — fixed
  contrast is defensible here, but it bypasses the token layer. Low priority.
- **~15 mixed spacing/radius sites** (`calendar_month_grid.dart:17`,
  `app_nav_drawer.dart:68,73,130,345`, `key_value_panel.dart:82`,
  `sheet_field_row.dart:56`, `appointment_card.dart:229,244-246`,
  `series_scope_dialog.dart:172`, `appointment_form_fields.dart:573`,
  `agenda_sliver_list.dart:167`, `calendar_header_block.dart:73`,
  `app_header_pair.dart:54`, `text_size_view.dart:232`,
  `auth_form_widgets.dart:301`) — each mixes numbers that coincide with a token
  and others that are documented intentional nudges, in the same call.
  **Deliberately not auto-applied:** swapping one leg mid-tuple is a judgment
  call, not a mechanical one. Same reasoning as the prior pass.

---

## Closed since the last audit — verified, not assumed

The 2026-08-04 second pass's improvement list has largely landed. Verified this
pass so the next one does not re-raise them:

- **I2 — `enforceDurableRateLimit` had zero tests → CLOSED.**
  `functions/__tests__/rate_limit.test.js`, 17 tests.
- **I3 — the `employee_accounts.js` callables' ordering was untested → CLOSED.**
  `functions/__tests__/employee_accounts_callables.test.js`, 9 tests, with
  explicit ordered call traces under `describe("createEmployeeAccount ordering")`
  and `describe("changeEmployeeEmail ordering")` — exactly the Auth-before-
  Firestore property that needed pinning.
- **I4 — `deleteAccount`, the repo's other irreversible deletion, was untested
  → CLOSED.** `functions/__tests__/account.test.js` + `account_policy.test.js`.
- **I5 — `PendingUploadStore._serialized` had no concurrency test → CLOSED.**
  `test/features/calendar/data/pending_upload_store_test.dart:130-151`
  deliberately interleaves an add and a remove through one `Future.wait` and
  comments that the un-awaited interleaving *is* the point.
- **I1 — the day route forked a fresh 15-day query per day tap → CLOSED.**
  `AppointmentDateRange.forWeekBucketOf` (`appointment_record.dart:186`) exists
  and `day_route_screen.dart:113` uses it.
- **I7 — the travel sweep resolved every (candidate × assignee) pair serially
  → CLOSED.** `travel_utils.js:621` is now
  `await Promise.all(pairs.map(...))`. **Small leftover:** the comment at
  `functions/notifications.js:112` still reads `// Serial pairs, each with up to
  one Routes round-trip.` above `timeoutSeconds: 120` — stale since that fix.
  Worth a one-line correction so the timeout's rationale still reads true.
- **`AppointmentDaySlice.isFirstDay` → CLOSED** (deleted).
- **The `#compat-1.37.1` shim → CLOSED in code**, including the `/clients`
  `allow delete` grant the last two passes flagged as the highest-value item.

`backfill_client_phone.test.js` also now exists, so the pending prod backfill is
itself covered by tests.

---

## Clean results — recorded so the next audit can skip them

- **Statics are spotless.** `flutter analyze`: no errors or warnings.
  `dart fix --dry-run`: "Nothing to fix". `functions npm run lint`: clean. No
  Dart file lacks an inbound import. **The safe-auto-fix bucket was empty.**
- **Zero code markers.** No `TODO`, `FIXME`, `HACK`, `XXX`, `TEMP` or
  `REMOVEME` anywhere in `lib/`, `functions/` or `test/`.
- **Retired features are fully gone.** The 1.37.1 shim, the signup-code invite
  flow, `table_calendar`, `AdaptiveShell`/nav rail, `AppointmentTile`,
  `ImageCompressService`, `testing_flags.dart`, `backfillLegacyClientNames`,
  `EntityFormHeader`/`AuthBrandHeader` and `google_fonts` — zero stray
  references in code, rules or `firestore.indexes.json`. Zero stranded test files.
- **Dead code is near-zero.** 431 public classes/enums/mixins, 129 public
  top-level functions and 85 Riverpod providers checked — one finding
  (`destinationByName`). All 25 backend exports accounted for; all 215 internal
  `functions/` helpers have a caller.
- **l10n: 657 keys in each ARB, identical sets, EN/FR parity perfect.** Two
  unreferenced keys, one of them deliberate (`nav_myDetails`).
- **Hand-mirrored pairs all agree today** — re-verified individually:
  `maxAppointmentSpanDays` (14) ↔ `MAX_APPOINTMENT_SPAN_DAYS` (14);
  `kDefaultStartingPassword` ↔ `DEFAULT_PASSWORD`; `_who` in
  `notification_messages.js:77-79` ↔ `live_activity_utils.js:73-75`; Siri schema
  `version: 2` ↔ `supportedVersion = 2` with matching field sets; Dart ↔ JS
  widget-payload field lists and `rolloverAt`.
- **Range-stream superset re-scoping is complete** except the two known Plan 2
  §8 mirrors. Drawer badge, roster counts, TODAY panel, day route, calendar and
  dashboard all re-scope through `runsOn`/`expandToDays`.
- **Reentrancy is correct everywhere.** All five submit/save controllers set the
  in-flight flag synchronously before the first await and reset on every early
  return and catch.
- **Status normalization is airtight.** `AppointmentStatus.overdue.raw` is
  unreachable — the only call sites iterate `appointmentValues` (which excludes
  it) or branch explicitly. Seed, `propagate` and the Siri builder all use
  `storedRaw`.
- **Calendar arithmetic:** no `add(Duration(days:))` in any day/month
  derivation; all use `DateTime(y, m, d ± n)`.
- **Callable guards:** all 12 `onCall` exports set `enforceAppCheck: true` and
  follow auth → `assertAdmin` → `assertPayloadShape`/`requireString` →
  `enforceDurableRateLimit` → work. No unauthenticated callable remains.
- **Rules:** deny-by-default holds; no `if true` or bare `request.auth != null`.
  Field denylists on **both** create and update for `/users` and `/clients`;
  neither `toMap()` emits them. `liveActivityTokens.expiresAt` is required *and*
  bounded at +31 d against a 30 d client write. Every rules cap ≥ its
  `TextLimits` counterpart. Query-vs-get constraints correct on all three
  `users` streams. Disabled-employee revocation complete.
- **Secrets/PII:** none in source. `dev/.env` gitignored, only `.env.example`
  tracked. Function logs carry `uid`/`docId` only — the `changeEmployeeEmail`
  revert logs ids, never addresses. Starting passwords never reach a log or
  persistent store.
- **Credential fields:** every `obscureText` field pairs
  `enableIMEPersonalizedLearning: false` unconditionally.
- **Convention drift: 8 of 12 categories fully clean** — exactly 3 sanctioned
  `SnackBar` sites, zero `FirebaseFirestore.instance` in UI, zero
  `throw Exception(`, zero `isDark` styling branches, zero bare `AppBar(`, zero
  raw debounce `Timer`, zero hand-rolled `launchUrl`, zero missing IME flags.
- **Disposal/leaks: zero defects.** Every `TextEditingController` /
  `ScrollController` / `AnimationController` / `PageController` / `Debouncer` /
  `StreamSubscription` has a `dispose`. `currentDayProvider`'s midnight timer is
  cancelled in `onDispose`.
- **Already-optimal, do not re-audit:** range-listener sharing via the
  `fetchStart` getter; search indexing once per result set with `compute` off
  the UI thread; `DateFormat` memoization per locale; the calendar day index
  rebuilt only on list-identity change; content-equality memoization on the
  employee colour/name maps; pagination hoisting `PagingState.items` out of the
  item builder; cached `ThemeData`; the travel sweep's batched presence
  `getAll`, capped context queries and TTL'd Routes memo; `recountClientJobs`'
  `count()` aggregate; Wave's lazy id index and hash gate.

---

## Notes / uncertainties

- **Nothing was auto-changed.** The tree's only modifications are this file and
  the rename of the prior report to
  `CODEBASE_AUDIT_2026-08-04-second-pass.md`. Every finding above changes
  behavior, output or shape, so all are report-only per
  `references/safe-vs-risky.md`.
- **Two reviewer findings were demoted after verification** (see Demoted). The
  travel-sweep one is the reason this section exists: it was the bug leg's
  headline, and `docs/plans/2026-08-02-multi-day-appointments.md` §8 contradicts
  it outright. Reviewer output was not taken at face value.
- **Prod state is not verifiable from the repo** — the two backfills' live runs,
  and whether the shim retirement has been deployed. Those checklist items are
  stated as unknown, not as failures.
- **Perf magnitudes assume** ~10–25 `users` docs, ~650 clients, ~10–20
  appointments/day. I1's cap risk is the one finding whose severity flips with
  volume: it becomes a correctness bug above ~14.3 jobs/day.
- **The prior pass's I9 ("two backend god-modules") is now answered and should
  be closed as stated.** Measured by *code* lines rather than raw lines, there
  is no backend god file: `wave/worker.js` is 888 raw lines but only 417 code
  lines (45% comments), and the largest backend file by code is
  `wave/callables.js` at 459. The real split candidates are the four long
  *functions* in I11, not the modules.
- **Findings were counted once, not per reviewer.** The bug and maintainability
  legs overlapped on the terminal-status family; it appears once, as B4.
- Generated files (`*.freezed.dart`, `lib/l10n/.gen/**`) excluded throughout.
- No secrets, tokens or PII appear in this report; findings name locations only.

---

## Implementation record

Applied 2026-08-08 on top of `49f38fbc`. Statuses are what actually shipped,
not what was proposed.

### Security

| # | Status | What was done |
|---|---|---|
| S1 | ✅ **fixed, beyond the report's recommendation** | `completeEmployeeSetup` requires `req.auth.token.email_verified` (an identity guard, so it sits ABOVE the rate limiter - an unverified caller cannot burn the real employee's five slots). `AccountSetupScreen` grew a verification panel: send / resend Firebase's own verification email, then "Check again", which calls `AuthService.refreshEmailVerified()` - `reload()` **plus a forced `getIdToken(true)`**, because the callable reads the claim off the token minted at sign-in. New `AuthFailureEmailNotVerified`. The report's cheap fix (ban `isAdmin: true` at creation) was **not** taken: with the mailbox check in place the race cannot be won at all, so restricting admin provisioning would cost the admin a real affordance and buy nothing. `CLAUDE.md`'s risk sentence rewritten - that mischaracterization was this audit's headline. 3 new jest tests. |
| S2 | ✅ **fixed, with a legacy fallback** | New `AppointmentImageUrlResolver` (`core/images/`) resolves each photo's URL from `storagePath` at render time, so `storage.rules` is re-evaluated per read; falls back to the stored `url` when `storagePath` is empty. `PhotoPickerSection` is now stateful and resolves on `existingImages` change. `ImageStorageService` still persists `url` **on purpose** - dropping it would blank photos on builds that predate the resolver; marked for retirement. 4 new tests. |
| S3 | ✅ fixed | `ledgerRef` moved inside the `try` in `_deliverRecipientOnce`, and `sendOverdueJobPrompts` wrapped + logged like its two sibling schedulers. |
| S4 | ✅ fixed | `_validate` checks `_passwordController.text.trim()`, and the strength meter / requirements checklist read the same trimmed value. |
| S5 | ⬜ no action needed | Unreachable (no RTDB in this project). `npm audit fix` remains optional; do **not** bump `firebase-admin` to 14. |

### Bugs

| # | Status | What was done |
|---|---|---|
| B1 | ✅ fixed | New `_clampedDayCount` is the single clamp; `sliceFor`, `runsOn`, `runsInRange`, `_windowsOf` and `expandToDays` all route through it. `AppointmentFormValidator` deliberately keeps the RAW count - it is the one caller that must SEE an out-of-range value to refuse it. 5 new tests. |
| B2 | ✅ fixed | The re-queue branch now folds in `permanentFailures` and passes `tooLargeNames`, so a mixed oversized + transient batch reports both and names the file that can never retry. 1 new test. |
| B3 | ✅ fixed | `palette.dangerFill` / `onDangerFill`, matching its three siblings. |
| B4 | ✅ fixed, one owner created | New pure `calendar/domain/appointment_status_values.dart` owns `terminalStatusRawValues`; `AppointmentRecord.isClosed`, the History `whereIn` and the conflict check all read it. Deliberately Material-free so the model layer can use it without importing `status_chip.dart` - the smell that let the fork happen. 7 new tests pin it against the `AppointmentStatus` mirror. |
| B5 | ✅ fixed | Callback retyped `Future<void> Function(...)` so the dropped-future shape is unexpressible; the handler catches, logs `APPLOCK`, and composes a notice via the new `error_introSaveAppLock`. |
| B6 | ✅ fixed | The `_` is gone - all 17 members are explicit. `AuthFailureUserNotFound` keeps the deliberate `null` (account-enumeration protection) with the reason written down; everything else returns a message. A future member now fails to compile. |
| B7 | ✅ fixed | Per-employee try/catch inside `runDailyDigest`'s map, so one transient read cannot cost the other employees tomorrow's schedule. |
| B8 | ✅ fixed | `mounted` / `context.mounted` guards on both post-picker `addImages` calls. |

### Improvements

| # | Status | What was done |
|---|---|---|
| I1 | ✅ fixed | Range split in two: `liveRangeAround` (this week onwards) is watched, `historyRangeAround` (the seven settled weeks) is a one-shot `fetchInRange` - a new repository method. Merged by doc id via `DashboardAggregator.mergeById`, because the two queries overlap by a fortnight. ~85% fewer live docs and the cap risk is off the trend charts. 6 new tests. |
| I2 | ✅ fixed | `AppointmentDateRange.forMirrors(today)` is the one window both mirrors ask for, so an employee's Siri snapshot and home widget share ONE listener. `mirrorLookaheadDays` owns the length; `scheduleSnapshotLookaheadDays` is that value. 4 new tests. |
| I3 | ✅ fixed | `employeesStreamProvider` is `autoDispose`. The "not derived from `allUsersStreamProvider`" invariant is untouched and now documented in place. |
| I4 | ✅ fixed | `EmployeeCard` reads its own entry through a Riverpod `select`. |
| I5 | ✅ fixed | Both repositories null the scan window in the already-existing staleness branch. |
| I6 | ✅ fixed, differently | The report proposed reshaping `watchUserDoc` to emit `(id, data)`. That ripples through ~10 `currentUserDocProvider` call sites **including the account-deletion kick-out**, which `CLAUDE.md` flags as delicate - a poor trade for a "low" item. Instead `watchUserDoc` memoizes the id it already resolved (`cachedUserDocId(uid)`, uid-scoped) and `activeUserIdentityProvider` reads it, keeping `findUserByUid` only as the cold-path fallback. Same read saved, no blast radius. 2 new tests. |
| I7 | ✅ fixed | `paul2.png`, `logo_splash.png`, `icon_foreground.png` deleted (~2.1 MB). |
| I8 | ⬜ **deliberately not done** | The report recommends against it: skipping the prefix delete would strand exactly the orphans the offline-upload invariant worries about. Only worth doing paired with a separate orphan sweep. |
| I9 | ✅ fixed | `AddressParser.canonicalFrom` (8 tests), `launchExternalUri` (3 - including the thrown-`launchUrl`-must-not-escape case it exists for), `TourSteps.stepIf`/`stepBarIf` (6), `AppointmentDraftDefaults.defaultEndTime` (4, including the 11:30 PM wrap). |
| I10 | ✅ fixed, all five | `stepBarIf` added to `TourSteps` (3 screens); `isAuthPropagationDenied` moved to `core/utils/retry.dart` (3 repositories); `assigneeNameAt` exported from `assignee_resolver.dart` (5 sites, each keeping its own fallback); `runLengthDays` added beside `appointmentSpan` (3 sites); `SkeletonList` added to `skeleton_loader.dart` (3 sites, resolving the drifted `sp12`/`sp8` gap). |
| I11 | ✅ fixed, all four | `details_edit_body._save()` 118 -> ~45 lines, split into `_resolveSeriesScope` (which owns its own busy-flag handoff; `null` = stop) and `_announce`. `dispatchQueuedJobs` 169 -> ~40, split into `claimJob` / `dispatchJob` / `resolveOutcome`. `runTravelAwareReminderSweep` 146 -> ~85, with `loadPresenceByEmployee` / `loadContextByEmployee` extracted (and now issued concurrently). `importCustomers` 146 -> ~75, with `importOneCustomer` extracted - the function whose five counters feed the watermark. |
| I12 | ✅ fixed | `design_tokens.dart` 965 -> **232** lines; the four `ThemeExtension`s moved to `core/theme/extensions/` and re-exported, so the single import path `CLAUDE.md` names is preserved. `appointment_card.dart`'s `build()` 94 -> 81 via `_barColors` / `_cardColor`. The other 52 long `build()`s were **not** swept, per the report. |

### Code-quality notes

- ✅ `destinationByName` deleted with its stale doc comment and its test.
- ✅ `EventDetailsController.exitEditing()` deleted (test-only) with its test.
- ✅ `image_viewer._share` now composes `calendar_couldNotSharePhoto` (new key, EN + FR) instead of the forbidden generic string.
- ✅ `calendar_date` pruned from both ARBs.
- ✅ `functions/notifications.js:112`'s stale "Serial pairs" comment corrected.
- ✅ `EmployeeFormActivity.isDeletingAccount` **kept**, with the asymmetry written into its doc comment - removing it would weaken four real test assertions for no gain. This is the report's own second option.
- ✅ `functions/scripts/backfill.js` given a provenance header instead of being deleted: prod state is not verifiable from the repo, and it is idempotent and re-runnable.
- ⬜ `nav_myDetails` kept (forward-provisioned for P5, as the report says).
- ⬜ Raw `Colors.white` sites and the ~15 mixed spacing/radius tuples left alone - the report calls both judgment calls rather than mechanical swaps.

### Still open

**One** deploy-gated item at the top, and it is a prod operation rather than a
code change: deploying the shim retirement (the repo's first *deletion*
deploy, 27 → 25 functions).

Both client backfills have now been run. The `archived` one was clean. The
phone one ran on the buggy joined-field version, but the damage audit came
back empty — no client was renamed — so the fix landed before it could cost
anything. The corrected script is what any future run uses.
