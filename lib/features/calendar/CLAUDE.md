# Calendar UI (lib/features/calendar/)

Rendering rules for the calendar surfaces. These moved out of the root
`CLAUDE.md` on 2026-08-14 because they are pure Flutter UI with no
`functions/` hand-mirror, so they only need to load when working here.

Everything with a server-side twin — the appointment status allowlist,
multi-day spans, all-day blocks, personal jobs, the photo subcollection,
`AppointmentDaySlice` and the range-stream re-scoping rule — deliberately
STAYS in the root `CLAUDE.md`, because those are reachable from
`functions/` where this file does not load.

- **Calendar (rebuilt in P2, 2026-07-30):** `table_calendar` is **deleted**;
  the month view is our own `CalendarMonthGrid` + `CalendarMonthPager`. It
  renders **only the weeks the month actually occupies** — 4, 5 or 6 rows from
  `monthGridRowCount` (owner call, 2026-07-31: a fixed 6 trailed a week of
  nothing but off-month cells). A fixed **5** is still wrong the other way and
  drops the end of months like August 2026, so the row count must stay derived,
  never a constant. Week start comes from the locale (`weekStartForLocale`,
  memoized per locale string — it builds a `DateFormat` just to read its
  symbols, and the grid, pager and week strip all ask on every calendar
  rebuild). Resolve it from a widget through `CalendarMonthGrid.weekStartOf(context)`
  rather than re-inlining `weekStartForLocale(Localizations.localeOf(...))`.
  Because rows vary, `CalendarMonthGrid.heightFor` takes a **required `rows`**
  (use `rowsFor(context, month)`), the pager animates its viewport to the month
  in view, and each page is wrapped in `ClipRect` + top-aligned `OverflowBox`
  so a taller month being dragged in doesn't overflow before the height
  settles. Off-month cells render a **faint day number AND their
  crew dots** but stay untappable and out of the semantics tree: the design says
  "blank, Ink 15, not tappable" while the program spec widened the fetch range
  precisely so trailing days aren't dotless, and dots-plus-faint-number is what
  reconciles the two (owner-confirmed). **The crew dots also survive selection**
  (owner call, 2026-07-31): the selection circle fills the day number only and
  the dot row sits below it on the plain cell background, so suppressing them
  there made the day being looked at the one day whose crew was invisible.
  Every cell that has crew shows it — off-month, selected, today, all of them.
  **A day's dots count JOBS, not distinct people** (owner call, 2026-08-04, which
  reversed the P2 rule): `dayJobDotColors` (`calendar/domain/appointment_crew.dart`)
  emits one entry per job in list order, capped at 3, each carrying that job's
  first colour-resolvable assignee. The dots answer "how busy is this day", so
  two jobs for the same person are two dots. It returns `List<Color?>` and a
  **null entry is load-bearing, not a gap**: a job whose crew resolves to no
  colour still gets a dot, painted `palette.textFaint` — the same neutral the
  card's crew bar uses for an unassigned job. The old per-assignee version
  simply skipped those, so a day holding only unassigned work read as empty.
  The week strip renders the same list capped at 1, for the same reason.
  `today` always comes from
  `currentDayProvider`, never `DateTime.now()`, or the circle sticks on
  yesterday in an app left open across midnight.
  **TODAY IS A RING AND SELECTION IS A FILLED CIRCLE, and that rule has ONE
  owner: `calendarDayCircleDecoration`** (`widgets/views/calendar_day_circle.dart`,
  owner call 2026-08-14 — today used to be a blue NUMBER, which was also the
  picker/field accent, so "today" and "the value you picked" spoke the same
  language). The ring is `onSurface`, so it survives both themes where a
  literal white vanishes on the light one; selection wins, since a filled
  circle under a ring is noise. Three widgets render a day token —
  `CalendarDayCell`, the week strip and the form's `InlineMonthCalendar` — and
  the rule had a hand-written copy in each, two carrying a comment asserting
  they matched the third. They had already drifted on the gate condition.
  Sizes and the number colour stay per-cell (they legitimately differ, and only
  the grid has a dot row); pass a `fill` for a tint like the picker's
  other-end-of-the-run marker.
  **The form's date picker is `InlineMonthCalendar`, and it renders from the
  same `month_grid.dart` helpers the calendar screen uses** — so the two can
  never disagree about where a day sits or where the week starts. It resolves
  the week start through `CalendarMonthGrid.weekStartOf(context)` like every
  other widget, and hoists its long-date `DateFormat` out of the 42 cells: the
  panel rebuilds on every day tap and on any other form change while it is
  open.
  **`AppointmentDateRange.visibleMonth` overscans ±7 days** (narrowed from ±14
  on 2026-08-13). The variable-row grid trails at most 6 off-month days on each
  side, so ±7 clears the worst case by one — where ±14 was a superset of every
  grid shape including the fixed-6-row one P2 replaced, and cost a fortnight of
  documents per month view on top of the fortnight `fetchStart` already adds.
  That saving buys a coupling: the window is now sized to the row rule, so
  bringing back a fixed row count leaves the edge cells dotless.
  **`month_grid_overscan_test.dart` is that coupling made to fail loudly** — it
  walks every month across a leap cycle at all seven week starts and asserts
  the fetch window contains every rendered cell. Change the row rule and it
  breaks there rather than in somebody's empty crew dots.
  **A single-day window has ONE owner: `AppointmentDateRange.forDay(day)`.**
  It is **calendar** arithmetic (`DateTime(y, m, d + 1)`), never
  `add(Duration(days: 1))`, which lands an hour off real midnight on the two
  DST-shift days. Two costs, not one: it mis-buckets a late-evening job, AND
  because `appointmentsInRangeProvider` is keyed by range **value**, an hour of
  drift stops matching the day-range another surface already holds open and
  forks a second live Firestore query for the same day. That is why
  `todayRangeProvider`, the drawer's job count, the day route and
  `forCalendar`'s selected-day leg all resolve through the one factory rather
  than re-deriving the pair — it was hand-copied at four sites, two of which
  cited each other as the authority.
  **Portrait is TWO scroll areas** (owner call, 2026-07-31): the grid is FIXED
  above the agenda, and the jobs have their own `CustomScrollView`, so reading
  down the day never moves the calendar. Collapse is a **drag on the divider
  between them** — `_CollapseHandle`, which is also a tap-toggle and carries the
  Hide/Show calendar tooltip that the widget tests find it by.
  `CalendarCollapse` (`domain/collapse_state.dart`) accumulates drag deltas past
  **24px**, resetting on a direction reversal and on `endDrag` so two half-drags
  don't add up. Only `onDragDelta` returns a bool (it means "the flag flipped",
  so the caller rebuilds on a transition and not per gesture frame); `toggle()`
  is `void` — it always flips, so a bool there would be a constant nobody reads.
  The agenda's own `ScrollController` is load-bearing for a second reason: an
  explicitly-controlled scrollable is not the *primary* one, which is what keeps
  it and the grid off the app-wide `Scrollbar`'s single controller. The old
  shared-viewport version needed a derived
  `gridHeight − stripHeight` spacer to hold the extent the grid vacated; with two
  viewports there is no vacated extent, and the spacer is gone. **The grid does
  not scroll at all** (owner call, 2026-07-31): it sits in a `Flexible` +
  `SingleChildScrollView` whose physics are `NeverScrollableScrollPhysics`, so
  the viewport is pure overflow protection — a short viewport (small phone,
  large text scale) shrinks the grid instead of running the column past the
  bottom, and at normal heights it shrink-wraps and is inert. The handle is the
  ONLY thing that moves the grid; don't restore scrollable physics to "fix" a
  clipped month.
  **Collapse is portrait-only** — `_splitCalendar` short-circuits the strip.
  **Paging selects.** A month swipe (or the month picker) lands on the 1st and
  SELECTS it, and a swipe on the collapsed week strip pages one week and selects
  that week's first day — the agenda must always describe the grid above it.
  That is also why the fetch window is `AppointmentDateRange.forCalendar`
  (month grid ∪ selected day) rather than the month alone: any path that leaves
  a selection outside the visible month drops its jobs from the fetch, and the
  agenda then reports "0 jobs" for a day that has some.
  The calendar is the **one screen with no `AppTopBar`** (see the frontend rule):
  `CalendarHeaderBlock` replaces it, and therefore must set the system overlay
  style itself via `AnnotatedRegion`, choosing icon brightness from the surface
  colour rather than the theme brightness. Its title and controls **stack under
  `context.isCompact`**. The month name itself is **measured, not gated**: the
  screen passes both `monthLabel` and `monthLabelShort` (`DateFormat.MMMM` /
  `.MMM`) and `_MonthRow` lays out the row, subtracts the year + chevron, and
  takes the abbreviation when the full name won't fit. Don't "simplify" that
  back to a text-scale threshold — the in-app XL setting is **exactly 1.4**, so
  the `isCompact` gate (`> 1.4`) missed it entirely, and the OS scaler, the
  device width and the locale's month lengths all move independently. The
  semantics label always speaks the full month. Note the widget test asserts
  against **viewport width**, not a scale: the test font is far wider per glyph
  than the shipped one.
