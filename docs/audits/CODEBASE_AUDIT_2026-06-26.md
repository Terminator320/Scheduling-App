# Codebase Audit & Mobile Optimization — 2026-06-26

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`, `test/`).
Baseline: working tree on branch `moblie` (clean at start).
Goal: maximize the app for mobile — UX, UI, performance, speed, security, simplicity.

This run combined the codebase-audit deep-review fan-out (security / bugs /
performance / dead-code / mobile-UX reviewers) with a mobile-optimization pass.
Because the explicit goal was to **improve** the app (not just report), the safe,
high-payoff UX / bug / performance fixes were **implemented and verified**; items
that need human judgment or a deploy (Firestore rules, the App Check pre-ship
flip, dependency removals, structural refactors) are **reported** below.

## Summary
- Static baseline: `flutter analyze` clean (no errors/warnings), `dart fix` nothing
  to fix, Functions ESLint clean.
- **Implemented this session (in the diff): 22 fixes across 25 source files** —
  4 verified bugs, 6 destructive-action/feedback safety fixes, 7 accessibility /
  touch-target / overflow fixes, 3 performance wins, plus app-wide keyboard
  ergonomics. 4 new l10n keys (EN+FR, no drift).
- **Follow-up: all 🔵 improvements (I1–I5) implemented** (see "Blue items —
  implemented" below): search-failure error states, form focus-chaining, three
  refactors (shared client-fields section, employee detail-view extraction,
  controller series-helpers split + assignee method), dead-code removal, and
  unused-dependency removal.
- **Still reported for your decision:** ⚠️ 1 pre-ship · 🔴 1 security.
- Verification: `flutter analyze` clean · `flutter test` **581/581 pass** ·
  Functions ESLint clean · `flutter pub get` resolves clean after dep removal.

---

## ✅ Implemented this session (review the diff)

### Verified bug fixes
| Area | File | Fix |
|---|---|---|
| Duplicate appointment on double-tap | `add_event_controller.dart` | Reentrancy guard + mark in-flight **before** the conflict-check round-trip, so the Save button disables on the first tap and a second tap is ignored. |
| Stale/just-deleted clients in search | `firebase_clients_repository.dart` | Added `_invalidateSearchCache()` and call it in `addClient`/`updateClient`/`deleteClient` (mirrors the appointments-repo invariant). |
| Split-layout client delete orphaned the detail pane + froze the button on "Deleting…" | `client_detail_view.dart`, `clients_screen.dart` | New `onDeleted` callback clears the pane in master-detail; `_isDeleting` reset on success. |
| Missing `mounted` re-check after the 120 ms unfocus delay (silent crash) | `employees_screen.dart` | Added `if (!mounted) return;` after `unfocusAfterSheet()` before touching `ref`/`context`. |

### Destructive-action safety & feedback
| Improvement | File |
|---|---|
| "Cancel Appointment" now asks for confirmation (was one-tap, irreversible) | `details_view_body.dart` |
| Employee Disable/Re-enable in the **edit form** now confirms + pushes a success notice (matched the details view) | `employee_form_sheet.dart` |
| Account deletion now shows a blocking progress overlay and can't be re-triggered mid-delete | `settings_screen.dart` |
| Sign-out hardened: try/catch + busy guard (no more uncaught error / double-tap) | `settings_screen.dart` |
| Client edit now pushes a "Changes saved" success notice (was silent vs. Add/Delete) | `client_edit_form.dart` |
| Wave Settings: loading spinner + inline error/retry instead of flashing "Connect"; Import hidden until connected (was a guaranteed-to-fail tap) | `wave_settings_section.dart` |

### Accessibility, touch targets, overflow
| Improvement | File |
|---|---|
| Status-picker chips: 44px min tap target, `Semantics(button, selected)`, `labelMedium` (was ~22px, `fontSize: 10`) | `appointment_status_picker.dart` |
| Employee-picker chips: 44px min tap target + `Semantics` | `employee_picker.dart` |
| Onboarding slides scroll instead of RenderFlex-overflowing at large text / short landscape | `onboarding_screen.dart` |
| Photo remove "×": 32px tap target + `Semantics`/label (was ~18px) | `form_helpers.dart`, `photo_picker_section.dart` |
| Tooltips/semantic labels on FABs (add client/employee), image-viewer close, password-visibility toggle | `clients_screen.dart`, `employees_screen.dart`, `image_viewer.dart`, `delete_account_dialog.dart` |
| `FadeInItem` honours `MediaQuery.disableAnimationsOf` (reduce-motion) and stops allocating a controller per row under it | `fade_in_item.dart` |

### Keyboard ergonomics (app-wide)
- `LabeledTextField` gained `textCapitalization`, `textInputAction`, `onSubmitted`.
- Wired `TextCapitalization.words` on all name fields (client name/first/last,
  contact name, employee name) and `.sentences` on appointment title/notes/materials
  — names auto-capitalize and titles sentence-case on the mobile keyboard.

### Performance
- `filteredEmployeesProvider` → `autoDispose.family` (was a session-long
  per-keystroke cache; now matches the other two search providers).
- `purgeExpiredHistory` (Functions): deletes per-doc image prefixes with
  `Promise.all` instead of awaiting one network round-trip at a time.

> Full detail is in `git diff`. Nothing below this line was changed in code.

---

## ⚠️ Pre-ship checklist (act before release)
- [ ] **App Check is disabled on 5 callables** — `functions/account.js:42`
  (`deleteAccount`), `:151` (`resolveMyInvite`), `functions/wave/callables.js:100`
  (`waveBootstrap`), `:181` (`waveGetConnection`), `:204` (`waveImportCustomers`)
  all set `enforceAppCheck: false`. This is the documented `TODO(pre-ship)`
  testing state. **Flip all five back to `true` before store release** once
  Play Integrity / DeviceCheck mint tokens for the store build, and confirm
  App Check **enforcement** is on for Firestore in the console (see S1).

---

## 🔴 Security findings (review required)

### S1 — `users` read rule exposes active-staff PII to any authenticated principal · severity: medium · confidence: low-med
- **Where:** `firestore.rules:81-86` — clause `isSignedIn() && resource.data.status == 'active'`.
- **Risk:** Email/password self-signup is enabled (`auth_service.dart` uses
  `createUserWithEmailAndPassword`), so a principal with no invite can mint a
  valid token directly against the public Firebase Auth endpoint and run a
  `users where status == 'active'` query to harvest the full active-staff
  directory (names, emails, phones). The client-side "no users doc → sign out"
  guard does not apply to a raw SDK/REST caller. The remaining gate is App Check
  **enforcement on Firestore** (a console toggle, not visible from code).
  Employees seeing *peers'* PII is documented as intentional — the new angle is
  **non-staff self-registered accounts**, which that intent doesn't cover.
- **Fix:** Confirm App Check enforcement is enabled on Firestore (not just
  `activate()`d client-side). For defense beyond App Check, tighten clause 2 so
  the reader must themselves be active staff (gate on the `usersByUid` bridge:
  `userByUidExists() && userByUid().data.status == 'active'`) rather than merely
  `isSignedIn()`. Needs a rules deploy + a query-constraint review (the four-clause
  `users` read rule means new queries must still satisfy a clause).

> Everything else on the security checklist verified clean: App Check active in
> `main()`; role/`isAdmin` always read from Firestore; image magic-byte validation
> client+server; employee `employeeIds` visibility filter enforced via the server
> bridge; `ClientRecord.toMap` never emits `waveCustomerId`/`wave`; Wave reads only
> via `waveGetConnection`; callable payloads validated; durable rate limiting on
> auth-sensitive callables; emails normalized; no secrets in source/logs.

---

## 🔵 Blue items — IMPLEMENTED (review the diff)

All five "areas to improve" were implemented in the follow-up, verified green.

### I1 — Search failures now show an error, not "no results" ✅
`clients_list_view.dart` and `appointment_history_view.dart`: the search
`error:` branch now renders an inline error (via `composeErrorNotice`, no logging
— it's a builder) when the instant local fallback is also empty, instead of the
empty state. An offline/permission-denied search no longer looks like "this
client/appointment doesn't exist."

### I2 — Form focus-chaining / keyboard "next" ✅
`LabeledTextField` gained `textInputAction`/`onSubmitted`; the shared client
fields, the employee name/email, and the appointment title now set
`TextInputAction.next` (Flutter's default `nextFocus` moves between fields with
no explicit FocusNode plumbing). Multi-line fields (notes/materials) keep the
newline action.

### I3 — Refactors ✅
- **Shared `ClientPersonalFieldsSection`** (`clients/widgets/sections/`) replaces
  the byte-identical 6-field block previously duplicated in `client_edit_form.dart`
  and `add_client_sheet.dart` — field changes now land once. (Drove I2's `next`
  wiring into one place.)
- **`employee_details_view.dart`** `build()` cut from ~152 → ~70 lines by
  extracting `_ColorRow` and `_ActionButtons`.
- **`event_details_controller.dart`** — moved the 4 pure series helpers into a
  new, unit-tested `event_series_helpers.dart` (6 new tests) and extracted the
  load-bearing assignee-preservation block into a named `_resolveAssignees`
  method (the freezed `part` was left untouched — no build_runner needed).

### I4 — Dead public members removed ✅
Deleted (each verified zero-reference): `ClientRecord.displayContact`,
`PhotoUploadNotifier.hasErrors`, `AuthService.authStateChanges`,
`MediaPermissionService.openSettings`, `TextLimits.clientNotes`,
`UnknownFailure`, `AppLogger` `debug`/`info`/`error`/`fatal` (kept `warn`),
`AppointmentsRepository.watchAll` + `EmployeesRepository.getEmployeeById`
(abstract+impl), `AuthErrorContext.passwordReset`. **Kept** `NoticeService.info`
(exercised by a test; intentional success/error/info symmetry) and
`EmployeeRecord.uid` (round-trips through Firestore serialization).

### I5 — Unused dependencies removed ✅
Removed from `pubspec.yaml`: `http`, `path`, `path_provider` (now resolve as
transitive), `json_annotation` + `json_serializable`, `riverpod_annotation` +
`riverpod_generator` (no `.g.dart` exists — manual Riverpod + hand-written
`fromMap`/`toMap`), `firebase_core_platform_interface` (redundant direct).
Removed `firebase-functions-test` from `functions/package.json`.
`flutter pub get` re-resolves clean. **Kept** `flutter_launcher_icons` — the
scan false-positived it; it's used via the `dart run flutter_launcher_icons` CLI
plus its `flutter_launcher_icons:` config block (not an import). Also kept
`firebase_app_check`, `firebase_performance` (native auto-init),
`build_runner`/`freezed`/`freezed_annotation` (9 `.freezed.dart` files).

---

## 🟡 Notes / smaller polish (optional)
- ~15 orphaned-looking l10n keys (e.g. `error_couldNotAddClientTryAgain`,
  `calendar_noNotes`, `common_searchAddress`) have no code references — but several
  are the deliberately-retained "Failure UX strings" reuse palette per CLAUDE.md.
  Confirm intent and prune EN/FR in lockstep in a **separate l10n pass**, not a
  code sweep.
- Settings dark-mode / app-lock rows and the EN/FR language pills are still
  sub-48px (only the switch/pill is the target, not the whole row). Low-risk
  follow-up: give the tiles an `onTap` that flips the value and the pills a 48px
  `InkWell` tap area.
- Convention discipline is otherwise strong: no raw `ScaffoldMessenger.showSnackBar`
  drift (3 sanctioned sites only), no `throw Exception(...)` in `lib/`, no
  `FirebaseFirestore.instance` in widgets, no `isDark` styling branches.

## Verification
- `flutter analyze` — clean (no errors/warnings vs. baseline).
- `flutter test` — **581/581 pass** (575 prior + 6 new series-helper tests;
  3 Wave tests realigned to the corrected Import-gated-on-connection behavior).
- `cd functions && npm run lint` — clean.
- `flutter pub get` — re-resolves clean after the dependency removals.
