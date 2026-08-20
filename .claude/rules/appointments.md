---
paths:
  - "lib/features/calendar/**"
  - "functions/**"
  - "test/features/calendar/**"
  - "test/core/security/appointment*"
---

# Appointments

Loaded when working on appointments. Root context: `../../CLAUDE.md`.
Calendar *rendering* rules live in `lib/features/calendar/CLAUDE.md`.

- **Appointment status allowlist:** The lifecycle is `pending` →
  `in_progress` → `done`, plus `cancelled` (set by the separate Cancel action).
  These four are the ONLY valid *stored* values — enforced by
  `isValidAppointmentStatus` in `firestore.rules` and `_allowedStatuses` in
  `firebase_appointments_repository.dart`. New appointments must be created
  with `status: 'pending'`. **`AppointmentStatus.overdue` is a display-only,
  time-derived state — NEVER stored, NEVER in the picker.** `displayStatus`
  (`appointment_record.dart`) maps a non-terminal visit to `in_progress` while
  now is within [start, end] and to `overdue` once `endTime` has passed.
  **That ladder has exactly ONE owner: `AppointmentRecord.displayStatusAt(now)`;
  `displayStatus` is `displayStatusAt(DateTime.now())` and
  `DashboardAggregator.displayStatusAt` delegates to it.** The dashboard used to
  carry a hand-copied "mirror" of it and had already drifted — it was missing
  the `isPersonal` carve-out, so a personal block past its end read "Scheduled"
  on its card and sat under the dashboard's Attention list as *overdue* —
  nagging an admin to close something "job finished?" is the wrong question
  for. (A started personal block CAN be marked complete: `DetailsActionBar`
  gates that button on `hasStarted && !isDone && !isCancelled` with no
  `isPersonal` branch. An earlier note here justified the carve-out by claiming
  personal jobs have no mark-done flow — they do; the carve-out stands on the
  wrongness of the prompt, not on the absence of a way out.)
  Never re-copy the ladder; add clock-derived rules to
  `displayStatusAt` only. The
  card/tile and the read-only detail header render `displayStatus`, but the edit
  picker and all writes seed from the real stored `status` (so `overdue` can't
  leak into a write). Don't add `overdue` to `appointmentValues` or the
  allowlist; reading `AppointmentStatus.overdue.raw` **throws** on purpose so a
  stray write path fails loudly at the source instead of emitting an
  off-allowlist value that the rules reject with an opaque `permission-denied`.
  **"Terminal" as a set of RAW STRINGS has one owner:
  `terminalStatusRawValues` in `calendar/domain/appointment_status_values.dart`**
  (2026-08-08) — `{done, completed, cancelled}`, deliberately Material-free so
  `AppointmentRecord.isClosed` and the History query's `whereIn` can share it.
  It had four definitions and the History one had dropped the legacy
  `completed` alias, so such a doc rendered as Done on its card and was
  **invisible in History and history search**, with no error anywhere.
  `AppointmentStatus.isTerminal` is the enum-level mirror and
  `appointment_status_values_test.dart` pins the two together. (`confirmed` was retired 2026-07-09 when the picker
  collapsed to three states; `done` is labeled "Complete" in the UI. Account
  statuses `active`/`invited`/`disabled` live in the separate `UserStatus` enum
  — `shared/widgets/feedback/user_status_chip.dart` — not `AppointmentStatus`.)
  **Any edit that re-serializes a stored record must normalize its status
  through `AppointmentStatus.storedRaw(status)` before writing** — legacy
  `confirmed`/unknown docs exist, an unchanged status is re-written verbatim,
  and the rules reject anything off the allowlist (a raw write would fail the
  whole save/series-update with `permission-denied`). Use `storedRaw`, never
  `fromRaw(x).raw`: it maps legacy/unknown AND the display-only `overdue` onto
  `pending`, so it can't throw the way a bare `.raw` does. Done at the seed in
  `event_details_controller`, per-sibling in `appointment_series_editor`'s
  `propagate`, and in the Siri snapshot builder. `UserStatus.fromRaw` is the
  matching mapper for account statuses (unknown/empty → `invited`).
