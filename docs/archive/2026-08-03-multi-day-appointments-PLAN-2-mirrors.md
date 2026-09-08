# Multi-day Appointments — Implementation Plan 2: the off-screen mirrors

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the home-screen widget, the Siri snapshot and the push/digest text
understand a multi-day job, so days 2+ of a run stop being invisible outside the app.

**Architecture:** Plan 1 established `AppointmentDaySlice` as the single owner of
day-scoping in Dart. This plan extends that to the three surfaces that serialize
appointments off-screen, and adds ONE hand-mirrored JS copy of the slice rule
(`functions/day_slice_utils.js`) because Cloud Functions cannot import Dart.

**Tech Stack:** Dart/Flutter, Node 20 Cloud Functions (jest), Swift (WidgetKit + App Intents).

> **BUILT 2026-08-10.** All nine tasks are done and committed on `redesgin`
> (1803 flutter / 874 jest, `flutter analyze` clean, `npm run lint` clean).
> Four deliberate deviations, each recorded in its commit: the JS mirror
> re-exports `MAX_APPOINTMENT_SPAN_DAYS` from `time_utils.js` instead of
> restating it; it rebuilds a window as a wall-clock time rather than
> midnight-plus-elapsed-minutes (the plan's formula is an hour off on the two
> DST shift days); it treats a record with no `endTime` as a single-day job
> rather than dropping it; and Task 1's list comprehension uses the null-aware
> element `?sliceFor(...)` because the analyzer rejects the plan's `if-case`
> form. **Tasks 4 and 6 (Swift) remain Xcode- and device-unverified** — there
> is no harness for either extension.
>
> **Reconciled against the code 2026-08-10 — still valid, three steps corrected.**
> Nothing in this plan has been built (there is no `functions/day_slice_utils.js`,
> and neither `widget_sync_service.dart` nor `widget_payload_utils.js` knows about
> day slicing; the Siri snapshot is still v2). What moved underneath it:
> **Task 1 Step 5** described a fetch range that no longer exists and is rewritten
> to "confirm, don't touch"; **Task 2** must now mirror the 14-day clamp the Dart
> side grew on 2026-08-08; **Task 3 Step 5** is confirmed still necessary, with the
> caller named. **Task 7 (push/digest text) is still open** — `contextFor` in
> `notification_policy.js` carries no `endTime` and `_when` renders the start
> alone, so an assignment push for a five-day run still names only the first
> morning. (`CLAUDE.md` says `notification_messages.js` was "closed by the
> 2026-08-04 audit"; that refers to the `isAllDay` and personal-job `_who` fixes,
> not to this.) Tasks 4–6 are unaffected: the snapshot already carries `isAllDay`
> and `title` at v2, so the v3 bump this plan specifies is still the right move.

**Prerequisite:** Plan 1 complete (`e0518c9`).
**Design doc:** `docs/plans/2026-08-02-multi-day-appointments.md` §8.
**Plan 1:** `docs/plans/2026-08-02-multi-day-appointments-PLAN-1-app.md`.

---

## What does NOT need changing (verified, not assumed)

Read this before starting — three surfaces the design doc listed turn out to be
correct already, and "fixing" them would be a regression.

- **`selectTravelCandidates` (`functions/travel_utils.js`) — NO CHANGE.** It
  requires `ms > nowMs && ms <= cutoff` against the record's `startTime`, which
  for a multi-day job is day 1 only. So the "time to leave" push already fires
  exactly once, on the first morning — which is the approved design (days 2+
  have no separate departure time and the crew is already on site). Do not add
  per-day travel reminders.
- **`selectOverdueCandidates` (`functions/notification_policy.js`) — NO CHANGE.**
  It gates on `endTime` having passed, which for a multi-day job is the end of
  the whole run. A job is correctly not nagged on day 2 of 5.
- **Live Activities — DEFERRED, not in this plan.** A card counting down to an
  end four days out would sit on the Lock Screen for the entire job. Recorded as
  an open item in the design doc §10; do not attempt it here.

---

## The hand-mirroring problem (read before Task 2)

`expandToDays`/`sliceFor` live in Dart. Cloud Functions can't import them, so
Task 2 creates a JS copy. This repo has been bitten twice by hand-copied rules
drifting (`displayStatusAt`, `_who`). Mitigations required by this plan:

1. The JS module carries a pointer to the Dart original and vice versa.
2. The JS tests use **the same worked examples** as the Dart tests (Aug 1–5
   day job; Aug 1 22:00 → Aug 4 06:00 night shift = 3 nights ending Aug 3), so a
   divergence fails a test rather than shipping.
3. `maxAppointmentSpanDays` is restated in JS with a comment naming the Dart
   constant as the source of truth.

---

## File Structure

**Create**
- `functions/day_slice_utils.js` — JS mirror of the slice rule.
- `functions/__tests__/day_slice_utils.test.js`

**Modify**
- `lib/features/home_widget/application/widget_sync_service.dart` — day-scoped `_job` + `buildWidgetPayload`.
- `functions/widget_payload_utils.js` — same, server side.
- `ios/ScheduleWidget/ScheduleWidget.swift` — `Job.dayIndex`/`dayCount`, `timeLabel`.
- `lib/features/siri/domain/schedule_snapshot.dart` — schema v3.
- `ios/SiriIntents/ScheduleSnapshot.swift` — `supportedVersion = 3`, decode the new fields.
- `ios/SiriIntents/SiriStrings.swift` (or wherever `timePhrase` lives) — speak the counter.
- `functions/notification_policy.js` — `contextFor` carries the span.
- `functions/notification_messages.js` — the date line renders a range.
- `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb` — none expected; confirm.
- `CLAUDE.md` — remove the "NOT YET MIRRORED" debt paragraph.
- `docs/plans/2026-08-02-multi-day-appointments.md` — mark §8 done.

