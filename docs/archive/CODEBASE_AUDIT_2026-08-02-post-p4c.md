# Codebase Audit — 2026-08-02 (post-P4c)

**Branch:** `redesgin` (clean tree at `95279ed`) · **Baseline:** 1434 Flutter tests /
689 jest tests passing, `flutter analyze` clean (0 errors/warnings), `dart fix` nothing
to fix, Functions ESLint green.
**Method:** deterministic static scan + five parallel deep reviewers (security, bugs,
dead code, performance, maintainability). Every headline finding below was re-verified
by hand against source before being written down.

> Supersedes `CODEBASE_AUDIT_2026-08-02-pre-p4c.md`, which audited the release cut
> *before* the P4c employee-account commits landed.

The static level is spotless. **Every finding here came from the deep review, not the
analyzer** — which is the expected shape for this repo.

---

## STATUS: implemented 2026-08-02

Every finding below was implemented except the **Pre-ship checklist** — those are
launch-time switches and the owner elected to keep the debug-gated client delete for now,
so the `/clients` rules hole stays open until a deliberate pre-submission pass.
Post-implementation state:

| | Before | After |
|---|---|---|
| Flutter tests | 1434 | **1451** |
| Jest tests | 689 | **692** |
| `flutter analyze` | clean | **clean** |
| Functions ESLint | clean | **clean** |
| ARB keys (EN / FR) | 569 / 569 | **561 / 561**, zero drift |

Two findings were implemented via the audit's *safer* branch, and both are called out
inline: **S3** (documentation corrected rather than adding a fragile
`tokensValidAfterTime` check that could lock a real employee out of setup) and **D1** (the
drawer hues stayed literals — indexing `crewPalette` would couple nav decoration to
employee colour-slot ordering; the reason is now a comment so it stops being re-flagged).

---

## Pre-ship checklist (launch blockers — NOT auto-implemented)

| Item | Where | Status |
|---|---|---|
| `allow delete: if isAdmin();` on `/clients` | `firestore.rules:490-498` | **OPEN IN PRODUCTION.** Rules are not build-aware. The Dart affordance is `kDebugMode`-gated (`lib/core/testing_flags.dart:25`) and cannot reach the App Store, but the rules hole is live once deployed. Closing it needs a **rules redeploy**, not just a code sweep. Checklist: `docs/plans/redesign-subdocs/2026-08-01-p3-HANDOFF.md` §5b (grep `#pre-ship`). |
| 12 `TODO(pre-ship)` markers | `testing_flags.dart` + 9 client files | Correctly formatted and self-documenting. Marker discipline is exemplary — no stale, undated, or `XXX`/`TEMP` markers anywhere; zero TODOs in `functions/`. |

**Deploy-state caveat (not verifiable from source):** deleting a function's export does
not delete the deployed function. Until `firebase deploy --only functions` runs and the
deletions are confirmed, the previously-**unauthenticated** `redeemSignupCode` may still
be live in production — and the Admin SDK bypasses the now-removed `/signupCodes` rules.
Leftover `signupCodes` docs also no longer have a TTL policy to reap them.

---

## What was auto-fixed (safe, mechanical — see the diff)

Only **two** changes. The safe-fix category was nearly empty because the static tooling
was already clean.

1. `lib/features/clients/widgets/fields/address_grid_fields.dart:39,52,65` — three
   `SizedBox` literals → `AppSpacing.sp12` / `AppSpacing.sp16` (exact-value match,
   behavior-preserving), plus the token import.
2. `.claude/rules/frontend.md:209` — stale pointer: the account-disabled SnackBar lives at
   `core/app/account_exit_listeners.dart:90`, not `main.dart`. Still exactly 3 sanctioned
   sites. *(Fixed because stale docs actively mislead the next audit into "fixing" a
   correct site.)*

Verified after: `flutter analyze` clean, `flutter test test/features/clients/` → 191 passed.

**Deliberately NOT auto-fixed:** 9 orphaned ARB keys (l10n needs a deliberate pass),
16 unadopted design tokens (two are named in shipped docs — owner call), and 8 hardcoded
crew hues in `drawer_catalog.dart:59-66` (mapping each hex to a palette index is a
judgment call, not a mechanical swap).

---

## Security findings

### S1 — An employee can complete setup using the shared default password *(verified)*

`lib/core/validators/auth_validators.dart:38-46` → `password_requirements.dart:17-26`,
gate applied at `account_setup_screen.dart:116`