- **The calendar agenda sinks CLOSED jobs to the bottom of the day, and only
  the calendar does** (2026-08-08). `_agendaOrder` in `appointment_day_slice.dart`
  gained a first tier — open before closed — above the existing all-day and
  window-start tiers, which still apply *within* the closed block. It reads the
  STORED status through **`AppointmentRecord.isClosed`**, never `displayStatus`,
  so the comparator stays clock-free like the rest of that module; `isClosed` is
  the model-layer mirror of `AppointmentStatus.isTerminal` and exists precisely
  so a pure module can ask without pulling Material in through `status_chip.dart`
  (it is also the one owner of the `done`/`completed`/`cancelled` triple —
  `displayStatusAt` calls it rather than re-spelling it). Both terminal states
  sink: a cancelled visit is as done with as a completed one.
  A closed job then renders in the **collapsed** treatment —
  `AppointmentCard(collapseWhenClosed: true)`, opt-in and passed ONLY by
  `AgendaSliverList`: the success tint for `done`, a one-line body putting the
  time beside the client, and no avatar stack (the crew bar still carries
  colour, so *who* survives the collapse). **`_kClosedMinHeight` (48) is
  load-bearing, not belt-and-braces** — the collapsed row lands near 56px, close
  enough that a small text scale drops it under Material's minimum, and the row
  is still a full `InkWell` opening the same sheet. The **multi-day counter
  stays** on a collapsed row (deviating from the approved mockup, deliberately):
  a closed job renders on every day of its run, so without "Day 3 of 5" those
  rows are indistinguishable. `AgendaSliverList` emits one `_ClosedRule`
  (`calendar_closedCount`, which reads **"Done"** — owner call 2026-08-08,
  reversing the earlier "Closed"; a cancelled visit sinks into the same block
  and is counted by it, so the label is deliberately looser than the set) at
  `_firstClosedIndex`, and its `length - index` count is only valid because the
  sort guarantees the closed jobs are one contiguous tail — don't reorder them
  at the call site. **The agenda header's count answers the same question and
  must use the same predicate**: `_jobLabel` (`main_calendar_screen.dart`)
  appends `· 1 DONE` to `3 JOBS` by counting `isClosed`, not `done` alone, so
  the header and the rule drawn over that block can never disagree about how
  much of the day is behind them. Everywhere else (day route, dashboard, employee TODAY panel,
  client job history) keeps its own sort and the plain full-height card.
