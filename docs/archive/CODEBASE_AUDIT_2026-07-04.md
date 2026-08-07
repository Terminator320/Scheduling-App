# Codebase Audit — 2026-07-04

Scope: whole repo — `lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`test/`. Baseline: clean working tree on branch `moblie` (`fca4d27`).
Per request, everything flagged or decided in prior audits is **excluded**
(see `docs/audits/CODEBASE_AUDIT_2026-07-01.md`, `docs/audits/CODEBASE_AUDIT_2026-06-26.md`,
`docs/audits/WAVE_REVIEW_FINDINGS.md`) — this report contains only NEW findings.
Review effort was weighted toward code that postdates the 2026-07-01 audit
(the application-controller refactor `620fc47`, robustness pass `6be1754`,
a11y `eb0cd39`, PR #30, and the `fca4d27` "mac" commit), none of which had
been reviewed before.

## Summary
- Scanned: ~190 `lib/` Dart + ~101 `test/` + 25 `functions/` JS + rules, via a
  5-way parallel deep review (security / bugs / conventions+dead-code /
  performance / maintainability) on top of the static scan.
- Auto-fixed (safe, in the diff): **3** — the Functions ESLint errors that
  appeared since the last audit (2 line-length, 1 JSDoc), all in
  `functions/wave/`.
- Reported for your decision: **18** (🔴 1 security · 🟠 5 bugs ·
  🔵 5 improvements · 🟡 7 code-quality) — **0 critical**.
- Good news: the 2026-06-26 security finding S1 (`users` read rule exposing the
  staff directory to any signed-in principal) is **now mitigated in
  `firestore.rules`** — clause 2 reads `isActiveUser() && resource.data.status
  == 'active'`, so the reader must be provisioned active staff. Close it in
  your tracking.
- Verification: `flutter analyze` **clean** (0 errors/warnings; no Dart source
  was modified this session, so no Flutter tests were re-run) · Functions
  ESLint **clean** · Functions jest **213/213 pass** · `dart fix` nothing to
  fix · dead-code scan **zero hits** (files, providers, routes, repo methods,
  constants all live).

## Update (2026-07-04) — findings implemented

Everything below **except the carried-over pre-ship App Check flips** has been
implemented on `moblie` (uncommitted), per "do everything but not the
pre-ship". Verified after the changes: `flutter analyze` clean ·
`flutter test` **723/723** · Functions ESLint clean · jest **213/213** ·
`gen-l10n` clean, no EN/FR drift.

- ✅ **B1** — `addClient` now resets `isSaving` in a `finally` (like
  `updateClient`); the pinned stays-busy test flipped to assert the reset.
- ✅ **B2** — `markAsDone`/`cancelAppointment` return the caught error;
  `details_view_body` composes an `APPT-STATUS` notice on failure
  (new `error_introUpdateAppointmentStatus` key EN+FR); warn label prefixed.
- ✅ **B3** — `resumeAfterSignUp` wraps the profile read; a throw maps to
  `SignInProfilePending` (+ regression test, 11 cases total).
- ✅ **B4** — `_loadClientIfNeeded` skips for a known non-admin session,
  gated on `ref.exists(currentUserDocProvider)` so the auth-gated stream is
  never initialized from the microtask (+ regression test).
- ✅ **B5** — `searchClients` got a monotonic request token mirroring the
  address field's `_requestId` (+ stale-response race test).
- ✅ **S1** — `createEmployeeInvite` now calls `enforceDurableRateLimit`
  (20/hour, keyed by admin uid). Needs a functions deploy to take effect.
- ✅ **I1** — hub tabs: built-screen cache (identity-keyed) + `_TabViewInsets`
  pins hidden tabs' `viewInsets` (always-mounted wrapper so tab switches never
  drop kept-alive state).
- ✅ **I2** — employees stream warn moved to a `ref.listen` data→error
  transition guard.
- ✅ **I3** — `myAppointmentsProvider` mirrors the admin keep-alive grace.
- ✅ **I4** — new `appointment_history_providers_test.dart` (invalidate-on-
  local-write + subscription cleanup) and `master_detail_scaffold_test.dart`
  (two primary lists under Cupertino scrollbars, breakpoint fold). The FAB
  hero-tag half was intentionally skipped — it would only exercise test stubs,
  not the shipped screens.
- ✅ **I5** — all five direct `AuthCache()`/`AuthService()` sites now resolve
  via `authCacheProvider`/`authServiceProvider`.
- ✅ **Code quality** — `AppShadow.pill` token (byte-identical shadow) + pill
  radius → `r8`; `CLI-LIST` warn prefix; address field raw `Timer` →
  `Debouncer`; radii/spacing snapped (`10→r12` search dropdowns, `10→r8` photo
  tiles, `14→r12` contact card, `12→sp12`, `4→sp4`); `ErrorCause` →
  `_ErrorCause` (file-private); error-handling.md + ARCHITECTURE.md drift
  fixed. The legacy employee default color stays raw by design (recoloring
  risk for pre-palette docs) — now documented with a NOTE at the site.
- ⏸️ **Deferred (pre-ship):** the 6 App Check flips (see checklist below).

The detailed findings below are retained as the rationale/record.

## Auto-applied cleanups (review the diff)
| File:line | Change | Why |
|---|---|---|
| `functions/wave/worker.js:160` | transient-error regex literal → named `RegExp` built from two string halves | ESLint `max-len` (93 > 80); behavior-identical |
| `functions/wave/worker.js:484` | `/** … */` on `pastDeadline` → `//` comment | ESLint `valid-jsdoc` (missing `@return`) |
| `functions/wave/__tests__/worker.test.js:1329` | wrapped the over-long `test(...)` call; `eslint --fix` re-indented the body | ESLint `max-len` (82 > 80) |

