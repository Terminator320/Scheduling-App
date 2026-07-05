# Codebase Audit — 2026-07-05

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`test/`), with the parallel deep review weighted on everything that changed since
the last audit's baseline (`fca4d27`). Baseline: working tree on branch `moblie`
(HEAD `1d3c7ba`), which already carries the doc reorg (`docs/audits/`,
`docs/plans/`) and the `flutter_contacts ^2.2.2` bump.

## Summary
- Scanned: ~35 changed code files across `lib/` + `functions/` (deep review),
  plus a whole-repo static + l10n + convention sweep.
- Auto-fixed (safe, in the diff): **1** — removed stray blank-line litter in
  `lib/main.dart` (leftover from comments trimmed in the `3071195` commit).
  `dart fix` had nothing to apply; Cloud Functions ESLint was clean.
- Reported for your decision: **~8** (⚠️ 2 pre-ship · 🔴 0 security · 🟠 0
  confirmed bugs (2 advisories) · 🔵 4 improvements · 🟡 2 quality · 16
  orphaned-looking l10n keys deferred).
- Verification: `flutter analyze` clean (no errors/warnings vs. baseline) ·
  `flutter test` — see the verification note at the bottom · `functions` ESLint
  clean.

**Bottom line:** the codebase is in excellent shape. The full 2026-07-04 audit
fixed everything it found, and the commits since (`3071195` "improving code",
`1d3c7ba` "fixing cloud functions") are disciplined hardening + net-positive
performance work — all reviewed and verified sound. No confirmed bugs, no new
security issues, no performance regressions. Everything below is report-only.

## Auto-applied cleanups (review the diff)
| File:line | Change | Why |
|---|---|---|
| `lib/main.dart:74-78` | Collapsed a stray double blank line and a leading blank inside `if (_useFirebaseEmulator)` | Whitespace litter left when invariant comments were trimmed in `3071195`; behavior-preserving |
> Full detail is in `git diff`. Nothing below this line was auto-changed.

## ⚠️ Pre-ship checklist (act before release)
- [ ] **App Check enforcement is OFF on the admin callables** —
  `functions/invites.js:43` (`APP_CHECK = {enforceAppCheck: false}`) and
  `functions/wave/callables.js:126` (`enforceAppCheck: false`), plus the other
  `TODO(pre-ship)` flips tracked in
  `docs/audits/CODEBASE_AUDIT_2026-07-01.md`. Callers are still protected by
  `req.auth` + `assertAdmin` today, but flip these to `true` before the store
  release. Carried over — unchanged this cycle.
- [ ] **Confirm `backfillLegacyClientNames` already ran in production before
  deploying `functions/maintenance.js`.** Commit `1d3c7ba` deleted the one-time
  `backfillLegacyClientNames` scheduled function. That's safe *if* the backfill
  completed (its guard doc was written). Documented legacy business-only docs
  store an empty-string `name` (present, not missing) so they stay visible via
  the `businessName` fallback — but any legacy doc missing `name` entirely would
  drop out of the `orderBy('name')` clients list/search. Verify the migration
  finished, then deploy. (Operational check, not a code defect.)

## 🔴 Security findings (review required)
None. The security review verified the full changed surface: image magic-byte
validation, the durable rate limits, App Check activation in `main()`, the
role-from-Firestore invariant, `signupCodes`/`wave` rule locks, and the
callable guards are all intact. The `maintenance.js` shrink only removed a
completed migration and its now-unused `FieldValue` import. No secrets, keys, or
PII introduced anywhere in the diff.

## 🟠 Bug findings (review required)
No confirmed high/medium-severity bugs. The recent defensive changes
(reentrancy `finally` reset, monotonic search-request-id guard, screen-cache
identity invalidation, `Object?` status returns threaded through mounted-checked
callers) all verified correct. Two low-confidence advisories, surfaced for
awareness:

### B-adv1 — `createEmployeeInvite` consumes a rate-limit slot before payload validation · low · ~20%
- **Where:** `functions/invites.js:126`
- **Problem:** `enforceDurableRateLimit("createEmployeeInvite", uid, 20, 1h)`
  runs before `assertPayloadShape`/`requireString`, so malformed requests and
  idempotent re-invites both consume a slot; a bulk onboarding of >20 employees
  at once would hit the cap at #21.
- **Fix:** Intentional (defense-in-depth parity with `waveBootstrap`) — no change
  needed unless you expect bulk onboarding sessions, in which case raise the cap
  or move the limit after shape validation.

### B-adv2 — backfill-removal data-shape edge case
- Covered by the pre-ship checklist item above (verify the migration ran).

## 🔵 Areas to improve (review required)
### I1 — `AppointmentSeriesEditor` has no direct unit test · impact: medium · high
- **Where:** `lib/features/calendar/application/appointment_series_editor.dart`
  (~108 lines)