- **`AppointmentCard` is the ONE appointment card** — calendar agenda, day
  route, client job history, both dashboard sections and the paginated history
  list (`AppointmentTile` is deleted, along with `colorFromMap` and
  `resolveAssigneeNames`). It takes `crew: List<AppointmentCrew>` from
  `crewFor(appointment, colorMap:, nameMap:)`; without a `nameMap` that falls
  back to the record's denormalized `employeeNames`, which is what the history
  and client surfaces already showed. **The crew bar bands EVERY assignee**
  (`_crewBarDecoration`, up to `_kMaxCrewShown` = 4 — the SAME cap the avatar
  stack uses, deliberately, so the bands and the faces never disagree on how
  much of the crew the card shows): a flat colour for one,
  a hard-stopped `LinearGradient` of each crew colour for more (owner call,
  2026-07-31 — it followed the first assignee alone before that, and the
  pre-redesign grey-for-multi-crew is doubly wrong: grey reads as
  *unassigned*). Only a job with no crew at all is `textFaint`. The meta line
  is an **overlapped avatar stack — one avatar per assignee — followed by the
  client name** (owner call, 2026-07-31; it was a single avatar plus the text
  `Theo +1 · Client`, and `calendar_crewAndClient` is deleted). `_CrewAvatars`
  computes its own width rather than laying out, because of the
  `IntrinsicHeight` rule below; `_crewLabel`/`calendar_crewPlusOthers` survive
  only as the fallback text for a record with no client name to show. `alwaysShowChip` is **gone**, not ported
  (every call site passed `true`); cancelled dims to **0.6**, not 0.75. The card
  uses `IntrinsicHeight` to stretch the crew bar, so **nothing in its subtree may
  use `LayoutBuilder`, `AutoSizeText` or `FittedBox`** — they cannot report
  intrinsics.