> Full detail is in `git diff`. Nothing below this line was auto-changed.
> `docs/audits/CODEBASE_AUDIT.md` was archived to `docs/audits/CODEBASE_AUDIT_2026-07-01.md`.

## ⚠️ Pre-ship checklist
No NEW pre-ship items. The carried-over one still stands: **App Check
enforcement is OFF on 6 callables** (`TODO(pre-ship)`) — see the checklist in
`docs/audits/CODEBASE_AUDIT_2026-07-01.md` for the exact lines to flip before the
store release.

## 🔴 Security findings (review required)

### S1 — `createEmployeeInvite` is the only admin callable without a durable rate limit · severity: low (defense-in-depth) · confidence: high
- **Where:** `functions/invites.js:115` (callable body; `assertAdmin` present,
  no `enforceDurableRateLimit`).
- **Risk:** A compromised admin session could mass-create `invited` `users`
  docs + `signupCodes` docs. Impact is bounded — an invited doc grants no
  access without a matching-email Auth account and a code redemption — so this
  is a consistency gap against the documented admin-callable pattern
  (`waveBootstrap`, `waveImportCustomers`, `deleteAccount` all carry the
  limiter), not an open door.
- **Fix:** Add `enforceDurableRateLimit` keyed by `req.auth.uid` (e.g.
  20/hour). Needs a functions deploy.

Everything else on the security checklist verified clean: no secrets in
source/logs; App Check activation intact; role always from Firestore; query
constraints satisfy rule clauses (including the new `isActiveUser()` peers
clause); privilege-escalation surface closed (`users` update blocks `uid`
rewrites, allowlists `role`/`status`); callable payloads validated; errors
returned to clients are PII-free app-owned codes; loose Map casts everywhere;
launcher URLs structured/encoded; deps current with committed lockfile.

## 🟠 Bug findings (review required)

### B1 — Split layout: a successful "Add client" permanently bricks the add sheet and all client edit saves · severity: high · confidence: high (code-traced; not device-verified)
- **Where:** `lib/features/clients/application/client_form_controller.dart:78-93`
  (`addClient` keeps `isSaving: true` on success by design) +
  `lib/features/clients/widgets/views/client_detail_view.dart:101` (detail pane
  watches the same provider).
- **Problem:** `clientFormControllerProvider` is a single non-family
  `NotifierProvider.autoDispose` shared by the add sheet, the edit form, and
  the detail view. `addClient` deliberately leaves `isSaving: true` on success
  ("sheet keeps its spinner while it pops"), relying on autoDispose to reset —
  but in `isSplitLayout` (tablets AND landscape phones) the master-detail pane
  stays mounted (and is kept alive across tabs by the hub `IndexedStack`), so
  its `ref.watch` keeps the provider alive with `isSaving == true` forever.
  Sequence: select a client → FAB → add a client → success → from then on every
  `AddClientSheet` opens with Save spinning and Cancel disabled
  (`add_client_sheet.dart:146,201-202`), and `client_edit_form.dart:129`'s
  reentrancy guard silently no-ops every edit save. Recovery only by unmounting
  the pane (delete the selected client, rotate to portrait). Portrait phones
  are unaffected — which is why testing missed it.
