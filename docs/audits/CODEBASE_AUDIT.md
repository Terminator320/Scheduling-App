# Codebase Audit — 2026-07-07

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`, `test/`).
Baseline: working tree (clean) on `moblie` @ `efac0d6`.

## Summary
- **Scanned:** 207 source Dart files in `lib/`, the `functions/` Node.js modules,
  `firestore.rules` / `storage.rules`, and `test/`.
- **Auto-fixed (safe, in the diff): 0.** The static level is already clean —
  `flutter analyze` reports no errors/warnings, `dart fix --dry-run` says
  "Nothing to fix", and Functions ESLint passes. The only analyzer-invisible dead
  code found (4 design-token constants) lives in `design_tokens.dart`, a curated
  design-system API on the "do not touch" list — removing palette/scale entries is
  a judgment call, so it is **reported, not removed**. Nothing was changed;
  the tree is untouched.
- **Reported for your decision:** ⚠️ 1 pre-ship · 🔴 0 security · 🟠 0 bugs ·
  🔵 5 improvements · 🟡 6 code-quality notes.
- **Verification:** `flutter analyze` clean (baseline unchanged) · Functions
  ESLint clean · no edits made, so the test suite is unaffected.

### Top 3 things to look at first
1. **⚠️ Pre-ship — App Check disabled on 6 callables** (`functions/invites.js`,
   `account.js`, `wave/callables.js`). Intentional for sideload testing; must be
   flipped back before store release.
2. **🔵 I1 — `functions/client_propagation.js` has zero tests.** A live Firestore
   trigger that fans client edits onto future appointments, deliberately written
   as pure testable helpers that were never tested. Highest-payoff gap.
3. **🟡 D1/D2 — two dead `AppColors` constants** (`design_tokens.dart:22,42`),
   zero references. Cut them or wire them up — your call on the palette.

## ✅ Resolution (2026-07-08) — all findings actioned
All report-only findings were implemented (commits on `moblie`), and the App
Check pre-ship gate was flipped at the user's direction:
- **Tests added** (I1–I4): `client_propagation.test.js`, `maintenance.test.js`,
  `account.test.js` (functions), `auth_cache_test.dart` (Flutter). Pure helpers
  `image_magic.js` / `isReauthStale` extracted to make them testable.
- **Dead tokens removed** (D1–D4); sheet/drawer corner radii tokenized via new
  `AppRadius.r20`/`r24` (C1).
- **App Check ENFORCED** on all 6 callables (`enforceAppCheck: true`,
  `TODO(pre-ship)` notes removed). ⚠️ **Needs `firebase deploy --only functions`
  to take effect**, and on deploy it blocks clients that can't mint a verified
  App Check token — cut testers over to Play internal testing / TestFlight first.
- Verified green: flutter analyze clean · flutter test 751 · functions eslint
  clean · jest 237.

Deferred by design (see notes): C2 spacing-token churn, I5 `build()` extraction,
L1/L2 reserved l10n keys.

---

## Auto-applied cleanups (review the diff)
None. `flutter analyze`, `dart fix`, and Functions ESLint were all clean, and the
only dead code found is design-system API surface that is report-only by policy.
**Nothing below this line was auto-changed.**

---

## ⚠️ Pre-ship checklist (act before release)
- [x] **App Check enforcement — DONE (2026-07-08).** All 6 callables flipped to
  `enforceAppCheck: true` and the `TODO(pre-ship)` notes removed
  (`account.js` — `deleteAccount`; `invites.js` — `createEmployeeInvite` +
  `redeemSignupCode`; `wave/callables.js` — `waveBootstrap`, `waveGetConnection`,
  `waveImportCustomers`). The 2 Places callables already enforced.
  **Still requires `firebase deploy --only functions` to take effect** — until
  deployed, production runs the old unenforced build. On deploy it blocks any
  client that can't mint a verified App Check token (App Distribution sideloads),
  so move testers to Play internal testing / TestFlight first.

---

## 🔴 Security findings (review required)
**None exploitable.** A full trace of the security-relevant data paths across
`functions/`, `firestore.rules`, `storage.rules`, and `lib/` found no vulnerability.
Verified correct: no secrets in source (real `dev/.env` / `google-services.json` /
`GoogleService-Info.plist` untracked; Wave token + `GOOGLE_MAP_API_KEY` read via
`defineSecret().value()` in functions only); App Check active in `main()`;
role/`isAdmin` never cached (`AuthCache` excludes role by design); `!employee.isActive`
gating; two-layer employee visibility filter; deny-by-default rules with matching
query constraints; `ClientRecord.toMap` omits `waveCustomerId`/`wave`; server-side
magic-byte image validation; all callables validate `req.auth.uid` +
`assertPayloadShape` + `requireString`/`readSessionToken`; rate limits keyed
correctly (`redeemSignupCode` by token email); no SQL/shell/`eval`; Wave GraphQL
values passed via `variables`, never interpolated; callable responses use the safe
loose-cast idiom.

**Defense-in-depth observations (intentional today — no action needed):**
- `waveGetConnection` has no rate limit (`functions/wave/callables.js:204`) —
  admin-gated, reads one doc, no secret / Wave call. Intentional, low-risk.
- Active employees can read active peers' email/phone
  (`firebase_employees_repository.dart:52`, `firestore.rules:102`) — a documented
  product decision for the assignee picker/display. Flagged only so it stays a
  conscious choice.

---

## 🟠 Bug findings (review required)
**None above the confidence bar.** Every historically bug-prone area was traced
and confirmed correct: submit/save reentrancy flags set before the first `await`
and reset on all paths (`add_event_controller.dart:192`,
`event_details_controller.dart:376`); the populated→empty kick-out signal intact
(`main.dart:238` passes `previous`); assignee preservation via `_resolveAssignees`;
`_invalidateSearchCache()` called on every write path; `whereArrayContainsAny`
chunked by 30 in `findBusyEmployees`; safe callable map casts; subscriptions /
controllers / debouncers disposed; `mounted` / `ref.mounted` guards after awaits;
DST-safe date math.

**Two sub-threshold observations (both ~20–25% confidence, likely unreachable):**
- `lib/features/employees/screens/employees_screen.dart` — `_liveSelectedEmployee`:
  if `allUsersStreamProvider` emitted a settled non-null *empty* list, a selected
  employee not found in it clears the detail pane. This is the documented intent
  for a deleted employee; unlike `watchUserDoc`, `watchAllUsers()` doesn't filter a
  transient from-cache empty snapshot. Unreachable in practice (selection requires
  a warm list, and the admin is always present in `users`).
- Same file, `_buildMasterList`: the list's loading/error `.when` is driven by
  `employeesStreamProvider` while contents come from `filteredEmployeesProvider`
  (backed by `allUsersStreamProvider`); if the two streams' timing diverged the
  list could momentarily read "no employees." They subscribe together, so no
  observable effect.

Neither is worth a code change; noted for completeness.

---

## 🔵 Areas to improve (review required)
Ordered by payoff. All report-only — the Functions test gaps are the real prize.

### I1 — `functions/client_propagation.js` has zero tests · impact: high · confidence: high
- **Where:** `functions/client_propagation.js:60-203` (logic), `:220-227` (exports).
- **Opportunity:** A live Firestore trigger (`propagateClientEdits`, wired at
  `index.js:23`) that fans client-doc edits onto the denormalized
  `clientName`/`clientPhone`/`address` of all *future* appointments. The author
  deliberately factored the tricky logic into pure, dependency-free functions —
  `relevantClientChange`, `buildAppointmentPatch`, `clientDisplayName`,
  `propagateClientChange(deps)` — and annotated them `// Exported for unit tests.`
  **No test file exists** (only `invites.test.js`, `security.test.js` are present).
  The edge cases are exactly the kind that silently corrupt data: empty-previous-
  address must NOT match (`:103`), custom-address detection (`:138`), legacy
  `businessName` fallback (`:60-65`), idempotency on retry, and pagination. jest is
  already configured; these take/return plain objects.
