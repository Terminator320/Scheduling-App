# Codebase Audit — 2026-07-21 (third pass)

> **Implementation status (same session).** Everything actionable was
> implemented on `notification` (uncommitted). S1 (byte guard), B1 + B2 (Live
> card marker authoritative on reschedule + per-occurrence refresh), and
> improvements I1/I3 (`ReentrantSync` mixin + coalesce test), I4 (extracted +
> tested `mergeRetainedAssignees`), I5 (`.limit(500)` on the presence feed), I6
> (autocomplete/getDetails response-shaping tests). **I2 was a false positive**
> — `_buildMaster()` is ~55 lines and already delegates to sub-builders (the
> agent's "192 lines" was a brace-counting artifact); no change made. Final
> state: `flutter analyze` clean (3 pre-existing info lints, unchanged) ·
> `flutter test` 1020/1020 · `functions` lint clean · `functions` jest 664/664.
> The functions changes still need a `firebase deploy --only functions` + a Mac
> rebuild to verify the Live Activity card behavior on device.

Scope: whole repo (`lib/`, `functions/`, `firestore.rules`, `storage.rules`,
`firestore.indexes.json`, `test/`). Baseline: working tree clean on branch
`notification` at `c6427dd`.

## Summary
- Scanned: 274 Dart files (`lib/`), 58 JS files (`functions/`), 163 test files,
  plus rules + indexes.
- Auto-fixed (safe, in the diff): **0** — the repo is clean at the static level
  (`flutter analyze` reports no errors/warnings, `dart fix` finds nothing,
  functions ESLint clean, no dead files, no genuinely unused deps).
- Reported for your decision: **9** (⚠️ 0 pre-ship · 🔴 1 security · 🟠 2 bugs ·
  🔵 6 improvements) + 3 optional code-quality nits.
- Verification: flutter analyze — clean (matches baseline; 3 pre-existing
  info-level lints, no new ones) · dart fix — nothing to fix · functions lint —
  clean. No files changed, so no test run was needed.

## Auto-applied cleanups (review the diff)
None. There was nothing safe and mechanical to apply:
- `flutter analyze`: no errors or warnings (only 3 pre-existing info lints, see
  🟡 below).
- `dart fix --dry-run`: "Nothing to fix!"
- Cloud Functions ESLint: clean.
- Unused-file heuristic: no orphans (one false positive — `l10n_extensions.dart`
  is re-`export`ed, not `import`ed).
- Unused-dependency heuristic: 4 candidates, all confirmed **false positives**
  (`freezed` + `build_runner` back the `.freezed.dart` codegen;
  `flutter_launcher_icons` is config-driven; `google_maps_flutter_ios_sdk9` is
  the endorsed SPM iOS override per CLAUDE.md).
- l10n: all 429 ARB keys are live (initial "orphan" hits were aliased receivers).
- Convention drift: none (the 3 sanctioned SnackBar sites only; zero
  `throw Exception`; no `FirebaseFirestore.instance` in widgets; no illegitimate
  `isDark` styling branches; raw `EdgeInsets`/`Color` are the documented
  intentional sub-4px nudges and token/palette files).

> Nothing below this line was auto-changed. All items are report-only.

## ⚠️ Pre-ship checklist (act before release)
**None this pass.** No `TODO(pre-ship)` markers exist in `lib/` or `functions/`,
and there is no destructive testing scaffolding wired into the UI. The remaining
launch work is Mac/device verification (App Attest on hardware, Dynamic Island
presentation, on-device Siri phrases), not code — tracked in project memory and
`docs/plans/APP_STORE_SUBMISSION.md`, not here.

> Note: the security + bug fixes below all live in `functions/` and would need a
> `firebase deploy --only functions` (and, for the Live Activity card behavior,
> a Mac rebuild) to take effect — but they are corrections, not launch switches.

## 🔴 Security findings (review required)

### S1 — `widgetPayload` size guard counts UTF-16 code units, not UTF-8 bytes · severity: low · confidence: high (bug traced) / medium (trigger frequency)
- **Where:** `functions/notification_utils.js:55` (`WIDGET_PAYLOAD_MAX_BYTES = 3000`)
  and `:584-585` (`msgData.widgetPayload.length > WIDGET_PAYLOAD_MAX_BYTES`).
- **Risk:** The constant is named `_MAX_BYTES` and exists to keep the FCM `data`
  map under FCM's 4 KB **byte** limit, but the comparison uses JS string
  `.length` (UTF-16 code units). For this bilingual Quebec app, client names and
  street addresses routinely contain accented characters (é, à, è, ç) that are
  2 bytes in UTF-8 but 1 code unit. A busy two-day widget payload of
  mostly-accented text can be ≤3000 code units yet exceed ~4096 bytes once the
  other `data` keys (`kind`, `appointmentId`, title, body) are added. When that
  happens the guard does **not** strip the payload, `messaging.sendEach` rejects
  the oversized message, and — per the code's own comment — the **visible
  notification is lost too**, not just the widget refresh. So an
  assignment/reschedule/cancel/"time to leave" alert silently fails to deliver.
  Not attacker-exploitable; it's a reliability gap on safety-relevant alerts.
- **Fix:** measure bytes —
  `Buffer.byteLength(msgData.widgetPayload, "utf8") > WIDGET_PAYLOAD_MAX_BYTES` —
  and ideally byte-check the whole assembled `data` map (title/body included),
  not just `widgetPayload`. Needs a functions deploy.

## 🟠 Bug findings (review required)

### B1 — Live card's on-site flip is keyed to a stale `startTime` after a reschedule · severity: low–medium · confidence: high (~85%)
- **Where:** `functions/live_activity_dispatch.js:238-258` (`updateLiveActivity`),
  `functions/live_activity_registry.js:168-187` (`writeCardMarker`, the only
  writer of `marker.startTime`), `:215-226` (`setCardPhase` merges **phase
  only**), `:256-269` (`listCardsDueForOnSite` selects on
  `.where("startTime", "<=", now)`), and `functions/travel_utils.js`
  `runOnSiteFlipPass`.
- **Problem:** The `liveActivityCards/{employeeDocId}` marker's `startTime` is
  written **only** at card start and never updated afterward. On a reschedule,
  `updateLiveActivity` refreshes the card *content* (new times via `ctx`) and, at
  most, flips `phase` — it never rewrites `marker.startTime`. But the on-site
  backstop selects candidates by that stale field. **When it breaks:** a card is
  live and the admin reschedules that occurrence **earlier** (5:00pm → 3:00pm).
  `phaseFor(newStart, rescheduleTime)` is still `travel`, so no flip, and the
  marker keeps `startTime = 5:00pm`. When real time reaches 3:00pm the card
  should flip to "On site", but `runOnSiteFlipPass` won't select it until
  `now >= 5:00pm` — the Lock Screen shows "On the way" for the full reschedule
  delta after the tech has already arrived. The mirror case (rescheduled
  **later**, 3pm → 5pm) is less harmful but wasteful: the stale `startTime=3pm`
  keeps the marker in the flip-candidate set, pushing a redundant `travel`-phase
  update every 5-min sweep for two hours.
- **Fix:** make the marker authoritative on reschedule — in `updateLiveActivity`
  (or the reschedule branch of `handleAppointmentWrite`) rewrite the marker's
  `startTime` from `ctx.startTime` when the appointment start changes (a merge
  `setCardStart`, or fold `startTime` into the existing `setCardPhase` merge).
  Needs a functions deploy.

### B2 — "This and all future" series reschedule can leave the live card un-refreshed · severity: low · confidence: ~70%
- **Where:** `functions/notification_utils.js:865-879` (`handleAppointmentWrite`
  reschedule branch) + `claimSeriesNotice` (`:991-1043`) interacting with
  `updateLiveActivity`'s marker check `_liveRowsFor`
  (`functions/live_activity_dispatch.js:96-102`).
- **Problem:** An apply-to-all series reschedule writes all siblings with one
  `seriesOpId`; `claimSeriesNotice` collapses to one push per `(employee, kind)`
  and **which sibling wins the claim is nondeterministic**. `updateLiveActivity`
  only acts when the winning sibling's `appointmentId` matches the card marker
  (`_liveRowsFor` returns `[]` otherwise). If the winner isn't the specific
  occurrence the tech's card is showing, the card's times are never refreshed
  for that reschedule — compounding B1's stale marker.
- **Fix:** shares B1's root cause. Keeping the card marker authoritative on
  reschedule (resolve the live card by employee and refresh it whenever any
  sibling this employee owns is rescheduled) closes both. Needs a functions
  deploy.

## 🔵 Areas to improve (review required)
Ordered by payoff.

### I1 — `PresenceSyncController` coalesce + deferred-write logic is untested · impact: high · confidence: high
- **Where:** `lib/features/presence/application/presence_sync_controller.dart`
  (coalesce guard 95–161; one-shot deferred-write re-arm 213–248;
  `PresenceWriteResult.denied → _stop()` teardown). Existing
  `presence_sync_gates_test.dart` covers only the pure `shouldTrackPresence`
  predicate and `shouldWritePresenceFix` throttle — not the controller.
- **Opportunity:** This is one of the newest/riskiest subsystems (background GPS;
  the 1.32.0 Crashlytics-spam fix lives exactly here), and the
  "last fix in a throttled burst still lands" deferred-write path is pure and
  fully testable with a fake clock + fake repo. It currently has zero
  controller-level coverage.
- **Suggested improvement:** add a test covering (a) `_busy`/`_pendingResync`
  coalescing, (b) the deferred-write timer landing the trailing fix, and (c)
  `denied → _stop()`. Highest-payoff test to add.

### I2 — `settings_screen.dart _buildMaster()` is a ~192-line god-method · impact: medium · confidence: high
- **Where:** `lib/features/settings/screens/settings_screen.dart:156`
  (~192 lines).
- **Opportunity:** One method assembles the entire settings master list inline
  (theme, language, app-lock, text-size, notifications, live-activity, Wave,
  version footer, sign-out, delete-account). It's the hardest-to-navigate method
  in the app; every settings-row change diffs this monolith. Rule of thumb is
  ~60 lines per `build()`/builder.
- **Suggested improvement:** extract cohesive row groups into
  `_buildSecurityTiles()` / `_buildNotificationTiles()` / `_buildAboutTiles()`
  sub-widgets — no new abstraction, just splitting one method the way the file
  already does elsewhere.

### I3 — Reentrancy/coalesce sync guard duplicated across 3 controllers · impact: medium · confidence: medium
- **Where:** `push_registration_controller.dart` (61,80,108,140),
  `presence_sync_controller.dart` (95,110,114,159),
  `live_activity_registration_controller.dart` (91,115,121,129) — all under
  `lib/features/{notifications,presence,live_activity}/application/`.
- **Opportunity:** Each carries the identical ~15-line
  `if (_busy) { _pendingResync = true; return; } … finally { _busy = false; if
  (_pendingResync) { _pendingResync = false; sync(); } }` shape (3 genuine
  instances, meets the 3× bar). Only the inner `_syncGuarded()` body differs.
  It's the coalesce-never-drop concurrency contract copied by hand three times,
  and none of the three has a test for the coalesce behavior — a subtle
  divergence in one would be a silent bug. (CLAUDE.md documents that Presence
  "mirrors" Push deliberately, so this is optional consolidation, not a defect.)
- **Suggested improvement:** extract a tiny `ReentrantSync` mixin exposing
  `runCoalesced(Future<void> Function() body)` — extract the guard only, leave
  each `_syncGuarded` in place — and test the mixin once (which also closes I1's
  and the two other controllers' coalesce test gap in one place). Best done
  *with* that shared test.

### I4 — `event_details_controller._resolveAssignees` is a ~129-line method in a 679-line file · impact: low–medium · confidence: medium
- **Where:** `lib/features/calendar/application/event_details_controller.dart`
  (`_resolveAssignees` ~332–460; `save()` ~358–454).
- **Opportunity:** The assignee-resolution block implements the load-bearing
  "preserve disabled/removed assignees not in the active picker" invariant
  (a save that mis-resolves it silently changes who can see a visit). It's
  complex enough to deserve isolation and a direct test.
- **Suggested improvement:** extract the active-set resolution into its own pure
  helper and unit-test it against the invariant. Optional; leave the rest of the
  file as-is.

### I5 — `allPresenceStreamProvider` collection-group read has no `.limit()` · impact: low · confidence: low
- **Where:** `lib/features/presence/data/presence_repository.dart:82`
  (`collectionGroup('presence').snapshots()`).
- **Opportunity:** Unbounded, unlike the deliberately-capped `_userStreamLimit`
  (500) on the users streams. Effectively self-bounded today (one presence doc
  per active staff member, admin-only, `autoDispose` tears it down when the map
  tab hides), so not a current bottleneck — purely defense-in-depth symmetry
  against a rules/data anomaly.
- **Suggested improvement:** add `.limit(500)` to match the users-stream posture.
  Cheap; optional.

### I6 — `places.js` autocomplete/details response-shaping is untested · impact: low · confidence: high
- **Where:** `functions/places.js` (JSON-shaping of the autocomplete/details
  proxy responses). Only the admin gate (`places_admin_gate.test.js`) and
  reverse-geocode are covered.
- **Opportunity:** Thin proxy, low risk, but the response mapping is pure and
  currently unverified.
- **Suggested improvement:** add a small unit test over the response-shaping
  helper if/when that code is next touched. Low priority.

## 🟡 Code-quality suggestions (optional)
Three pre-existing info-level analyzer lints. Left un-fixed because two are
behavior-adjacent (a judgment call) and one is cosmetic:
- `lib/features/presence/screens/live_map_screen.dart:384` —
  `avoid_catching_errors` (catches `StateError`, an `Error` subclass). May be
  load-bearing; confirm the catch is intentional before narrowing it.
- `lib/features/wave/widgets/wave_settings_section.dart:65` —
  `avoid_positional_boolean_parameters`. Convert to a named parameter if this
  widget's API is touched.
- `lib/shared/widgets/sheets/app_bottom_sheet.dart:10` — `comment_references`
  (doc comment references `[DraggableSheetFrame]`, not imported into scope).
  Purely cosmetic.

## Notes / uncertainties
- This is the third audit in three days; the repo was already exhaustively swept
  on 2026-07-21 (see prior `docs/audits/` reports and project memory). The
  static level is genuinely clean and the new findings are concentrated in the
  freshest code — the notification / Live Activity / presence stack committed in
  `c6427dd` and `1192fc1`.
- S1, B1, and B2 all require a `firebase deploy --only functions` to take effect;
  B1/B2 additionally involve the on-device Live Activity card behavior, so
  confirm on hardware after deploy.
- Robustness (mounted-guards, catch-with-log discipline) was spot-checked and
  found clean, not exhaustively proven. The only bare `catch (_)` is the
  sanctioned FCM-background-isolate site (`widget_sync_service.dart:135`).
- Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/.gen/**`,
  `firebase_options.dart`, `build/**`) were excluded per the analysis config.