- **Fix:** Reset `isSaving` in a `finally` like `updateClient` already does
  (the sheet pops in the same frame, so the double-tap window is negligible),
  or scope the provider `.family` per surface. Note the stays-busy semantics is
  pinned by `test/features/clients/application/client_form_controller_test.dart:67`
  — the test must change with it, so this is a deliberate semantic change, not
  a patch. (`SignInController` and `EmployeeFormController.deleteEmployee` use
  the same stays-busy idiom *safely* — their sole watcher provably unmounts on
  success. Only this path violates that precondition.)

### B2 — "Mark as done" / "Cancel appointment" fail silently — no error notice, untagged log · severity: medium · confidence: high
- **Where:** `lib/features/calendar/widgets/views/details_view_body.dart:181,201`
  (`if (!(await notifier.markAsDone(...))) return;`) +
  `lib/features/calendar/application/event_details_controller.dart:284-302`
  (`_setStatusOnRepo` logs `'updateAppointmentStatus($status) failed'` — no tag).
- **Problem:** On failure (offline, permission-denied) the button un-busies and
  *nothing* happens — no notice, while the success paths do push notices.
  Violates the project rule: "For user-visible failures (save/delete/status),
  also push `noticeServiceProvider.error(...)`", plus the cause+tag composer
  convention. The tag list has `EMP-STATUS` but no appointment-status tag.
- **Fix:** On `false`, surface `composeErrorNotice(context, intro: <new
  error_intro key>, tag: 'APPT-STATUS', error: ...)` (controller must expose the
  caught error), and prefix the warn label `'APPT-STATUS …'`. New tag ⇒ new
  `error_intro*` key in both ARBs.

### B3 — `resumeAfterSignUp` has no error handling; a throw right after account creation strands the user silently · severity: medium · confidence: high
- **Where:** `lib/features/auth/application/sign_in_controller.dart:164-174`;
  consumers `login_screen.dart:180-202` (`_routeAfterSignUp` → `_openCreateAccount`)
  also have no try/catch.
- **Problem:** Unlike `signIn()` (maps every throw to `SignInError`),
  `resumeAfterSignUp` can throw: `_retryOnAuthPropagation` absorbs exactly one
  `permission-denied` — a second one rethrows, and any non-`FirebaseException`
  propagates immediately. The throw escapes to the zone handler: a user who
  *just successfully created an account* is left on the login screen with no
  banner and a silent Crashlytics fatal. Violates "Async calls … must have
  `.catchError` or try/catch".
- **Fix:** Wrap the profile read; on error return `SignInProfilePending` (the
  screen already shows "account created, you can now sign in") or `SignInError`.
  Add the missing throwing-path case to the 11-case test file.

### B4 — Every appointment-detail open by a non-admin fires a guaranteed `permission-denied` Firestore read + Crashlytics non-fatal · severity: low · confidence: high
- **Where:** `lib/features/calendar/application/event_details_controller.dart:101,159-189`
  (`build()` unconditionally microtasks `_loadClientIfNeeded`) vs
  `firestore.rules:192` (`clients` read is `isAdmin()` only).
- **Problem:** For the entire employee user class the client-enrichment read is
  denied 100% of the time; the catch logs a warn (→ Crashlytics in release), so
  every employee detail-open produces one wasted read attempt and one non-fatal,
  forever. UI is unaffected (the read-only body renders the denormalized
  `clientName`/`clientPhone`/`address`) — but it's a code path that can never
  succeed for non-admins and it pollutes Crashlytics with rules noise.
- **Fix:** Gate `_loadClientIfNeeded` on the session role (the enrichment only
  feeds the admin-only edit body), or don't log `permission-denied` there.

### B5 — Client search in the appointment forms can render stale results (no request token) · severity: low · confidence: medium-high
- **Where:** `lib/features/calendar/application/appointment_form_concerns.dart:85-112`
  (`searchClients`, shared by `AddEventController` and `EventDetailsController`).
- **Problem:** Two in-flight searches have no ordering guard — whichever
  resolves last wins `clientResults`. Concretely: cold repo cache, user types
  "ma" → scan-window read A starts; user types "mar" → read B starts (window
  still unset); B resolves and renders, then A resolves and replaces the list
  with matches for "ma" while the field shows "mar". Self-corrects on the next
  keystroke; mild harm. The codebase already fixed this exact pattern in
  `address_autocomplete_field.dart` (`_requestId`, added in `6be1754`) — this
  call site didn't get it.