- **Suggested improvement:** Add `functions/__tests__/client_propagation.test.js`
  covering `relevantClientChange` (name/phone/address change matrix incl. empty-from)
  and `buildAppointmentPatch` (custom-address skip, already-propagated no-op). Skip
  the paginated `propagateClientChange` integration unless quick via injected `deps`.

### I2 — `deleteAccount` callable has no test · impact: medium · confidence: high
- **Where:** `functions/account.js:36-149`.
- **Opportunity:** A security-load-bearing, irreversible callable with branches
  that are easy to regress: stale-`auth_time` rejection *before* the rate limiter
  (`:47-60`), rate-limit slot **refund** on server-side auth-delete failure
  (`:125`), and the deliberate "delete Auth user first, then Firestore doc"
  ordering (`:109-144`). None is exercised by a test.
- **Suggested improvement:** A `firebase-functions-test`-style unit test (as
  `invites.test.js` already does) asserting: stale `auth_time` throws without
  consuming a limiter slot; auth-delete failure triggers `refund()`; success returns
  `{deleted:true}`. Three focused cases — not full coverage.

### I3 — `functions/maintenance.js` magic-byte validation + purge loop untested · impact: medium · confidence: high
- **Where:** `functions/maintenance.js:11-58` (`validateUploadedImage`), `:100-169`
  (`purgeExpiredHistory`).