`AccountSetupScreen` gates the new password on length ≥ 8 + upper + lower + digit +
symbol. **`Welcome123!` satisfies all five.** There is no comparison against
`kDefaultStartingPassword` anywhere in `lib/`, and `User.updatePassword` accepts the
current password unchanged — so setup completes and the doc flips to `active`.

The entire documented P4c tradeoff rests on "the window closes when the employee replaces
the shared default." An employee who types back the password the admin just read to them
ends up **permanently `active` on a hardcoded constant** that is in the source, printed on
every pending roster row, on the "Copy both" clipboard payload, and known to every admin
and every previously-onboarded employee. Anyone who knows that person's email signs in as
them. The window never closes, and no surface reports it — the roster just says `active`.

**Fix (preferred):** make the starting password **per-account random** in
`provisionAuthAccount` — the server already echoes it back to the admin surface
(`return {email, password}`, `employee_accounts.js:229`) and the Dart constant is only a
display fallback, so re-use stops being catastrophic. **Minimum:** reject the default in
`AuthValidators.newPassword`, with a matching test.

### S2 — `createEmployeeAccount` can reset a live employee's password and delete their bridge doc *(mechanism verified)*

`functions/employee_accounts.js:79-93` (`provisionAuthAccount`), `:194-198` (pre-check),
`:139-148`; reached via `edit_person_sheet.dart:426` → `firebase_employees_repository.dart:200`

The "never reset a real person's chosen password" guard is a Firestore query on
`users.email`. But `provisionAuthAccount` then does `getUserByEmail` →
`updateUser(existing.uid, {password})` — resetting **whatever Auth account holds that
address**, with no check that it is the account the Firestore query cleared.

**Verified precondition:** `users.email` is admin-editable and **is never synced to
Firebase Auth**. A repo-wide grep finds exactly three `auth.updateUser` calls — two
`{disabled}` flips in `bridge.js:85,91` and the password reset at
`employee_accounts.js:88`. Nothing changes the Auth email. So the two stores can diverge:

1. Admin edits active employee Bob's `users.email`. Auth still holds the old address.
2. Admin creates an account for the old address → the `claimed` query is empty, guard passes.
3. **Bob's Auth password is reset to `Welcome123!`** and his `displayName` overwritten.
4. A **second `users` doc carrying Bob's uid** is minted (the transaction checks email
   uniqueness, not uid).
5. `syncUsersByUid` sees an `invited` doc → `shouldHaveBridge` false → `bridge.js:190`
   deletes `usersByUid/{bobUid}` → **Bob loses every rules grant.**

This is exactly the hazard the `allow create` uid denylist was written to prevent
(`firestore.rules:131-137`) — but the callable uses the Admin SDK, so rules don't apply.

**Fix:** resolve the target by **uid, not email** before touching Auth; assert uid
uniqueness inside `performCreateAccount`'s transaction; and either make `email` read-only
for a doc that already has a `uid`, or sync it to Auth via a callable.

### S3 — "Password first, then activate" is a client-side convention, not a server guarantee

`functions/employee_accounts.js:269-318` vs. `lib/features/auth/services/auth_service.dart:70-116`

`completeEmployeeSetup` checks only: authenticated uid, matching doc, `status == 'invited'`.
It performs **no check that the password was rotated**. The ordering is enforced solely by
`AuthService` calling `updatePassword` before the callable.

CLAUDE.md states this as a guarantee ("unreachable until `User.updatePassword` succeeds").
It isn't — it's unreachable *in this build*. `enforceAppCheck: true` is the real barrier,
which is why this is S3 — but App Check is anti-abuse attestation, not an authorization
boundary. **Fix:** check `getAuth().getUser(uid).tokensValidAfterTime` against the doc's
`createdAt` inside the transaction, or downgrade the claim in CLAUDE.md so the next change
doesn't build on it.

### Security: verified clean

Checked and confirmed correct — **an `invited` user really is granted nothing**
(no `usersByUid` bridge → every non-`/users` grant fails; storage rules likewise);
`deleteEmployeeAccount` genuinely refuses post-setup (transactional);
guard order correct on all callables (payload validation *before* the rate limiter);
`enforceAppCheck: true` on **all 11** `onCall`s, with no unauthenticated callable left;
the `/users` create+update denylist covers all three fields and `toMap()` emits none of
them; the `private/emergency` subcollection is shape-locked and correctly gated;
**credential handling is clean** — the starting password never reaches `logger.*`, never
hits SharedPreferences or secure storage, and has a single sanctioned clipboard egress;
no hardcoded secrets in `lib/` or `functions/`.

