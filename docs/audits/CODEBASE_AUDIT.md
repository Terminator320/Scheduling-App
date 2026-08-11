# Codebase Audit — 2026-08-11

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `lib/l10n/*.arb`, `pubspec.yaml`, `docs/`).
Baseline: working tree at `8bf07c6e` on `redesgin`, version `1.44.1+71`, tree clean.

## Summary

- **Scanned:** whole repo — 5 parallel deep reviewers (security, bugs, dead
  code/conventions, performance, maintainability) on top of the deterministic
  static pass.
- **Status (2026-08-11): ALL 20 findings actioned.** See *Resolution* below for
  what was built, what was scoped deliberately, and the two findings that
  turned out to rest on a wrong premise.
- **Reported: 20**
  (⚠️ 0 pre-ship · 🔴 3 security · 🟠 6 bugs · 🔵 10 improvements · 🟡 code-quality notes)
- **Verification after the fix pass:** `flutter analyze` clean · `flutter test`
  **1844 passed / 0 failed** (was 1801/1) · `functions` jest **882/882** (was
  874) · `functions` ESLint clean · no BOMs · no EN/FR ARB drift.

**Top 3 to look at first:** B1 (a test that rots with the calendar and has
silently voided its own file's coverage), B2 (P5's availability warning is dead
for every technician), B4 (`CLAUDE.md` asserts a Live-Activity protection that
no code implements).

## Resolution — 2026-08-11 fix pass

**Backend changes are NOT deployed.** S1, B4 and B5 all need
`firebase deploy --only functions`.

| # | What was done |
|---|---|
| S1 | `isReauthStale` lifted into `security.js` beside a new `assertFreshReauth`; `changeEmployeeEmail` now demands a re-auth under 5 min **on the self branch**, and its budget drops 20/h → 5/h. **Scoped deliberately:** the ADMIN branch is reached from `updateEmployee`, which has no re-auth step, so gating it would reject every admin email edit made minutes after sign-in. Closing that half needs a re-auth prompt on the admin save path first — the residue is stated in `CLAUDE.md` rather than left implied. |
| S2 | No action, as reported — only matters if the repo's visibility changes. |
| S3 | No action, as reported — informational; no code path passes a `buf`. |
| B1 | Clock pinned via `currentDayProvider.overrideWithValue` in `containerWith`. The three vacuous tests now sit inside the window and fail for the right reasons. |
| B2 | `myUpcomingAppointmentsProvider` role-branches to `myAppointmentsProvider`, matching the Siri snapshot and the drawer badge. |
| B3 | `computeTodayOps` holds the `AppointmentDaySlice` and tests/sorts `windowStart`; `TodayOps.upcoming` carries slices, so the dashboard card now shows "Day 3 of 5" too. Two new tests. |
| B4 | The skip is now REAL: `dayCountOf(c) > 1` in `resolveReminderForAssignee`. The `leaveNow` push still goes out; only the card is withheld. `CLAUDE.md` corrected to say it was built on 2026-08-11 and that the plan doc was right. |
| B5 | `colorValue` is parsed from its stored numeric-string form, so a push-started card shows the crew colour instead of always-orange. |
| B6 | The resolver returns `''` on `unauthorized`/`permission-denied` and keeps the fallback for transport failures. An empty URL is a REFUSAL: `PhotoPickerSection` renders the error tile untappable and `buildImageProviders` substitutes a 1×1 transparent image so viewer indices don't shift. Two new tests. |
| I1 | `self_email_service_test.dart` added — `verifyInOrder` plus a thrown re-auth that must `verifyNever` the callable. |
| I2 | **Premise was wrong.** `healSyncState` is already pinned by five pre-existing tests in `wave_customers.test.js` (via `upsertCustomer`), including the concurrent-edit case. Added the one genuine gap: a doc with no `lastSyncedHash` is left alone. |
| I3 | **Premise was wrong.** `notification_messages.js` is covered by ~30 tests in `notification_utils.test.js` — `_who`, multi-day ranges, the night-shift end, the personal-job fallback and all-day are all there. Moving them to a new file would be churn; added the genuinely-missing cases instead (every repeat interval, unknown kind, null ctx, unknown locale). |
| I4 | The log moved to the ONE place that isn't a build method: `emergencyContactProvider` transforms its stream, logs `EMP-EMERGENCY` once per error emission and rethrows. The detail view's loading/error collapse is now documented as deliberate (the panel is omitted either way) rather than silently ambiguous. |
| I5 | All four drifts corrected in `ARCHITECTURE.md` / `CLOUD_FUNCTIONS.md`, including a full description of P5's dirty-gated-identity vs. immediate-availability split and the genuinely admin-only field list. |
| I6 | 923 → 591 lines. The five presentational widgets moved to `features/auth/widgets/account_setup/*.dart` (one class per file); `build()` is ~22 lines over `_identityPanels` / `_formFields` / `_submitBlock`. |
| I7 | `AvailabilityPanel` (`employees/widgets/fields/`) is now the one panel both screens render. This closed a real drift the audit didn't name: My details picked its times with a raw `showTimePicker` while the Team sheet used `showAdaptiveTimePicker`, so the same row opened a Material dialog on one screen and a Cupertino wheel on the other. |
| I8 | `event_details_save_pipeline.dart` owns assignee merge, record build, series branch and photo changes over explicit values; the controller keeps state, reentrancy and `ref.mounted`. Storage resolution stays LAZY and mounted-guarded — resolving it eagerly initialized FirebaseStorage on photo-free saves, which the tests caught. |
| I9 | Tests for all six: `firestore_parsing`, `breakpoints` (including the exact 1.4 boundary), `dialableUri` + `parseWebUrl` (both extracted as pure helpers), `mediaPermissionResultOf` (extracted; pins `limited`→granted and `restricted`→permanent) and `hub_shell_scope`'s three nav branches. |
| I10 | `WAVE-BADGE unknown syncState` is logged once per distinct value per process — a Set guard, so a build method can't spam it. |
| 🟡 | `nav_myDetails` removed from both ARBs and the stale `drawer_catalog.dart` comment rewritten; "exported for unit tests" comments added to `live_activity_registry.js` and `maintenance_policy.js`. **Not done, deliberately:** the `heroGradient` swap (a design decision, as the note itself says) and deleting `ParsedAddress`'s components / `AppointmentImage.fileName` / `EmployeeRecord.createdAt` — those are reserved fields whose removal would ripple through a tested server field mask for no behavioural gain, so each now carries a comment saying so rather than being silently left ambiguous. |