- **Fix:** Monotonic request id in the mixin (mirror the address field), or
  drop responses whose query no longer matches the latest one.

## 🔵 Areas to improve (review required)

### I1 — Hidden kept-alive hub tabs rebuild (and re-lay-out) per frame during keyboard open/close and rotation · impact: medium · confidence: medium-high
- **Where:** `lib/routes/hub_shell.dart:126-150` (`IndexedStack` of always-alive
  tabs; `_screenFor` builds fresh instances per shell `setState`).
- **Opportunity:** Every visited tab is a `Scaffold` (depends on `MediaQuery`),
  so keyboard `viewInsets` animation dirties **all** kept-alive tabs per frame —
  including the calendar's 42-cell `TableCalendar` grid — not just the visible
  one (`TickerMode` mutes animations, not rebuilds; `IndexedStack` lays out all
  children). ~10–20 frames per keyboard transition × up to 4 hidden screens; est.
  2–10 ms/frame extra on mid/low-end Android once calendar + 2–3 tabs have been
  visited. Paid on every search-field focus/blur and rotation, all session.
- **Suggested improvement:** (a) cache built tab widgets in `HubShellState`
  (invalidate only when the `isAdmin`/`employeeId` key changes) so identical
  instances short-circuit rebuilds; (b) wrap non-current tabs in
  `MediaQuery(data: outer.copyWith(viewInsets: EdgeInsets.zero), ...)` — a
  hidden tab can never own the focused field. Worth one timeline trace to
  confirm magnitude first.

### I2 — `employees_screen` logs inside `.when`'s error branch — re-logs on every rebuild · impact: medium-low · confidence: high
- **Where:** `lib/features/employees/screens/employees_screen.dart:153-156`.
- **Opportunity:** While the stream is errored, every master-list rebuild
  (search keystrokes, text-scale changes) re-fires `logger.warn` — Crashlytics
  spam that masks real signal. Direct violation of the error-handling rule
  ("one-shot side effects on AsyncValue transitions belong in `ref.listen`").
  `main_calendar_screen.dart:163-187` shows the correct transition-guarded
  pattern.
- **Suggested improvement:** Move the warn into a `ref.listen` data→error
  transition guard; keep the error UI in `.when`.

### I3 — Employee month stream lacks the keep-alive grace the admin path has · impact: low · confidence: high
- **Where:** `lib/features/calendar/application/appointments_providers.dart:40-46`
  (`myAppointmentsProvider`) vs `:20-34` (`appointmentsInRangeProvider` with
  `ref.keepAlive()` + 3-min evict timer).
- **Opportunity:** Every employee month swipe tears the Firestore listener down;
  swiping back re-opens the query (re-billed read + skeleton flash) — exactly
  what the admin path was fixed to avoid.
- **Suggested improvement:** Mirror the `keepAlive()` + evict-timer/`onResume`
  pattern.

### I4 — Test gaps on newly-shipped invariants · impact: low-medium · confidence: high
- **Where:** (a) `lib/features/clients/application/appointment_history_providers.dart:38-41`
  — the `onLocalWrite → invalidateSelf` wiring (enforces the "just-deleted
  appointment must leave history search" invariant) is stubbed as
  `Stream.empty()` in every existing test, so a regression is silent.
  (b) `fca4d27`'s three runtime-throw fixes (`primary_scroll_scope.dart`,
  `master_detail_scaffold.dart:29-43`, unique FAB `heroTag`s) have zero tests,
  and those throws go silently to Crashlytics in release.
- **Suggested improvement:** (a) one provider-level test with a
  StreamController-backed `onLocalWrite` asserting `searchHistory` re-invokes;
  (b) one widget test: wide `MasterDetailScaffold`, two primary `ListView`s
  under `AppScrollBehavior`, assert `takeException()` is null.

### I5 — Five sites still construct `AuthCache()`/`AuthService()` directly, bypassing the providers `620fc47` introduced · impact: low · confidence: high
- **Where:** `lib/main.dart:203` (`AuthService().signOut()`), `lib/main.dart:273`
  (`AuthCache().loadIfMatch`), `lib/features/splash/screens/splash_screen.dart:73`,
  `lib/features/splash/application/splash_controller.dart:56,60`.