---

## Bug findings

### B1 — Dashboard counts personal jobs as overdue *(shipped user-visible bug — verified)*

`lib/features/dashboard/domain/dashboard_aggregator.dart:39-44` and `:197`
vs. `lib/features/calendar/domain/models/appointment_record.dart:97`

`displayStatus` has `if (isPersonal) return status;`. Its documented mirror
`displayStatusAt` — whose docstring literally says *"Mirrors displayStatus"* — **does
not**. Verified: `grep isPersonal lib/features/dashboard/` returns **zero hits**.

So for one and the same record — a personal block past its end time — the calendar card
and detail header correctly say "Scheduled", the server correctly skips the "job finished?"
nudge, and **the dashboard counts it as `overdue` and lists it under Attention**, where the
admin has no affordance to clear it (personal jobs have no mark-done flow). Landed when
personal jobs shipped 2026-07-31; never propagated.

**Fix:** add the `isPersonal` line to `displayStatusAt` (already the more general form),
make `displayStatus` delegate to it, and rewrite `:197` as
`displayStatusAt(a, now) == 'overdue'`. Collapses three clock-vs-status ladders to one.
`dashboard_aggregator_test.dart` has 22 tests and zero `isPersonal` coverage — which is
why this shipped.

### B2 — Editing an employee's email silently doesn't change their sign-in

Same root cause as S2, but user-facing on its own: the roster, detail view and pending tile
all show the new address; the employee can still only sign in with the old one. The admin
hands over an address that cannot work, and neither party can see why.

### B3 — A reentrancy skip renders as a false "you appear to be offline"

`client_form_controller.dart:60` and `:87`, `employee_form_controller.dart:168`