## Auto-applied cleanups

**None at audit time** — the statics were already green and both candidate
cleanups failed verification as "safe" (see *Notes*). Everything in the
*Resolution* table above was applied afterwards, on request, as a deliberate
fix pass rather than an automatic one.

## ⚠️ Pre-ship checklist

**Empty, verified.** There are zero `TODO(pre-ship)`, `FIXME`, `HACK`, `XXX`,
`TEMP` or `REMOVEME` markers anywhere in `lib/`, `test/`, `functions/`,
`firestore.rules` or `storage.rules`. The last known one
(`lib/core/testing_flags.dart`) was deleted 2026-08-03 with the client
archive/delete work. All 11 callables enforce App Check; there is no
`enforceAppCheck: false` carve-out left to flip.

## 🔴 Security findings

### S1 — `changeEmployeeEmail` has no server-side re-auth freshness check · severity: medium · confidence: high

- **Where:** `functions/employee_accounts.js:392-416`
- **Risk:** Guard chain is auth → payload → `resolveEmailChangeCaller` → rate
  limit → work, with no `auth_time` staleness check. Its sibling irreversible
  callable does have one: `functions/account.js:52-61` rejects
  `isReauthStale(authTime, nowSec, 300)` *before* the limiter. P5 opened this
  callable to the SELF branch (`employee_accounts.js:375-376`), so any active
  employee can rewrite their own sign-in identity, and the only proof-of-password
  is client-side at `lib/features/settings/services/self_email_service.dart:51`.
  That file's own comment names the threat: *"an unattended unlocked phone
  changing the sign-in address is the account-takeover primitive."* A caller with
  a valid ID token but no fresh re-auth (unattended unlocked device, stolen
  token, patched client) can call the callable directly, move the address to a
  mailbox they control, then trigger a password reset. The admin branch is the
  stronger version of the same primitive — rewriting a *colleague's* sign-in
  identity. App Check raises the bar but is attestation, not authorization.
  Budget is `CREATE_RATE_MAX` = **20 sign-in-identity rewrites per hour per
  caller** (`:414-416`), which is generous for a self-service path.
