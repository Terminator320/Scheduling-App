# Day off — card and detail design

**Date:** 2026-08-24
**Status:** SHIPPED — built 2026-08-24 and released in 1.50.0+79. App-side
only; nothing to deploy. `_DayOffStrip` in
`lib/features/calendar/widgets/cards/appointment_card.dart` is what landed.
**Mockup:** https://claude.ai/code/artifact/b9d91b97-d78e-46ea-9090-f3241cf90ca3

Design for how a day off (`isDayOff` on a personal block — see
`.claude/rules/appointments.md`) renders, now that the flag exists and keeps the
block out of every job count. This doc covers appearance only; the counting rule
and the flag itself already shipped in 1.50.0+79.

## Chosen: Option B, "day banner", with the side colour dropped

Three options were rendered — A a dashed quiet row, B a low tinted strip, C a
card with an away glyph. **B was picked, with one change: no colour bar down the
side.**

The strip:

- Not a card. No fill beyond a faint tint, no border, no shadow, **no crew
  colour bar** — the bar is what says "this is a job with a crew on it", and a
  day off is neither.
- Reads `<avatar> <b>Marc Tremblay</b> is off ............ DAY OFF`, with the
  label as a mono uppercase caption at the trailing edge.
- Sits in date order among the day's work and stays tappable.
- The crew avatar stays: it is identity, not job colour, and it is what makes a
  row scannable when several people are off the same day.

**Leads with the person, not the title.** This is the reason B beat A and C: a
day off usually has no title typed, and the two title-led options both fall back
to the word "Personal" in that case. The name is what the reader came for.

## Detail view — confirmed as mocked (2026-08-24)

Header is the person's name, with `Day off · Mon 25 – Fri 29 Aug` as the mono
when-line under it and the crew avatar at the trailing edge. Body is `OFF —
5 days`, an optional `NOTE`, and an `Edit` button. Nothing else.

## It completes itself at the end of the last day

There is no Complete button — nothing about a day off is finished by a person —
so **the end of its span is what closes it** (owner call, 2026-08-24). Before
then the strip's trailing caption reads `DAY OFF`; after, it reads **Complete**
and the sentence goes past tense ("Marc Tremblay *was* off").

**Derived from the clock, never written.** It belongs in
`AppointmentRecord.displayStatusAt`, the one owner of every clock-derived state,
as a branch ABOVE the existing `isPersonal` early return (a day off is personal,
so it would otherwise never be reached):

```dart
if (isTimeOff) return now.isAfter(endTime) ? 'done' : status;
```

`endTime` on an all-day block is 23:59 of the last day, so "after the end" is
literally the end of that day. Three things follow, and each is a reason to
prefer this over a stored write:

- **No sweep, no writes, no deploy.** The same contract `overdue` already has —
  display-only, never stored, never in the picker. A scheduled function marking
  past blocks `done` would cost an invocation per day and could be wrong; this
  cannot be.
- **It does not sink into the agenda's closed block.** `_agendaOrder` sorts on
  `AppointmentRecord.isClosed`, which reads the STORED status and is
  deliberately clock-free — so the strip stays in date order where it happened
  rather than dropping to the bottom of the day under a "Done" rule.
- **It makes the `!status.isTerminal` carve-out in `appointmentChip` the
  mechanism** rather than the dead code this doc previously said it would
  become: the chip resolver already shows the status instead of "Day off" once
  the status is terminal, which is exactly this.

The stored status stays `pending` forever, which has one consequence worth
naming: `purgeExpiredHistory` only purges `done`/`cancelled`, so day-off records
are never purged. At a handful per person per year that is not worth a sweep,
but it is a real difference from a completed job.

## What a day off drops

Address · materials · photos · start and end times (it is all day) · repeat ·
the status picker · **Mark as complete** (the end of the day does it) ·
**Cancel** (delete it instead) · the crew colour bar.

Kept: the assignee (required — it is the point, and it is what makes the person
read as busy when you try to book them), the dates, and an optional note.
Deleting the block is how you undo one.

## Consequences to carry into the build

- **A day off reaches Done only by the clock, never by a write** (see above), so
  the `closedJobCount` filter added in 1.50.0+79 stays as defence for legacy
  stored-done rows rather than a live case — `isClosed` is stored-only and a
  derived completion never reaches it.
- The `displayStatusAt` change must sit ABOVE the `isPersonal` early return, and
  its JS mirror needs no change: `selectOverdueCandidates` skips `isPersonal`
  records already, so nothing server-side nudges a day off either way.
- A day off with no title still saves a title internally; the strip and the
  detail header must not render it, or an untitled block reads "Personal".
- Built as designed. The short-lived `appointmentChip`/`appointmentChipLabel`
  resolver and `DayOffChip` were deleted with the build: the strip and the
  day-off body render their own state, so nothing reached them.

## Not decided here

Whether a dispatcher can have a day off booked for them: **no** (owner call,
2026-08-24). Dispatchers are not offered as assignees anywhere, day off
included, so a day off is never recorded for one.