---

### Task 1: The widget payload speaks days (Dart)

**Files:**
- Modify: `lib/features/home_widget/application/widget_sync_service.dart`
- Test: `test/features/home_widget/widget_sync_service_test.dart` (find the real path with `grep -rln "buildWidgetPayload" test/`)

**The bug being fixed.** `inRange` tests `a.startTime` against the day bounds, so
a job that started yesterday and runs through today is absent from `todayJobs`
entirely. `widgetPayloadProvider`'s range also starts at `today`, so such a
record isn't even fetched.

- [ ] **Step 1: Write the failing test**

```dart
  test('a job that started yesterday and runs through today is listed today', () {
    final running = _record(
      id: 'multi',
      start: DateTime(2026, 8, 1, 9),
      end: DateTime(2026, 8, 5, 17),
    );
    final payload = buildWidgetPayload([running], DateTime(2026, 8, 3, 7));
    final today = payload['todayJobs'] as List;
    expect(today, hasLength(1));
    final job = today.single as Map<String, dynamic>;
    expect(job['dayIndex'], 3);
    expect(job['dayCount'], 5);
    // The clock the widget shows must be TODAY's window, not Aug 1's.
    expect(job['startTime'], DateTime(2026, 8, 3, 9).toUtc().toIso8601String());
  });

  test('a night shift is listed on the evening it starts, not the morning after', () {
    final night = _record(
      id: 'night',
      start: DateTime(2026, 8, 1, 22),
      end: DateTime(2026, 8, 4, 6),
    );
    // Aug 3 is the last night the crew starts.
    final onLastNight = buildWidgetPayload([night], DateTime(2026, 8, 3, 7));
    expect((onLastNight['todayJobs'] as List), hasLength(1));
    // Aug 4 is only the morning it ends — nobody starts work.
    final morningAfter = buildWidgetPayload([night], DateTime(2026, 8, 4, 7));
    expect((morningAfter['todayJobs'] as List), isEmpty);
  });

  test('a single-day job carries no day counter', () {
    final one = _record(
      id: 'one',
      start: DateTime(2026, 8, 3, 8, 30),
      end: DateTime(2026, 8, 3, 10),
    );
    final payload = buildWidgetPayload([one], DateTime(2026, 8, 3, 7));
    final job = (payload['todayJobs'] as List).single as Map<String, dynamic>;
    expect(job['dayIndex'], isNull);
    expect(job['dayCount'], isNull);
  });
```

Adapt `_record` to the file's existing fixture helper. Use `DateTime(2026, 8)`
for Aug 1 — a bare `1` day argument trips `avoid_redundant_argument_values`.

- [ ] **Step 2: Run it, verify it fails**

`flutter test test/features/home_widget/widget_sync_service_test.dart` →
the multi-day job is absent from `todayJobs`.

- [ ] **Step 3: Rewrite `_job` to take a slice**

```dart
/// One job as the widget renders it, scoped to the day it appears on.
///
/// [slice] carries that day's window and position in the run — the widget must
/// show TODAY's clock, not the run's first morning. `dayIndex`/`dayCount` are
/// omitted for a single-day job so a pre-multi-day Swift decoder still parses
/// (it reads them as `Int?`) and so the widget shows no counter.
Map<String, dynamic> _job(AppointmentDaySlice slice) {
  final a = slice.appointment;
  return {
    'id': a.id ?? '',
    // Emit an absolute UTC instant with the Z suffix — a bare toIso8601String()
    // omits the zone designator the widget's formatter needs.
    'startTime': slice.windowStart.toUtc().toIso8601String(),
    'clientName': a.clientName,
    'title': a.title,
    'address': a.address,
    'status': a.status,
    'isAllDay': a.isAllDay,
    if (slice.isMultiDay) 'dayIndex': slice.dayIndex,
    if (slice.isMultiDay) 'dayCount': slice.dayCount,
  };
}
```

- [ ] **Step 4: Rewrite the bucketing in `buildWidgetPayload`**

Replace the `inRange` helper and the two `.where(...)` buckets with slice-based
ones. `sliceFor` returns null when the record doesn't run that day, which is
exactly the membership test:

```dart
  // A job is "on" a day when it WORKS that day — not when its stored startTime
  // happens to fall in it. Without this a run that began yesterday is invisible
  // today, which is the whole point of multi-day support.
  List<AppointmentDaySlice> slicesOn(DateTime day) => [
    for (final a in appointments)
      if (sliceFor(a, day) case final slice?) slice,
  ];

  final todayAll = slicesOn(startOfToday);
  final todayIncomplete = todayAll
      .where((s) => !statusOf(s.appointment).isTerminal)
      .toList();

  // "Still ahead of you today", judged against THIS day's window. An all-day
  // block starts at midnight, so a start test would drop it the moment the day
  // began — it stays listed until its 23:59 end passes.
  bool stillAhead(AppointmentDaySlice s) => s.appointment.isAllDay
      ? s.windowEnd.isAfter(now)
      : s.windowStart.isAfter(now);

  final todayJobs = todayIncomplete.where(stillAhead).toList()
    ..sort((x, y) => x.windowStart.compareTo(y.windowStart));

  final tomorrowJobs =
      slicesOn(startOfTomorrow)
          .where((s) => !statusOf(s.appointment).isTerminal)
          .toList()
        ..sort((x, y) => x.windowStart.compareTo(y.windowStart));
```

`startOfDayAfter` becomes unused — delete it.

