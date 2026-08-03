# Multi-day appointments — design decision

**Date:** 2026-08-02
**Status:** Design approved. **Not built.** Build go-ahead is separate.
**Mockup:** https://claude.ai/code/artifact/a6fbab99-4e86-405b-a001-cc5ba5485ea1
**Branch context:** paused the redesign program (P5+) to add this first.

An appointment can run across more than one day. The form gains an end date;
every day the job spans shows it, described from that day's point of view.

---

## 1. The decisions

| # | Question | Decision |
|---|---|---|
| 1 | Which days show a multi-day job? | **Every day it spans** — grid dots, agenda, day route, dashboard, widget, Siri. |
| 2 | Maximum span? | **14 days**, enforced client-side in the validator. |
| 3 | What do the two times mean? | A **daily window**, not one unbroken stretch. 9:00 AM–5:00 PM means 9–5 *on each of those days*. |
| 4 | Card treatment | **Option A** — the day counter joins the mono time line after a middot. |
| 5 | Form shape | **Always-visible Start date / End date pair**, mirroring the Start time / End time pair below it. |
| 6 | All-day multi-day? | **Yes** — and `isAllDay` now applies to **client jobs too**, not just personal blocks. |
| 7 | Night shifts (end time before start time)? | **Real, supported.** The window crosses midnight and the job counts **nights**. |
| 8 | End date semantics | **The last day the crew STARTS work**, never the morning it finishes. Count is `end − start + 1` for day jobs and night shifts alike. |
| 9 | Scope | Everything in one pass — app, home widget, Siri, push text. |

### Why the daily-window reading (3)

The first pass treated `Aug 1 9:00 AM → Aug 5 5:00 PM` as one continuous
instant span, which forced middle days to render as "All day". That collides
with the **all-day toggle's own label** — two different meanings for one
string, on cards sitting next to each other in the same agenda.

Reading the times as a daily window removes the collision at the source: a
timed job always shows real clock times, and "All day" stays reserved for
`isAllDay`. It is also what a tradesperson means by "a five-day job".

### Why the end date is not behind a "multi-day" switch (5)

A stored `isMultiDay` flag can disagree with the dates it describes — the same
class of bug the `isAllDay` / `isPersonal` notes in CLAUDE.md were written
about. Two dates cannot desync from themselves.

---

## 2. What is NOT changing

- **No schema change, no migration, no rules change.** `startTime`/`endTime`
  are already real instants and already carry the span. `isValidAppointmentData`
  in `firestore.rules` does not constrain them, so the 14-day cap is
  client-side only.
- **`isMultiDay` is derived, never stored** (`endTime.dateOnly !=
  startTime.dateOnly`) — same discipline as `AppointmentStatus.overdue` being
  display-only.
- **Repeating series already work.** `occurrenceEnd`
  (`repeat_interval.dart:62`) already preserves the day-span when generating
  occurrences, and the shortest repeat is 4 months — far longer than the 14-day
  cap, so a series can never overlap itself. **No work here.**
- **The overdue sweep already gates on `endTime`**, so a multi-day job is not
  nagged until it genuinely runs late. **No work here.**
- **Single-day cards render exactly as they do today.**

---

## 3. Domain model

One new pure concept, one owner. `lib/features/calendar/domain/appointment_day_slice.dart`:

```dart
class AppointmentDaySlice {
  AppointmentRecord appointment;
  int dayIndex;            // 1-based
  int dayCount;            // end − start + 1
  bool isOvernight;        // window crosses midnight → counts NIGHTS
  bool get isFirstDay / isLastDay;
  DateTime get windowStart;  // this day @ start time
  DateTime get windowEnd;    // this day (+1 if overnight) @ end time
}

AppointmentDaySlice? sliceFor(AppointmentRecord, DateTime day);
Map<DateTime, List<AppointmentDaySlice>> expandToDays(records, range);
```

**Slices are generated per work-day — each day the daily window BEGINS — not
per calendar day the instant span touches.** That single rule makes the night
shift fall out correctly: a 10 PM–6 AM job on Aug 1–3 produces three slices
(Aug 1, 2, 3) and nothing on Aug 4, because nobody starts work that morning.

Every surface asks this: card, agenda, grid dots, day route, dashboard,
widget, Siri. CLAUDE.md documents two separate incidents where a hand-copied
"mirror" of a rule drifted (the `displayStatusAt` ladder, `_who` in the push
text). Day-scoping is exactly the kind of rule that would otherwise get copied
five times.

---

## 4. Fetch strategy

`maxAppointmentSpanDays = 14`. `AppointmentDateRange` gains a `fetchStart` of
`start − 14 days`. `watchInRange` keeps its single `startTime` inequality, its
existing composite index, its `orderBy` and its `_rangeStreamLimit` —
**the query shape does not change.** `expandToDays` drops non-overlappers in
Dart. Cost is ~14 extra days of docs per range, far inside the 1000 cap.

**The widening must live INSIDE `AppointmentDateRange`, not at call sites.**
`appointmentsInRangeProvider` is keyed by range *value*, so a call site that
widened it itself would fork a second Firestore listener for the same day —
precisely the failure `forDay`'s doc comment already warns about.

The true two-inequality overlap query (`startTime < end AND endTime > start`)
was considered and rejected for now. It already works in this codebase —
`findBusyEmployees` uses exactly that shape — but on `watchInRange` it would
force `endTime` into the `orderBy`, need a new composite index, and rework of the
range-stream cap. The 14-day ceiling makes it unnecessary.