- **Opportunity:** The JPEG/PNG magic-byte check (`:42-46`) is a stated security
  invariant (the server-side backstop against the Storage rule trusting client
  `contentType`), and the purge loop has a subtle no-progress bailout (`:158`)
  guarding against an infinite loop. Both untested.
- **Suggested improvement:** Extract the byte check into a pure
  `hasValidImageMagic(buffer)` helper and unit-test it against JPEG / PNG / invalid
  buffers. Leave the Storage/schedule wrappers untested (integration-heavy).

### I4 — `lib/features/auth/data/auth_cache.dart` untested · impact: low · confidence: high
- **Where:** `auth_cache.dart:18-54`.
- **Opportunity:** Security-adjacent (persists signed-in identity to encrypted
  secure storage; the role-cache invariant is enforced *by omission* here).
  `loadIfMatch` has real branching — uid mismatch → null, empty docId → null,
  color-parse fallback (`:43`) — and no test. It takes an injectable
  `SecureStorageService`, so it's testable with
  `FlutterSecureStorage.setMockInitialValues({})`.
- **Suggested improvement:** One small test: `save` → `loadIfMatch` round-trips the
  record; wrong-uid and missing-docId return null. Low priority.

### I5 — Two `build()` methods exceed the ~60-line guideline · impact: low · confidence: medium
- **Where:** `main_calendar_screen.dart:211-344` (~133 lines);
  `details_view_body.dart:41-155` (~114 lines).
- **Opportunity:** Both exceed the frontend rule's ~60-line target, but both are
  already decomposed into extracted sub-widgets — what remains is largely
  declarative assembly. The one honest wart is `main_calendar_screen.build()`,
  which *interleaves* imperative logic (day-index memoization `:250-253`,
  `ref.listen` wiring `:222-240`, locale-format caching `:261-264`) with the tree.
- **Suggested improvement:** Optionally extract that pre-tree logic into
  `_syncDayIndex()` / `_wireListeners()` so `build()` reads as pure assembly. Do
  **not** further split the widget trees (the sub-widgets already exist — more
  indirection would be premature). `details_view_body` is fine as-is.

---

## 🟡 Code-quality suggestions (optional)
Convention/hygiene items that need a real edit, so they're report-only.

- **D1 — `AppColors.disabled` is dead** (`lib/core/theme/design_tokens.dart:22`,
  `Color(0xFFBFCBDD)`). Zero references in `lib/` or `test/` (the many `disabled`
  hits elsewhere are the status *string* `'disabled'`). Not fed into any
  `ColorScheme` / `ThemeExtension`. Remove, or wire a disabled-surface color into
  the theme.
