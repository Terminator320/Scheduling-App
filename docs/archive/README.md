# Archived docs

Completed plans/specs and superseded audit snapshots — kept for history, not
maintained against the current code. Started 2026-07-10; last updated
**2026-08-15**, when the docs sweep added the three audit snapshots this index
had been missing — the 2026-08-11 second pass (on disk but unlisted) and the two
2026-08-14 passes, which had been **overwritten in place** by the next sweep and
were restored from git history. The 2026-08-11 sweep before it moved thirteen
documents in: six plans whose work had shipped (the multi-day trio, the
closed-jobs agenda, the photo cue, the History restyle), six superseded audit
snapshots, and the pre-redesign `WORKFLOW.md`.

**Overwriting the rolling `docs/audits/CODEBASE_AUDIT.md` with the next sweep is
how a snapshot goes missing.** Copy the outgoing one here first.

**Do not treat these as accurate references.** For current state see
`docs/ARCHITECTURE.md`, `docs/CLOUD_FUNCTIONS.md`, and the active plans in
`docs/plans/`.

Documents here are frozen as written, so several still cite each other by their
old `docs/plans/` or `docs/audits/` paths. Those pointers are left alone on
purpose — a task list that says "edit `docs/plans/X`" was true when it ran, and
rewriting it would falsify the record. Read a bare filename as "same folder as
this one".

## Executed plans / specs (feature shipped)
- `INVITED_SIGNUP_REDESIGN.md` / `_PLAN.md` — canonical spec + implementation
  checklist for the one-time signup-code invite flow (shipped 1.19.4, then
  itself replaced by P4c's admin-invites flow 2026-08-02 and fully retired from
  the backend 2026-08-08 with the `#compat-1.37.1` shim). Both live here now;
  neither root `CLAUDE.md` nor `docs/CLOUD_FUNCTIONS.md` cites the spec any
  more — this is a plain historical record, not an authoritative reference. The
  checklist predates dropping `regenerateSignupCode`.
- `2026-06-06-error-animation.md` / `-design.md` — field-error shake/animation
  (shipped; now built into `LabeledTextField` / `AnimatedFormFieldWrapper`).
- `2026-07-01-ios-adaptive-feel.md` / `-design.md` — Cupertino-on-iOS adaptive
  layer (shipped; `lib/core/adaptive/`).
- `2026-07-08-admin-dashboard.md` — admin dashboard (shipped;
  `lib/features/dashboard/`).
- `2026-07-08-push-notifications.md` — FCM push triggers + iOS home-screen
  widget (implemented; `functions/notifications.js`,
  `lib/features/notifications/`, `lib/features/home_widget/`; functions + rules
  deployed to prod 2026-07-11). Residual ops items (Firestore ledger TTL policy,
  on-device verify) are tracked in CLAUDE.md, not here.
- `2026-07-11-wave-auto-import-schedule.md` / `-plan.md` — Wave auto-import
  cadence (deployed 2026-07-11; `functions/wave/import_schedule.js`,
  `waveScheduledImport` / `waveSetImportSchedule`). The design doc's "not yet
  implemented" status line was stale at archive time.
- `2026-07-13-offline-hardening.md` — offline guards + durable photo-upload
  retry queue (Tasks 1–6 implemented/committed on `notification`).
- `2026-07-13-day-route-view.md` — employee day-route timeline + multi-stop
  Google Maps hand-off (Tasks 1–5 implemented on `notification`;
  `lib/features/calendar/screens/day_route_screen.dart`). Task 6 is a
  device-only verification pass.
- `2026-07-09-travel-time-notifications.md` — travel-aware "time to leave"
  reminders with live background GPS presence (implemented + committed on
  `notification`, shipped in 1.31.0+50; `functions/travel_utils.js`,
  `lib/features/presence/`). Residual ops items (Routes API console enable +
  functions deploy + Mac Time-Sensitive entitlement) are tracked in CLAUDE.md,
  not here.
- `2026-07-15-live-staff-map.md` — admin-only Find-My-style live staff map
  (implemented + committed on `notification`, shipped in 1.32.0+51;
  `lib/features/presence/screens/live_map_screen.dart`, `LiveMapAggregator`,
  `placesReverseGeocode`; **functions + rules deployed to prod 2026-07-18**,
  client Maps keys + Geocoding API provisioned). Residual items (verify Routes
  API is enabled/restricted, on-device pass, App Store Location privacy
  declaration) are tracked in CLAUDE.md and the iOS handoff, not here. The
  plan's own header status line was stale (pre-deploy) at archive time.