- **Fix:** Lift `isReauthStale` out of `account.js` into `security.js` and apply
  it in `changeEmployeeEmail` above the limiter, matching `deleteAccount`.
  Consider a tighter budget on the self branch. Needs a functions deploy.
- **Note:** `CLAUDE.md` documents the client-side ordering honestly and does not
  claim server enforcement — but unlike the `Welcome123!` window, it does not
  record this as an accepted residual either. Worth a decision either way.

### S2 — `ios/GoogleService-Info.plist` is reachable in git history · severity: low · confidence: high

- **Where:** commit `bc5a7aaa` (deleted at `6f89c3cb`); not in the working tree,
  correctly gitignored via `**/GoogleService-Info.plist`.
- **Risk:** Same class as `dev/.env` — restricted client config that ships inside
  the IPA anyway, with App Check + rules as the real defense. Impact is limited
  while the repo is private; it matters only if this repo ever becomes public.
- **Fix:** Purge from history and rotate only if the repo's visibility changes.
  No action needed today. (Value not reproduced here.)

### S3 — 9 moderate npm advisories in `functions/`, all transitive · severity: low · confidence: high

- **Where:** `functions/package.json:19-22` → `firebase-admin@13.6.0` →
  `@google-cloud/firestore` / `@google-cloud/storage` / `google-gax` → `uuid`
  (missing buffer bounds check in v3/v5/v6 when `buf` is supplied).
- **Risk:** No code path in this repo passes a `buf`. Zero high/critical.
- **Fix:** Informational. A `firebase-admin` bump is a separate deliberate change
  — note the existing memory that admin@14 breaks on functions 7.x.

## 🟠 Bug findings

### B1 — A time-rotting test is failing, and has silently voided its own file's coverage · severity: high · confidence: high

- **Where:** `test/features/settings/application/my_details_providers_test.dart:46`
  (failing), `:53`, `:59`, `:65` (now vacuous)
- **Problem:** The test pins a job to Monday **2026-08-10** and overrides
  `myUpcomingAppointmentsProvider`, but never overrides `currentDayProvider`. So
  `myDetailsRangeProvider` (`lib/features/settings/application/my_details_providers.dart:74`)
  builds `AppointmentDateRange.forMirrors(DateTime.now())`, whose window starts at
  *today*. The test passed on the day it was written and has failed every day
  since: as of 2026-08-11 the job is in the past, `expandToDays` scopes it out,
  and the expected `{1}` comes back `{}`.
  **The bigger problem is the three tests that still "pass".** "reports nothing
  when the day being switched off is free", "reports nothing when no day is
  switched off" and "a cancelled job is not a conflict" now pass because *every*
  job is out of range — not because the logic works. Four of the file's five
  tests are asserting nothing. This is the only red in an otherwise green
  1802-test suite, so it also masks the next real regression here.
- **Fix:** Pin the clock, using the idiom that already exists one directory over
  at `test/features/employees/application/employee_schedule_providers_test.dart:35`
  — add `currentDayProvider.overrideWithValue(DateTime(2026, 8, 10))` to the
  container overrides in `containerWith`. Then re-confirm the three vacuous tests
  actually exercise their branches.

### B2 — P5's availability-conflict warning is dead for every technician · severity: high · confidence: high

