# Codebase Audit — 2026-07-26 (second pass)

> **Implementation status (same session, uncommitted on `notification`).**
> "Do all" — implemented **B1, I1, I3**. **I2 was deliberately NOT implemented**:
> on inspection there are only **2** genuine adaptive show-dialog branch sites
> (the third the review cited is a widget-build branch that can't route through
> a show-helper), which is below the project's 3+-instance bar for extraction —
> a helper for 2 six-line branches is the premature abstraction the anti-defaults
> forbid. The 🟡 quality items are intentionally left as-is. Verification:
> `flutter analyze` clean (no new errors/warnings), **1062 flutter tests green**
> (1055 baseline + 7 new).

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`). Baseline: working tree on branch
`notification` (clean before audit — prior audit 295118d already committed).

## Summary
- Scanned: ~279 lib files + `functions/` + rules; deep-reviewed by 5 parallel
  agents (security, bugs, dead code/convention, performance, maintainability).
- Auto-fixed (safe, in the diff): **0** — `flutter analyze` clean (no
  errors/warnings), `dart fix --dry-run` "Nothing to fix", Functions ESLint
  clean, no confirmed dead code, no convention drift. Nothing safe to change.
- Reported for your decision: **5** (⚠️ 0 pre-ship · 🔴 0 security · 🟠 1 bug ·
  🔵 3 improvements · 🟡 1 quality)
- Verification: no edits made, so baseline unchanged — `flutter analyze` clean,
  Functions lint clean (as run by the static scan).

## Auto-applied cleanups
None. The static level is entirely clean and no dead code was confirmed, so
there was nothing reversible-and-obvious to apply. Expected state for this repo
after its prior audit passes.

## ⚠️ Pre-ship checklist
None. No `TODO(pre-ship)`, `FIXME`, `HACK`, or destructive scaffolding markers
exist in `lib/`. No pre-ship App Check flips outstanding (all callables enforce
App Check; providers gate Debug on `kDebugMode`).

## 🔴 Security findings
None. Full sweep found no new verifiable issues. Verified concretely: App Check
active + every callable `enforceAppCheck: true`; Firestore/Storage rules
deny-by-default with correct query-vs-get discipline; client-writable TTL field
`liveActivityTokens.expiresAt` required + bounded; `presence` writes anti-spoofed
(`updatedAt == request.time`, self-only); every callable validates payload before
consuming a rate slot; secrets only in Secret Manager; no role/`isAdmin` from
SharedPreferences; no PII in function logs; image magic-byte validation client-
and server-side.

_Informational only (not shipped code):_ `functions/scripts/seed-emulator.js:123`
logs throwaway test-account passwords — emulator-only dev seeding, not deployed,
standard practice. No action.

## 🟠 Bug findings

### B1 — Photos can be orphaned if the metadata append throws transiently after uploads succeed · severity: low · confidence: medium (~65%)
- **Where:** `lib/features/calendar/data/appointment_image_upload_service.dart:107-155`
- **Problem:** In `_attempt`, each file uploads to Storage and its local staged
  copy is `_deleteQuietly`-d immediately on success (L125–126). Only after the
  loop does `appendAppointmentPictures` (L151) link them to the appointment doc.
  If that single `arrayUnion` update throws **transiently** (e.g.
  `deadline-exceeded` / a brief blip right after the uploads land), the exception
  propagates, the queue entry is **not** removed, and on the next drain
  `_attempt` maps `entry.paths` → `File`s filtered by `existsSync()` — but those
  files were already deleted — so `files` is empty, the entry is removed (L113),
  and the already-uploaded Storage objects are never linked. Result: photos exist
  in Storage but are invisible on the appointment (effectively lost + orphaned
  bytes). Narrow: uploads must succeed, then the metadata write must fail
  non-hangingly. `permission-denied`/`not-found` cases are harmless (appointment
  is gone anyway); the real exposure is a transient error on the append.
- **Note:** The eager-delete is a **deliberate** design (documented in CLAUDE.md)
  to avoid `DateTime.now()`-minted duplicate Storage paths on retry — so this is
  a tradeoff, not an oversight. Any fix must not reintroduce the duplicate-path
  risk.
- **Fix (if pursued):** Remove the queue entry only after the append succeeds.
  On append failure, re-queue the successfully-uploaded images as a "link-only"
  batch (by URL/path) so the retry re-attempts just the Firestore `arrayUnion`
  without re-uploading or re-minting paths.

## 🔵 Areas to improve

### I1 — No direct test for the shared `AppointmentFormConcerns` search race-guard · impact: medium · confidence: high
- **Where:** `lib/features/calendar/application/appointment_form_concerns.dart`
  (169-line shared mixin)
- **Opportunity:** Holds non-trivial shared logic used by both add + edit flows:
  `searchClients` debounce + a **request-id race guard** (stale results dropped),
  `selectClient` custom-address seeding, `toggleEmployee`. It's only exercised
  indirectly through the two controller tests, which may not pin the race guard —
  a regression that drops the request-id check could ship green.
- **Suggested improvement:** Add a focused test driving two overlapping
  `searchClients` calls asserting the stale result is discarded, plus
  `toggleEmployee` add/remove.

### I2 — Three raw cupertino/material dialog branches could share one helper · impact: low-medium · confidence: high
- **Where:** `lib/features/settings/screens/settings_screen.dart:417` (reauth) and
  the signup-code dialog (2×) — each inlines
  `context.isCupertino ? showCupertinoDialog<T> : showDialog<T>`.
- **Opportunity:** The already-extracted `confirm_dialog.dart` proves the pattern;
  these three remain hand-rolled (3 instances → warrants extraction).
- **Suggested improvement:** Add one `showAdaptiveAppDialog<T>(context, builder)`
  in `core/adaptive/` (mirrors the existing `showAdaptiveActionSheet`) and route
  the three sites through it.

### I3 — `day_route_screen` build() mixes ~35 lines of data-prep · impact: low · confidence: high
- **Where:** `lib/features/calendar/screens/day_route_screen.dart:106-163`
  (build is 57 lines; first ~35 are filter-cancelled / sort / resolve-assignee /
  compute-stops derivation).
- **Opportunity:** Under the 60-line guideline but mixes derivation into `build()`.
- **Suggested improvement:** Extract into a `_DayRouteData _prepareBuild()` helper
  — matches the `_prepareBuild` pattern already used in `main_calendar_screen.dart`.

## 🟡 Code-quality suggestions (optional)
- **"One class per file" grab-bags** (`.claude/rules/code-quality.md`) — intentional
  "related small widgets" groupings, low priority, split only if they keep growing:
  `auth_form_widgets.dart` (372 lines, 8 classes),
  `photo_picker_section.dart` (476, 7), `details_view_leaf_widgets.dart` (294, 6),
  `image_viewer.dart` (376, 3).
- **`event_details_controller.dart`** (600 lines) — cohesive but broad; `save()` is
  a ~93-line coordinator that delegates cleanly. Optional: peel the photo-
  orchestration helpers (`_applyPhotoChanges`, `_deleteOrphanedImages`) into an
  `EventDetailsPhotoSync` collaborator. Don't force it — genuinely one controller.

## Notes / uncertainties
- **Dead code / l10n:** zero confirmed dead code, zero unreferenced files, zero
  orphaned ARB keys (463 keys, 1:1 `@`-metadata, all referenced). Nothing to prune.
- **Performance:** no High/Medium wins found. Two negligible LOW items —
  once-daily digest N+1 (`notification_utils.js:888`, runs 1×/day, small staff)
  and a double `jsonEncode` in `widget_sync_service.dart:133-137` — not worth
  acting on.
- **Robustness:** essentially clean — all 5 StreamSubscriptions cancelled with
  `onError`, controllers/timers disposed, `mounted`/`ref.mounted` guards present.
  The decl-vs-dispose count flagged `add_appointment_sheet.dart` and
  `event_details_view.dart` but both are false positives (controllers bundled in
  `AppointmentFormControllers`, released by one `.dispose()`).
- Generated files (`.gen/`, `*.g.dart`, `firebase_options.dart`) excluded per
  `analysis_options.yaml`.