Update `rolloverAt`'s computation to read `s.windowEnd` rather than
`a.endTime`, so a multi-day run rolls the widget over at the end of TODAY's
window, not at the end of the whole run:

```dart
    rolloverAt = finished.isEmpty
        ? startOfToday
        : finished
              .map((s) => s.windowEnd)
              .reduce((a, b) => a.isAfter(b) ? a : b)
              .add(widgetRolloverGrace);
```

and the two `_job(a)` call sites become `_job(s)`.

Import `package:scheduling/features/calendar/domain/appointment_day_slice.dart`.

- [ ] **Step 5: Confirm the fetch range — do NOT change it**

> **Rewritten 2026-08-10.** This step described a range that no longer exists.
> `widgetPayloadProvider` no longer builds `today → today + 3 days`; since
> 2026-08-08 both off-screen mirrors resolve **`AppointmentDateRange.forMirrors(today)`**
> (`mirrorLookaheadDays` = 7, +1), and `scheduleSnapshotLookaheadDays` is defined
> as that same constant.

The range is already correct for this plan and **must not be touched**. Two
reasons, both load-bearing:

- It already reaches back. `AppointmentDateRange.fetchStart` widens the query
  14 days behind `start`, and Plan 1 changed `watchInRange` /
  `watchForEmployeeInRange` to use it — so a job that started 13 days ago and is
  still running today is already in the stream. Confirm that by reading
  `myAppointmentsProvider`'s repository method and say so in your report; if it
  does NOT reach `fetchStart`, report `NEEDS_CONTEXT` rather than widening here.
- **The widget and the Siri snapshot deliberately share one range.** They ask the
  same value-keyed provider family and both are held open for the whole session by
  `AppSyncListeners`, so two different windows means two permanent Firestore
  listeners per signed-in employee — one a strict subset of the other. That was
  fixed on 2026-08-08. Narrowing or widening one mirror's range on its own
  re-forks it.

`buildWidgetPayload` re-scopes to today/tomorrow in Dart regardless, so the wider
list feeds it unchanged.

- [ ] **Step 6: Verify**

- `flutter test` → all pass; report the count (Plan 1 ended at 1503)
- `flutter analyze` → **`No issues found!`**

- [ ] **Step 7: Commit**

```bash
git add lib/features/home_widget/ test/features/home_widget/
git commit -m "feat(widget): day-scope the payload so a running job shows every day"
```
Trailers:
```
Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KwcVuAQWUwYRgoF5djQw18
```

---

### Task 2: The JS slice mirror

**Files:**
- Create: `functions/day_slice_utils.js`, `functions/__tests__/day_slice_utils.test.js`

This is the hand-mirrored copy of Plan 1's `appointment_day_slice.dart`. Keep it
dependency-free apart from `time_utils.js` so jest can load it directly.

> **Added 2026-08-10 — the Dart side grew a clamp after this plan was written.**
> Every day-scoping answer in `appointment_day_slice.dart` now routes through
> **`_clampedDayCount`** (`min(end − start + 1, maxAppointmentSpanDays)`):
> `sliceFor`/`runsOn`, `runsInRange`, `expandToDays` and `dailyWindowsOverlap`.
> `firestore.rules` gained a matching bound on 2026-08-11, but it reaches
> **client writes only** — the console and the Admin SDK bypass rules, so a doc
> CAN still exceed it, and when the owners disagreed the calendar rendered 14
> slices while every
> `runsOn` consumer counted the full corrupt length (a drawer badge reading
> "1 job today" every day for a year; a card counter reading "Day 400 of 900").
> **`dayCountOf` in the JS mirror must clamp the same way**, and the worked
> examples should gain a case for an over-long window so a drift fails a test.
> Note the one deliberate Dart exception — `AppointmentFormValidator` reads the
> RAW count, because it is the caller that has to see an out-of-range value in
> order to refuse it. Nothing in the JS mirror has that job, so the JS side
> clamps everywhere.
>
> Do **not** mirror `_agendaOrder`. `expandToDays` also sorts open-before-closed
> now, but that is the calendar agenda's rule, not a day-scoping rule — the
> widget and the snapshot have their own ordering.

- [ ] **Step 1: Write the failing test**

`functions/__tests__/day_slice_utils.test.js`:

```javascript
"use strict";

const {
  MAX_APPOINTMENT_SPAN_DAYS,
  sliceForDay,
  dayCountOf,
  lastWorkDayMs,
} = require("../day_slice_utils");

const ms = (y, m, d, h = 0, min = 0) => new Date(y, m - 1, d, h, min).getTime();

describe("day_slice_utils", () => {
  test("the cap matches the Dart constant", () => {
    expect(MAX_APPOINTMENT_SPAN_DAYS).toBe(14);
  });

  test("a single-day job is day 1 of 1", () => {
    const r = {startTime: ms(2026, 8, 1, 9), endTime: ms(2026, 8, 1, 17)};
    expect(dayCountOf(r)).toBe(1);
    const s = sliceForDay(r, ms(2026, 8, 1));
    expect(s.dayIndex).toBe(1);
    expect(s.dayCount).toBe(1);
  });

  test("a 5-day job reports the same daily window on every day", () => {
    const r = {startTime: ms(2026, 8, 1, 9), endTime: ms(2026, 8, 5, 17)};
    const s = sliceForDay(r, ms(2026, 8, 3));
    expect(s.dayIndex).toBe(3);
    expect(s.dayCount).toBe(5);
    expect(s.windowStartMs).toBe(ms(2026, 8, 3, 9));
    expect(s.windowEndMs).toBe(ms(2026, 8, 3, 17));
  });

  test("a day outside the run has no slice", () => {
    const r = {startTime: ms(2026, 8, 1, 9), endTime: ms(2026, 8, 5, 17)};
    expect(sliceForDay(r, ms(2026, 7, 31))).toBeNull();
    expect(sliceForDay(r, ms(2026, 8, 6))).toBeNull();
  });

  test("a night shift counts nights and ends the next morning", () => {
    const r = {startTime: ms(2026, 8, 1, 22), endTime: ms(2026, 8, 4, 6)};
    expect(dayCountOf(r)).toBe(3);
    expect(lastWorkDayMs(r)).toBe(ms(2026, 8, 3));
    const s = sliceForDay(r, ms(2026, 8, 2));
    expect(s.dayIndex).toBe(2);
    expect(s.isOvernight).toBe(true);
    expect(s.windowStartMs).toBe(ms(2026, 8, 2, 22));
    expect(s.windowEndMs).toBe(ms(2026, 8, 3, 6));
  });

  test("a night shift has no slice on the morning it finishes", () => {
    const r = {startTime: ms(2026, 8, 1, 22), endTime: ms(2026, 8, 4, 6)};
    expect(sliceForDay(r, ms(2026, 8, 4))).toBeNull();
  });

  test("an all-day run is not overnight", () => {
    const r = {startTime: ms(2026, 8, 10), endTime: ms(2026, 8, 14, 23, 59)};
    expect(sliceForDay(r, ms(2026, 8, 12)).isOvernight).toBe(false);
    expect(dayCountOf(r)).toBe(5);
  });
});
```