All three return `XSaveFailed(SocketException('in-flight'))` when the guard skips a
re-entrant call. `_classifyError` (`core/errors/error_cause.dart:28`) keys on the
`SocketException` **type** → `offline`, and all four call sites feed it straight to
`composeErrorNotice`. Since the sheet's primary button only disables on the *next* frame
(by design — the guard's own comment says so), a same-frame double-tap shows
**"Couldn't save the employee — you appear to be offline. (EMP-SAVE)"** while online, and
the first save then succeeds behind the error.

This violates the project's own rule in `error-handling.md`: *"A no-op outcome (Busy)
surfaces nothing."* **Fix:** follow the existing in-repo precedent —
`EventDetailsActionOutcome` (`event_details_outcome.dart:56-72`) already solved exactly
this. Add a `Busy` member to `ClientSaveOutcome` and `EmployeeSaveOutcome`; the sealed
family then forces all four call sites to handle it.

### B4 — `AccountSetupScreen._finishSetup` sets an in-flight flag it never checks

`lib/features/auth/screens/account_setup_screen.dart:161-187` — `_isLoading` is set at
`:187` but there is no `if (_isLoading) return;`. Every other submit path in the codebase
opens with that check. A same-frame double-tap runs `completeAccountSetup` twice: two
`updatePassword` calls, two `completeEmployeeSetup` invocations (burning 2 of 5 rate-limit
slots), and two `pushNamedAndRemoveUntil`. **Fix:** one line.

### B5 — `resumeAfterSignUp` returns success without the active/invited gate

`sign_in_controller.dart:187-205` — `signIn` gates on both (`:142`, `:150`); the resume
path returns `SignInSuccess` unconditionally. If the read is served stale (offline
persistence, or the `permission-denied` retry returning a cached doc), the person lands in
the hub on an `invited` account where every rules gate denies them, with no route back to
setup. *(Confidence: medium-high — the window is small today.)*

### B6 — Non-transactional pre-check can still clobber a concurrent setup

`functions/employee_accounts.js:194-201` — the pre-check narrows the window it claims to
eliminate. If the employee's `completeEmployeeSetup` commits between the check and
`provisionAuthAccount`, their just-chosen password is reset to `Welcome123!` while they are
already `active` — so the setup screen never reappears and they are locked out, while the
admin sees `email-exists` and assumes nothing happened.

### Bugs: verified clean

The offline photo queue matches its invariant exactly (serialized mutations, preserved
`enqueuedAtMs`, append-only carry-forward); all-day/span logic is correct on both save
paths; all 10 raw `.listen()` sites pass `onError`; the single bare `catch (_)` is the
documented FCM-isolate exception; `mounted` guards, force-unwraps and sealed-switch
defaults all came back clean on inspection.

---

## Areas to improve

### I1 — Duplicate `users` listener pinned for the session *(highest read-cost win)*

`lib/features/employees/screens/employees_screen.dart:277` — `ref.listen(employeesStreamProvider, …)`
in `build()` instantiates a **second live `users` query** (limit 500) that nothing renders;
the rows come from `allUsersStreamProvider`. Because the hub's `IndexedStack` keeps the tab
mounted and the provider is not `autoDispose`, it is pinned for the whole session.

The comment at `:175-180` explicitly documents removing this exact second query — the
`ref.watch` went, the `ref.listen` stayed. **Fix:** delete it, or repoint it at
`allUsersStreamProvider` (the stream this screen actually shows errors for).

### I2 — `PagingState.items` re-flattened inside `itemBuilder`

`lib/features/clients/widgets/views/appointment_history_view.dart:340` — `items` is a
computed getter (`List.unmodifiable(pages.expand(…))`), so every row built copies the whole
loaded list. Ten pages deep (N=250) at 5–15 items per frame is 1,250–3,750 element copies
per frame, growing with scroll depth. The file already knows this hazard — `:270` memoizes
on `state.pages` identity for exactly this reason. **Fix:** pass the existing `loaded`
local into `_historyItem`. One line.

### I3 — Client search matching has two owners, already diverging

`client_search_policy.dart:59-95` (declares itself "the single source of truth") vs.
`firebase_clients_repository.dart:267-315`. The policy concatenates client + contact phone
digits into **one** string; the repository keeps **two**. Worked example: client
`514-555-1234`, contact `438-555-9999`, query `1234438` — the policy matches, the
repository does not. Both run back-to-back in the same UI, so it surfaces as a result
flickering in and then out. **Fix:** the repository already builds the `ClientRecord` at
`:265` before the raw-map work — call the policy directly; keep only the relevance scoring
local.

### I4 — Test-coverage gaps, ranked

1. **The `invited` sign-in gate is unpinned.** `SignInNeedsAccountSetup` appears **0 times
   in `test/`** (5 times in `lib/`). Deleting or reordering the branch keeps the suite
   green — and the existing test at `sign_in_controller_test.dart:162` would still pass in
   the broken world, actively reassuring you. Runtime symptom: an invited employee is told
   "account disabled" with setup permanently unreachable.
   **→ CLAUDE.md's "Tests pin both halves" claim is FALSE and should be corrected.** (The
   *splash* half is pinned, and the "password replaced FIRST" claim **is** genuinely pinned
   by a real `verifyInOrder` at `auth_service_test.dart:46`.)
2. **`account_setup_screen.dart` (591 lines) has no behavioral test** — only a scale sweep.
   Untested: the `!_consented` gate at `:166` (commented as *the* real enforcement, since
   keyboard-Done bypasses the disabled button — drop it and accounts activate with the
   legal consent record never stamped), the `SetupAlreadyComplete` recovery at `:216`, and
   the offline guard.
3. **`employee_accounts.js` onCall wrappers** — the Auth rollback at `:208-226` and the
   pre-Auth `email-exists` refusal at `:194-198` are both load-bearing and both uncovered;
   move or delete either and every test still passes. Copy the wrapper-driving pattern from
   `functions/__tests__/places_admin_gate.test.js:4-13`.
4. `AppointmentStatus.overdue.raw`'s deliberate throw is unpinned.
5. `account_exit_listeners.dart` (166 lines) has **zero** test references, while its
   sibling `app_sync_listeners.dart` has a full test file — and CLAUDE.md declares its
   ordering load-bearing.
6. `dashboard_aggregator` `isPersonal` coverage (add with B1).

### I5 — Dead weight (zero runtime risk)

- **9 orphaned ARB keys** — 8 stranded by the P4c deletion (EN 2443/2447/2451/2455/2459/
  2468/2472/2526; FR 552-558/570), safe to prune in a deliberate l10n pass. 1
  (`nav_myDetails`) is P5 pre-staging — owner call. **EN/FR lockstep is perfect: 568/568,
  zero drift.**