- **Where:** `lib/features/settings/application/my_details_providers.dart:85`
- **Problem:** `myUpcomingAppointmentsProvider` reads
  `appointmentsInRangeProvider`, whose query
  (`lib/features/calendar/data/firebase_appointments_repository.dart:314-329`)
  constrains `startTime` only — no `employeeIds` constraint. But
  `firestore.rules:482` grants `/appointments` read as
  `isAdmin() || isAssignedEmployee(resource.data)`, and for a **list query**
  Firestore evaluates rules against query *constraints*, not documents. A
  non-admin's whole query is therefore rejected `permission-denied`.
  `MyDetailsScreen` is the one deliberately employee-reachable self-service
  surface — `my_details_screen.dart:349` uses `isAdmin` only to gate the
  SCHEDULING section, and `:401-408` watches `myAvailabilityConflictProvider`
  unconditionally. The rejection is swallowed by `?? const []` at
  `my_details_providers.dart:87`, so for every technician the *"you're switching
  off a day that still has booked work"* warning **silently never fires**, and a
  permanently-failing Firestore listener is held open for the session.
  Rules hold — this is a fail-closed silent feature failure, not data exposure.
  It is exactly the query-constraints-must-mirror-a-rule-clause trap `CLAUDE.md`
  documents.
- **Fix:** Role-branch the way two sibling call sites already do —
  `lib/features/siri/application/schedule_snapshot_provider.dart:26-33` and
  `lib/features/navigation/widgets/app_nav_drawer.dart:305-308` both pick
  `myAppointmentsProvider((employeeId:, range:))` for non-admins. That also makes
  the manual `job.employeeIds.contains(docId)` filter at `:91` redundant.
  Note the `:66-70` comment claiming the range is shared with the mirrors is only
  true for an admin — an employee currently forks a second, denied listener.

### B3 — Dashboard "Upcoming today" drops days 2+ of a multi-day run · severity: medium · confidence: high

- **Where:** `lib/features/dashboard/domain/dashboard_aggregator.dart:120` (and
  the sort at `:122`)
- **Problem:** The same loop re-scopes correctly at `:114`
  (`if (!runsOn(a, dayStart)) continue;`) — and the comment directly above it at
  `:112` even says *"testing `startTime` alone hid days 2+ of a multi-day run"* —
  but two lines later the `upcoming` list tests `a.startTime.isAfter(now)`, i.e.
  the run's **first morning**, not this day's window. The fix was applied to the
  status counts and not to the upcoming list.
  Concretely: a 5-day job, 14:00–18:00 daily, started Monday. Wednesday 09:00,
  admin opens the Dashboard — the status counts include it, but
  `upcoming_today_section.dart:38` renders "No visits today". Secondarily, `:122`
  sorts by the stored instant, so a continuing run would float above today's
  genuinely-earlier jobs.
- **Fix:** Hold the slice from the `runsOn` check and use its window:
  `final slice = sliceFor(a, dayStart); if (slice == null) continue; … if
  (slice.windowStart.isAfter(now) && !_isTerminal(a)) upcoming.add(a);`, sorting
  on the same `windowStart`. Optionally pass the slice into
  `AppointmentCard(slice:)` so the dashboard shows "Day 3 of 5" like the agenda.

### B4 — `CLAUDE.md` asserts a Live-Activity protection that no code implements · severity: medium · confidence: high

- **Where:** `functions/travel_utils.js:237` (`selectTravelCandidates`),
  `functions/live_activity_dispatch.js:203` (`startLiveActivity`); doc claim in
  root `CLAUDE.md`
- **Problem:** `CLAUDE.md` states as fact: *"**Live Activities deliberately skip
  multi-day jobs** — a four-day Lock Screen countdown is worse than no card; see
  `docs/plans/2026-08-02-multi-day-appointments.md` §10."* **No such skip
  exists.** Verified: zero references to `isMultiDay`, `dayCountOf` or `dayCount`
  anywhere in `travel_utils.js`, `live_activity_dispatch.js` or
  `live_activity_utils.js`. The candidate filter excludes only `isAllDay` and
  non-pending. The cited plan doc contradicts `CLAUDE.md` directly — line 206
  lists Live Activities as `Deferred → §10`, and line 222 reads *"deferred out of
  Plan 2, still open."*
  Concretely: Aug 1–5, 09:00–17:00. At ~08:00 on Aug 1 the sweep starts the card;
  `resolveReminderForAssignee` (`travel_utils.js:489`) builds ctx via
  `liveActivityCtx`, carrying the raw `endTime` = **Aug 5 17:00**. After the
  on-site flip, `ios/ScheduleWidget/JobLiveActivity.swift:163` renders
  `Text(timerInterval: …, countsDown: true)` — a 4-day countdown parked on the
  Lock Screen for the whole run, exactly the harm the doc claims is prevented.