These are deliberately the SAME worked examples as
`test/features/calendar/domain/appointment_day_slice_test.dart`. If the two
implementations ever diverge, one of these fails.

- [ ] **Step 2: Run it, verify it fails**

`cd functions && npx jest __tests__/day_slice_utils.test.js` → module not found.

- [ ] **Step 3: Implement**

`functions/day_slice_utils.js`:

```javascript
"use strict";

/**
 * @fileoverview Server-side mirror of the Dart day-slice rule
 * (`lib/features/calendar/domain/appointment_day_slice.dart`). An appointment's
 * two stored times describe a DAILY WINDOW — 9:00–17:00 means 9-to-5 on each
 * day of the run, not one unbroken stretch through the nights.
 *
 * Keep this and the Dart original in lockstep: the jest cases here use the same
 * worked examples as the Dart tests, so a divergence fails rather than ships.
 *
 * Day boundaries use `America/Toronto` (`BUSINESS_TIME_ZONE`) like every other
 * server-side day computation, so this and `widget_payload_utils` agree.
 *
 * @module day_slice_utils
 */

const {toMillis, businessYmd, businessMidnight} = require("./time_utils");

/**
 * Longest span a job may be booked for. Mirrors `maxAppointmentSpanDays` in
 * `lib/features/calendar/domain/appointment_day_slice.dart`, which is the
 * source of truth — change both together.
 * @const {number}
 */
const MAX_APPOINTMENT_SPAN_DAYS = 14;

/**
 * Toronto midnight of the day containing `ms`, as epoch ms.
 * @param {number} msValue
 * @return {number}
 */
function dayStartMs(msValue) {
  const [y, m, d] = businessYmd(new Date(msValue));
  return businessMidnight(y, m, d).getTime();
}

/**
 * Toronto midnight `n` days from the day containing `ms`.
 * @param {number} msValue
 * @param {number} n
 * @return {number}
 */
function addDaysMs(msValue, n) {
  const [y, m, d] = businessYmd(new Date(msValue));
  return businessMidnight(y, m, d + n).getTime();
}

/**
 * Whole calendar days between two instants' Toronto days.
 * @param {number} fromMs
 * @param {number} toMs
 * @return {number}
 */
function calendarDaysBetween(fromMs, toMs) {
  const [fy, fm, fd] = businessYmd(new Date(fromMs));
  const [ty, tm, td] = businessYmd(new Date(toMs));
  return Math.round(
      (Date.UTC(ty, tm - 1, td) - Date.UTC(fy, fm - 1, fd)) / 86400000);
}

/**
 * Minutes past Toronto midnight for an instant.
 * @param {number} msValue
 * @return {number}
 */
function minutesOfDay(msValue) {
  return Math.round((msValue - dayStartMs(msValue)) / 60000);
}

/**
 * True when the record's daily window crosses midnight.
 *
 * Equal times count as overnight: a booking at the same clock time on
 * consecutive days is a run of continuous 24-hour windows, and a strict `<`
 * would collapse each of them to zero length.
 * @param {!Object} r
 * @return {boolean}
 */
function isOvernightRecord(r) {
  const s = toMillis(r.startTime);
  const e = toMillis(r.endTime);
  if (s == null || e == null) return false;
  return minutesOfDay(e) <= minutesOfDay(s);
}

/**
 * Toronto midnight of the last day the crew STARTS work — never the morning an
 * overnight run finishes.
 * @param {!Object} r
 * @return {?number}
 */
function lastWorkDayMs(r) {
  const e = toMillis(r.endTime);
  if (e == null) return null;
  return isOvernightRecord(r) ? addDaysMs(e, -1) : dayStartMs(e);
}

/**
 * How many days (or nights) the record runs. Can come back below 1 on a corrupt
 * record whose end precedes its start — callers must guard.
 * @param {!Object} r
 * @return {number}
 */
function dayCountOf(r) {
  const s = toMillis(r.startTime);
  const last = lastWorkDayMs(r);
  if (s == null || last == null) return 0;
  return calendarDaysBetween(s, last) + 1;
}

/**
 * The record as it appears on the Toronto day containing `dayMs`, or null when
 * it doesn't run that day.
 *
 * Slices are generated per WORK day — each day the window BEGINS — not per
 * calendar day the stored span touches. That is what keeps a night shift off
 * the morning it ends.
 * @param {!Object} r
 * @param {number} dayMs
 * @return {?{dayIndex: number, dayCount: number, windowStartMs: number,
 *   windowEndMs: number, isOvernight: boolean, isMultiDay: boolean,
 *   record: !Object}}
 */
function sliceForDay(r, dayMs) {
  const startMs = toMillis(r.startTime);
  const endMs = toMillis(r.endTime);
  if (startMs == null || endMs == null) return null;
  const rawCount = dayCountOf(r);
  if (rawCount < 1) return null;
  const count = Math.min(rawCount, MAX_APPOINTMENT_SPAN_DAYS);
  const index = calendarDaysBetween(startMs, dayMs) + 1;
  if (index < 1 || index > count) return null;

  const overnight = isOvernightRecord(r);
  const base = dayStartMs(dayMs);
  const windowStartMs = base + minutesOfDay(startMs) * 60000;
  const windowEndMs =
      (overnight ? addDaysMs(base, 1) : base) + minutesOfDay(endMs) * 60000;
  return {
    record: r,
    dayIndex: index,
    dayCount: count,
    windowStartMs,
    windowEndMs,
    isOvernight: overnight,
    isMultiDay: count > 1,
  };
}

module.exports = {
  MAX_APPOINTMENT_SPAN_DAYS,
  calendarDaysBetween,
  isOvernightRecord,
  lastWorkDayMs,
  dayCountOf,
  sliceForDay,
};
```

