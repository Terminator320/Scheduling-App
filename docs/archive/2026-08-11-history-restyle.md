# History restyle — the chosen design

**Decided 2026-08-11** · branch `redesgin` · mockup:
<https://claude.ai/code/artifact/db74507f-942a-478e-8adb-47c61f0bfbcf>

This is P7's History half (`docs/plans/redesign-subdocs/2026-08-11-p7-dashboard-history.md`
Phase D). **BUILT 2026-08-11** — see that document's Phase D section for what
the build cost, which was mostly re-owning the pagination a sticky header
cannot share with `PagedListView`.

Three options were rendered in the app's own tokens and bundled faces: **A** day
panels (each day a card containing its jobs), **B** a date rail (day on a left
rail, cards untouched), **C** a dense ledger (mono time column, ~2× the rows per
screen). **Chosen: B, with the month as the grouping header.**

## Chosen

| | |
|---|---|
| **Grouping** | A **sticky month bar** (`August 2026`), and under it the day on a left rail. The old bold **year separator is deleted** — the month already carries the year, so keeping both is a third heading repeating the second. |
| **Rows** | The shared `AppointmentCard`, **unchanged**. |
| **Count** | **One mono count at the top only**, carrying the cancelled share — `18 JOBS · 2 CANCELLED`. No per-month counts. |
| **Quick filters** | Two chips: **Complete** and **Cancelled** — the app's existing `StatusChip` wording, not a second vocabulary. |
| **Search** | Spans **every appointment**; results render **flat** — no month bars — and the rail carries the month, plus the year when the hit is older than the current one. |
| **Filters** | Year and Crew keep their chips but open a **single-select sheet** instead of a `MenuAnchor`. On iOS that is a Cupertino action sheet. |
| **Cancelled** | Dimmed to 0.6 **and struck through**. |

## Why B over A and C

Both A and C stop using the shared `AppointmentCard` — A because the row loses
its border to the enclosing panel, C because it is a genuinely new row widget.
That card is deliberately the **one** appointment card across the calendar
agenda, day route, history, both dashboard sections and client job history; it
had already drifted into four copies once, which is the whole reason the rule
exists. B carries the date on a rail instead, so the card is untouched and this
is the smallest of the three builds.

C's density (~9 rows per screen against ~5) was the real argument against B, and
it was not enough to justify a second row shape.

**Cost accepted:** the rail takes 44px of a 372px screen, so titles truncate
sooner than they do today.

## Decisions worth keeping

- **No per-month counts, ever.** History is paginated, so an early month can only
  count what has loaded — the number would climb as you scroll, which is a figure
  that changes while you look at it. The top-level total is the only count that
  can be honest. (Owner call; the mockup had drawn per-month counts and they were
  removed.)
- **The month bar is sticky, and that is load-bearing at the boundary.** Crossing
  from August into July, the day numbers reset from 3 back to 31. Without a
  header announcing the month, that reads as a data error rather than a
  transition. Frame 02 of the mockup exists purely to check this case.
- **Search goes flat because search is not month-scoped.** It spans every
  appointment, so results are not a contiguous run of days and month bars over
  scattered hits are noise.
  **Consequence: the rail must change shape in search.** A bare `Tue 11` is
  ambiguous once results cross years, so in search mode the rail shows the
  **month** abbreviation instead of the weekday, and adds the **year** when the
  result is not from the current one. This fell out of the decision rather than
  being asked for, and it is the one piece of the design that is genuinely
  conditional on state.
- **Quick filters are exactly the two statuses History holds.** `done` and
  `cancelled` — the `terminalStatusRawValues` set. Anything richer needs a field
  the record does not carry.
- **The chips reuse the app's existing labels rather than inventing wording.**
  They read **Complete** and **Cancelled**, matching the `StatusChip` rendered on
  the card in the same row. The mockup first drew *Completed*, which put two words
  for one state on one screen; the owner settled it on the existing label
  (2026-08-11). So the chips bind to the same `statusLabel` the chip already uses
  — don't add `history_filterCompleted`-style keys beside it.
- **The count carries the cancelled share, and it is a SUBSET, not an addition.**
  `18 JOBS · 2 CANCELLED` means 2 of those 18 were cancelled — the same shape as
  the calendar agenda's `4 JOBS · 1 DONE`. It must be computed with the same
  `isClosed`-family predicate the agenda's `_ClosedRule` uses, or the two
  surfaces can disagree about the same day's work. **The search state carries it
  too** (`5 RESULTS · 1 CANCELLED`); a count that drops the clause on one state
  and keeps it on the other reads as a different metric.
- **Filtering itself does not change.** It stays the bounded Dart-side search
  over loaded pages with the debounced server-backed `historySearchProvider`
  behind it. **No new server queries, no composite index, no deploy.**

## Nothing open

Every question the mockup raised is answered above. The remaining notes are
constraints, not choices.

## Constraints the build must not break

- `AppointmentHistoryView` takes an `isAdmin` and passes it straight through as
  `showActions`. History is where `done`/`cancelled` jobs live, so it is the one
  screen an admin looks for a completed job's Edit button on. Do not re-hardcode
  it closed.
- The closed-job **collapsed green treatment is calendar-agenda-only by design.**
  History keeps the plain full-height card. Don't unify them: the agenda sinks
  closed work because it answers *what's left today*, and History is a record
  where everything is closed.
- `onFirstPageSettled` gates the feature tour. The filter row only renders once a
  page has supplied years/employees, so a tour started earlier drops its steps and
  marks the whole scope seen. Any restructuring of the filter row has to keep that
  callback firing.