- **Fix:** Two options — gate the card (`if (dayCountOf(c) > 1)` before
  `startLiveActivity`, using the already-exported `day_slice_utils.dayCountOf`),
  or send *today's* window end (`sliceForDay(record, nowMs).windowEndMs`) instead
  of the run's `endTime`. **Either way, correct the `CLAUDE.md` bullet** — as
  written it will stop the next reader from noticing this is unbuilt.

### B5 — Live Activity crew-colour rail is dead code; every card is orange · severity: low · confidence: high

- **Where:** `functions/live_activity_dispatch.js:75`
- **Problem:** `return typeof value === "number" ? value : 0;` — but `colorValue`
  is stored as a **numeric string** by design, everywhere: `firestore.rules:156`
  requires `s is string && s.matches('^-?[0-9]+$')`;
  `employee_record.dart:94` and `firebase_employees_repository.dart:212` both
  write `.toARGB32().toString()`; `employee_accounts.js:212` reads it with
  `requireString`. The `number` branch is unreachable, so this always returns
  `0`, and `LiveActivitiesAppAttributes.swift:202` does
  `guard let value = employeeColorValue, value != 0 else { return .orange }`.
  Every push-started Lock Screen card shows an orange rail instead of the crew
  colour. The comment above it ("A failed read just yields 0") reads as a rare
  fallback; it is the only path.
- **Fix:** `const n = typeof value === "number" ? value : Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(n) ? n : 0;`

### B6 — Photo URL resolver falls back to the rules-bypassing token URL on a permission error · severity: low-medium · confidence: high (behaviour) / medium (severity)

- **Where:** `lib/core/images/appointment_image_url_resolver.dart:43-48`
- **Problem:** The `catch` is unconditional, and its comment claims *"someone who
  is not entitled gets the same 403 the rules would have given them."* That is
  not true of `image.url`: it is the permanent `?alt=media&token=…` URL from
  `getDownloadURL()` which — as the class doc says at `:15-23` — *"anyone holding
  it can read with no auth and no rules evaluation."* So the one error this
  resolver exists to convert into a blank tile (a `permission-denied` from
  `storage.rules`' `status == 'active'` gate) is instead converted back into a
  working, rules-free URL. Blast radius is narrowed by the appointment doc read
  itself being rules-gated, so this is a weakening rather than an open hole — but
  the stated guarantee does not hold, and the comment will mislead whoever
  retires the `url` write.
- **Fix:** Only fall back when the failure is *not* a permission rejection
  (`FirebaseException` code `unauthorized` / `permission-denied` → return empty),
  and reword the comment to describe what the fallback actually does.

## 🔵 Areas to improve

### I1 — `SelfEmailService`'s re-auth-before-callable ordering has no test · impact: high · confidence: high

- **Where:** `lib/features/settings/services/self_email_service.dart` (no test file)
- **Opportunity:** Its own docstring says this ordering is what stops an
  unattended unlocked phone moving the sign-in address. This is the same class of
  invariant as `AuthService.completeAccountSetup`'s password-then-activate order,
  which *is* pinned with a `verifyInOrder` test. This one isn't, so swapping the
  two calls ships silently. Directly compounds S1, whose whole mitigation is this
  client-side ordering.
- **Suggested improvement:** Mirror the existing `verifyInOrder` pattern, plus
  the half that matters — a thrown re-auth must `verifyNever` the callable.

### I2 — `healSyncState`'s transactional race-safety has no test · impact: high · confidence: high

- **Where:** `functions/wave/customers.js` (absent from
  `functions/__tests__/wave_customers.test.js`)
- **Opportunity:** It re-reads and re-hashes *inside* the transaction rather than
  trusting the caller's hash, specifically so an edit landing in that window is
  not marked synced. That subtle property is unverified. A regression either
  re-introduces the stuck-badge bug it was written to fix, or — worse — marks a
  doc synced while an edit is still in the outbox, which is the exact lie the
  badge exists to remove.
- **Suggested improvement:** A jest test asserting the in-transaction re-hash and
  that a concurrent-edit case leaves the state un-healed.

### I3 — `functions/notification_messages.js` has no dedicated test · impact: high · confidence: medium-high

- **Where:** `functions/notification_messages.js` (only touched incidentally via
  `employee_accounts.test.js`)
- **Opportunity:** `_who` / `_when` / `_at` / `_whoAt` / `_repeatLabel` /
  `buildNotificationMessage` / `buildDigestMessage` compose every EN/FR push and
  digest, including the personal-job title fallback and the new multi-day range
  line. `CLAUDE.md` documents this *exact* function drifting before — it is the
  codebase's single most-repeated bug shape (`_who`, the display-status ladder,
  the live-activity ctx), and this is the major instance with no direct test.
