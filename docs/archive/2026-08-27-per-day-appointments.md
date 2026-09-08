# Multi-day jobs book as one appointment per day

**Date:** 2026-08-27
**Status:** SHIPPED. Implemented 2026-08-27, cut as 1.53.0+82 on 2026-08-28,
and the rules half **deployed 2026-08-29** at `77c6a66f` (`firestore:indexes`
first, then functions, rules, storage). Nothing here is outstanding.

## Release-review gaps, CLOSED in 1.53.0+82

All three were found by the release review and fixed before the cut.

1. **Only the ADD path split a run.** `showEndDate` was gated on `isRunMember`
   alone, so opening a ONE-day client job and widening its end date wrote the
   single wide document this design exists to eliminate — indistinguishable
   from a real run on screen, but marking one day complete closed the week.
   `AppointmentFormFields.canSpanDays` now gates the end-date row, and
   `details_edit_body` passes `appointment.isPersonal`: a client job's shape is
   fixed at booking, while personal blocks and time off keep the row because
   they legitimately stay one wide document.
2. **Run scope was ordered by `startTime`, but a run's identity is
   `dayIndex`.** A run member's start date stays editable, so moving day 1 past
   its siblings made "cancel this and the following days" select NOTHING and
   report success, while the same action on day 4 swept the moved day up.
   `futureSeriesRecords` now takes an `anchor` and compares day positions when
   that anchor carries a coherent run pair, falling back to `startTime` for a
   repeat series or a legacy document.
3. **A run day counted as a job.** `recountClientJobs` counted documents, so a
   5-day booking made the client's `jobCount` badge read 5 and rendered 5 rows
   in the client's job history. `recountOne` now subtracts a second aggregate
   over `dayIndex > 1` — the inequality naturally excludes single-day jobs
   (no field) and day 1 (stores 1), so no backfill was needed — served by a new
   `(clientId ASC, dayIndex ASC)` composite. `fetchClientHistory` filters to
   `dayIndex <= 1` in Dart rather than in the query, because a server-side
   inequality would drop every document written before the field existed.

**Still open (cosmetic):** nothing renumbers `dayIndex`/`dayCount` after a
this-day-only delete, so the survivors of a 5-day run keep reading "of 5".
The scope actions are correct — only the label is stale.

## The problem

A multi-day job is ONE Firestore document whose `startTime`/`endTime` describe a
daily window — 9:00–17:00 means 9-to-5 on each day of the run.
`AppointmentDaySlice` renders that one document as a card on each of its days,
labelled `Day 3 of 5`.

One document carries one `status`. So a crew that finishes day 1 and marks it
complete closes the entire run: days 2 through 5 read as done, the server stops
nudging anyone about them, and the only way back is an admin re-opening the job.
Per-day completion is the thing the crew actually needs and the data model
cannot express it.

The fix is to book each day as its own appointment.

## What production actually holds

`functions/scripts/count-multi-day-appointments.js` (read-only) was run against
prod on 2026-08-27:

```
scanned 67 appointments
multi-day runs (2+ work days): 3
  open (pending/in_progress):  1
  closed (done/cancelled):     2
  booked time off (any status): 1, 1 of them open
  longest run seen: 4 day(s)
```

The open run IS the time off (the open count and the open-time-off count are the
same 1), and the "open WORK runs by length" histogram did not print, which only
happens when it is empty.

**There are zero open multi-day jobs.** Nothing in production has the
all-or-nothing completion problem today, and nothing needs migrating: two closed
runs are history, and the one open run is an absence that this design does not
split anyway. That removes the irreversible prod write, the photo-loss edge case
and the half-migrated-run recovery story from the whole project.

Keep the count script. It is the thing that says whether that is still true
before this ships.

## Decisions

Each is an owner call made during design; the alternative is recorded because
the reasoning is what stops it being re-litigated.

1. **Days are separate documents linked by `seriesId`, carrying a stored
   `dayIndex`/`dayCount`.** Not fully independent documents: the run has to stay
   legible as one job on the calendar (`Day 3 of 5`) and an address edit must
   not mean editing five cards.
2. **Time off and personal blocks do NOT split.** Nothing marks a day off
   complete, so per-day statuses buy nothing there, and a two-week vacation
   fanned into 14 independently-cancellable rows makes the clash alert and the
   availability reducer reason about 14 documents where they now read one span.
   `AppointmentDaySlice` therefore is not legacy code being carried — it stays
   the live representation for absences.
3. **Every destructive or propagating action asks scope, matching repeats.**
   Editing details, cancelling and deleting a day in a run raise the same
   "This day only / This and the following days" dialog repeats already use.
   Mark-complete never asks — this day only is the entire point of the change.
   Rejected: fixed no-prompt rules, which leave a crew that finishes early with
   no way to drop days 4 and 5.