- **"Mark as complete" carries NO clock gate at all** (owner call, 2026-08-17,
  which widened the 2026-07 `hasStarted` rule). `DetailsActionBar` offers it on
  every open job — the only conditions are `!isDone && !isCancelled` — so the
  bar reads nothing from the clock and `details_view_body.dart` derives no
  `now`. The old `!appointment.startTime.isAfter(now)` gate already existed
  because the edit form's status picker is admin-only, so an employee who
  misses the button before midnight (or is on day 2+ of a multi-day visit) has
  no other way to close a job the server keeps nudging them about; the same
  reasoning applies before the start time, to a crew that finishes early or a
  job booked for later today. The rules have always allowed an assignee to
  write `status:'done'` with no date restriction (pinned by
  `appointment_employee_update_rules_test.dart`), so nothing server-side
  changed. Don't reintroduce a start-time or "is today" test here.
- **Admin-only appointment actions are gated by an explicit `showActions`.**
  `showEventDetails(..., showActions:)` is a REQUIRED param, and
  `AppointmentTile` / `EventDetailsSheet` / `EventDetailsView` all default it
  **CLOSED** (`false`). A default of `true` silently showed employees the
  Edit/Cancel/Delete affordances, which the rules then reject with an opaque
  `permission-denied`. Pass the caller's resolved role; never re-add a `true`
  default. (Rules remain the real gate — this is defense-in-depth plus UX.)
  **A DONE job's edit affordance is the action bar's bottom button, not the
  top chip** (owner call, 2026-08-08): `DetailsViewBody` suppresses
  `DetailsEditChip` when the stored status is done and hands
  `DetailsActionBar.onEdit` instead, which takes over the slot the inert
  "Complete" indicator held — that job has no mark-done or cancel action left,
  so the slot was dead. `onEdit` is null-gated on the same `showActions`, so a
  read-only surface (client job history) still renders the indicator and offers
  nothing. Cancelled and open jobs keep the top chip. The two move together:
  don't restore the chip on a completed job without removing the button, and
  don't drop the button without bringing the chip back, or a finished job
  becomes uneditable again.
  **`AppointmentHistoryView` takes an `isAdmin` and passes it straight through
  as `showActions`** (restored 2026-08-08 after a revert dropped it). It used to
  hardcode `false` on the grounds that History is a read-only surface, but
  History is where `done` and `cancelled` jobs actually LIVE, so that made the
  completed-job edit button above unreachable from the one screen an admin would
  look for it on. It still DEFAULTS closed like every other appointment surface;
  `HistoryScreen` passes `widget.isAdmin`.
- **Personal jobs (`isPersonal`, added 2026-07-31) carry no client, and their
  address is OPTIONAL** (owner call, 2026-08-11, which reversed the original
  "no address"). The switch at the top of the form's WHO section is on BOTH the
  add and edit flows (unlike the template chips), because the flag is stored and
  has to be reversible. Turning it on hides the client picker, clears its
  controller and drops `clientRequired` from `AppointmentFormValidator` —
  **the assignees stay required**, they are who the block is for and who can
  see it. Both save paths write `clientId`/`clientName`/`clientPhone` as
  **empty strings**, including when an existing client visit is converted, so a
  hidden field can never keep a stale value the UI no longer shows.
  **`address` is deliberately NOT in that set**: a dentist appointment or a
  supply run still happens somewhere, and the crew wants directions to it. The
  field stays on screen for a personal job, marked "(Optional)"
  (`AppointmentAddressField.optional`, forwarded to `AddressAutocompleteField`),
  and both save paths write `address.trim()` unconditionally — so the
  "hidden field can't keep a stale value" reasoning doesn't apply to it: what
  saves is what the user can see and edit. The switch therefore must NOT clear
  `controllers.address`, which is the one clear that was removed here; the
  validator never required an address on any job, so nothing was relaxed there.
  Every read surface already gated on `address.isNotEmpty` (the detail row, the
  Directions quick action), so a personal job with one renders it and a
  personal job without one is unchanged — and a *timed* one with an address is
  now a genuinely routable travel candidate rather than one that always
  degraded to the fixed 30-minute reminder for want of a destination.
  Everything that speaks a client name falls back
  to the **title**: the card and the detail row say "Personal"
  (`calendar_personal`), the widget and Siri decoders already fell back to
  `title`, and `_who` in `functions/notification_messages.js` now does too
  (`_contextFor` therefore has to keep passing `title` through).
  **`live_activity_utils.js` carries its OWN `_who` with the same fallback, and
  it is not optional:** a *timed* personal job is still a travel candidate, so
  the `leaveNow` push and the Lock Screen card describe the same trip at the
  same moment — the card read "Client"/"un client" while the push read
  "Dentist" until `title` was threaded through. Every `ctx` passed to
  `startLiveActivity`/`updateLiveActivity`/`endLiveActivity` (the sweep, the
  on-site flip, the terminal end, the reschedule hook) must carry `title`, and
  `_stateFor` must forward it into `buildContentState` — the state builder
  field-picks its `ctx`, so a dropped field fails silently back to "Client".
  **Build that `ctx` with `liveActivityCtx(record, opts)`
  (`live_activity_utils.js`) — never a hand-written object literal.** There were
  four copies and they had already drifted again (two normalized `address`, two
  passed it raw), which is exactly the silent-failure shape above.
  `propagateClientEdits` can't touch these — it
  queries by `clientId`, which is empty. Also dropped from a personal job: the
  template chips, the repeat picker, materials and photos. The **title is
  optional** there and an unnamed one saves as "Personal" — substituted in the
  widget layer (both sheets), which is where `l10n` lives. The edit form shows
  the switch **only when the job is already personal** (`onPersonalChanged: null`
  otherwise), so an ordinary client visit can't be converted mid-life. Turning
  it on clears the hidden text controllers and, in the ADD flow only, resets
  `repeat` — the edit flow keeps its repeat, where clearing it would rewrite a
  live series.