- **Suggested improvement:** A jest file exercising `_who`, multi-day formatting
  and the personal-job fallback directly.

### I4 — Every `emergencyContactProvider` error branch swallows without logging · impact: medium · confidence: high

- **Where:** `lib/features/employees/widgets/views/employee_details_view.dart:59-61`,
  `lib/features/employees/widgets/sheets/edit_person_sheet.dart:151-155`,
  `lib/features/settings/screens/my_details_screen.dart:365-371`
- **Opportunity:** `.claude/rules/error-handling.md` is explicit: *"A user-visible
  failure notice is not a substitute for a log… every swallowed failure needs a
  `warn` beside it."* All three consumers skip it, so a failing read on this path
  is invisible in Crashlytics. Separately, `employee_details_view.dart:59` uses
  `.value ?? EmergencyContact.empty`, which collapses **loading** and **error**
  into the same value.
  *Scope note:* this is less severe than it first appears — `:211` omits the
  panel entirely when the rows are empty, so a failed read renders as *not shown*
  rather than *none on file*, which is what the `CLAUDE.md` invariant demands. The
  real residue is the missing log plus loading being indistinguishable from
  failure.
- **Suggested improvement:** Add a tagged `logger.warn` in each error branch; on
  the detail view, branch loading vs. error rather than collapsing both.

### I5 — `docs/ARCHITECTURE.md` no longer describes the P5 self-service surface · impact: medium · confidence: high

- **Where:** `docs/ARCHITECTURE.md:71`, `:848-849`, `:857-859`, `:1023`
- **Opportunity:** Four verified drifts:
  1. `:71` calls `my_details_screen` *"the ONLY self-service edit surface (own
     emergency contact; everything else about a person is admin-owned)"*. Since
     P5 (2026-08-10) the same screen self-edits phone, full availability,
     `travelAlertsEnabled` and — via `SelfEmailService` — the person's own
     sign-in email. A reader trusting this misjudges the self-service attack
     surface, which is security-adjacent.
  2. `:857-859` still credits the 1.37.1 build for the live `platform:` field —
     root `CLAUDE.md` already corrected that sentence and `ARCHITECTURE.md`
     wasn't updated with it.
  3. `:1023` cites error tag `EMP-DEL`; the actual tag is `EMP-DELETE`
     (`employee_form_controller.dart:289`).
  4. `docs/CLOUD_FUNCTIONS.md:44,160-161` claims `revokeInvite`/`previewInvite`
     *"never existed in code"* — they existed under P4b (`461f84ba`) and were
     removed by P4c (`ea375b1b`).
- **Suggested improvement:** Update all four; describe the P5 dirty-gated-identity
  vs. immediate-availability split and list the genuinely admin-only fields
  (`maxJobsPerDay`, `role`, `jobTitle`, `colorValue`, `status`).

### I6 — `account_setup_screen.dart` is 923 lines with a 140-line `build()` · impact: medium · confidence: high

- **Where:** `lib/features/auth/screens/account_setup_screen.dart` (923 lines;
  `build()` at `:409-548`)
- **Opportunity:** One `State` plus six more widget classes (`_SetupBanner`,
  `_LockedEmailPanel`, `_SignedInChip`, `_VerifyEmailPanel`, `_ConsentRow`,
  `_ConsentRowState`) in one file, against the project's one-class-per-file rule
  and the ~60-line `build()` rule. This is the P4c activation screen — password
  rotation ordering, `email_verified` gating, consent stamping — i.e. the screen
  `CLAUDE.md` spends the most words on. Size raises the risk of the next edit.