- **Opportunity:** The refactor added `authCacheProvider`/`authServiceProvider`
  precisely for test seams; these sites (all with a `ref` in scope) bypass them
  — and bypass the provider-wired secure storage, so overrides don't reach the
  splash warm-cache path.
- **Suggested improvement:** `ref.read(authCacheProvider)` /
  `ref.read(authServiceProvider)` at each site.

## 🟡 Code-quality suggestions (optional — need a real edit)

- `lib/features/settings/widgets/cards/settings_tiles.dart:262-266` — hardcoded
  `BoxShadow(color: Color(0x1A000000))` (mode-invariant black shadow, raw color)
  and `BorderRadius.circular(6)` at `:248,:259`. Route through `AppShadow` /
  `theme.cardStyle` and snap 6 → `AppRadius.r4`/`r8`.
- `lib/features/clients/widgets/views/clients_list_view.dart:68` — warn label
  `'clients page fetch error'` doesn't start with the surface's `CLI-LIST` tag
  (the indicator at `:256-259` shows `(CLI-LIST)` to the user). Rename to
  `'CLI-LIST clients page fetch error'`.
- `lib/shared/widgets/fields/address_autocomplete_field.dart:46,79,91` — raw
  `Timer` debounce instead of `Debouncer` (correctly cancelled in `dispose`, so
  drift only; predates the rule but was touched in `6be1754` without migrating).
- Off-token radii/spacing introduced or touched recently (mechanical pass):
  `circular(10)` in `address_autocomplete_field.dart:218`,
  `client_search_field.dart:81`, `photo_picker_section.dart:243,248,280`;
  `circular(14)` in `additional_contacts_section.dart:163`; raw
  `SizedBox(height: 12)` in `employees_screen.dart:147,149`; raw
  `EdgeInsets.only(top: 4)` in `address_autocomplete_field.dart:215`.
- `lib/features/employees/domain/models/employee_record.dart:13` — default
  employee color `Color(0xFF2196F3)` is not in `AppColors.employeePalette`.
  Possibly an intentional legacy default for pre-palette docs — check stored
  data before changing.
- `lib/core/errors/error_cause.dart:12` — `ErrorCause` enum is public but has
  zero external references since `620fc47` privatized `classifyError`; could be
  file-private.
- Doc drift: `.claude/rules/error-handling.md` still cites
  `login_screen._retryOnAuthPropagation` (moved to
  `sign_in_controller.dart:186`; note `.claude/` is gitignored — local-only
  edit), and `docs/ARCHITECTURE.md` predates `620fc47` (says "StateNotifier",
  names none of the new controllers) — refresh at the next `/release`.

## Notes / uncertainties
- **B1 is code-traced, not device-verified** — a 2-minute check on a landscape
  phone/tablet (select client → add client → try to add/edit another) would
  confirm it.
- **Sub-threshold hardening notes** (contrived triggers, no action needed):
  `details_edit_body.dart:199` resets the busy flag before the mounted guard —
  only throws if the whole route stack is torn down (account-disable kick-out)
  while the series-scope dialog is open, and the zone handler records it fatal;
  `functions/client_propagation.js` denormalized patches don't set `updatedAt`
  (idempotent absolute-value writes, no correctness impact today);
  `functions/wave/callables.js` caches the Wave businessId per instance —
  only matters if re-bootstrap to a *different* business ever becomes supported.
- **Why the ESLint errors existed:** `functions/wave/worker.js` was edited
  after the 2026-07-01 audit (transient-error classification) without running
  `npm run lint` — consistent with the CLAUDE.md "lint before deploying" rule
  being skipped on the Mac.
- **Verified sound this pass** (beyond the prior audit's list): reentrancy-flag
  ordering in all five new controllers; search-cache invalidation on every
  appointments write path + `onLocalWrite` self-invalidation; assignee
  preservation (the cold-read hazard is not concretely reachable); account
  -deletion populated→empty transition wiring incl. warm-cache cold-start
  discrimination; employee visibility filters + rules `hasOnly` on the
  employee "mark done" write; date/DST math (`combineEndDateAndTime`,
  `occurrenceEnd`, `_addMonthsClamped`); `retry.dart` semantics and call sites;
  `fca4d27` scroll/hero fixes; invite-flow transaction; `deleteAccount`
  ordering + rate-limit refund; Wave worker lease/claim/commit/reclaim outbox
  invariant; image pipeline append/remove-only writes; leak sweep (all
  debouncers/controllers/subscriptions disposed); startup path; no dead code.