**Note on DST:** `windowStartMs` is computed from Toronto midnight plus a
minute offset, so on the two shift days a 09:00 window lands at 09:00 wall
clock. That is the intent — the crew works 9-to-5 by the clock, not by elapsed
hours. Do not "fix" this to a fixed-duration offset.

- [ ] **Step 4: Verify**

`cd functions && npx jest __tests__/day_slice_utils.test.js` → 7 pass.
`cd functions && npm run lint` → clean (Google ESLint, **80-char limit**).

- [ ] **Step 5: Commit**

```bash
git add functions/day_slice_utils.js functions/__tests__/day_slice_utils.test.js
git commit -m "feat(functions): mirror the Dart day-slice rule for server payloads"
```
(same trailers)

---

### Task 3: The server widget payload speaks days

**Files:**
- Modify: `functions/widget_payload_utils.js`
- Test: `functions/__tests__/widget_payload_utils.test.js`

- [ ] **Step 1: Write the failing test**

Add cases mirroring Task 1's Dart tests exactly: a job started Aug 1 09:00 →
Aug 5 17:00 appears in `todayJobs` for a `now` on Aug 3 with `dayIndex: 3`,
`dayCount: 5` and a `startTime` of Aug 3 09:00 Toronto; a night shift Aug 1
22:00 → Aug 4 06:00 appears on Aug 3 and NOT on Aug 4; a single-day job carries
no `dayIndex`/`dayCount`.

Use the file's existing fixture/`now` helpers — it already constructs Toronto
instants, so follow that rather than inventing a second convention.

- [ ] **Step 2: Run it, verify it fails**

`cd functions && npx jest __tests__/widget_payload_utils.test.js`

- [ ] **Step 3: Rewrite `serializeWidgetJob` to take a slice**

```javascript
/**
 * Serializes one day-slice into the widget's job JSON, mirroring `_job` in
 * widget_sync_service.dart. `startTime` is THIS day's window start (not the
 * run's first morning) as an absolute UTC instant with milliseconds so Swift's
 * ISO8601DateFormatter can parse it, and every other field must be a plain
 * non-null string or the Swift decode fails. `dayIndex`/`dayCount` are omitted
 * for a single-day job — Swift reads them as `Int?`, so a payload without them
 * still decodes.
 * @param {!Object} slice A slice from `day_slice_utils.sliceForDay`.
 * @return {!Object}
 */
function serializeWidgetJob(slice) {
  const r = slice.record;
  const job = {
    id: String(r.id == null ? "" : r.id),
    startTime: new Date(slice.windowStartMs).toISOString(),
    clientName: String(r.clientName == null ? "" : r.clientName),
    title: String(r.title == null ? "" : r.title),
    address: String(r.address == null ? "" : r.address),
    status: String(r.status == null ? "pending" : r.status),
    isAllDay: r.isAllDay === true,
  };
  if (slice.isMultiDay) {
    job.dayIndex = slice.dayIndex;
    job.dayCount = slice.dayCount;
  }
  return job;
}
```

- [ ] **Step 4: Rewrite the bucketing in `buildWidgetPayload`**

Replace `inRange` with slice membership, mirroring Task 1:

```javascript
  const slicesOn = (dayMs) => (records || [])
      .map((r) => sliceForDay(r, dayMs))
      .filter((s) => s != null);
  const sortByWindow = (a, b) => a.windowStartMs - b.windowStartMs;

  const todayAll = slicesOn(startTodayMs);
  const todayIncomplete =
      todayAll.filter((s) => !isTerminalStatus(s.record.status));
  // "Still ahead of you today", judged against THIS day's window.
  const stillAhead = (s) => s.record.isAllDay === true ?
      s.windowEndMs > nowMs : s.windowStartMs > nowMs;
  const todayJobs = todayIncomplete.filter(stillAhead).sort(sortByWindow);
  const tomorrowJobs = slicesOn(startTomorrowMs)
      .filter((s) => !isTerminalStatus(s.record.status))
      .sort(sortByWindow);
```

`startDayAfterMs` becomes unused — delete it and its `torontoDayStartOffsetMs`
call.