- **Suggested improvement:** Move the five presentational widgets to
  `features/auth/widgets/account_setup/*.dart`; extract the ~74-line stacked
  text-field block into a `_SetupFormFields` widget.

### I7 — The AVAILABILITY panel is hand-duplicated across two screens · impact: medium · confidence: high

- **Where:** `lib/features/employees/widgets/sheets/edit_person_sheet.dart:488-542`
  and `lib/features/settings/widgets/.../my_availability_section.dart`
- **Opportunity:** `CLAUDE.md` requires both screens *"render that panel
  identically"* but the enforcement is manual. This is the documented drift shape
  (`SheetPanelRow` was extracted for exactly this reason when the panel appeared
  on My details in P5) with the last step left undone.
- **Suggested improvement:** Extract one shared availability-panel widget used by
  both. Also shrinks `edit_person_sheet.dart` (668 lines).

### I8 — `event_details_controller.dart` mixes state setters with a 250-line save pipeline · impact: medium · confidence: medium

- **Where:** `lib/features/calendar/application/event_details_controller.dart`
  (680 lines; `save()` at `:348-461` plus `_applyPhotoChanges` /
  `_settleAndValidate` / `_buildUpdatedRecord` / `_applySeriesChange`)
- **Opportunity:** This is the controller `CLAUDE.md` flags most heavily for
  correctness (assignee retention, `storedRaw` normalization, series propagation,
  reentrancy). Each rule would be easier to unit-test in isolation, with a smaller
  blast radius, if the pipeline were its own class.
- **Suggested improvement:** Extract `event_details_save_pipeline.dart`; leave the
  controller as state mutation + delegation. Structural judgment call, not a defect.

### I9 — Six core helpers gating app-wide behaviour have no tests · impact: medium · confidence: high

- **Where:** `lib/core/layout/breakpoints.dart`,
  `lib/core/utils/firestore_parsing.dart`,
  `lib/core/launchers/phone_call_launcher.dart`,
  `lib/core/permissions/media_permission_service.dart`,
  `lib/core/launchers/web_url_launcher.dart`,
  `lib/core/navigation/hub_shell_scope.dart`
- **Opportunity:** Ranked by what breaks silently: `firestoreDateTime` is the
  single Firestore-date boundary (`Timestamp`/`DateTime`/legacy `String`/`null`)
  — a dropped legacy-string fallback silently nulls dates on older docs.
  `breakpoints.dart`'s compound getters gate layout app-wide and `CLAUDE.md`
  records a real historical regression from exactly that shape (the 1.4× text-
  scale case). `web_url_launcher` gates the Terms/Privacy links that give the
  consent record its legal meaning.
- **Suggested improvement:** Pure unit tests; all six are Firebase-free.

### I10 — `WaveSyncBadge` silently renders nothing for an unknown `syncState` · impact: low-medium · confidence: medium

- **Where:** `lib/features/wave/widgets/wave_sync_badge.dart:63-87`
- **Opportunity:** `default: return null` over a server-owned string vocabulary.
  A future server-side state (e.g. `conflict`) would ship invisibly on an
  admin-only surface with no signal anywhere.
- **Suggested improvement:** Log on the unrecognized branch so a mismatch reaches
  Crashlytics instead of just looking blank.

## 🟡 Code-quality suggestions

- `lib/features/dashboard/widgets/sections/dashboard_hero.dart:59-68` — hand-rolls
  `Color.alphaBlend(Colors.black.withValues(alpha: 0.2), scheme.primary)` where
  the `AppPalette.heroGradient` token exists for exactly this hero role and is
  used by `auth_form_widgets.dart:151`. **Not a mechanical swap** — the token
  uses different colours (`AppColors.blue`→`navy`) *and* different alignments
  (`Alignment(-0.5,-1)`→`(0.5,1)` vs `topLeft`→`bottomRight`), so adopting it
  changes the dashboard's appearance. Treat as a design decision, not a cleanup.