- `2026-07-19-ios-live-activities.md` / `-implementation.md` — the iOS Live
  Activity "time to leave" Lock Screen card (built 2026-07-19; **functions,
  rules, and the two required composite indexes deployed to prod 2026-07-19**
  in 1.34.1). `functions/apns_client.js`, `live_activity_*.js`,
  `lib/features/live_activity/`, `ios/ScheduleWidget/JobLiveActivity.swift`.
  **Both header status lines were stale at archive time** — the design doc still
  said "NOT started, NOT approved to build" and the implementation doc still
  called the APNs secrets a deploy blocker; the secrets were created 2026-07-19
  and the deploy has happened. Residual item (on-device verification) is tracked
  in CLAUDE.md and `ios/ScheduleWidget/LIVE_ACTIVITY_README.md`, not here.
- `2026-07-22-feature-tour-design.md` / `-implementation.md` — per-tab,
  role-aware in-app feature tours (showcaseview 5.x; built + committed on
  `notification`, "live tour of app"). `lib/features/feature_tour/`; CLAUDE.md
  carries the full invariant. On-device verification is the one residual item.

- `2026-08-03-client-archive-and-delete.md` / `-plan.md` — archive-instead-of-
  delete for clients, plus the `deleteClient` callable gated on a live `count()`
  of the client's appointments (built + committed on `redesgin`; **functions,
  rules and the `(archived, name, __name__)` index deployed 2026-08-03**, with
  the required prod backfill run first — 674 clients patched). The design doc's
  own "approved, not implemented" status line was stale at archive time and was
  corrected. `allow delete` on `/clients` was withdrawn 2026-08-08 with the
  `#compat-1.37.1` shim, so `deleteClient` is now the only delete path in rules
  as well as in code.
- `2026-08-04-drawer-icons-and-tour-expansion.md` / `-PLAN.md` — tinted icon
  chips on the nav drawer rows, and the feature tour regrown from 14 screen-level
  steps to 43, including the three create-flow **sheet** tours that the sealed
  `TourScope` split made expressible (pushed, `2845d43a`..`881834b2`).
  `lib/features/feature_tour/domain/tour_scope.dart`. On-device verification is
  the one residual item.

- `2026-08-02-multi-day-appointments.md` (design) / `-PLAN-1-app.md` /
  `2026-08-03-multi-day-appointments-PLAN-2-mirrors.md` — an appointment spans
  up to 14 days and its two times are a **daily window**. Plan 1 built the app
  half (`140fc92`, 2026-08-03): `AppointmentDaySlice` as the one owner of
  day-scoping, and every consumer of the range stream re-scoped through
  `runsOn`. Plan 2 built the off-screen mirrors (2026-08-10): the home widget,
  `functions/day_slice_utils.js`, the Siri snapshot at **schema v3** and the
  push date line, so days 2+ of a run stopped being invisible outside the app.
  The design doc's §8 mirror table is complete and its §10 question 2 (a
  `firestore.rules` span bound) was **closed and built 2026-08-11**
  (`isValidAppointmentSpan`). **One open item was carried out of §10 rather than
  archived with it** — what a Live Activity for a multi-day job should look like
  — and now lives in `docs/plans/README.md` §5; the containment (skip multi-day
  jobs outright) is built. The rules bound and the skip are **not deployed**.
  Both Swift halves are Xcode/device-unverified. Every invariant is in
  `CLAUDE.md`; the unticked checkboxes in both plans are an artifact of how they
  were executed.
- `2026-08-08-completed-jobs-agenda.md` — closed jobs (`done` **and**
  `cancelled`) sink below the day's open work in the calendar agenda, take the
  success tint, and render collapsed under a labelled rule (built 2026-08-08).
  `_agendaOrder` in `appointment_day_slice.dart`, `AgendaSliverList`,
  `AppointmentCard(collapseWhenClosed:)`. Only the calendar sinks them — every
  other appointment surface keeps its own sort and the full-height card.
- `2026-08-10-photo-cue-and-day-count.md` — two small agenda signals (built
  2026-08-10): a photo glyph at the end of the title line when a job carries
  pictures, and the agenda header's `4 JOBS · 1 DONE` second clause. Not
  device-verified.
- `2026-08-11-history-restyle.md` — P7's History half (built 2026-08-11): a left
  date rail under a sticky month bar, replacing the bold year separator, with
  the shared `AppointmentCard` untouched. `HistoryMonthBar`, `HistoryDateRail`,
  `clients/domain/history_grouping.dart`. Its build record is P7 phase D in
  `docs/plans/redesign-subdocs/2026-08-11-p7-dashboard-history.md`, which stays
  active-adjacent with the rest of the redesign sub-docs.