- **An all-day block (`isAllDay`) stores real instants**, midnight → 23:59, so
  every range query, `orderBy('startTime')` and sweep keeps working unchanged —
  the flag only changes how it is SHOWN (`allDaySpan` builds the pair).
  **Neither save path may re-derive that pair itself** — both the add and edit
  controllers resolve their instants through the one `appointmentSpan(...)`
  helper beside `allDaySpan` (`calendar/domain/policies/appointment_form_validator.dart`),
  which picks the all-day span or the picked times. Hand-writing the ternary in
  a controller gives the convention three owners, and a change to it (23:59 →
  23:59:59, a DST-safe end) then lands on one save path and not the other.
  **`setPersonal(value: false)` MUST NOT clear `isAllDay`** (2026-08-03).
  It used to — the switch was personal-only, so a surviving flag saved a
  midnight–23:59 *client* visit with neither the switch nor the time rows on
  screen to repair it. **All-day is now offered on EVERY job**, so that state is
  reachable, repairable and legitimate: a client visit can genuinely run whole
  days. Clearing the flag now discards a deliberate choice, and both controllers
  pin the new behaviour with a test. **The two controllers are NOT symmetric
  here, and this is the part that is easy to get wrong.** `AddEventController`
  keeps the ON-direction default: `setPersonal(value: true)` sets `isAllDay`
  when neither a start nor an end time has been picked, and leaves it alone on
  the way OFF (pinned by "turning Personal on with no times picked still
  defaults to all-day" / "turning Personal off KEEPS an explicitly set all-day",
  `add_event_controller_test.dart`). `EventDetailsController` does **not** touch
  `isAllDay` in EITHER direction — the flag is whatever the saved record and the
  user's own switch made it, and turning Personal on does not resurrect all-day
  (pinned by "turning Personal on again does not resurrect all-day",
  `event_details_controller_test.dart`). The asymmetry is deliberate: on the add
  form there is no stored value to protect and an untimed personal block almost
  always means all-day, while on an edit any default would overwrite a choice
  already made. The travel sweep still skips all-day
  records (no departure time to compute), and the overdue sweep still gates on
  `isPersonal`, so an all-day *client* job does go overdue after its 23:59 end —
  which is correct. **There is no longer an end-after-start check to gate**: an
  end time at or before the start time now means the window crosses midnight
  (see the multi-day bullet below). Now offered
  on every job, ON by default for a personal block when no time has been picked,
  and it hides the start/end rows. The switch is the schedule `SheetPanel`'s first
  row — **that panel holds the whole of "when": all-day, date, start/end and
  the repeat rule**, which is a `SheetFieldRow` + `showAdaptiveActionSheet`
  rather than the standalone dropdown it used to be (owner call, 2026-07-31). `AppointmentCard` and the detail when-line render
  "All day" instead of "12:00 AM – 11:59 PM". A personal job also **never
  derives `in_progress`/`overdue`**: `displayStatus` returns its stored status
  (which reads "Scheduled"), and `selectOverdueCandidates` in
  `functions/notification_utils.js` skips `isPersonal` records for the same
  reason — "job finished?" is the wrong question for a dentist appointment.
  Keep those two in sync. **`isAllDay` is threaded through all four off-screen
  mirrors** (2026-07-31), and each one needs it for a different reason:
  - **Reminder sweep** — `selectTravelCandidates` (`functions/travel_utils.js`)
    skips all-day records. Without it the midnight start put the block inside
    the 90-min window at ~23:30 the night before and fired a "time to leave"
    push for something that has no departure time. A *timed* personal job keeps
    its reminder; only the all-day skip is new.
  - **Push/digest text** — `_contextFor` carries `isAllDay`, and
    `notification_messages.js` renders the date alone ("Wed, Jul 8") instead of
    "Wed, Jul 8, 12:00 a.m."; `_whoAt` joins with "·" rather than "at"/"à",
    since there is no clock time to sit after the preposition.
  - **Home-screen widget** — `isAllDay` is in the job JSON in BOTH hand-mirrored
    builders (`widget_sync_service.dart`, `widget_payload_utils.js`) and the
    Swift `Job` decodes it as `Bool?` so a pre-existing payload still parses.
    `timeLabel` says "All day". **The "today" filter is `endTime`-based for an
    all-day block** — the old `startTime.isAfter(now)` test dropped it from
    today from 00:00 onward, so it appeared only under *tomorrow* and then
    vanished. `DaySchedule.nextJob` prefers a timed job, falling back to the
    all-day one, or a midnight block owns "up next" all day.
  - **Siri snapshot** — **v2 of the schema** (`scheduleSnapshotVersion`, matched
    by `supportedVersion` in `ScheduleSnapshot.swift`; the CURRENT value is
    **3** — see the multi-day mirrors bullet below, which bumped it): adds
    `isAllDay` AND
    `title`, since a personal job has no client and the snapshot previously had
    no title to fall back to, so Siri said "unnamed client". `SiriStrings.who`
    is now the single client→title→placeholder resolver and `timePhrase` speaks
    "all day"; `nextAppointment` applies the same prefer-timed rule as the
    widget, and treats an all-day block as upcoming until its 23:59 end.
    **That prefer-timed test must be scoped to the block's OWN span**
    (`$0.start < earliest.end`), not to every timed visit in the 7-day window:
    the widget's `nextJob` runs against a single day's bucket, but the Siri
    snapshot is flattened across 8 days, so a window-wide comparison skipped
    today's all-day block whenever *any* later day held a timed job — Siri
    answered with Thursday's visit and never mentioned today's.