In the `rolloverAt` block, `finished` is now a slice array — read
`s.windowEndMs` instead of `toMillis(r.endTime)`, and `isCancelledStatus(s.record.status)`.

Import at the top: `const {sliceForDay} = require("./day_slice_utils");`

- [ ] **Step 5: Widen the server's lookahead**

`WIDGET_LOOKAHEAD_DAYS` is 3 and describes a forward window. The caller's query
must also reach BACK far enough to see a still-running job. Find the caller
(`grep -rn "WIDGET_LOOKAHEAD_DAYS" functions/`) and widen its lower bound by
`MAX_APPOINTMENT_SPAN_DAYS`. **Read the query first** and report what you found
— if the caller already reads a wide window, say so rather than widening twice.

> **Verified 2026-08-10 — this step is still needed, and here is the answer to
> the grep.** The caller is `notification_utils.js:~193`, which builds
> `[businessMidnight(now), +WIDGET_LOOKAHEAD_DAYS days)` and filters on
> `startTime`. Its floor is today 00:00 Toronto, so a job that started
> yesterday and runs through today is **invisible to the push-written payload**
> — which is the whole bug this task exists to fix. Widen the FLOOR by
> `MAX_APPOINTMENT_SPAN_MS` (`time_utils.js`, added 2026-08-04, hand-mirroring
> the Dart `maxAppointmentSpanDays`); leave the 3-day ceiling alone. The Dart
> mirror needs no equivalent change — `fetchStart` already does this.
>
> Note also the comment on `WIDGET_LOOKAHEAD_DAYS` ("matches the Dart widget
> range: [today 00:00, today + 3 days)") went stale on 2026-08-08 when the Dart
> mirrors moved to `AppointmentDateRange.forMirrors` (8 days). The two windows
> are allowed to differ — both builders re-scope to today/tomorrow — but fix the
> comment while you are in the file.

- [ ] **Step 6: Verify**

`cd functions && npx jest` → all pass; report the count.
`cd functions && npm run lint` → clean.

- [ ] **Step 7: Commit**

```bash
git add functions/widget_payload_utils.js functions/__tests__/widget_payload_utils.test.js
git commit -m "feat(functions): day-scope the server widget payload"
```

---

### Task 4: The Swift widget renders the counter

**Files:**
- Modify: `ios/ScheduleWidget/ScheduleWidget.swift`

**No test harness exists for the widget extension** — this is device/Xcode-verified.
Keep the change small and obviously correct.

- [ ] **Step 1: Extend `Job`**

After `let isAllDay: Bool?` (line ~45):

```swift
    // Optional so a payload written before multi-day support still decodes —
    // a missing key would fail the whole `Job`. Absent means a single-day job.
    let dayIndex: Int?
    let dayCount: Int?

    /// True when this job runs across more than one day, so the row names
    /// which day of the run it is showing.
    var isMultiDay: Bool { (dayCount ?? 1) > 1 }
```

- [ ] **Step 2: Extend `timeLabel`**

```swift
private func timeLabel(_ job: Job, french: Bool) -> String {
    let base: String
    if job.allDay {
        base = french ? "Toute la journée" : "All day"
    } else if let start = job.start {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: french ? "fr_CA" : "en_CA")
        fmt.dateFormat = french ? "H 'h' mm" : "h:mm a"
        base = fmt.string(from: start)
    } else {
        base = ""
    }
    guard job.isMultiDay, let i = job.dayIndex, let n = job.dayCount else {
        return base
    }
    // A run whose window crosses midnight counts nights, but the widget only
    // receives the counter — not the overnight flag — so it says "Day".
    let counter = french ? "Jour \(i) sur \(n)" : "Day \(i) of \(n)"
    return base.isEmpty ? counter : "\(base) · \(counter)"
}
```

> **Decision to confirm with the owner before shipping:** the widget says "Day"
> even for a night shift, because the payload carries no overnight flag. The
> alternative is adding `isOvernight` to the job JSON in all three builders.
> Flag this in your report; do NOT add the field unilaterally.

- [ ] **Step 3: Verify**

There is no automated check here. Confirm the file still parses by eye and
report that Xcode verification is outstanding. Do NOT claim it builds.

- [ ] **Step 4: Commit**

```bash
git add ios/ScheduleWidget/ScheduleWidget.swift
git commit -m "feat(widget): decode and render the multi-day counter"
```

---

### Task 5: Siri snapshot v3

**Files:**
- Modify: `lib/features/siri/domain/schedule_snapshot.dart`
- Test: `test/features/siri/schedule_snapshot_test.dart` (find the real path)

- [ ] **Step 1: Write the failing test**

```dart
  test('a multi-day job is bucketed on every day it runs', () {
    final snapshot = buildScheduleSnapshot(
      appointments: [
        _record(id: 'm', start: DateTime(2026, 8, 3, 9), end: DateTime(2026, 8, 5, 17)),
      ],
      role: 'employee',
      now: DateTime(2026, 8, 3, 7),
    );
    final days = snapshot['days'] as List;
    List appointmentsOn(String date) => (days.firstWhere(
          (d) => (d as Map)['date'] == date,
        ) as Map)['appointments'] as List;

    expect(appointmentsOn('2026-08-03'), hasLength(1));
    expect(appointmentsOn('2026-08-04'), hasLength(1));
    expect(appointmentsOn('2026-08-05'), hasLength(1));
    expect(appointmentsOn('2026-08-06'), isEmpty);

    final day2 = appointmentsOn('2026-08-04').single as Map<String, dynamic>;
    expect(day2['dayIndex'], 2);
    expect(day2['dayCount'], 3);
    // Siri must speak THIS day's window, not the run's first morning.
    expect(day2['startMillis'], DateTime(2026, 8, 4, 9).millisecondsSinceEpoch);
  });

  test('the schema version is bumped for the new fields', () {
    expect(scheduleSnapshotVersion, 3);
  });
```

- [ ] **Step 2: Run it, verify it fails**

- [ ] **Step 3: Implement**

```dart
/// Schema version; bump only alongside Swift `ScheduleSnapshot` decoder.
/// v2 added `title` and `isAllDay` for personal jobs. v3 adds `dayIndex` and
/// `dayCount`, and buckets a multi-day job on every day it runs rather than
/// only its first.
const scheduleSnapshotVersion = 3;
```

`_appointment` takes a slice:

```dart
Map<String, dynamic> _appointment(AppointmentDaySlice slice) {
  final a = slice.appointment;
  return {
    'id': a.id,
    // THIS day's window — a multi-day run works the same hours each day, and
    // Siri answering with the run's first morning would be wrong on day 2.
    'startMillis': slice.windowStart.millisecondsSinceEpoch,
    'endMillis': slice.windowEnd.millisecondsSinceEpoch,
    'clientName': a.clientName,
    'title': a.title,
    'address': a.address,
    'status': AppointmentStatus.storedRaw(a.status),
    'isAllDay': a.isAllDay,
    if (slice.isMultiDay) 'dayIndex': slice.dayIndex,
    if (slice.isMultiDay) 'dayCount': slice.dayCount,
    if (slice.isMultiDay) 'isOvernight': slice.isOvernight,
  };
}
```

and the bucketing loop fans across days:

```dart
  for (final a in appointments) {
    if (a.id == null || a.id!.isEmpty) continue;
    if (AppointmentStatus.fromRaw(a.status).isCancelled) continue;
    // A run is bucketed on every day it WORKS, not just the day it began.
    for (final key in buckets.keys) {
      final day = _dayFromKey(key);
      if (sliceFor(a, day) case final slice?) {
        buckets[key]!.add(slice);
      }
    }
  }
```

`buckets` becomes `Map<String, List<AppointmentDaySlice>>`, the sort key
becomes `windowStart`, and you need a `_dayFromKey` inverse of `_dayKey` — or,
cleaner, build the bucket map keyed by `DateTime` and format the key at
serialization time. **Prefer the latter**; it avoids a parse and keeps `_dayKey`
one-directional. Report which you chose.

- [ ] **Step 4: Verify**

`flutter test` → all pass; `flutter analyze` → `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/siri/ test/features/siri/
git commit -m "feat(siri): snapshot v3 buckets a run on every day and carries the counter"
```

---

### Task 6: Siri Swift decoder v3

**Files:**
- Modify: `ios/SiriIntents/ScheduleSnapshot.swift`
- Modify: whichever file owns `SiriStrings.timePhrase` (`grep -rn "timePhrase" ios/SiriIntents/`)

**No automated tests** — Xcode/device-verified.

- [ ] **Step 1: Bump and decode**

```swift
private let supportedVersion = 3
```

Add to `SnapshotAppointment`:

```swift
    // Optional so a v2 payload still decodes field-wise; the version gate above
    // is the real compatibility check. Absent means a single-day job.
    let dayIndex: Int?
    let dayCount: Int?
    let isOvernight: Bool?

    var isMultiDay: Bool { (dayCount ?? 1) > 1 }
```

> **Note the compatibility consequence and report it:** `supportedVersion` is an
> exact-match gate, so bumping it means an app that has not yet rewritten its
> snapshot leaves Siri answering "no schedule" until the next write. Confirm
> whether the snapshot is rewritten on launch — if it is, the window is one
> cold start and acceptable. If it is NOT, say so; that is a shipping decision,
> not yours to absorb.

- [ ] **Step 2: Speak the counter**

In `timePhrase` (or the equivalent), append the counter when multi-day:

```swift
        guard appointment.isMultiDay,
              let i = appointment.dayIndex,
              let n = appointment.dayCount else { return base }
        let unit = (appointment.isOvernight == true)
            ? (french ? "nuit" : "night")
            : (french ? "jour" : "day")
        let of = french ? "sur" : "of"
        return "\(base), \(unit) \(i) \(of) \(n)"
```

Match the file's existing localization idiom — if it uses a different
French/English switch, follow that rather than introducing `french:`.

- [ ] **Step 3: Commit**

```bash
git add ios/SiriIntents/
git commit -m "feat(siri): decode snapshot v3 and speak the day counter"
```

---

### Task 7: Push and digest text

**Files:**
- Modify: `functions/notification_policy.js` (`contextFor`)
- Modify: `functions/notification_messages.js` (`_when`)
- Test: `functions/__tests__/notification_utils.test.js` (or wherever `_contextFor`/message tests live)

- [ ] **Step 1: Write the failing test**

Assert that an assignment push for a job Aug 1 09:00 → Aug 5 17:00 renders a
date RANGE, not a single date, in both locales. Read the existing message tests
first and follow their shape — they already exercise `_MESSAGES` through a
public entry point.

- [ ] **Step 2: Carry the span in the context**

In `notification_policy.js`'s `contextFor`, beside the existing `isAllDay`:

```javascript
    // The run's end, so a multi-day job's message reads a date RANGE rather
    // than naming only the first morning.
    endTime: d.endTime,
```

- [ ] **Step 3: Render the range**

In `notification_messages.js`:

```javascript
/**
 * `_dateTime` for a message context — all-day and multi-day aware.
 *
 * A run spanning days reads as a range ("Wed, Aug 1 – Sun, Aug 5"), because
 * naming only the first morning tells a tech nothing about a job they are on
 * for the rest of the week.
 * @param {string} locale
 * @param {!Object} c
 * @return {string}
 */
function _when(locale, c) {
  const base = _dateTime(locale, c.startTime, c.isAllDay === true);
  const last = lastWorkDayMs(c);
  if (last == null) return base;
  const startMs = toMillis(c.startTime);
  if (startMs == null || calendarDaysBetween(startMs, last) < 1) return base;
  return `${base} – ${_dateOnly(locale, last)}`;
}
```

You will need a date-only formatter. **Check whether `notification_messages.js`
already has one** (`_dateTime` presumably composes date + time internally) and
reuse it; only add `_dateOnly` if none exists. Import `lastWorkDayMs` and
`calendarDaysBetween` from `./day_slice_utils` and `toMillis` from
`./time_utils`.

Leave `_whoAt`/`_at` alone: those speak a clock time, which is unchanged — the
daily window means the start time is the same every day.

- [ ] **Step 4: Verify**

`cd functions && npx jest` → all pass; `npm run lint` → clean.

- [ ] **Step 5: Commit**

```bash
git add functions/notification_policy.js functions/notification_messages.js functions/__tests__/
git commit -m "feat(functions): push text reads a date range for a multi-day job"
```

---

### Task 8: Close the debt and prepare the deploy

**Files:**
- Modify: `CLAUDE.md`, `functions/CLAUDE.md`, `docs/plans/2026-08-02-multi-day-appointments.md`

- [ ] **Step 1: Remove the debt paragraph**

In `CLAUDE.md`'s multi-day bullet, delete the block beginning
**"NOT YET MIRRORED (owed by Plan 2)"** and replace it with:

```markdown
  **The mirrors are day-scoped too** (2026-08-03): the widget payload (Dart +
  `functions/widget_payload_utils.js`), the Siri snapshot (**schema v3**) and
  the push date line all fan a run across the days it works.
  **`functions/day_slice_utils.js` is a HAND-MIRROR of
  `appointment_day_slice.dart`** — its jest cases deliberately reuse the Dart
  tests' worked examples (Aug 1–5 day job; Aug 1 22:00 → Aug 4 06:00 = 3 nights
  ending Aug 3), so a divergence fails a test instead of shipping. Change both
  together. **The travel sweep and the overdue sweep need NO day-scoping**: the
  first gates on `startTime > now` so it already fires on day 1 only, and the
  second gates on the run's real `endTime`. **Live Activities deliberately skip
  multi-day jobs** — a four-day Lock Screen countdown is worse than no card.
```

- [ ] **Step 2: Note the new module in `functions/CLAUDE.md`**

Add `day_slice_utils.js` to the module map in the opening paragraph, described
as the pure hand-mirror of the Dart slice rule, dependency-free apart from
`time_utils.js`.

- [ ] **Step 3: Mark the design doc's §8 done**

In `docs/plans/2026-08-02-multi-day-appointments.md`, change §8's table intro to
record that it shipped in Plan 2, and move the Live Activities row into §10's
open items.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md functions/CLAUDE.md docs/plans/
git commit -m "docs: close the multi-day mirror debt"
```

---

### Task 9: Pre-deploy verification (human-gated)

**Do not deploy from a subagent.** This task produces a checklist for the owner.

- [ ] **Step 1: Full verification**

```bash
flutter test          # expect ≥1503 + this plan's additions
flutter analyze       # expect: No issues found!
cd functions && npm run lint && npx jest
```

- [ ] **Step 2: Read `docs/DEPLOYMENT.md` before proposing any deploy**

Ordering matters: **backend deploys BEFORE the app build**, because
`assertPayloadShape` rejects unknown keys. The widget payload gains
`dayIndex`/`dayCount`, so an OLD app build receiving a NEW server payload must
still decode — Swift reads both as `Int?`, which is why they are optional and
omitted for single-day jobs. **Confirm that reasoning holds by re-reading the
Swift decoder** and state it explicitly in your report.

- [ ] **Step 3: Report, do not deploy**

Produce: the deploy command from `docs/DEPLOYMENT.md`, whether
`firestore.indexes.json` changed (it should NOT — this plan adds no query), and
the outstanding Xcode/device items (Tasks 4 and 6 are unverified by any
automated check).

---

## Self-Review

**Spec coverage** — design doc §8: home widget (Tasks 1, 3, 4), Siri v3 (Tasks
5, 6), push/digest text (Task 7), travel sweep (**verified no change needed** —
documented at the top), overdue sweep (**verified no change needed**), Live
Activities (**deferred**, recorded in Task 8). §10 open items carried forward.

**Type consistency** — `sliceForDay`/`dayCountOf`/`lastWorkDayMs`/
`calendarDaysBetween`/`MAX_APPOINTMENT_SPAN_DAYS` are defined once in Task 2 and
used with those exact names in Tasks 3 and 7. Slice fields
`windowStartMs`/`windowEndMs`/`dayIndex`/`dayCount`/`isOvernight`/`isMultiDay`/
`record` are consistent across the JS tasks; the Dart side reuses Plan 1's
`windowStart`/`windowEnd`/`dayIndex`/`dayCount`/`isMultiDay`/`isOvernight`.

**Decisions deliberately escalated rather than assumed** — three, each marked
inline: the widget saying "Day" for a night shift (Task 4), the exact-match
`supportedVersion` gate briefly blanking Siri after the bump (Task 6), and
whether the widget's server-side caller already reads a wide enough window
(Task 3 Step 5). None are safe to decide inside a subagent.

**Known risk** — Tasks 4 and 6 touch Swift with **no automated verification
available in this environment**. Their steps say so explicitly and forbid
claiming a successful build.