4. **Repeat is not offered on a multi-day job.** The picker hides once the end
   date is past the start date, exactly as it already hides for a personal
   block. This is what lets one `seriesId` mean one thing: a weekly 3-day job
   would make `seriesId` ambiguous across two axes and force a third state into
   the scope dialog ("the rest of this run" vs "this and future weeks") for a
   capability the business does not book. If it is ever needed, a second
   `runId` field is a clean addition on top of this structure.
5. **A run's LENGTH is fixed at creation.** The end-date picker is hidden on a
   run member. To shorten, cancel the tail through the scope dialog; to extend,
   book another job. Rejected: letting day 1 reshape the run through
   `AppointmentSeriesEditor.rewrite`, which deletes and recreates the trailing
   documents — destroying exactly the per-day statuses and photos this change
   exists to create.

## Data model

Two new fields on `AppointmentRecord` and the appointment document:

| Field | Type | Meaning |
|---|---|---|
| `dayIndex` | int, 1-based | this document's position in its run |
| `dayCount` | int | how many days the run covers |

A run's days share `seriesId` = **day 1's document id**. That is the same field
a repeat series uses, which is safe only because decision 4 makes the two
mutually exclusive; `repeat` stays `RepeatInterval.none` on every run member.

**`dayCount` absent or `< 1` means "legacy wide document — derive from the
span".** That single fallback is what lets the three production documents keep
rendering with no migration.

### `AppointmentDaySlice` stays the one owner

A split day's window is one day wide, so `_dayIndexOn` naturally returns
`(1, 1)` for it. The `Day 3 of 5` label must come from the stored pair instead.

**The substitution is the LABEL only, and that boundary is load-bearing.**
`_dayIndexOn` answers two different questions with one pair: *does this document
run on this day* (`index` inside `[1, count]`) and *what does the card say*.
Feeding the stored `dayCount: 5` into the first would make day 3's document
claim it runs on the five days following its own start — every split run would
smear across the calendar, each of its days rendering five cards, and
`runsOn` is the mandated re-scoping call on every superset consumer, so the
drawer badge, the roster's jobs-today and the dashboard would all inherit it.

So: `_dayIndexOn` stays **purely derived** and keeps owning the runs-on test.
`sliceFor` substitutes the stored pair into the slice it returns — the
`dayIndex`/`dayCount` the card, the widget and Siri read — while the window and
the day test stay derived. A stored pair is only honoured when it is coherent
(`1 <= dayIndex <= dayCount <= maxAppointmentSpanDays`); anything else falls
back, so a console-written document cannot render "Day 9 of 5".

Putting the substitution inside `sliceFor` rather than at the call sites is the
whole point: the card, the widget payload, the Siri snapshot and the push text
all keep asking one function, and a legacy document and a split day give the
same shape of answer. A second spelling of "which day of the run is this" at any
call site is the drift this file exists to prevent — the same trap
`displayStatusAt` and `_who` each fell into.

`runsOn`, `countsAsWork`, `countsAsLoadOn` and `runsInRange` need no change: a
one-day document answers all four correctly on its own.

## Create path

`AddEventController.submit()` expands the form's `selectedDate`→`endDate` into N
per-day records before writing.

- A new pure helper beside `expandToDays` in `appointment_day_slice.dart` takes
  the resolved `(start, end)` window and returns one `(start, end)` pair per
  work day, clamped to `maxAppointmentSpanDays`. Pure, so it is tested without a
  repository, and it lives beside the day-scoping rules it has to agree with.
- Day 1 keeps `docId`; each later day gets `repo.newDocId()`.
- Every member carries `seriesId: docId` (empty when the run is one day),
  its own `dayIndex`, and the shared `dayCount`.
- Everything else — title, client, address, crew, notes, materials, `isAllDay` —
  is copied unchanged.
- One `repo.addAppointments([...])` batch, so a run is atomic.
- **Photos attach to day 1 only**, exactly as repeat copies already work: the
  `images` subcollection belongs to one document. Photos taken on day 3 attach
  to day 3's own document afterwards, which is an improvement over the wide
  document, where every day's photos landed in one pile.
- **The conflict check is unchanged.** `findBusyEmployees` already takes the
  whole `(start, end)` span and filters through `dailyWindowsOverlap`, so it
  covers every day of the run before a single document is written.
- **A personal block skips the expansion entirely** (decision 2) and saves as
  one wide document, exactly as today.

### Push notifications need no work

`diffAppointmentForNotifications` already suppresses the `assigned` push for any
created document whose `seriesId` is non-empty and not equal to its own id — the
repeat-series anchor rule. Because day 1's document id IS the `seriesId`, a
5-day run created in one batch sends **one** "job assigned" push, not five. The
`seriesOpId` batch-claim in `claimSeriesNotice` covers the edit and cancel
batches the same way.

This is a consequence of reusing `seriesId` rather than inventing a `runId`, and
it is worth stating because it looks like it should need work and does not.

## Edit, cancel and delete

A run member has a non-empty `seriesId`, so `details_edit_body`'s
`_resolveSeriesScope` already raises the scope dialog on save. What changes:

- **`SeriesScopeDialog` gains run-flavoured copy** — "This day only" / "This and
  the following days" — selected on `dayCount > 1`. New EN/FR ARB keys under the
  `calendar_` prefix. `seriesOutlook` writes the consequence line unchanged
  ("this and 3 more, through Fri Aug 7"), since counting forward from a date is
  the same question on either axis.
- **The end-date picker is hidden when `dayCount > 1`** (decision 5), beside the
  repeat picker's new `isMultiDay` condition in `appointment_form_fields.dart`.
- **Cancel gains a scope.** `_setStatusOnRepo` writes one document today;
  cancelling a run member has to offer the tail. This is the one genuinely new
  path in the edit flow — it needs the same reentrancy discipline as `save()`
  (flag set synchronously before the first await, reset on every early return
  and catch) and it returns the existing sealed `EventDetailsActionOutcome`.
- **Delete already has `includeFuture`** and needs only the dialog copy.
- **Mark-complete does not change at all.** No scope, no dialog, one document.

## Server side

- **`functions/day_slice_utils.js`** takes the same stored-pair preference in
  `sliceForDay`, so the widget payload, the Siri snapshot and the push text
  cannot disagree with the Dart side about which day of a run a document is.
  Its jest cases reuse the Dart suite's worked examples, so a divergence fails
  rather than ships — change both together.
- **`firestore.rules`** bounds the two new fields in `isValidAppointmentData`:
  each an int in `[1, maxAppointmentSpanDays]` when present. The appointment
  validator is a per-field allowlist with no `hasOnly`, so adding them cannot
  reject an existing write. `isValidAppointmentSpan` is untouched — a one-day
  document passes it trivially, and it still has to bound the wide documents
  time off keeps writing.
- **Live Activities start working on long jobs.** `travel_utils.js` skips them
  today (`kind === "leaveNow" && delivered > 0 && dayCountOf(c) <= 1`), because
  a four-day Lock Screen countdown is worse than no card. Every split day is one
  day, so each day of a run now gets its own working card. This is a behaviour
  change that falls out of the design rather than one being added; the guard
  stays as-is for the wide documents time off still writes.
- **The overdue prompt and the tomorrow digest now speak per day.** A 5-day job
  produces five "job tomorrow" lines across five nights instead of one, and an
  unclosed day 2 is nagged about on its own. That is the correct behaviour and
  the reason the change exists, but it is a visible increase in message volume
  and worth watching after release.

## Migration

**None.** The count establishes there is nothing to move. The three existing
wide documents keep rendering through the derived branch of `sliceFor`.

Re-run `functions/scripts/count-multi-day-appointments.js` immediately before
shipping. If it then reports open multi-day WORK runs, they were booked between
this design and the release, and the choice is to let them finish as wide
documents (they still render and still close all-or-nothing) or to rebook them
by hand. There are few enough that a backfill script is not worth writing.

## Testing

Dart:

- `appointment_day_slice_test.dart` — the stored-pair substitution: a document
  with `dayCount: 5, dayIndex: 3` reports day 3 of 5 on its own day; one with
  `dayCount: 0` derives from its span exactly as today; an incoherent stored
  pair falls back rather than rendering "Day 9 of 5". **And the boundary
  itself**: that same `dayCount: 5` document returns non-null from `sliceFor`
  and true from `runsOn` on exactly ONE day — the regression that would smear
  every run across the calendar and into the drawer badge, the roster count and
  the dashboard.
- The new run-expansion helper — a 5-day 9-to-5 window yields five one-day
  windows; a night shift yields one per night, not per calendar day touched; a
  span past the cap clamps to 14; a one-day window yields one pair.
- `add_event_controller` — a multi-day save writes N records in one batch with
  the shared `seriesId` and correct indices; a personal multi-day save writes
  ONE wide record; photos go to day 1; the repeat picker is absent on a
  multi-day form.
- `event_details_controller` — mark-done on day 3 leaves days 1, 2, 4 and 5
  untouched (the regression this whole change exists to prevent, and the test
  that must never be deleted); cancel with "this and the following" closes the
  tail and nothing before it; the cancel reentrancy guard.
- Overflow pass on the run-flavoured scope dialog at 260 logical px with
  `TextScaler.linear(2)`, per the local `_harness` convention.

JS:

- `day_slice_utils.test.js` — the stored-pair branch, mirroring the Dart cases.

## Accepted costs

- **Two representations survive**: split days for jobs, wide spans for time off
  and for the legacy documents. `AppointmentDaySlice` is not going away, and its
  derived branch stays live and tested.
- **A run's length is immutable after booking.** Shortening means cancelling the
  tail, extending means a second booking.
- **No repeating multi-day jobs.** Deliberate; see decision 4.
- **Five documents where there was one.** A 14-day job is 14 documents against
  the same range-stream limits and the same 5000-doc search windows. At 67 total
  appointments this is not a pressure point, but it is the number that grows
  fastest if long jobs become common.