- **An appointment may span up to `maxAppointmentSpanDays` (14) days, and its
  two times are a DAILY WINDOW** (2026-08-03) — 9:00 AM–5:00 PM means 9–5 on
  *each* of those days, not one unbroken stretch through the nights. **No schema
  change**: `startTime`/`endTime` already carry the span, `isMultiDay` is
  derived and never stored (same discipline as display-only `overdue`).
  **`firestore.rules` bounds the span too, as of 2026-08-11** —
  `isValidAppointmentSpan`, on `allow create` and the admin `allow update` —
  but rules reach CLIENT writes only, so the app's clamp is still what contains
  a console or Admin-SDK write. The bound is **14 days inclusive PLUS a two-hour
  DST allowance**: a run booked at one clock time (09:00 → +14d 09:00) is a
  legitimate chain of 24-hour windows, so a `<` would reject the widest thing the
  form can save. The `+2h` is the unit mismatch, not slack — the app counts
  CALENDAR days and `combineDateAndTime` composes LOCAL wall-clock instants,
  while CEL's `duration.value` is absolute, so a window containing the autumn
  fall-back stores an hour MORE than its calendar length (that widest run
  becomes 14d 1h; a 14-day all-day block 14d 0h59m). A flat `duration.value(14,
  'd')` therefore refused, for about two weeks each autumn, a booking the form
  had already accepted — as an opaque `permission-denied`. Pinned by
  `appointment_span_rules_test.dart`; don't "simplify" the term away.
  **An UPDATE whose span is out of range but not WIDENED still passes**
  (`appointmentSpanNotWidened`) — the same asymmetry as `emergencyFieldNotSet`,
  and for the same reason: a doc that already exceeds the cap must stay
  updatable, or the admin trying to CANCEL it is refused too. Don't
  "simplify" that branch into a flat bound. An assignee's status flip never
  reaches either guard (that branch restricts the diff to `status`/`updatedAt`).
  Consequences that must stay in sync:
  **`AppointmentDaySlice` (`calendar/domain/appointment_day_slice.dart`) is the
  ONE owner of day-scoping** — `sliceFor` / `expandToDays` / `lastWorkDayOf`
  (plus `lastWorkDayOfWindow`, its raw start/end form, for the one caller that
  holds a resolved pair and no record yet: the booking-conflict dialog).
  Never re-derive a day index or a run length at a call site, the way the
  `displayStatusAt` ladder and `_who` were re-derived and drifted.
  **The end date names the last day the crew STARTS work**, never the morning an
  overnight run finishes, so the length is `end − start + 1` for day jobs and
  night shifts alike. A window whose end time is at or before its start time
  crosses midnight and counts **nights** — which is why **there is deliberately
  no end-time-after-start-time validation**: that ordering IS a night shift.
  (Consequence, accepted: picking 9:00–9:00 on a one-day job books 24 hours
  rather than erroring, because it is structurally identical to a legitimate
  one-night shift.)
  **Slices are generated per WORK day** — each day the window *begins* — not per
  calendar day the stored instant span touches; that is what keeps a night shift
  off the morning it ends.
  **`AppointmentDateRange.fetchStart` widens the query 14 days back and MUST
  stay a derived getter**, never a constructor field: `==` is keyed on
  `start`/`end`, so two surfaces asking for the same day still produce equal
  ranges and share one listener. Widening at a call site instead forks a second
  Firestore query for the same day.
  **"All day" is reserved for `isAllDay`** and is never borrowed to describe a
  timed job's middle day — the card reads `9:00 AM – 5:00 PM · Day 3 of 5`.
  A continuing *timed* job has a real start time that day and sorts in clock
  order; only all-day blocks pin above the day.
  **A RANGE STREAM IS A SUPERSET OF ITS RANGE — every consumer must re-scope**
  (2026-08-04 audit). Because the query starts at `fetchStart`, the emitted list
  holds every job that STARTED in the previous 14 days. Only the calendar
  clipped it; the day route, the roster's "jobs today", the employee detail's
  TODAY panel and the drawer's calendar badge all read it raw and silently
  reported a fortnight of past jobs as today's. Re-scope through
  **`runsOn(appointment, day)`** (beside `sliceFor` in the same owner file) —
  never by comparing `startTime` at the call site. A reducer over
  `appointmentsInRangeProvider` without a day predicate is a bug.
  **And a "today's window" test on a MULTI-DAY run must use the SLICE's
  window, not the record's `startTime`** (2026-08-11): the dashboard's
  "Upcoming today" re-scoped through `runsOn` and then asked
  `startTime.isAfter(now)`, i.e. the run's first morning — so on day 3 of a
  14:00 job the status counts included it while the section rendered "No visits
  today", and sorting on the stored instant floated it above jobs genuinely
  earlier that day. `computeTodayOps` now carries `AppointmentDaySlice`s.
  **`appointmentsInRangeProvider` is ADMIN-ONLY, and every non-admin consumer
  must role-branch to `myAppointmentsProvider`**: its query constrains
  `startTime` alone, and for a LIST query the rules are evaluated against the
  CONSTRAINTS, so `isAssignedEmployee` rejects a technician's whole query.
  `MyDetailsScreen`'s availability-conflict warning read it raw, and the
  rejection was swallowed by a `?? const []` — the warning silently never fired
  for the only role that screen exists to serve, while a permanently-failing
  listener stayed open. The Siri snapshot and the drawer badge already branch;
  copy them.
  **A conflict check is a DAILY-window overlap, not an instant overlap.**
  `findBusyEmployees`' Firestore query is only a coarse prefilter; its results
  are filtered through **`dailyWindowsOverlap`** (same owner file). Testing the
  raw instants reported a 9-5 run across a week as clashing with a 7 pm job
  inside it — a phantom clash the admin had to force through on every evening
  job. That helper compares ALL window pairs rather than matching day indices,
  because an overnight window runs into the following calendar day.
  **`MAX_APPOINTMENT_SPAN_DAYS`/`_MS` in `functions/time_utils.js` hand-mirrors
  `maxAppointmentSpanDays`** (each carries a pointer to the other). Every
  backend sweep that filters on `startTime` must reach at least that far back,
  or a job already under way is invisible to it — that single missing constant
  caused three separate bugs (no overdue prompt for multi-day runs, a digest
  that told an on-site crew "no jobs tomorrow", and a long job dropping out of
  its own travel context).
  **"Is this job still live?" gates on the run's END, not its start, and has
  ONE owner: `hasWorkLeft(record, nowMs)` in `functions/time_utils.js`.**
  Gating on `startTime` meant cancelling or deleting a job mid-run pushed
  NOTHING to the crew, who then turned up the next morning (the Live Activity
  card still ended, so the only signal was a card silently vanishing), and it
  meant `propagateClientEdits` never reached a crew already on site. It was a
  per-module closure in `notification_policy.js` and `client_propagation.js` —
  the same drift shape as `displayStatusAt` and `_who` — so route any new test
  through the shared helper rather than re-deriving `endTime ?? startTime`.
  **Admitting started jobs makes a status filter MANDATORY where it used to be
  free.** A `startTime >= now` query cannot match a job already marked done, so
  terminal jobs were excluded incidentally; any bound that reaches a run
  already under way admits them. `countFutureAssignments`
  (`firebase_appointments_repository.dart`) therefore tests
  `AppointmentStatus.fromRaw(status).isTerminal` explicitly, or a visit
  completed this morning still tells the admin to reassign it before disabling
  the person. Check every bound relaxed this way for the same gap.
  **That query asks `endTime >= now` and nothing else** (2026-08-13), on the
  existing `(employeeIds CONTAINS, endTime ASC)` index — "has work left" is a
  test on `endTime`, so the query states it rather than approximating it with
  `startTime >= now - maxAppointmentSpanDays` and re-testing in Dart. The old
  form had **no upper bound**: it read every job this person was assigned to
  from a fortnight ago to the end of time — and the repeat horizon pre-books
  five years out — to render one caption. Keep the status test in Dart: a
  `whereIn` over the open statuses would need a third index field and would
  silently drop any status the allowlist doesn't name, and this caption must
  err towards telling the admin to reassign.
  **It is also `.limit`ed** (`_futureAssignmentScanLimit`, 200, added
  2026-08-13) — `endTime >= now` still has no upper bound of its own, and a
  repeat series pre-books up to `RepeatInterval.maxOccurrences` (120)
  occurrences, so a tech on several series was several hundred documents read
  to render that caption. **Every query in every repository names a ceiling
  AND warns at it** — the invariant has now been broken twice: once by
  `deleteTokensOfKind` (`live_activity_token_repository.dart`) running an
  unbounded subcollection query, and again on 2026-08-19 when the cleanup
  commits replaced every named ceiling in the data layer with an unbounded
  `while (true)` paging loop. Both are restored: `_deviceTokenScanLimit` (50),
  and `_rangeStreamLimit` (3000) / `_userStreamLimit` (1000) /
  `_presenceStreamLimit` (1000) / `_historySearchScanLimit` (5000) /
  `_clientScanLimit` (5000) / `_clientHistoryScanLimit` (1000). Paging and a
  ceiling are not alternatives — page so one snapshot can't truncate the
  answer, cap so the loop can't walk the collection, warn so a truncation is
  visible in Crashlytics. A `.limit` rather than a horizon bound
  deliberately: with `endTime` the only inequality, Firestore returns these
  `endTime` ASC, so the cap keeps the SOONEST-ending jobs — the ones actually
  needing reassignment — and the number stays EXACT below the cap, so
  `employees_disableReassignCaption` needs no rewording. Bounding the horizon
  instead ("12 jobs in the next 90 days") would read less again but changes
  what the sentence claims; that is a product call, not a performance one. It
  warns at the cap for the same reason the range streams do: understating this
  caption tells an admin they have less to reassign than they do.
  **The mirrors are day-scoped too** (Plan 2, 2026-08-10): the widget payload
  (Dart `widget_sync_service.dart` + `functions/widget_payload_utils.js`), the
  Siri snapshot (**schema v3**) and the push date line all fan a run across the
  days it works. Each carries THAT day's window, never the run's first morning,
  and a multi-day run gets a `dayIndex`/`dayCount` counter that is **omitted**
  for a single-day job so an older decoder still parses.
  **`functions/day_slice_utils.js` is a HAND-MIRROR of
  `appointment_day_slice.dart`** — its jest cases deliberately reuse the Dart
  tests' worked examples (Aug 1–5 day job; Aug 1 22:00 → Aug 4 06:00 = 3 nights
  ending Aug 3), so a divergence fails a test instead of shipping. Change both
  together. Two things it does NOT copy: it re-exports
  `MAX_APPOINTMENT_SPAN_DAYS` from `time_utils.js` rather than restating a
  third copy, and it rebuilds a window as a **wall-clock** time rather than
  midnight-plus-elapsed-minutes, since the latter lands a 9:00 window at 10:00
  on the two DST shift days. It also treats a record with **no `endTime`** as a
  single-day job (the `hasWorkLeft` fallback) — the Dart model never emits one,
  so only the server meets legacy and console-written docs, and reading the
  absent end as "equal times" would make it overnight, count the run backwards
  to zero days, and drop the job out of every mirror silently.
  **The travel sweep and the overdue sweep need NO day-scoping**: the first
  gates on `startTime > now`, so it already fires on day 1 only (days 2+ have
  no separate departure time and the crew is already on site), and the second
  gates on the run's real `endTime`. **Live Activities deliberately skip
  multi-day jobs** — a four-day Lock Screen countdown is worse than no card.
  That skip is `dayCountOf(c) > 1` in `resolveReminderForAssignee`
  (`functions/travel_utils.js`), and it was BUILT 2026-08-11: this bullet
  asserted it as fact from 2026-08-10 while no such gate existed anywhere, so
  the card really did carry the run's `endTime` into
  `Text(timerInterval:countsDown:)`. `docs/archive/2026-08-02-multi-day-appointments.md`
  §10 deferred it, and the doc was right. Only the CARD is withheld — the
  `leaveNow` push still goes out on day 1, which is the only day with a
  departure time.
  **The 14-day cap is applied by ONE clamp, `_clampedDayCount`, and every
  day-scoping answer routes through it** (2026-08-08): `sliceFor`/`runsOn`,
  `runsInRange`, `expandToDays` and `dailyWindowsOverlap`. The rules bound
  stops a CLIENT writing past the cap, but the console and the Admin SDK
  bypass rules entirely, so a doc CAN still exceed it, and
  when the owners disagreed the calendar rendered 14 slices while every
  `runsOn` consumer counted the full corrupt length: a drawer badge reading
  "1 job today" every day for a year, a card counter reading "Day 400 of 900".
  `AppointmentFormValidator` is the one deliberate exception — it reads the
  RAW count, because it is the caller that has to see an out-of-range value in
  order to refuse it.
  **A form's run length has one owner too, `runLengthDays`** (beside
  `appointmentSpan`): the `end − start + 1` rule was hand-copied into both form
  bodies, which even shared the same five-line comment.
- **`findBusyEmployees` must exclude the appointment under edit.** Pass
  `excludeAppointmentId` from any edit-flow conflict check or the job collides
  with itself and reports every one of its own assignees as busy. The exclusion
  is by **doc id, not by series**, so a genuine clash with a sibling occurrence
  still surfaces. A clash returns the sealed `EventDetailsBusyEmployees` (not an
  error) and **must clear `isSaving`** before returning, or Save stays stuck
  once the dialog is dismissed.
