# Codebase Audit — 2026-07-11

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`, `test/`). Baseline: working tree on branch `notification` (clean at start).

> **Update — all findings implemented (2026-07-11).** After the audit the user said "do all", so every finding below (S1, B1–B2, I1–I6, CQ1–CQ3) was implemented in this same working tree. Verification: `flutter analyze` **clean**, `flutter test` **809 pass** (was 792 — 2 new test files added), `functions` ESLint **clean** + jest **289 pass**. S1 requires a `firebase deploy --only firestore:rules` to take effect. The sections below are the original findings, kept as the record of what changed.

## Summary
- Scanned: whole repo — Flutter client (`lib/`), Cloud Functions (`functions/`), security rules, tests.
- Auto-fixed (safe, in the diff): **0** — static scan was clean (`flutter analyze`: no errors/warnings; `dart fix`: nothing to fix; Functions ESLint: clean; no unused files; no unused deps). Nothing met the safe-to-auto-apply bar.
- Reported for your decision: **12** (⚠️ 0 pre-ship · 🔴 1 security · 🟠 2 bugs · 🔵 6 improvements · 🟡 3 code-quality)
- Verification: `flutter analyze` clean (no change vs baseline — no edits made) · tests not re-run (no code changed) · Functions lint clean.

This is a mature, repeatedly-audited codebase. All five review lenses (security, bugs, dead-code, performance, maintainability) came back with only low-severity findings; the newest code on branch `notification` (push, iOS widget, Wave cadence, dashboard) is well-engineered and upholds its documented invariants.

## Auto-applied cleanups
None. The static scan found nothing safe to auto-fix, and the borderline mechanical items (EdgeInsets → `AppSpacing`) are report-only because a prior deliberate spacing pass left some sub-4px nudges raw on purpose — see 🟡 CQ3.

## ⚠️ Pre-ship checklist
No **code-level** pre-ship blockers found this run. No destructive `TODO(pre-ship)` scaffolding, and the App Check enforcement flips are already live (verified in prior audits). The remaining launch tasks are all iOS/Mac-side and non-code (App Attest console enable + Xcode entitlement, dSYM Run Script, carry `ios/GoogleService-Info.plist`, ASC privacy form) — tracked in `docs/plans/IOS_APP_STORE_HANDOFF.md`, not actionable from this Windows box.

## 🔴 Security findings

### S1 — Invited-user `users` read rule omits `email_verified` · severity: low · confidence: high (gap) / med (reachability)
- **Where:** `firestore.rules:119-121` — the `users` read clause `isSignedIn() && resource.data.status == 'invited' && resource.data.email == request.auth.token.email`.
- **Risk:** Firebase email/password signup does not verify email ownership, so someone who registers an Auth account with an *unclaimed* invited email can read that invited employee's doc (name, email, phone, colorValue, role) and squat the invite (blocking the real employee's signup). **Disclosure/DoS only — no privilege escalation:** activation is code-gated server-side (`redeemSignupCode` requires the one-time code and re-checks token email), and the update rule is admin-only.
- **Fix:** add `&& request.auth.token.email_verified == true` to that read clause, or drop the clause entirely (the comment above it already notes invite resolution runs server-side and this isn't meant as a client list query). Needs a `firebase deploy --only firestore:rules`.

## 🟠 Bug findings

### B1 — Deleted admin sees "admin access revoked" instead of "account disabled" · severity: low · confidence: high (verified)
- **Where:** `lib/main.dart:388-395` (`_listenForRoleRevocation`), registered before `_listenForDeletedAccount` at `:436-437`.
- **Problem:** When an admin account is deleted at runtime, `currentUserDocProvider` goes populated→empty and `userRoleProvider` emits `''` (confirmed: `account_status_provider.dart:35-39`). The revocation guard `prevRole == 'admin' && nextRole != null && nextRole != 'admin'` is true for `''`, so it fires first, claims the shared `_isHandlingAccountExit` flag, and signs the user out with `error_yourAdminAccessWasRevoked` — suppressing the deletion handler's correct `error_thisAccountHasBeenDisabled`. Cosmetic (wrong exit message on a rare edge), not a security issue.
- **Fix:** in `_listenForRoleRevocation`, ignore the empty-doc transition — require `nextRole != null && nextRole != '' && nextRole != 'admin'` — so the deletion listener owns the empty-doc case.

### B2 — iOS home widget locale goes stale after in-app language change · severity: low · confidence: med
- **Where:** `lib/main.dart:295-300` (`setLanguage`) + `lib/features/home_widget/application/widget_sync_service.dart:158`.
- **Problem:** `widgetPayloadProvider` reads `AppLanguageController.instance.value` at build time, but that controller isn't a watched Riverpod dependency, so the provider isn't recomputed on language switch. `setLanguage` re-syncs the FCM token locale (correct) but not the widget, so the iOS home-screen widget keeps rendering old-language status/chrome labels until the next `myAppointmentsProvider` emission changes the payload signature — potentially a long time for a static schedule.
- **Fix:** in `setLanguage`, also refresh the widget — `ref.invalidate(widgetPayloadProvider)` or read `widgetPayloadProvider.value` and call `widgetSyncServiceProvider.sync(...)` — mirroring the push re-sync.

## 🔵 Areas to improve

### I1 — `PushRegistrationController` has no controller test · impact: medium · confidence: high
- **Where:** `lib/features/notifications/application/push_registration_controller.dart` (176 lines; only the pure `shouldRegisterPush` helper is tested).
- **Opportunity:** The FCM-token lifecycle — sync gating, the uid+locale fast-path dedup (`:83-88`), refresh-subscription lifecycle, sign-out teardown — is load-bearing (decides whether a device gets push at all) and untested. It's hard to test today because it reads `FirebaseAuth.instance` directly (`:66, :76`) instead of an injected dep, inconsistent with the repo's "inject deps for testability" convention.
- **Suggested improvement:** inject `FirebaseAuth` (default `.instance`) like other services, then add a controller test covering the register gate + fast-path skip.

### I2 — `dashboard_hero.dart` `build()` is 165 lines · impact: medium · confidence: high
- **Where:** `lib/features/dashboard/widgets/sections/dashboard_hero.dart:25-190`.
- **Opportunity:** One `build()` inlines the header block, the stacked proportional status bar, the legend `Wrap`, and a conditional unassigned banner — well over the ~60-line guideline; bar and legend share the `visible` list and are easy to break independently.
- **Suggested improvement:** extract `_StatusBar`, `_StatusLegend`, `_UnassignedBanner` sub-widgets (each a distinct self-contained block — a genuine split, not single-use churn).

### I3 — Per-recipient Firestore reads redundant in notification sweeps · impact: low · confidence: high (redundancy) / ~50% (measurable here)
- **Where:** `functions/notification_utils.js:578` (`sendToEmployee`), called from `runReminderSweep:789`, `runOverduePromptSweep:838`, `runDailyDigest:882`.
- **Opportunity:** each delivery does `users/{id}.get()` + `fcmTokens.get()`, so an employee on N appointments in one sweep is re-read N times. Only bites on a burst of genuinely-new claims (the ledger `create()` short-circuits repeats); reminders run every 5 min, overdue every 15 min.
- **Suggested improvement:** memoize a `Map<employeeDocId, {user, tokenDocs}>` per sweep invocation and pass it into `_deliverRecipientOnce`/`sendToEmployee` so each employee is read at most once per run.

### I4 — `WidgetSyncService._signatureOf` dedup is untested pure logic · impact: low · confidence: high
- **Where:** `lib/features/home_widget/application/widget_sync_service.dart:112-115`.
- **Opportunity:** `buildWidgetPayload` is tested, but the "skip write when jobs unchanged" signature dedup (which strips `generatedAt`) isn't. A regression that lets `generatedAt` into the signature would silently re-write/reload the widget on every stream emission with no test guard.
- **Suggested improvement:** two-line unit test asserting two payloads differing only in `generatedAt` produce equal signatures.

### I5 — `event_details_controller.dart` is a 668-line multi-class file · impact: low-medium · confidence: medium
- **Where:** `lib/features/calendar/application/event_details_controller.dart`.
- **Opportunity:** holds `EventDetailsState` (freezed), the 4-class sealed `EventDetailsSaveOutcome` family, `EventDetailsKey`, and the controller — against the "one class per file" convention. It's well-tested and cohesive, so risk is low; this is tidiness, not urgency.
- **Suggested improvement:** optionally move the sealed `EventDetailsSaveOutcome` family + `EventDetailsKey` to a sibling `event_details_outcome.dart`.

### I6 — Root-app stream subscriptions lack `onError` (and aren't cancelled) · impact: low · confidence: medium
- **Where:** `lib/main.dart:172` (`HomeWidget.widgetClicked.listen`) and `:189` (`service.onMessageOpenedApp.listen`).
- **Opportunity:** both live on `_PaulAppState` (app-lifetime, so the un-cancelled leak is benign) but neither passes `onError`, so a stream error escapes as an unhandled zone error. Inconsistent with the refresh-token sub in `push_registration_controller.dart:148`, which does pass `onError`.
- **Suggested improvement:** add `onError: (e, st) => logger.warn(...)` to each; optionally store + cancel in `dispose()`.

## 🟡 Code-quality suggestions

- **CQ1 — Silent catch in `_signOutQuietly`** (`lib/features/auth/services/auth_service.dart:181`): `} catch (_) {}` swallows all errors during signup rollback, violating "never swallow errors silently." The sibling `signOut()` (`:192-196`) already logs its best-effort failure via `logger.warn` — mirror it: `logger.warn('signOut quiet failed', e, st)`.
- **CQ2 — Two orphaned l10n keys (report only — do NOT strip in a code sweep):** `error_couldNotSaveChangesTryAgain` (`app_en.arb:326` / `app_fr.arb:80`) and `error_couldNotAddClientTryAgain` (`app_en.arb:330` / `app_fr.arb:81`) have **zero** references across `lib/` + `test/` (verified by key name and substring). Catch sites migrated to the `composeErrorNotice` cause+tag pattern. In a deliberate l10n pass, confirm and remove both keys + their `@`-metadata from both ARBs — and update the CLAUDE.md / error-handling.md notes that still list them as reusable strings.
- **CQ3 — ~12 raw scale-value `EdgeInsets` that map to `AppSpacing`:** e.g. `employees_screen.dart:190` `only(bottom: 16)` → `sp16`; `settings_tiles.dart:137` `symmetric(vertical: 12)` → `sp12`; `employee_details_view.dart:203` `only(right: 12)` → `sp12`; `delete_account_dialog.dart:82` `symmetric(horizontal: 8)` → `sp8`. Behavior-preserving but **not auto-applied**: several sites (`main_calendar_screen.dart:455`, `settings_tiles.dart:35`, `text_size_view.dart:91`) interleave clean values with intentional 1-3px nudges the prior spacing-tokenization pass left raw on purpose — swapping needs a per-site judgment call. Swap only the pure `8/12/16/24/32` literals if you do this.

## Notes / uncertainties
- **Verified clean:** deny-by-default Firestore/Storage rules; every callable enforces App Check + auth + `assertPayloadShape` + `assertAdmin`/rate-limit as appropriate; secrets only via Secret Manager; App Check active in `main()`; role never cached; employee `employeeIds` visibility filter present; loose Map casting of callable responses everywhere; the 3 sanctioned SnackBar sites only; zero `throw Exception(...)`; no `FirebaseFirestore.instance` in UI; all `isDark`/brightness branching sanctioned (helpers + theme-extension resolution + the dark-mode toggle UI).
- **No dead code** and **no unused files** (`l10n_extensions.dart` is live via the `l10n.dart` barrel). The 3 static-scan "unused dep" hits — `build_runner`, `freezed`, `flutter_launcher_icons` — are all expected tooling false-positives (codegen + a CLI icon generator, config at `pubspec.yaml:146`).
- Two hardcoded-color sites are intentional and were **not** flagged for change: `dashboard_hero.dart:21-22` (theme-invariant on-primary data hues, comment-documented) and `employee_color_grid.dart:194-200` (decorative rainbow `SweepGradient` for the custom-color affordance).
- No files were edited, so tests were not re-run; `flutter analyze` remains clean.
