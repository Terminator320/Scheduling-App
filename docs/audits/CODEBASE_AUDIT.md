# Codebase Audit — 2026-07-21

> **Implementation status (same day):** every reported finding below was
> implemented on `notification` — S1 (`first_unlock_this_device` + marker
> bump), S2 (APNs token shape check, malformed → pruned), B1–B3 (`mounted`
> guards), B4 (backup-slot migration), I1–I2 (61 jest tests; also surfaced
> that `functions/wave/__tests__/` already held overlapping tests in a
> convention-violating location — all six files consolidated into
> `functions/__tests__/` as `wave_*.test.js`), I3 (19 Flutter tests; two
> controller cases skipped honestly — they sit behind `sync()`'s
> `Platform.isIOS` gate, unfakeable on a Windows host), I4
> (`showAppBottomSheet` + shared `showClientDetailSheet`), I5 (per-host
> HTTP/2 session reuse with idle timeout + drop-on-transport-error), I6 (all
> seven extractions; every build() now ≤73 lines), and both 🟡 items
> (comment added; the Timer→Debouncer swap deliberately NOT made — the
> report itself advises against a blind swap).
>
> **New finding discovered during implementation (NOT yet acted on):**
> `functions/wave/mappers.js` — `toWaveCustomerInput` reads only `name` and
> never applies the documented Dart-side `name ← businessName` legacy
> fallback, so a legacy business-only client (empty `name`, populated
> `businessName`) syncs to Wave with an empty name. The new test pins the
> CURRENT behavior; changing it also changes `mappedFieldsHash` (would
> re-enqueue those customers once). Decide deliberately.

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`, `lib/l10n/*.arb`). Baseline: `56b399d`
(the Crashlytics fix pass) on `notification`, clean tree.

> Supersedes `docs/archive/CODEBASE_AUDIT_2026-07-19.md`. The three S1/S2
> findings from that pass (disabled-employee read hole, two missing Live
> Activity indexes) were implemented and deployed in 1.34.1; this run
> confirms none of them regressed.

**Method:** deterministic static scan (analyzer, `dart fix`, functions ESLint,
unused-file/dep heuristics), then five parallel deep reviewers (security, bugs,
dead-code/convention, performance, maintainability), each primed with the
project's do-not-touch invariants.

## Summary

- Scanned: all of `lib/` (~350 top-level types across 9 features + core/shared),
  `functions/` (21 exports + wave module), both rules files, 429 ARB keys,
  `test/` and `functions/__tests__/`.
- Auto-fixed (safe, in the diff): **11** — spacing-token consistency swaps
  (`SizedBox(height: 12)` → `AppSpacing.sp12` etc.) across 8 files. Nothing
  else was auto-fixable: the analyzer, `dart fix`, and ESLint were **all
  already clean**, and the l10n/dead-symbol/dependency sweeps found zero
  removable code.
- Reported for your decision: **12** (⚠️ 0 pre-ship · 🔴 2 security S4 ·
  🟠 4 bugs (3×S3 crash-class, 1×S4) · 🔵 6 improvements)
- Verification: `flutter analyze` clean (0 errors/warnings, unchanged vs.
  baseline) · `flutter test` full suite **981/981 passed** ·
  functions `npm run lint` clean.

## Auto-applied cleanups (review the diff)

| File:line | Change | Why |
|---|---|---|
| `lib/features/clients/widgets/views/client_detail_view.dart:130,159,228` | raw `24`/`12`/`12` → `AppSpacing.sp24`/`sp12`/`sp12` | token consistency (file already uses tokens) |
| `lib/features/calendar/screens/main_calendar_screen.dart:341-342` | `Positioned(bottom: 16, left: 16)` → `AppSpacing.sp16` | token consistency |
| `lib/features/settings/widgets/views/settings_drawer.dart:131` | `12` → `AppSpacing.sp12` | token consistency |
| `lib/features/settings/widgets/dialogs/delete_account_dialog.dart:22,68,121` | `12` → `AppSpacing.sp12` ×3 | token consistency |
| `lib/features/settings/widgets/views/text_size_view.dart:241` | `8` → `AppSpacing.sp8` | token consistency |
| `lib/features/calendar/widgets/sections/photo_picker_section.dart:254,292,328,447` | `4`×3, `8` → `sp4`/`sp8` | token consistency |
| `lib/features/calendar/widgets/views/details_view_widgets.dart:76` | `8` → `AppSpacing.sp8` | token consistency |
| `lib/shared/widgets/fields/labeled_text_field.dart:179` | `4` → `AppSpacing.sp4` | token consistency |

All swaps are value-identical (`sp4=4 … sp24=24`) — zero visual change.
> Full detail is in `git diff`. Nothing below this line was auto-changed.

## ⚠️ Pre-ship checklist

None. No `TODO(pre-ship)` scaffolding exists in `lib/` or `functions/` (all
references are archived docs); App Check is enforced on every callable.

## 🔴 Security findings (review required)

### S1 — Cached identity keys are backup-eligible under `first_unlock` · severity: low (S4) · confidence: high
- **Where:** `lib/core/storage/secure_storage_service.dart:64-72` (the new
  `IOSOptions(accessibility: KeychainAccessibility.first_unlock)`)
- **Risk:** `first_unlock` items are included in encrypted device/iCloud
  backups, so the cached uid/docId/name/email and the biometric flag can
  propagate to a restored device. Not a regression — the previous default
  (`unlocked`) was also backup-eligible — and nothing here is a secret
  (tokens live in FirebaseAuth; role is never cached). The migration design
  itself was reviewed and judged correct.
- **Fix (optional hardening):** use `first_unlock_this_device` for these keys
  — strictly better than both old and new settings; the only cost is the
  cache not surviving a device restore, which self-heals on next sign-in.
  Requires bumping the migration marker so existing items re-migrate.

### S2 — APNs device token interpolated into HTTP/2 `:path` without charset check · severity: low (S4) · confidence: high
- **Where:** `functions/apns_client.js:271` (`/3/device/${token}`); the
  `liveActivityTokens` rule caps size (1–500) but not charset.
- **Risk:** Not practically exploitable (HTTP/2 headers are length-delimited —
  no request splitting; Node rejects invalid path chars → caught `ok:false`;
  a user can only write their own token rows). Defense-in-depth only.
- **Fix:** validate `^[A-Za-z0-9]+$` server-side before building the path,
  and optionally mirror the charset in the rules. Needs a functions deploy.

## 🟠 Bug findings (review required)

### B1 — Add-appointment date picker writes to a controller with no `mounted` guard · severity: S3 (crash-class edge) · confidence: high
- **Where:** `lib/features/calendar/widgets/sheets/add_appointment_sheet.dart:82`
- **Problem:** `await showAdaptiveDatePicker(...)` then
  `_controllers.date.text = ...` with no `!mounted` check. The sibling
  `_pickStartTime`/`_pickEndTime` in the same file (lines 93, 108) both guard.
  If the sheet is torn down while the picker is open (sign-out/kick-out,
  account-status flip), this writes to a disposed `TextEditingController`.
- **Fix:** `if (picked == null || !mounted) return;`

### B2 — Same bug in the edit form's date picker · severity: S3 · confidence: high
- **Where:** `lib/features/calendar/widgets/views/details_edit_body.dart:143`
  (siblings at 157/171 guard with `!context.mounted`; this one doesn't)
- **Fix:** `if (picked == null || !context.mounted) return;`

### B3 — Month/year picker calls `setState` without `mounted` · severity: S3 · confidence: high
- **Where:** `lib/features/calendar/screens/main_calendar_screen.dart:224`
  (`_pickMonth()` → `_setFocusedDay(picked)`; the guarded twin is at line 212)
- **Fix:** `if (picked != null && mounted) _setFocusedDay(picked);`

### B4 — Keychain migration has a delete→write gap with no rollback · severity: S4 (latent) · confidence: medium (real in code, hard to reach)
- **Where:** `lib/core/storage/secure_storage_service.dart:96-102`
- **Problem:** `_migrate()` does read → delete → write per key. A crash or
  Keychain error in the gap after `delete` loses that key's value (the retry
  reads null and skips it). Impact is bounded: every key is re-derivable
  (re-login / re-onboard / re-enable biometrics). The window is very narrow
  and post-first-unlock.
- **Fix:** stash the value under a temp key before the delete (or accept the
  risk — plain add-before-delete isn't possible: SecItemAdd fails on a
  duplicate account/service regardless of accessibility class). Low priority.

## 🔵 Areas to improve (review required)

### I1 — Untested Wave mapping layer · impact: high · confidence: high
- **Where:** `functions/wave/mappers.js` (355 lines, zero jest coverage)
- **Opportunity:** `toWaveCustomerInput` / `fromWaveCustomer` /
  `mappedFieldsHash` / province-country mapping / `streetFromAddress` are all
  pure and directly requireable. `mappedFieldsHash` drives outbox idempotency —
  a silent bug corrupts synced billing records or causes duplicate/missed syncs.
- **Suggested improvement:** unit tests: province/country round-trips (incl.
  legacy values), `streetFromAddress` edges, a representative record incl. the
  legacy businessName-only case, and hash stability (same input → same hash).

### I2 — Untested Wave import cadence gate · impact: high · confidence: high
- **Where:** `functions/wave/import_schedule.js` (`isImportDue` — extracted
  expressly "so jest can require it directly", but no test exists)
- **Suggested improvement:** plain cases — off/unknown → false; never-run →
  true; at-boundary and ±1ms around the weekly/monthly thresholds. A boundary
  bug here silently stops or over-runs the daily import and only shows days later.

### I3 — Untested Live Activity token repo + registration controller · impact: high · confidence: high
- **Where:** `lib/features/live_activity/data/live_activity_token_repository.dart`
  (no test; `deleteTokensOfKind` is the ONLY thing that stops push-started
  cards for an opted-out user) and
  `lib/features/live_activity/application/live_activity_registration_controller.dart`
  (only its pure gate is tested; CLAUDE.md documents an ordering bug already
  fixed here once — exactly what a controller test would pin)
- **Suggested improvement:** mirror `presence_repository_test.dart` for the
  repo (mock the query/delete chain; assert `createdAt` stamped once).
  Controller test: cold-start `sync()` no-ops when the preference is off;
  `unregister()` deletes by kind even when `_docId` was never set; concurrent
  `sync()` calls coalesce via `_pendingResync`.

### I4 — Sheet-opening boilerplate repeated at 8 sites + one cloned function body · impact: medium · confidence: high
- **Where:** `calendar/utils/sheet_helpers.dart:12-39`,
  `clients/screens/clients_screen.dart:55-61`,
  `clients/widgets/sheets/add_client_sheet.dart:34-39`,
  `clients/widgets/views/clients_list_view.dart:116-122`,
  `employees/screens/employees_screen.dart:60-67,99-108`,
  `presence/widgets/staff_roster_sheet.dart:23-28`
- **Opportunity:** all 8 repeat `isScrollControlled: true, backgroundColor:
  Colors.transparent, sheetAnimationStyle: AppMotion.sheetStyle`; and
  `clients_screen.dart:55` / `clients_list_view.dart:116` are an exact cloned
  `ClientDetailSheet`-opening body (fix-one-miss-the-other risk).
- **Suggested improvement:** `showAppBottomSheet<T>(context, {builder, shape})`
  wrapping the 3 fixed properties; extract one shared
  `showClientDetailSheet(context, client)` for the two clones. (8 ≥ 3
  instances — passes the anti-premature-abstraction bar.)

### I5 — APNs client: no HTTP/2 session reuse within a sweep · impact: low-medium · confidence: high
- **Where:** `functions/apns_client.js:283-313` (`sendTo` connects + closes
  per push)
- **Opportunity:** each Live Activity push pays a fresh TCP+TLS+HTTP/2
  handshake (~100–300 ms) to Apple; a 5-min sweep can send several.
  Bounded by active-card count (single digits at this business's scale).
- **Suggested improvement:** cache one connected session per host for the
  invocation (idle timeout + reconnect-on-error), reuse across `_sendToRow`.

### I6 — Six `build()` methods well over the 60-line guideline, each with a named seam · impact: low · confidence: high
- **Where / seam:**
  - `calendar/widgets/dialogs/image_viewer.dart:211-325` (115) → extract the
    three overlay layers into `_ViewerOverlay`
  - `settings/widgets/cards/settings_tiles.dart:302-416` (115) → promote the
    existing `identity` local into `_ProfileIdentity` + `_ProfileHeaderBanner`
  - `calendar/widgets/sections/photo_picker_section.dart:116-229` (114) →
    split the two thumbnail loops into `_existingThumb`/`_newThumb` builders
  - `settings/widgets/views/text_size_view.dart:34-142` (108) → `_PreviewCard`
  - `wave/widgets/wave_settings_section.dart:148-244` (97) →
    `_connectedStatus(connection)`; plus its 3 action methods repeat an
    identical try/WaveFailure/finally shape → one `_runWaveAction` helper
    (also a chance to add the missing `logger.warn` per error-handling.md)
  - `employees/widgets/sheets/employee_form_sheet.dart:265-367` (103) → hoist
    the duplicated label+description block shared by compact/wide branches
  - (minor) `presence/screens/live_map_screen.dart:407-483` → `_MapFabColumn`

## 🟡 Code-quality suggestions (optional)

- `lib/features/presence/application/presence_sync_controller.dart:219` — the
  trailing-flush `Timer` is a cancel-and-restart shape matching `Debouncer.run`,
  but it's entangled with throttle state and heartbeat cancellation — refactor
  deliberately if ever touched, don't blind-swap.
- `lib/features/employees/widgets/fields/employee_color_grid.dart:194-200` —
  hardcoded rainbow-gradient colors for the "any color" affordance; decorative
  and fine as-is, but add a "deliberately theme-invariant" comment mirroring
  `dashboard_hero.dart:22-24` so the next audit doesn't re-flag it.

## Notes / uncertainties

- Confirmed clean (checked, not skipped): 0 orphaned ARB keys (429 swept with a
  validated boundary regex), 0 dead public symbols (all 18 borderline
  candidates resolved to provider/isolate/factory patterns), 0 SnackBar /
  Firestore-in-UI / `throw Exception` / `isDark`-styling violations, and all 4
  unused-dependency heuristics were false positives (`freezed` has 9 generated
  files; `flutter_launcher_icons` has its config block;
  `google_maps_flutter_ios_sdk9` registers natively via
  `GeneratedPluginRegistrant.m`).
- `appointment_form_validator` was flagged as a possible test gap and
  disproven — `test/features/calendar/appointment_form_validator_test.dart`
  exists.
- The token-repo get-then-set (in place of `runTransaction`) is the deliberate
  cloud_firestore-iOS-crash workaround from 56b399d, not a race finding.
- Security positives re-confirmed: callable guard ordering, App Check on all
  callables, sha256-only signup codes, bounded TTLs, admin-gated
  collection-group presence read, no PII/secrets in logs.