## Superseded session snapshots
- `2026-07-20-session-handoff.md` — a point-in-time "resume here" snapshot; its
  live next-action (the Siri Phase 4 write-actions runbook) lives in the active
  `docs/plans/2026-07-20-siri-phase4-write-actions.md`. Kept for history only.
- `WORKFLOW.md` — the user-side UI map of the **pre-redesign** app (~2026-07-29),
  written as the brief the redesign was specified against. Archived 2026-08-11
  now that P1–P5 and P7 have shipped: the nav rail, `table_calendar`,
  `AppointmentTile`, `AuthBrandHeader`, `google_fonts`, the `todayFab` and the
  signup-code flow are all deleted, there are four hub tabs rather than six, and
  it predates personal jobs, all-day blocks and multi-day appointments. It had
  carried a SUPERSEDED banner since the redesign began and was flagged by the
  2026-08-04 audit for presenting itself as current. Kept for its §6 constraints
  and as the record of what the redesign was answering. Current sources of
  truth: `CLAUDE.md`, `docs/ARCHITECTURE.md`.

## Superseded audit snapshots
Point-in-time whole-repo audits; each run's findings were implemented at the
time. Superseded by later audits — **the active one is
`docs/audits/CODEBASE_AUDIT.md`, the 2026-08-15 sweep**, whose 41 findings are
all closed and deployed, so it too is now a record rather than a work list.
`docs/audits/` also keeps `SECURITY_ASSESSMENT_2026-08-04.md` and
`AUDIT_FOLLOWUPS.md` (one item, §2, still open), plus two read-only repair-audit
scripts for the client-rename damage (`audit-renamed-client-names.js` and the
earlier `audit-client-phone-backfill-damage.js`).
- `CODEBASE_AUDIT_2026-06-26.md`
- `CODEBASE_AUDIT_2026-07-01.md`
- `CODEBASE_AUDIT_2026-07-04.md`
- `CODEBASE_AUDIT_2026-07-07.md`
- `CODEBASE_AUDIT_2026-07-19.md` — the same-day deep pass that replaced the
  `-earlier` run below.
- `CODEBASE_AUDIT_2026-08-02-pre-p4c.md` — the 1.39.0+64 release cut, audited
  *before* the P4c employee-account commits landed.
- `CODEBASE_AUDIT_2026-08-02-post-p4c.md` — the re-run over the P4c result.
  Supersedes the pre-P4c snapshot.
- `CODEBASE_AUDIT_2026-08-04-first-pass.md` — closed 21 findings at `9b384aa`.
- `CODEBASE_AUDIT_2026-08-04-second-pass.md` — a fresh sweep over the shipped
  result at `46154b1`, not a re-run of the first pass's checks; it found a
  distinct set.
- `CODEBASE_AUDIT_2026-08-11-first-pass.md` — 20 findings at `8bf07c6e`, all
  actioned in `a90474cc`. Superseded the same day by the second pass below.
- `CODEBASE_AUDIT_2026-08-11-second-pass.md` — 31 findings at `55ea3cb3`, closed
  in `ef698365` + `78d89478`. It caught the rules span bound that DST would have
  made reject legal saves, before that bound deployed.
- `CODEBASE_AUDIT_2026-08-14-first-pass.md` — 30 findings at `bf316828`,
  implemented the same day in `4b500e84`; it found the edit sheet renaming real
  Wave customers. Its ⚠️ pre-deploy item (deleting three live Cloud Functions)
  ran in the 2026-08-14 deploy.
- `CODEBASE_AUDIT_2026-08-14-pre-deploy.md` — a fresh sweep run immediately
  before that deploy and before the Wave client-name/phone backfills, weighted
  toward what breaks once deployed. 27 findings, all closed at `a30eb3ef`.
  **Both 2026-08-14 snapshots were restored from git history on 2026-08-15** —
  each had been overwritten in place by the sweep that followed it.
- `MOBILE_AUDIT_2026-07-13.md` — a mobile-optimization-lens pass (perf, memory,
  battery, network, mobile UX) rather than a general audit. Nothing mechanical
  to fix; its verdict was that the hot paths already implement the mitigations
  it hunts for.
- `CODEBASE_AUDIT_2026-07-19-earlier.md` — the first 2026-07-19 run, which
  reported zero security findings and zero bugs. The **same-day deep pass that
  replaced it contradicts that conclusion** (it found the disabled-employee read
  hole and the two missing indexes), so this snapshot is kept only as a record
  of what a shallower pass missed. Its auto-applied spacing/token cleanups
  remain valid.
- `WAVE_REVIEW_FINDINGS.md` — Wave-integration ultra review (fixes applied
  2026-06-21; Wave shipped).