- **Opportunity:** Series rewrite/replace is a load-bearing correctness
  invariant. It's currently only *indirectly* covered through
  `event_details_controller_test.dart` save() series cases. It takes the
  `AppointmentsRepository` interface, so it's trivially mockable.
- **Suggested improvement:** Add a focused unit test with a mock repo, or
  consciously accept the integration coverage.

### I2 — `hub_shell` screen-cache invalidation is untested · impact: low-medium · high
- **Where:** `lib/routes/hub_shell.dart` (the new `_cachedScreenFor` identity
  cache + `_TabViewInsets` pin added this cycle)
- **Opportunity:** `hub_shell_test.dart` covers keep-alive but not cache
  invalidation on `_isAdmin|_employeeId|_userName|_userEmail` change or the
  hidden-tab `viewInsets` zero-pin.
- **Suggested improvement:** One widget test asserting the same screen instance
  survives a shell `setState` and is rebuilt when the identity args change.

### I3 — `details_view_body.build()` carries a ~35-line derivation preamble · impact: low-medium · high
- **Where:** `lib/features/calendar/widgets/views/details_view_body.dart:41-83`
  (135-line `build()`)
- **Opportunity:** Lines 49-83 derive phone/address/onCall/materials/contacts
  before a flat `Column` of already-extracted sub-widgets. The tree is fine; the
  preamble is what pushes it over the ~60-line guideline.
- **Suggested improvement:** Move the derivation into a small
  `_DetailsViewModel.from(appointment, client)` value object. Optional — pure
  readability.

### I4 — Two off-scale `EdgeInsets.all(14)` paddings · impact: low · low
- **Where:** `lib/features/clients/widgets/sections/additional_contacts_section.dart:57`
  and `lib/features/settings/widgets/views/text_size_view.dart:153`
- **Opportunity:** `14` sits between `AppSpacing.sp12` and `sp16` (not a
  sanctioned sub-4px nudge). Not auto-fixed because the target token is
  ambiguous — snapping it is a design call.
- **Suggested improvement:** Snap each to `sp12` or `sp16` per your visual
  preference.

## 🟡 Code-quality suggestions (optional)
- `lib/features/employees/widgets/fields/employee_color_grid.dart:194-200` — the
  "custom color" `SweepGradient` hardcodes 7 raw `Color(0xFF…)` hex values where
  `AppColors.employeeColors` exists. **Known/intentional** per prior audits
  ("employee_color_grid gradient intentionally skipped") — listed for
  completeness only.
- `lib/main.dart:74-83` (context) — commit `3071195` trimmed the `C3`
  cold-start-deletion, `C12` flag-reset, and `U2` text-size-composition
  invariant comments that `CLAUDE.md` invariants lean on. Behavior is unchanged
  and improved (DI via `ref.read(...)`), but consider restoring a one-line
  pointer to those invariants so the load-bearing logic stays self-documenting.

## Notes / uncertainties
- **16 orphaned-looking l10n keys** in `lib/l10n/app_en.arb` have zero code
  references — flagged, NOT deleted (many l10n keys are reached via generated
  getters; ARB keys are never stripped in a code sweep). Likely superseded by
  the `composeErrorNotice` migration (`error_couldNotDeleteClientTryAgain:318`,
  `error_couldNotSaveChangesTryAgain:322`, `error_couldNotAddClientTryAgain:326`,
  `error_somethingWentWrongCreatingTheAppointment:534`,
  `error_somethingWentWrongSavingChanges:538`, `error_couldNotCreateEmployee:750`,
  `error_couldNotLoadAppointments:902`, `error_couldNotDeleteAccount:1352`), by
  the read-only detail view's "omit empty sections" refactor (`calendar_noNumber:566`,
  `calendar_noNotes:574`, `calendar_noMaterials:578`,
  `calendar_selectAnAppointmentToViewDetails:674`), test-only
  (`common_resetPassword:762`, used only in `test/widget_test.dart`), or the
  address-field refactor (`common_searchAddress:998`, `common_typeToSearchAnAddress:1002`,
  `common_street:1006`). ⚠️ Caveat: `CLAUDE.md` lists
  `couldNotAddClientTryAgain`/`couldNotSaveChangesTryAgain` as the canonical
  "reuse before adding new" failure-string pool — they may be intentionally
  retained. Confirm against that guidance before pruning. Recommend a deliberate
  l10n pass that removes confirmed-dead keys from both `app_en.arb` and
  `app_fr.arb` in lockstep, then `flutter gen-l10n`.
- Static level was fully clean: `flutter analyze` no errors/warnings, `dart fix`
  nothing, ESLint clean, no unused files. The only "unused dependency" heuristic
  hits (`build_runner`, `freezed`, `flutter_launcher_icons`) are codegen/CLI
  tooling — expected false positives, all legitimately used.
- Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/.gen/**`) and
  device-only services (`image_picker_service`, `media_permission_service`,
  `biometric_auth_service`) were intentionally excluded per project convention.