- **D2 — `AppColors.darkDisabled` is dead** (`design_tokens.dart:42`,
  `Color(0xFF1E3260)`). Zero references, including inside `design_tokens.dart`
  itself (its value duplicates `darkSurfaceAlt`). Dead pair with D1 — remove
  together.
- **D3 — `AppRadius.r4` unused** (`design_tokens.dart:84`). No references; the rest
  of the scale (`r8`/`r12`/`r16`/`rFull`) is used. Remove, or keep as an
  intentional scale anchor (document the intent).
- **D4 — `AppDuration.slow` unused** (`design_tokens.dart:110`). No references;
  `fast`/`normal`/`shimmer` are used. Remove or keep as a deliberate scale anchor.
- **C1 — Off-`AppRadius` corner radii.** Hardcoded `Radius.circular(20)` at
  `cupertino_time_picker.dart:79`, `sheet_helpers.dart:18,35`,
  `month_year_picker.dart:23`; `Radius.circular(24)` at `settings_drawer.dart:71`.
  The `AppRadius` scale stops at `r16` then jumps to `rFull`, so these sheet/drawer
  top-corner radii have no token. Add an `AppRadius.r20`/`r24` (or a `sheetTop`
  token) and reference it, or accept as sheet-specific and document.
- **C2 — On-scale spacing written as raw literals** (systemic, low priority).
  Many `SizedBox`/`EdgeInsets` use values that are *on* the AppSpacing scale
  (12/16/24…) but as literals instead of `AppSpacing.spN`
  (e.g. `client_detail_view.dart:130`, `employee_details_view.dart:146`,
  `settings_tiles.dart:137`). No genuinely off-scale value exists (verified — the
  1–3px nudges, 1px calendar gutter, and 48px splash inset are sanctioned). This is
  a single optional tokenization pass, not per-line bugs.

**Orphaned-looking l10n keys (deferred — do NOT delete in a code sweep):**
- **L1 — `error_couldNotSaveChangesTryAgain`** (`app_en.arb:318` + `app_fr.arb`).
- **L2 — `error_couldNotAddClientTryAgain`** (`app_en.arb:322` + `app_fr.arb`).
  Both have zero `context.l10n.*` call sites but are explicitly listed in CLAUDE.md
  as *reserved failure-UX strings* ("reuse before adding new ones"). Treat as
  reserved-for-reuse; revisit only in a deliberate l10n-pruning pass that also
  updates the CLAUDE.md reserve list. All other ~350 ARB keys have live call sites.

---

## Notes / uncertainties
- **Doc drift:** `functions/index.js:23` exports `propagateClientEdits` (from
  `functions/client_propagation.js`), but the "Cloud Functions" section of
  `CLAUDE.md` lists the older module set and doesn't mention `client_propagation.js`.
  Worth a docs refresh. **Caveat:** in this repo `CLAUDE.md` and `.claude/` are
  gitignored, so that update can't be committed — it's a local-only edit.
- **Unused-dependency scan false positives (confirmed, not dead weight):** the
  static scan flagged `build_runner`, `freezed`, and `flutter_launcher_icons` as
  having no `package:<name>/` import. All three are tooling — `freezed`/`build_runner`
  generate the `.freezed.dart` files that ARE in active use, and
  `flutter_launcher_icons` is a manually-run CLI configured in `pubspec.yaml`.
  Keep all three.
- **`functions/scripts/backfill.js`** is a one-time `usersByUid` bridge migration
  (idempotent, run-once) — not the removed `backfillLegacyClientNames`. Likely
  already executed; kept as an ops runbook.
- Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/.gen/**`) were excluded
  from the review per `analysis_options.yaml`.
- No commented-out code blocks, stray `print`/`debugPrint`, or non-`pre-ship`
  `TODO`/`FIXME`/`HACK` markers exist in `lib/`.