---

## 5. Form

- Controllers and both controllers' state gain `endDate`.
- **End date follows start date until touched**, tracked by an explicit
  `endDateTouched` flag in form state — never inferred. Editing the start of a
  3-day job shifts the end by 3 days rather than collapsing it.
- `appointmentSpan()` takes `endDate` and stays the **one owner** of the span
  convention. `allDaySpan(start, end)` becomes midnight-of-start →
  23:59-of-end. Both save paths keep routing through it.
- The time-cell labels gain a **`· each day`** qualifier once the end date
  moves past the start (`· each night` / `· next morning` when the window
  crosses midnight). On a one-day job the labels read plainly.
- The end-date cell shows a trailing **`5 days`** / **`3 nights`** count.

### Validator

- New: `endDateBeforeStart`, `spanTooLong` (> 14 days).
- **`endTimeMustBeAfterStart` is DELETED, not relaxed.** Under the
  daily-window reading an end time before the start time is the *definition* of
  a night shift, which is now supported. Nothing rejects it.
  - *Correction to an earlier draft of this design*, which said the check
    would apply only on same-day jobs. Once night shifts are real, there is no
    case left where it should fire.
- `combineEndDateAndTime`'s silent overnight day-bump is **retired**. With a
  visible end-date row, auto-advancing the day behind the user's back is a
  second, invisible owner of the same fact. The stored `endTime` for a night
  shift is derived once, in `appointmentSpan`, as `endDate + 1 day @ endTime`.

---

## 6. All-day now applies to every job

The `_AllDaySwitch` moves out of the `if (isPersonal)` guard and renders on
every job, as the schedule panel's first row.

> **⚠ This retires a documented CLAUDE.md invariant.** CLAUDE.md currently
> requires `setPersonal(value: false)` to clear `isAllDay` (`isAllDay: value &&
> state.isAllDay` in both controllers). That rule exists *only* because the
> switch was personal-only, so leaving the flag set would strand an
> unreachable state — a midnight–23:59 client visit with no switch on screen to
> fix it. Now that the switch is always visible, the clearing would silently
> discard a deliberate choice the moment someone toggles Personal off. **It must
> be removed, and the CLAUDE.md note rewritten rather than patched.**

Knock-on effects, all correct as-is:

- `selectTravelCandidates` skips all-day records — still right, an all-day job
  has no departure time. Now applies to all-day *client* jobs too.
- `selectOverdueCandidates` skips `isPersonal`, not `isAllDay` — so an all-day
  **client** job does become overdue after its 23:59 end. Correct.
- `displayStatusAt` derives `in_progress`/`overdue` for a non-personal all-day
  job. Correct.

---

## 7. Display

- `AppointmentCard` takes an optional `slice`. Time line reads:
  - `9:00 AM – 5:00 PM · Day 3 of 5` (timed multi-day)
  - `All day · Day 2 of 3` (all-day multi-day)
  - `10:00 PM – 6:00 AM · Night 2 of 3` (night shift)
  - unchanged when there is no slice.
- **Agenda sort is unchanged in principle:** a continuing timed job has a real
  start time today, so it sorts by the clock like any other job. Only all-day
  blocks pin to the top, exactly as now.
  - *Correction to an earlier draft*, which pinned continuing timed jobs above
    the timed work. That followed from the continuous-span reading and is wrong
    under the daily-window one.
- Grid crew dots come from the expanded index, so they appear on every day of
  the span.
- The read-only detail when-line reads the **full span**, not the slice.

---

## 8. Off-screen mirrors

| Surface | Change |
|---|---|
| Home widget | `widgetPayloadProvider` range starts 14 d back; `buildWidgetPayload`'s `inRange` becomes an overlap test; job JSON gains `dayIndex`/`dayCount`; Swift `Job` decodes them as `Int?` so a pre-existing payload still parses. Mirrored in `widget_payload_utils.js`. |
| Siri snapshot | Schema **v3** — adds the two fields, bumps `supportedVersion` in `ScheduleSnapshot.swift`, day-scopes `timePhrase` / `nextAppointment`. |
| Push / digest | `_contextFor` carries the span; the date line reads "Aug 1 – Aug 5". |
| Travel "leave now" | **Day 1 only.** Days 2+ have no separate departure time and the crew is already on site. Documented, not accidental. |
| Overdue sweep | No change — already `endTime`-based. |
| Live Activities | **Multi-day jobs skip Live Activities in this pass.** A card counting down to an end four days out would sit on the Lock Screen for the whole job. Noted as a follow-up, not solved here. |

---

## 9. Rejected card options (for the record)

- **Counter as a chip beside the status chip.** Scans fastest, but the second
  chip visibly crowds a realistic title ("Inspection annuelle — Tour
  Chaudière") at `isCompact`.
- **Notched crew rail + own micro line.** Clearest of the three, but it adds a
  bar treatment and a fourth text row to a component used in six places.

---

## 10. Open items

1. **Live Activities for multi-day jobs** — deferred, see §8.
2. Whether the 14-day cap deserves a matching `firestore.rules` bound. Today
   nothing constrains `startTime`/`endTime` there, so adding one is a
   tightening, not a fix — and per CLAUDE.md a rules cap must never be tighter
   than the widest value a shipped write path can produce.