- **16 never-adopted design tokens** in `design_tokens.dart`, all traced to the P1 redesign
  commit `71c9a12`: 6 consts (`AppSpacing.cardGap`, `AppRadius.rHero`/`rInput`/`rSwatch`,
  `AppMotion.riseIn`/`dropdownSheet`) and 10 fully-wired-but-unread `ThemeExtension` fields
  (`AppCardStyle.dialogShadow`/`fabShadow`/`thumbShadow`/`knobShadow`,
  `AppPalette.barTint`/`brandNavy`/`noticeAmber`, `AppMonoType.numeralKpi`/`numeralSection`/
  `numeralSub`), plus the `AppColors.barTint` cascade.
  ⚠️ **Two caveats:** `numeralKpi` is named in `.claude/rules/frontend.md:13` as documented
  token vocabulary (owner call — drop the token *and* amend the rule, or keep it reserved);
  and **keep `AppRadius.r24`**, a documented scale rung.
- **All 5 flagged dependencies are false positives** — nothing removable from `pubspec.yaml`
  or `functions/package.json`.
- 8 hardcoded crew hues at `drawer_catalog.dart:59-66`.

### I6 — Structure: measured, and mostly fine

54 `build()` methods exceed 60 lines and 30 non-build functions exceed 60 — but I read the
largest and **do not recommend splitting them.** They are flat widget compositions with
very low complexity per line, carrying dated owner-decision comments; extracting would
produce single-use helpers, which the project's anti-defaults forbid. `edit_person_sheet.dart`
(703 lines, 21-line `build()`, six section builders) is the model to copy.

The one real structural split is **`functions/notification_utils.js` (951 lines)** — pure
policy (`diffAppointmentForNotifications`, `selectOverdueCandidates`) genuinely mixed with
I/O orchestration and three sweeps. It is the only file in either tree where size tracks a
responsibility split.

> **DONE** (owner call, 2026-08-02). Split into `notification_policy.js` (362 lines, the
> pure clock/data rules — no `deps`, no db, no messaging) and `notification_utils.js`
> (658 lines, the orchestration). `notification_utils.js` **re-exports every moved symbol
> under its original name**, so `notifications.js` and all existing jest tests are
> untouched — verified: all 18 public exports intact, 692/692 jest green, ESLint clean.
> The two private helpers `_record`/`_contextFor` became `recordOf`/`contextFor` (they are
> the policy module's public API now) and are aliased back at the require. The boundary is
> stated in `functions/CLAUDE.md`: **a helper that needs `deps` stays in the orchestration
> file.** Note this is a structural change only — the push pipeline itself remains
> device-unverified, as it was before.

Also worth one line of comment honesty: `employee_form_controller.dart:124-139` claims
taking the whole `EmployeeRecord` makes an omitted field *"unexpressible"*, but the body
destructures into 8 loose strings at `:127-135` — the guarantee holds at the controller
boundary only.

### Performance: verified clean

Every collection query is bounded; no query in a `build()` or item builder; no per-row
provider family; the one-listener-reduced-to-a-map pattern is followed. **All**
controllers/subscriptions/timers are disposed. The `DateFormat`-per-cell bug is genuinely
fixed and not reintroduced. `functions/` has no unbatched N+1. *(One sub-threshold note:
`app_nav_drawer.dart:288` and `day_route_screen.dart:61` build a day range with
`.add(Duration(days:1))` while `todayRangeProvider` uses `DateTime(y,m,d+1)` — identical on
363 days a year, divergent on the two DST days, which forks a second listener and
mis-buckets an 11 p.m. job. One-word fix if you are in those lines anyway.)*

---

## Suggested order

1. **S1** — the password hole. The only finding that is a live security regression with no
   mitigating control.
2. **B1** — the dashboard `isPersonal` divergence. The only shipped, user-visible bug.
3. **S2 / B2** — decide what an employee's email *is*: lock the field or sync it to Auth.
   Leaving the two stores free to diverge is what turns an ordinary edit into a silent
   password reset plus a bridge-doc deletion.
4. **I4.1** — the invited sign-in test, and correct the CLAUDE.md "both halves" sentence.
5. **B3, B4** — the `Busy` outcome member and the one-line guard.
6. **I1, I2** — the two performance wins (both one-liners).
7. **I3, I4.2-6, I5** — matching-policy unification, coverage, dead weight.
8. **Pre-ship checklist** — the `/clients` rules hole. Needs a redeploy.