- `lib/l10n/app_en.arb:2628` + `lib/l10n/app_fr.arb:591` — `nav_myDetails` is
  orphaned (zero call sites; P5 shipped using `settings_myDetails`). A stale
  comment at `lib/features/navigation/domain/drawer_catalog.dart:36` still names
  it. Both ARBs are otherwise perfectly matched at 687 keys with no EN/FR drift.
  Per project rules, ARB keys are not stripped in a code sweep — flagged for a
  deliberate l10n pass.
- `lib/features/maps/domain/models/parsed_address.dart:10-13` —
  `street`/`city`/`province`/`postalCode` are populated by
  `google_places_repository.dart` but the only caller
  (`address_autocomplete_field.dart:169-176`) reads `.fullAddress` alone; the
  map round-trip is exercised only by a test. Either wire them up or trim the
  model. (Distinct from the live `ParsedAddressFields` in `address_parser.dart`.)
- `lib/features/employees/domain/models/employee_record.dart:43` —
  `createdAt` is parsed but never read (unlike `ClientRecord.createdAt`, which
  drives dashboard trends).
- `lib/features/calendar/domain/models/appointment_image.dart:11` — `fileName` is
  written and round-tripped but never read off an instance. Plausibly reserved.
- `functions/live_activity_registry.js:352-359` and
  `functions/maintenance_policy.js:117-119` export internal constants used only
  by their own tests, without the "exported for unit tests" comment that
  `apns_client.js` / `account.js` carry. Informational — matches an established
  convention; worth a comment, not a change.

## Notes / uncertainties

- **Why zero auto-fixes.** The statics were already clean, so the only two
  candidates came from the deep review, and both failed verification as "safe":
  the `heroGradient` swap is not behaviour-preserving (different colours *and*
  alignments), and ARB keys are explicitly report-only per
  `references/project-map.md`. Reporting both rather than applying either.
- **B1 left the suite red at audit time.** The failure pre-dated this audit (the
  tree was clean on arrival). Fixed in the 2026-08-11 pass: the clock is pinned
  to 2026-08-10 and the three previously-vacuous tests were re-checked.
- **I corrected two reviewer findings during verification.** The emergency-contact
  finding was returned as High/"tells an admin nobody has an emergency contact";
  the panel is actually omitted when empty, so it renders as *not shown* — I
  downgraded it to I4 and restated the real residue. The `heroGradient` swap was
  returned as a one-line token swap; it isn't.
- **Deliberately not flagged**, so they are not re-litigated later:
  `groupTomorrowsJobsByEmployee`'s over-inclusive instant-span overlap
  (self-documented, out of Plan 2 scope); the widget's "Day N of M" for a night
  shift (`ScheduleWidget.swift:216` documents the missing `isOvernight` flag);
  `_barColors` skipping colourless assignees while the avatar stack shows them
  (documented at `appointment_card.dart:196`); `PURGE_STATUSES` omitting legacy
  `completed` (fails safe); `EventDetailsController.save`'s reentrancy returning
  `EventDetailsInvalid` rather than a `Busy` member (both surface nothing).
- **Verified clean and stated plainly rather than padded:** all 8
  `appointmentsInRangeProvider` consumers re-scope through the day-slice owner;
  `day_slice_utils.js` is a faithful wall-clock mirror of the Dart; `storedRaw`
  normalization is applied at all three re-serializing sites;
  `kSelfServiceUserFields` matches the rules exactly (7 keys); the P5
  `allow update` parentheses do bind the denylist and validator to both branches;
  all 11 callables enforce App Check with correct guard order; no PII reaches
  `logger.*` in `functions/`; no secrets in the working tree; role is never read
  from SharedPreferences; all four credential fields set
  `enableIMEPersonalizedLearning: false`; every `setState`-after-`await` across 39
  files guards on `mounted`; no duplication cleared the 3+-site bar; the
  performance pass found nothing actionable.
- **Not covered:** device-only paths (`ImagePickerService`/`ImageStorageService`,
  biometric app-lock, camera) per the project's testing rules; Swift under
  `ios/` was read only where a Dart/JS finding crossed into it; catch-block
  logging was sampled (~30 of 56 candidate files), not exhaustively swept.
