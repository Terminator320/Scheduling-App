# Multi-day Appointments — Implementation Plan 1: the Flutter app

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An appointment can span up to 14 days; the two times describe a daily window; every day it spans shows it with a day/night counter.

**Architecture:** No schema change — `startTime`/`endTime` already carry the span. One new pure domain unit (`AppointmentDaySlice`) fans a record into per-work-day slices and is the single owner of that rule. The range query keeps its single `startTime` inequality and simply reaches 14 days further back; overlap is decided in Dart.

**Tech Stack:** Flutter 3.10.7 / Dart, Riverpod 3, Freezed, `flutter_test`, `gen_l10n`.

**Design doc:** `docs/plans/2026-08-02-multi-day-appointments.md`
**Mockup:** https://claude.ai/code/artifact/a6fbab99-4e86-405b-a001-cc5ba5485ea1

**Out of scope — Plan 2:** home widget, Siri snapshot v3, `notification_messages.js`,
`travel_utils.js`, `widget_payload_utils.js`. Different toolchain (jest/Xcode) and
`docs/DEPLOYMENT.md` requires backend to deploy *before* the app build. Task 13
records that debt so it cannot be silently dropped.

---

## File Structure

**Create**
- `lib/features/calendar/domain/appointment_day_slice.dart` — the day-slice value + `sliceFor` + `expandToDays`. Pure, no Firebase, no Flutter widgets.
- `test/features/calendar/appointment_day_slice_test.dart`

**Modify**
- `lib/features/calendar/domain/policies/appointment_form_validator.dart` — `appointmentSpan`/`allDaySpan` take an end date; new errors; delete `endTimeMustBeAfterStart` + `combineEndDateAndTime`.
- `lib/features/calendar/domain/models/appointment_record.dart` — `AppointmentDateRange.fetchStart`.
- `lib/features/calendar/data/firebase_appointments_repository.dart:292-306` and `:83-90` — query from `fetchStart`.
- `lib/features/calendar/application/add_event_controller.dart` — `endDate`, `endDateTouched`, `selectEndDate`, `setPersonal` no longer clears `isAllDay`.
- `lib/features/calendar/application/event_details_controller.dart` — same.
- `lib/features/calendar/widgets/sections/appointment_form_fields.dart` — the date pair; all-day switch unconditional.
- `lib/features/calendar/widgets/sheets/add_appointment_sheet.dart`, `lib/features/calendar/widgets/views/details_edit_body.dart`, `lib/features/calendar/widgets/views/event_details_view.dart` — `endDate` controller + picker.
- `lib/features/calendar/widgets/cards/appointment_card.dart` — optional `slice`.
- `lib/features/calendar/screens/main_calendar_screen.dart:191-208` — index via `expandToDays`.
- `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`.
- `CLAUDE.md`.

---

### Task 1: The day-slice domain unit

**Files:**
- Create: `lib/features/calendar/domain/appointment_day_slice.dart`
- Test: `test/features/calendar/appointment_day_slice_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/calendar/appointment_day_slice_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

AppointmentRecord _record({
  required DateTime start,
  required DateTime end,
  bool isAllDay = false,
}) => AppointmentRecord(
  id: 'a1',
  title: 'Repipe',
  startTime: start,
  endTime: end,
  isAllDay: isAllDay,
);

void main() {
  group('sliceFor', () {
    test('a single-day job is day 1 of 1', () {
      final a = _record(
        start: DateTime(2026, 8, 1, 9),
        end: DateTime(2026, 8, 1, 17),
      );
      final slice = sliceFor(a, DateTime(2026, 8, 1))!;
      expect(slice.dayIndex, 1);
      expect(slice.dayCount, 1);
      expect(slice.isMultiDay, isFalse);
    });

    test('a 5-day job reports the same daily window on every day', () {
      final a = _record(
        start: DateTime(2026, 8, 1, 9),
        end: DateTime(2026, 8, 5, 17),
      );
      final slice = sliceFor(a, DateTime(2026, 8, 3))!;
      expect(slice.dayIndex, 3);
      expect(slice.dayCount, 5);
      expect(slice.windowStart, DateTime(2026, 8, 3, 9));
      expect(slice.windowEnd, DateTime(2026, 8, 3, 17));
      expect(slice.isOvernight, isFalse);
    });

    test('a day outside the span has no slice', () {
      final a = _record(
        start: DateTime(2026, 8, 1, 9),
        end: DateTime(2026, 8, 5, 17),
      );
      expect(sliceFor(a, DateTime(2026, 7, 31)), isNull);
      expect(sliceFor(a, DateTime(2026, 8, 6)), isNull);
    });

    test('a night shift counts nights and ends the next morning', () {
      // Aug 1, 2, 3 at 10pm; the last window ends Aug 4 at 6am.
      final a = _record(
        start: DateTime(2026, 8, 1, 22),
        end: DateTime(2026, 8, 4, 6),
      );
      final slice = sliceFor(a, DateTime(2026, 8, 2))!;
      expect(slice.dayCount, 3);
      expect(slice.dayIndex, 2);
      expect(slice.isOvernight, isTrue);
      expect(slice.windowStart, DateTime(2026, 8, 2, 22));
      expect(slice.windowEnd, DateTime(2026, 8, 3, 6));
    });

    test('a night shift shows nothing on the morning it finishes', () {
      final a = _record(
        start: DateTime(2026, 8, 1, 22),
        end: DateTime(2026, 8, 4, 6),
      );
      expect(sliceFor(a, DateTime(2026, 8, 4)), isNull);
    });

    test('an all-day block is not overnight', () {
      final a = _record(
        start: DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 14, 23, 59),
        isAllDay: true,
      );
      final slice = sliceFor(a, DateTime(2026, 8, 12))!;
      expect(slice.dayCount, 5);
      expect(slice.dayIndex, 3);
      expect(slice.isOvernight, isFalse);
    });
  });

  group('expandToDays', () {
    test('fans one record across every day it spans', () {
      final a = _record(
        start: DateTime(2026, 8, 1, 9),
        end: DateTime(2026, 8, 3, 17),
      );
      final index = expandToDays(
        [a],
        AppointmentDateRange(start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 9)),
      );
      expect(index.keys.toList(), [
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 2),
        DateTime(2026, 8, 3),
      ]);
    });

    test('drops days outside the requested range', () {
      final a = _record(
        start: DateTime(2026, 7, 30, 9),
        end: DateTime(2026, 8, 2, 17),
      );
      final index = expandToDays(
        [a],
        AppointmentDateRange(start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 9)),
      );
      expect(index.keys.toList(), [DateTime(2026, 8, 1), DateTime(2026, 8, 2)]);
    });

    test('sorts all-day blocks above timed jobs, then by window start', () {
      final timedEarly = _record(
        start: DateTime(2026, 8, 3, 8, 30),
        end: DateTime(2026, 8, 3, 10),
      ).copyWith(id: 'early');
      final timedLate = _record(
        start: DateTime(2026, 8, 3, 13),
        end: DateTime(2026, 8, 3, 16),
      ).copyWith(id: 'late');
      final allDay = _record(
        start: DateTime(2026, 8, 3),
        end: DateTime(2026, 8, 3, 23, 59),
        isAllDay: true,
      ).copyWith(id: 'allday');

      final index = expandToDays(
        [timedLate, timedEarly, allDay],
        AppointmentDateRange(start: DateTime(2026, 8, 3), end: DateTime(2026, 8, 4)),
      );
      expect(
        index[DateTime(2026, 8, 3)]!.map((s) => s.appointment.id).toList(),
        ['allday', 'early', 'late'],
      );
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/calendar/appointment_day_slice_test.dart`
Expected: FAIL — `Error: Not found: 'package:scheduling/features/calendar/domain/appointment_day_slice.dart'`

- [ ] **Step 3: Write the implementation**

Create `lib/features/calendar/domain/appointment_day_slice.dart`:

```dart
import 'package:flutter/foundation.dart' show immutable;

import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// The longest span a job may be booked for. Also the distance
/// [AppointmentDateRange.fetchStart] reaches back, so a job cannot begin
/// before the fetch window and still overlap it.
const int maxAppointmentSpanDays = 14;

/// One appointment as it appears on ONE of the days it spans.
///
/// The two stored times describe a **daily window** — 9:00 AM to 5:00 PM on
/// each of those days, not one unbroken stretch through the nights. A slice
/// carries that day's concrete window plus its position in the run.
@immutable
class AppointmentDaySlice {
  const AppointmentDaySlice({
    required this.appointment,
    required this.dayIndex,
    required this.dayCount,
    required this.windowStart,
    required this.windowEnd,
  });

  final AppointmentRecord appointment;

  /// 1-based position in the run.
  final int dayIndex;
  final int dayCount;

  /// This day's concrete window. [windowEnd] lands on the following calendar
  /// day when the window crosses midnight.
  final DateTime windowStart;
  final DateTime windowEnd;

  bool get isMultiDay => dayCount > 1;
  bool get isFirstDay => dayIndex == 1;
  bool get isLastDay => dayIndex == dayCount;

  /// The window crosses midnight, so the run counts NIGHTS, not days.
  bool get isOvernight => windowEnd.dateOnly.isAfter(windowStart.dateOnly);
}

/// Calendar days from [from] to [to]. Normalized through UTC so the two
/// DST-shift days can't make a whole-day difference come back as 23 or 25
/// hours and round to the wrong integer.
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

DateTime addCalendarDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// True when the record's daily window crosses midnight.
///
/// Equal times are treated as overnight, which yields a 24-hour booking —
/// the established behaviour for a zero-duration appointment.
bool isOvernightRecord(AppointmentRecord a) {
  final startMinutes = a.startTime.hour * 60 + a.startTime.minute;
  final endMinutes = a.endTime.hour * 60 + a.endTime.minute;
  return endMinutes <= startMinutes;
}

/// The last day the crew STARTS work — never the morning an overnight run
/// finishes. Keeps the count at `end - start + 1` for day jobs and night
/// shifts alike.
DateTime lastWorkDayOf(AppointmentRecord a) => isOvernightRecord(a)
    ? addCalendarDays(a.endTime.dateOnly, -1)
    : a.endTime.dateOnly;

/// How many days (or nights) the record runs for. At least 1.
int dayCountOf(AppointmentRecord a) =>
    calendarDaysBetween(a.startTime.dateOnly, lastWorkDayOf(a)) + 1;

/// The record as it appears on [day], or null when it doesn't run that day.
AppointmentDaySlice? sliceFor(AppointmentRecord a, DateTime day) {
  final count = dayCountOf(a);
  if (count < 1) return null;
  final index = calendarDaysBetween(a.startTime.dateOnly, day) + 1;
  if (index < 1 || index > count) return null;
  return _sliceAt(a, day: day.dateOnly, index: index, count: count);
}

AppointmentDaySlice _sliceAt(
  AppointmentRecord a, {
  required DateTime day,
  required int index,
  required int count,
}) {
  final overnight = isOvernightRecord(a);
  return AppointmentDaySlice(
    appointment: a,
    dayIndex: index,
    dayCount: count,
    windowStart: DateTime(
      day.year,
      day.month,
      day.day,
      a.startTime.hour,
      a.startTime.minute,
    ),
    windowEnd: DateTime(
      day.year,
      day.month,
      day.day + (overnight ? 1 : 0),
      a.endTime.hour,
      a.endTime.minute,
    ),
  );
}

/// Buckets [records] by the days they run, clipped to [range].
///
/// Slices are generated per WORK day — each day the daily window begins — not
/// per calendar day the stored instant span touches. That one rule is what
/// makes a night shift file under the evening it starts and show nothing on
/// the morning it ends.
Map<DateTime, List<AppointmentDaySlice>> expandToDays(
  Iterable<AppointmentRecord> records,
  AppointmentDateRange range, {
  void Function(AppointmentRecord record, int days)? onSpanClamped,
}) {
  final index = <DateTime, List<AppointmentDaySlice>>{};
  for (final a in records) {
    final rawCount = dayCountOf(a);
    if (rawCount < 1) continue;
    // A corrupt endTime years out must not explode the index. Clamp, but
    // report it — a silently truncated run reads as a short job.
    final count = rawCount > maxAppointmentSpanDays
        ? maxAppointmentSpanDays
        : rawCount;
    if (count != rawCount) onSpanClamped?.call(a, rawCount);

    final startDate = a.startTime.dateOnly;
    for (var i = 0; i < count; i++) {
      final day = addCalendarDays(startDate, i);
      if (day.isBefore(range.start) || !day.isBefore(range.end)) continue;
      (index[day] ??= <AppointmentDaySlice>[]).add(
        _sliceAt(a, day: day, index: i + 1, count: rawCount),
      );
    }
  }
  for (final slices in index.values) {
    slices.sort(_byAllDayThenWindowStart);
  }
  return index;
}

/// An all-day block owns the whole day, so it reads above the clock; the rest
/// run in clock order. A continuing TIMED job has a real start time today and
/// deliberately takes its place in that order rather than being pinned.
int _byAllDayThenWindowStart(AppointmentDaySlice a, AppointmentDaySlice b) {
  final aAllDay = a.appointment.isAllDay;
  final bAllDay = b.appointment.isAllDay;
  if (aAllDay != bAllDay) return aAllDay ? -1 : 1;
  return a.windowStart.compareTo(b.windowStart);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/calendar/appointment_day_slice_test.dart`
Expected: PASS, 9 tests.

- [ ] **Step 5: Verify the analyzer is still clean**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: no output (the baseline is 0 issues).

- [ ] **Step 6: Commit**

```bash
git add lib/features/calendar/domain/appointment_day_slice.dart test/features/calendar/appointment_day_slice_test.dart
git commit -m "feat(calendar): add AppointmentDaySlice, the one owner of day-scoping"
```

---

### Task 2: `appointmentSpan` takes an end date

**Files:**
- Modify: `lib/features/calendar/domain/policies/appointment_form_validator.dart:98-146`
- Test: `test/features/calendar/appointment_form_validator_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/features/calendar/appointment_form_validator_test.dart` (inside `main()`):

```dart
  group('appointmentSpan', () {
    test('a same-day job spans the picked times', () {
      final span = appointmentSpan(
        date: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 1),
        isAllDay: false,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
      );
      expect(span.start, DateTime(2026, 8, 1, 9));
      expect(span.end, DateTime(2026, 8, 1, 17));
    });

    test('a multi-day job ends on the end date at the end time', () {
      final span = appointmentSpan(
        date: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 5),
        isAllDay: false,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
      );
      expect(span.start, DateTime(2026, 8, 1, 9));
      expect(span.end, DateTime(2026, 8, 5, 17));
    });

    test('a night shift ends the morning after the last night', () {
      final span = appointmentSpan(
        date: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 3),
        isAllDay: false,
        startTime: const TimeOfDay(hour: 22, minute: 0),
        endTime: const TimeOfDay(hour: 6, minute: 0),
      );
      expect(span.start, DateTime(2026, 8, 1, 22));
      expect(span.end, DateTime(2026, 8, 4, 6));
    });

    test('an all-day run spans midnight to 23:59 of the end date', () {
      final span = appointmentSpan(
        date: DateTime(2026, 8, 10),
        endDate: DateTime(2026, 8, 14),
        isAllDay: true,
      );
      expect(span.start, DateTime(2026, 8, 10));
      expect(span.end, DateTime(2026, 8, 14, 23, 59));
    });
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/calendar/appointment_form_validator_test.dart`
Expected: FAIL — `No named parameter with the name 'endDate'`.

- [ ] **Step 3: Replace lines 98-146 of the validator file**

Replace the whole block from `/// The instants an all-day block spans.` through the end of `combineEndDateAndTime` with:

```dart
/// The instants an all-day run spans. Real instants, not sentinels: every
/// range query, `orderBy('startTime')` and overdue sweep in the app and on the
/// server keeps treating it as an ordinary appointment.
({DateTime start, DateTime end}) allDaySpan(DateTime start, DateTime end) => (
  start: start.dateOnly,
  end: DateTime(end.year, end.month, end.day, 23, 59),
);

/// The instants a form's schedule fields resolve to. The one place the all-day
/// convention and the overnight roll-over are chosen — both save paths route
/// through it, so the two can't drift on what gets stored.
///
/// [startTime] and [endTime] are required unless [isAllDay]; the validator has
/// already rejected an empty pair by the time a save gets here.
///
/// The times are a DAILY WINDOW. When [endTime] is at or before [startTime]
/// the window crosses midnight, so the last one finishes the morning after
/// [endDate] — which is why [endDate] always names the last day the crew
/// STARTS work, never the morning an overnight run ends.
({DateTime start, DateTime end}) appointmentSpan({
  required DateTime date,
  required DateTime endDate,
  required bool isAllDay,
  TimeOfDay? startTime,
  TimeOfDay? endTime,
}) {
  if (isAllDay) return allDaySpan(date, endDate);
  final lastDay = isOvernightWindow(startTime!, endTime!)
      ? addCalendarDays(endDate, 1)
      : endDate;
  return (
    start: combineDateAndTime(date, startTime),
    end: combineDateAndTime(lastDay, endTime),
  );
}

/// True when a daily window runs past midnight. Equal times count as
/// overnight, giving a 24-hour booking.
bool isOvernightWindow(TimeOfDay start, TimeOfDay end) =>
    end.hour * 60 + end.minute <= start.hour * 60 + start.minute;

DateTime combineDateAndTime(DateTime date, TimeOfDay time) =>
    DateTime(date.year, date.month, date.day, time.hour, time.minute);
```

Add to the imports at the top of the file:

```dart
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
```

- [ ] **Step 4: Confirm `combineEndDateAndTime` has no surviving callers**

Run: `grep -rn "combineEndDateAndTime" lib/ test/`
Expected: no output. If any remain, they are in the validator body being rewritten in Task 3 — finish Task 3 before re-running.

- [ ] **Step 5: Run the test**

Run: `flutter test test/features/calendar/appointment_form_validator_test.dart`
Expected: the four new `appointmentSpan` tests PASS. Existing tests referencing `endTimeMustBeAfterStart` still FAIL — Task 3 fixes them.

- [ ] **Step 6: Commit**

```bash
git add lib/features/calendar/domain/policies/appointment_form_validator.dart test/features/calendar/appointment_form_validator_test.dart
git commit -m "feat(calendar): appointmentSpan takes an end date and owns the overnight roll-over"
```

---

### Task 3: Validator — span rules replace the end-time check

**Files:**
- Modify: `lib/features/calendar/domain/policies/appointment_form_validator.dart:7-96`
- Modify: `lib/features/calendar/utils/appointment_form_error_text.dart`
- Test: `test/features/calendar/appointment_form_validator_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()`:

```dart
  group('span validation', () {
    Map<String, AppointmentFormError> run({
      required DateTime date,
      required DateTime endDate,
    }) => AppointmentFormValidator.validate(
      AppointmentFormInput(
        title: 'Repipe',
        date: date,
        endDate: endDate,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 17, minute: 0),
        client: null,
        selectedEmployees: const [],
        isPersonal: true,
      ),
    );

    test('rejects an end date before the start date', () {
      final errors = run(
        date: DateTime(2026, 8, 5),
        endDate: DateTime(2026, 8, 1),
      );
      expect(errors['endDate'], AppointmentFormError.endDateBeforeStart);
    });

    test('accepts a span of exactly 14 days', () {
      final errors = run(
        date: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 14),
      );
      expect(errors['endDate'], isNull);
    });

    test('rejects a span of 15 days', () {
      final errors = run(
        date: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 15),
      );
      expect(errors['endDate'], AppointmentFormError.spanTooLong);
    });

    test('accepts an end time before the start time — that is a night shift', () {
      final errors = AppointmentFormValidator.validate(
        AppointmentFormInput(
          title: 'Nuit',
          date: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 3),
          startTime: const TimeOfDay(hour: 22, minute: 0),
          endTime: const TimeOfDay(hour: 6, minute: 0),
          client: null,
          selectedEmployees: const [],
          isPersonal: true,
        ),
      );
      expect(errors['endTime'], isNull);
      expect(errors['endDate'], isNull);
    });
  });
```

Then delete any existing test in this file that asserts
`AppointmentFormError.endTimeMustBeAfterStart` — that error no longer exists.
Find them with: `grep -n "endTimeMustBeAfterStart" test/features/calendar/appointment_form_validator_test.dart`

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/calendar/appointment_form_validator_test.dart`
Expected: FAIL — `endDateBeforeStart` isn't a member of `AppointmentFormError`.

- [ ] **Step 3: Replace lines 7-96 of the validator**

```dart
enum AppointmentFormError {
  titleRequired,
  dateRequired,
  startTimeRequired,
  endTimeRequired,
  endDateBeforeStart,
  spanTooLong,
  clientRequired,
  employeesRequired,
}

class AppointmentFormInput {
  const AppointmentFormInput({
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.client,
    required this.selectedEmployees,
    this.endDate,
    this.isPersonal = false,
    this.isAllDay = false,
  });

  final String title;
  final DateTime? date;

  /// The last day the crew STARTS work. Null is read as same-day.
  final DateTime? endDate;

  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final ClientRecord? client;
  final List<EmployeeRecord> selectedEmployees;

  /// A personal job blocks time out for the crew instead of visiting a client,
  /// so it carries no client, no address, and needn't be named. The assignees
  /// are still required — they are who the block is for, and who can see it.
  final bool isPersonal;

  /// No time was put in, so the run owns whole days and neither time is
  /// required.
  final bool isAllDay;
}

class AppointmentFormValidator {
  const AppointmentFormValidator._();

  static Map<String, AppointmentFormError> validate(
    AppointmentFormInput input,
  ) {
    final errors = <String, AppointmentFormError>{};

    // A personal block may go unnamed — it saves under a "Personal" title.
    if (!input.isPersonal && input.title.trim().isEmpty) {
      errors['title'] = AppointmentFormError.titleRequired;
    }
    if (input.date == null) {
      errors['date'] = AppointmentFormError.dateRequired;
    }
    // An all-day run has no times to validate — it runs midnight to 23:59.
    if (!input.isAllDay && input.startTime == null) {
      errors['startTime'] = AppointmentFormError.startTimeRequired;
    }
    if (!input.isAllDay && input.endTime == null) {
      errors['endTime'] = AppointmentFormError.endTimeRequired;
    }

    // NOTE: there is deliberately no end-time-after-start-time rule. The two
    // times are a DAILY window, so an end time at or before the start time is
    // the definition of a night shift, which is supported.
    final date = input.date;
    final endDate = input.endDate;
    if (date != null && endDate != null) {
      final span = calendarDaysBetween(date, endDate) + 1;
      if (span < 1) {
        errors['endDate'] = AppointmentFormError.endDateBeforeStart;
      } else if (span > maxAppointmentSpanDays) {
        errors['endDate'] = AppointmentFormError.spanTooLong;
      }
    }

    if (!input.isPersonal && input.client == null) {
      errors['client'] = AppointmentFormError.clientRequired;
    }
    if (input.selectedEmployees.isEmpty) {
      errors['employees'] = AppointmentFormError.employeesRequired;
    }

    return errors;
  }
}
```

- [ ] **Step 4: Update the error-text mapper**

In `lib/features/calendar/utils/appointment_form_error_text.dart`, replace the
`endTimeMustBeAfterStart` case with these two:

```dart
    AppointmentFormError.endDateBeforeStart =>
      l10n.validation_endDateBeforeStart,
    AppointmentFormError.spanTooLong =>
      l10n.validation_spanTooLong(maxAppointmentSpanDays),
```

Add the import:

```dart
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
```

- [ ] **Step 5: Add the ARB keys**

In `lib/l10n/app_en.arb`:

```json
  "validation_endDateBeforeStart": "The end date can't be before the start date.",
  "@validation_endDateBeforeStart": {
    "description": "Shown on the appointment form when the picked end date falls before the start date."
  },
  "validation_spanTooLong": "A job can run at most {days} days. Shorten the end date or book a second job.",
  "@validation_spanTooLong": {
    "description": "Shown on the appointment form when the booked span exceeds the maximum.",
    "placeholders": { "days": { "type": "int" } }
  },
```

In `lib/l10n/app_fr.arb`:

```json
  "validation_endDateBeforeStart": "La date de fin ne peut pas précéder la date de début.",
  "validation_spanTooLong": "Un travail peut durer au plus {days} jours. Réduisez la date de fin ou créez un deuxième travail.",
```

The repo's ARB hook regenerates l10n automatically — do NOT run `flutter gen-l10n` manually.

- [ ] **Step 6: Run the tests**

Run: `flutter test test/features/calendar/appointment_form_validator_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/calendar/domain/policies/appointment_form_validator.dart lib/features/calendar/utils/appointment_form_error_text.dart lib/l10n/app_en.arb lib/l10n/app_fr.arb test/features/calendar/appointment_form_validator_test.dart
git commit -m "feat(calendar): span validation replaces the end-time-after-start rule"
```

---

### Task 4: The fetch window reaches 14 days back

**Files:**
- Modify: `lib/features/calendar/domain/models/appointment_record.dart:128-175`
- Modify: `lib/features/calendar/data/firebase_appointments_repository.dart:83-90`, `:292-306`
- Test: `test/features/calendar/appointment_date_range_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/calendar/appointment_date_range_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

void main() {
  test('fetchStart reaches 14 days before the range start', () {
    final range = AppointmentDateRange.forDay(DateTime(2026, 8, 15));
    expect(range.start, DateTime(2026, 8, 15));
    expect(range.fetchStart, DateTime(2026, 8, 1));
  });

  test('fetchStart crosses a month boundary by calendar arithmetic', () {
    final range = AppointmentDateRange.forDay(DateTime(2026, 8, 5));
    expect(range.fetchStart, DateTime(2026, 7, 22));
  });

  test('two ranges for the same day are equal, so they share one listener', () {
    expect(
      AppointmentDateRange.forDay(DateTime(2026, 8, 5)),
      AppointmentDateRange.forDay(DateTime(2026, 8, 5)),
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/calendar/appointment_date_range_test.dart`
Expected: FAIL — `The getter 'fetchStart' isn't defined`.

- [ ] **Step 3: Add `fetchStart` to `AppointmentDateRange`**

Insert immediately after the `const AppointmentDateRange({...})` constructor
(line 129 of `appointment_record.dart`):

```dart
  /// How far back the range QUERY must reach. A job that started up to
  /// [maxAppointmentSpanDays] ago can still be running inside this window, and
  /// the query filters on `startTime` alone — so without this the calendar
  /// simply never sees it.
  ///
  /// Deliberately a derived getter and NOT a constructor field: `==` stays
  /// keyed on [start]/[end], so two surfaces asking for the same day still
  /// produce equal ranges and share one Firestore listener. Widening at a call
  /// site instead would fork a second query for the same day.
  DateTime get fetchStart =>
      DateTime(start.year, start.month, start.day - maxAppointmentSpanDays);
```

Add the import at the top of `appointment_record.dart`:

```dart
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
```

> If `appointment_day_slice.dart` importing `appointment_record.dart` and vice
> versa trips a circular-import analyzer error, move `maxAppointmentSpanDays`
> into `lib/features/calendar/domain/appointment_span_limits.dart` (a
> dependency-free constants file) and import that from both. Dart tolerates
> cycles, so only do this if the analyzer actually objects.

- [ ] **Step 4: Point the two range queries at `fetchStart`**

In `lib/features/calendar/data/firebase_appointments_repository.dart`, in
`watchInRange` (line ~296), change the lower bound:

```dart
          .where(
            'startTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(range.fetchStart),
          )
```

Apply the identical change at the other two range sites — line ~88 (the
`employeeIds` + `startTime` query) and line ~425. Find them with:

Run: `grep -n "isGreaterThanOrEqualTo: Timestamp.fromDate(range.start)" lib/features/calendar/data/firebase_appointments_repository.dart`
Expected: three matches, all replaced with `range.fetchStart`.

Leave every `isLessThan: Timestamp.fromDate(range.end)` untouched — a job
starting after the window ends cannot overlap it.

- [ ] **Step 5: Run the tests**

Run: `flutter test test/features/calendar/appointment_date_range_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
git add lib/features/calendar/domain/models/appointment_record.dart lib/features/calendar/data/firebase_appointments_repository.dart test/features/calendar/appointment_date_range_test.dart
git commit -m "feat(calendar): range queries reach 14 days back so running jobs are fetched"
```

---

### Task 5: `endDate` in the add-flow controller

**Files:**
- Modify: `lib/features/calendar/application/add_event_controller.dart:25-42`, `:119-137`, `:196-221`
- Test: `test/features/calendar/add_event_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()` of `test/features/calendar/add_event_controller_test.dart`:

```dart
  group('end date', () {
    test('follows the start date until it is touched', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        addEventControllerProvider(null).notifier,
      );

      notifier.selectDate(DateTime(2026, 8, 1));
      expect(container.read(addEventControllerProvider(null)).endDate,
          DateTime(2026, 8, 1));

      notifier.selectDate(DateTime(2026, 8, 4));
      expect(container.read(addEventControllerProvider(null)).endDate,
          DateTime(2026, 8, 4));
    });

    test('once touched, moving the start shifts the end by the same days', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        addEventControllerProvider(null).notifier,
      );

      notifier.selectDate(DateTime(2026, 8, 1));
      notifier.selectEndDate(DateTime(2026, 8, 5)); // a 5-day run
      notifier.selectDate(DateTime(2026, 8, 3)); // moved 2 days later

      final state = container.read(addEventControllerProvider(null));
      expect(state.endDate, DateTime(2026, 8, 7)); // still 5 days
      expect(state.endDateTouched, isTrue);
    });

    test('a start date after a touched end date drags the end along', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        addEventControllerProvider(null).notifier,
      );

      notifier.selectDate(DateTime(2026, 8, 1));
      notifier.selectEndDate(DateTime(2026, 8, 2));
      notifier.selectDate(DateTime(2026, 8, 10));

      expect(container.read(addEventControllerProvider(null)).endDate,
          DateTime(2026, 8, 11));
    });
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/calendar/add_event_controller_test.dart`
Expected: FAIL — `The getter 'endDate' isn't defined for the class 'AddEventState'`.

- [ ] **Step 3: Add the state fields**

In `add_event_controller.dart`, add to the `AddEventState` factory, right after
`DateTime? selectedDate,`:

```dart
    DateTime? endDate,

    /// The user has picked an end date explicitly, so it no longer mirrors the
    /// start — moving the start now SHIFTS it instead of collapsing the run.
    @Default(false) bool endDateTouched,
```

- [ ] **Step 4: Replace `selectDate` and add `selectEndDate` (lines 119-124)**

```dart
  void selectDate(DateTime date) {
    state = state.copyWith(
      selectedDate: date,
      endDate: _shiftedEndDate(date),
      errors: withoutKey(withoutKey(state.errors, 'date'), 'endDate'),
    );
  }

  /// Where the end date lands when the start moves to [date].
  ///
  /// Untouched, it simply mirrors the start. Touched, the run keeps its
  /// LENGTH — a 5-day job stays 5 days rather than collapsing to one — which
  /// is the whole reason `endDateTouched` is tracked explicitly rather than
  /// inferred from the two dates being equal.
  DateTime _shiftedEndDate(DateTime date) {
    final previousStart = state.selectedDate;
    final previousEnd = state.endDate;
    if (!state.endDateTouched || previousStart == null || previousEnd == null) {
      return date;
    }
    final length = calendarDaysBetween(previousStart, previousEnd);
    return addCalendarDays(date, length < 0 ? 0 : length);
  }

  void selectEndDate(DateTime date) {
    state = state.copyWith(
      endDate: date,
      endDateTouched: true,
      errors: withoutKey(state.errors, 'endDate'),
    );
  }
```

Add the import:

```dart
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
```

- [ ] **Step 5: Feed `endDate` to the validator and the span (lines 196-221)**

In `submit()`, add to the `AppointmentFormInput`:

```dart
        endDate: state.endDate ?? state.selectedDate,
```

and change the `appointmentSpan` call:

```dart
    final (:start, :end) = appointmentSpan(
      date: state.selectedDate!,
      endDate: state.endDate ?? state.selectedDate!,
      isAllDay: state.isAllDay,
      startTime: state.selectedStartTime,
      endTime: state.selectedEndTime,
    );
```

- [ ] **Step 6: Regenerate Freezed**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `Succeeded after ...` with `add_event_controller.freezed.dart` rewritten.

- [ ] **Step 7: Run the tests**

Run: `flutter test test/features/calendar/add_event_controller_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/features/calendar/application/add_event_controller.dart lib/features/calendar/application/add_event_controller.freezed.dart test/features/calendar/add_event_controller_test.dart
git commit -m "feat(calendar): add-flow end date, following the start until touched"
```

---

### Task 6: `endDate` in the edit-flow controller, and all-day for every job

**Files:**
- Modify: `lib/features/calendar/application/event_details_controller.dart:39-95`, `:169-223`, `:374-378`, `:485-500`, `:535-542`
- Test: `test/features/calendar/event_details_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()`:

```dart
  group('multi-day editing', () {
    test('seeds the end date from the stored last work day', () {
      final appointment = AppointmentRecord(
        id: 'a1',
        title: 'Repipe',
        startTime: DateTime(2026, 8, 1, 9),
        endTime: DateTime(2026, 8, 5, 17),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(
        eventDetailsControllerProvider(EventDetailsKey(appointment: appointment)),
      );
      expect(state.endDate, DateTime(2026, 8, 5));
      expect(state.endDateTouched, isTrue);
    });

    test('seeds a night shift end date as the last night, not the morning', () {
      final appointment = AppointmentRecord(
        id: 'a2',
        title: 'Nuit',
        startTime: DateTime(2026, 8, 1, 22),
        endTime: DateTime(2026, 8, 4, 6),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(
        eventDetailsControllerProvider(EventDetailsKey(appointment: appointment)),
      );
      expect(state.endDate, DateTime(2026, 8, 3));
    });

    test('turning Personal off KEEPS isAllDay', () {
      final appointment = AppointmentRecord(
        id: 'a3',
        title: 'Bloc',
        startTime: DateTime(2026, 8, 1),
        endTime: DateTime(2026, 8, 1, 23, 59),
        isPersonal: true,
        isAllDay: true,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final key = EventDetailsKey(appointment: appointment);
      container
          .read(eventDetailsControllerProvider(key).notifier)
          .setPersonal(value: false);
      expect(
        container.read(eventDetailsControllerProvider(key)).isAllDay,
        isTrue,
      );
    });
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/calendar/event_details_controller_test.dart`
Expected: FAIL — `The getter 'endDate' isn't defined for the class 'EventDetailsState'`.

- [ ] **Step 3: Add the state fields (after line 40)**

```dart
    required DateTime endDate,
    @Default(true) bool endDateTouched,
```

`endDateTouched` defaults to **true** here, unlike the add flow: an existing
record already has a real end date, and moving its start must preserve the run
length rather than collapse it.

- [ ] **Step 4: Seed them in `build()` (after line 81)**

```dart
      endDate: lastWorkDayOf(appointment),
```

Add the import:

```dart
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
```

- [ ] **Step 5: Replace `selectDate` (lines 169-174) and add `selectEndDate`**

```dart
  void selectDate(DateTime date) {
    final length = calendarDaysBetween(state.selectedDate, state.endDate);
    state = state.copyWith(
      selectedDate: date,
      endDate: addCalendarDays(date, length < 0 ? 0 : length),
      errors: withoutKey(withoutKey(state.errors, 'date'), 'endDate'),
    );
  }

  void selectEndDate(DateTime date) {
    state = state.copyWith(
      endDate: date,
      endDateTouched: true,
      errors: withoutKey(state.errors, 'endDate'),
    );
  }
```

- [ ] **Step 6: Stop clearing `isAllDay` in `setPersonal` (line 216-220)**

Replace the `isAllDay: value && state.isAllDay,` line **and its comment** with:

```dart
      // isAllDay is deliberately NOT cleared here. The all-day switch is shown
      // on every job now, not just personal ones, so the flag is always
      // reachable and clearing it would discard a deliberate choice.
```

(That is, drop the `isAllDay:` argument from the `copyWith` entirely.)

- [ ] **Step 7: Thread `endDate` through the save paths**

At line ~374:

```dart
    final (:start, :end) = appointmentSpan(
      date: state.selectedDate,
      endDate: state.endDate,
      isAllDay: state.isAllDay,
      startTime: state.selectedStartTime,
      endTime: state.selectedEndTime,
    );
```

At line ~491, add to the `AppointmentFormInput`:

```dart
        endDate: state.endDate,
```

- [ ] **Step 8: Regenerate Freezed and run the tests**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/features/calendar/event_details_controller_test.dart
```
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/features/calendar/application/event_details_controller.dart lib/features/calendar/application/event_details_controller.freezed.dart test/features/calendar/event_details_controller_test.dart
git commit -m "feat(calendar): edit-flow end date; all-day survives turning Personal off"
```

---

### Task 7: Mirror the add-flow all-day rule

**Files:**
- Modify: `lib/features/calendar/application/add_event_controller.dart:153-175`
- Test: `test/features/calendar/add_event_controller_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
  test('add flow: turning Personal off keeps an explicitly set isAllDay', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(addEventControllerProvider(null).notifier);

    notifier.setPersonal(value: true);
    notifier.setAllDay(value: true);
    notifier.setPersonal(value: false);

    expect(container.read(addEventControllerProvider(null)).isAllDay, isTrue);
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/calendar/add_event_controller_test.dart`
Expected: FAIL — `Expected: true, Actual: <false>`.

- [ ] **Step 3: Replace the `isAllDay` argument in `setPersonal` (lines 166-169)**

```dart
      // Turning Personal ON defaults an untimed block to all-day. Turning it
      // OFF leaves the flag alone — the switch is on every job now, so an
      // all-day CLIENT visit is a legitimate, reachable, repairable state.
      isAllDay: value
          ? state.selectedStartTime == null && state.selectedEndTime == null
          : state.isAllDay,
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/calendar/add_event_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/application/add_event_controller.dart test/features/calendar/add_event_controller_test.dart
git commit -m "feat(calendar): add flow keeps isAllDay when Personal is turned off"
```

---

### Task 8: The form's date pair

**Files:**
- Modify: `lib/features/calendar/widgets/sections/appointment_form_fields.dart:26-59`, `:294-380`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`
- Test: `test/features/calendar/appointment_form_fields_test.dart`

- [ ] **Step 1: Add the ARB keys**

`lib/l10n/app_en.arb`:

```json
  "calendar_startDate": "Start date",
  "@calendar_startDate": { "description": "Label on the appointment form's start-date picker row." },
  "calendar_endDate": "End date",
  "@calendar_endDate": { "description": "Label on the appointment form's end-date picker row." },
  "calendar_startTimeEachDay": "Start time · each day",
  "@calendar_startTimeEachDay": { "description": "Start-time label on a multi-day job, where the times are a daily window." },
  "calendar_endTimeEachDay": "End time · each day",
  "@calendar_endTimeEachDay": { "description": "End-time label on a multi-day job, where the times are a daily window." },
  "calendar_startTimeEachNight": "Start time · each night",
  "@calendar_startTimeEachNight": { "description": "Start-time label on a multi-day job whose daily window crosses midnight." },
  "calendar_endTimeNextMorning": "End time · next morning",
  "@calendar_endTimeNextMorning": { "description": "End-time label on a multi-day job whose daily window crosses midnight." },
  "calendar_spanDays": "{count} days",
  "@calendar_spanDays": { "description": "Trailing run length beside the end date.", "placeholders": { "count": { "type": "int" } } },
  "calendar_spanNights": "{count} nights",
  "@calendar_spanNights": { "description": "Trailing run length beside the end date for an overnight job.", "placeholders": { "count": { "type": "int" } } },
  "calendar_dayOfCount": "Day {index} of {count}",
  "@calendar_dayOfCount": { "description": "Position of one day within a multi-day job, shown on the appointment card.", "placeholders": { "index": { "type": "int" }, "count": { "type": "int" } } },
  "calendar_nightOfCount": "Night {index} of {count}",
  "@calendar_nightOfCount": { "description": "Position of one night within a multi-night job, shown on the appointment card.", "placeholders": { "index": { "type": "int" }, "count": { "type": "int" } } },
```

`lib/l10n/app_fr.arb`:

```json
  "calendar_startDate": "Date de début",
  "calendar_endDate": "Date de fin",
  "calendar_startTimeEachDay": "Heure de début · chaque jour",
  "calendar_endTimeEachDay": "Heure de fin · chaque jour",
  "calendar_startTimeEachNight": "Heure de début · chaque nuit",
  "calendar_endTimeNextMorning": "Heure de fin · lendemain matin",
  "calendar_spanDays": "{count} jours",
  "calendar_spanNights": "{count} nuits",
  "calendar_dayOfCount": "Jour {index} sur {count}",
  "calendar_nightOfCount": "Nuit {index} sur {count}",
```

- [ ] **Step 2: Write the failing widget test**

Create `test/features/calendar/appointment_form_fields_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/features/calendar/widgets/sections/appointment_form_fields.dart';
import 'package:scheduling/l10n/l10n.dart';

AppointmentFormControllers _controllers({
  String date = 'Sat, Aug 1',
  String endDate = 'Sat, Aug 1',
}) => AppointmentFormControllers(
  title: TextEditingController(),
  date: TextEditingController(text: date),
  endDate: TextEditingController(text: endDate),
  startTime: TextEditingController(text: '9:00 AM'),
  endTime: TextEditingController(text: '5:00 PM'),
  clientSearch: TextEditingController(),
  address: TextEditingController(),
  notes: TextEditingController(),
  materials: TextEditingController(),
);

Widget _host(AppointmentFormControllers controllers, {bool isPersonal = false}) =>
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: AppointmentFormFields(
            controllers: controllers,
            allEmployees: const [],
            selectedClient: null,
            clientResults: const [],
            isSearchingClient: false,
            selectedEmployees: const [],
            repeat: RepeatInterval.none,
            useCustomAddress: false,
            isPersonal: isPersonal,
            isAllDay: false,
            onAllDayChanged: (_) {},
            errors: const {},
            employeeLabel: 'Crew',
            employeeRequired: true,
            materialsHint: '',
            photosSection: const SizedBox.shrink(),
            onSearchClients: (_) {},
            onSelectClient: (_) {},
            onClearClient: () {},
            onToggleEmployee: (_) {},
            onPickDate: () {},
            onPickEndDate: () {},
            onPickStartTime: () {},
            onPickEndTime: () {},
            onSelectRepeat: (_) {},
            onUseCustomAddress: (_) {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('renders a start-date and end-date pair', (tester) async {
    await tester.pumpWidget(_host(_controllers()));
    await tester.pumpAndSettle();
    expect(find.text('Start date'), findsOneWidget);
    expect(find.text('End date'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the all-day switch shows on a CLIENT job', (tester) async {
    await tester.pumpWidget(_host(_controllers()));
    await tester.pumpAndSettle();
    expect(find.text('All day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('time labels gain the daily-window qualifier when multi-day',
      (tester) async {
    await tester.pumpWidget(
      _host(_controllers(endDate: 'Wed, Aug 5')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start time · each day'), findsOneWidget);
    expect(find.text('End time · each day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/features/calendar/appointment_form_fields_test.dart`
Expected: FAIL — `No named parameter with the name 'endDate'`.

- [ ] **Step 4: Add the `endDate` controller**

In `appointment_form_fields.dart`, add `endDate` to `AppointmentFormControllers`
— the constructor, the field list, and `dispose()`:

```dart
  final TextEditingController endDate;
```

Update the doc comment on the class from "eight text controllers" to "nine text
controllers".

- [ ] **Step 5: Add the widget parameters**

Add to `AppointmentFormFields`'s constructor (required) and fields:

```dart
  final VoidCallback onPickEndDate;

  /// True when this job runs more than one day — drives the daily-window
  /// qualifier on the time labels and the run-length beside the end date.
  final bool isMultiDay;

  /// True when the daily window crosses midnight, so the run counts nights.
  final bool isOvernight;

  /// Run length in days (or nights). 1 for a single-day job.
  final int spanLength;
```

Give `isMultiDay`, `isOvernight` and `spanLength` defaults of `false`, `false`
and `1` so existing call sites compile before Task 9 wires them.

- [ ] **Step 6: Replace the schedule panel (lines 339-367)**

```dart
    return [
      MonoSectionLabel(l10n.calendar_sectionSchedule),
      const SizedBox(height: AppSpacing.sp8),
      SheetPanel(
        children: [
          // All day decides whether the time rows below exist at all, so it
          // leads the panel. Offered on every job — a client visit can run
          // whole days too, not just a personal block.
          _AllDaySwitch(value: isAllDay, onChanged: onAllDayChanged),
          _dateRow(context, l10n),
          if (!isAllDay) ...timeRows(),
          // Repeat: same panel as the dates and times, so everything about
          // when the job happens reads as one block. Not offered on a personal
          // job.
          if (!isPersonal)
            RepeatIntervalPicker(current: repeat, onChanged: onSelectRepeat),
        ],
      ),
      const SizedBox(height: AppSpacing.sp16),
      // --- Status (edit flow only) ---
      if (showStatus) ...[
        formLabel(context, l10n.calendar_appointmentStatus),
        const SizedBox(height: AppSpacing.sp4),
        AppointmentStatusPicker(
          currentStatus: editingStatus!,
          onChanged: onStatusChanged!,
        ),
        const SizedBox(height: AppSpacing.sp16),
      ],
    ];
  }

  /// Start date and End date, side by side — mirroring the time pair below.
  /// Folds to stacked rows on a narrow phone, exactly as the times do.
  Widget _dateRow(BuildContext context, AppLocalizations l10n) {
    final startRow = SheetFieldRow(
      label: l10n.calendar_startDate,
      value: controllers.date.text,
      placeholder: l10n.calendar_selectDate,
      accent: true,
      useMonoValue: true,
      errorText: _err(context, 'date'),
      onTap: onPickDate,
      trailing: const Icon(Icons.calendar_today_outlined, size: 18),
    );
    final endRow = SheetFieldRow(
      label: l10n.calendar_endDate,
      value: controllers.endDate.text,
      placeholder: l10n.calendar_selectDate,
      accent: true,
      useMonoValue: true,
      // The run length only earns its space once the job actually spans days.
      trailingLabel: isMultiDay
          ? (isOvernight
                ? l10n.calendar_spanNights(spanLength)
                : l10n.calendar_spanDays(spanLength))
          : null,
      errorText: _err(context, 'endDate'),
      onTap: onPickEndDate,
    );
    if (context.isNarrowWidth) {
      return Column(children: [startRow, const Divider(height: 1), endRow]);
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: startRow),
          const VerticalDivider(width: 1),
          Expanded(child: endRow),
        ],
      ),
    );
  }
```

- [ ] **Step 7: Qualify the time labels**

Inside `timeRows()`, replace the two `label:` arguments:

```dart
      final startRow = SheetFieldRow(
        label: !isMultiDay
            ? l10n.calendar_startTime
            : (isOvernight
                  ? l10n.calendar_startTimeEachNight
                  : l10n.calendar_startTimeEachDay),
```

```dart
      final endRow = SheetFieldRow(
        label: !isMultiDay
            ? l10n.calendar_endTime
            : (isOvernight
                  ? l10n.calendar_endTimeNextMorning
                  : l10n.calendar_endTimeEachDay),
```

- [ ] **Step 8: Add `trailingLabel` to `SheetFieldRow`**

In `lib/shared/widgets/fields/sheet_field_row.dart`, add an optional field:

```dart
  /// Muted text after the value — e.g. a run length beside an end date. Null
  /// renders nothing.
  final String? trailingLabel;
```

Render it beside the value:

```dart
        if (trailingLabel case final label?) ...[
          const SizedBox(width: AppSpacing.sp8),
          Text(
            label,
            style: theme.monoType.micro.copyWith(
              color: theme.palette.textMuted,
            ),
          ),
        ],
```

- [ ] **Step 9: Run the tests**

Run: `flutter test test/features/calendar/appointment_form_fields_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 10: Commit**

```bash
git add lib/features/calendar/widgets/sections/appointment_form_fields.dart lib/shared/widgets/fields/sheet_field_row.dart lib/l10n/app_en.arb lib/l10n/app_fr.arb test/features/calendar/appointment_form_fields_test.dart
git commit -m "feat(calendar): start/end date pair; all-day switch on every job"
```

---

### Task 9: Wire the two form hosts

**Files:**
- Modify: `lib/features/calendar/widgets/sheets/add_appointment_sheet.dart:87-100`
- Modify: `lib/features/calendar/widgets/views/details_edit_body.dart:120-152`
- Modify: `lib/features/calendar/widgets/views/event_details_view.dart:60-75`

- [ ] **Step 1: Add the end-date controller to the edit host**

In `event_details_view.dart`'s `_ensureControllers()`, after the `date:` entry:

```dart
      endDate: TextEditingController(
        text: DateUtilsHelper.formatDate(lastWorkDayOf(a)),
      ),
```

Add the import:

```dart
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
```

- [ ] **Step 2: Add the picker to the edit body**

In `details_edit_body.dart`, after `_pickDate` (line 152):

```dart
  Future<void> _pickEndDate(
    BuildContext context,
    EventDetailsState state,
    EventDetailsController notifier,
  ) async {
    final picked = await showAdaptiveDatePicker(
      context,
      initialDate: state.endDate,
      // Never offer a date before the start — an end date that precedes it is
      // unbookable, so it shouldn't be reachable in the picker either.
      firstDate: state.selectedDate,
      lastDate: AppointmentDraftDefaults.datePickerLastDate,
    );
    if (picked == null || !context.mounted) return;
    widget.controllers.endDate.text = DateUtilsHelper.formatDate(picked);
    notifier.selectEndDate(picked);
  }
```

Then update `_pickDate` so the mirrored end date stays visible — after
`notifier.selectDate(picked);`:

```dart
    widget.controllers.endDate.text = DateUtilsHelper.formatDate(
      ref.read(_provider).endDate,
    );
```

Use whichever provider accessor that file already has for the controller state;
if it reads through `state`, re-read it after `selectDate` rather than using the
stale `state` argument.

- [ ] **Step 3: Pass the new arguments to `AppointmentFormFields`**

In `details_edit_body.dart`, alongside `onPickDate`:

```dart
          onPickEndDate: () => _pickEndDate(context, state, notifier),
          isMultiDay: calendarDaysBetween(state.selectedDate, state.endDate) > 0,
          isOvernight: !state.isAllDay &&
              isOvernightWindow(state.selectedStartTime, state.selectedEndTime),
          spanLength:
              calendarDaysBetween(state.selectedDate, state.endDate) + 1,
```

- [ ] **Step 4: Do the same in the add sheet**

In `add_appointment_sheet.dart`, after `_pickDate()`:

```dart
  Future<void> _pickEndDate() async {
    final state = ref.read(_provider);
    final picked = await showAdaptiveDatePicker(
      context,
      initialDate: state.endDate ?? state.selectedDate,
      firstDate: state.selectedDate ?? AppointmentDraftDefaults.datePickerFirstDate,
      lastDate: AppointmentDraftDefaults.datePickerLastDate,
    );
    if (picked == null || !mounted) return;
    _controllers.endDate.text = DateUtilsHelper.formatDate(picked);
    _notifier.selectEndDate(picked);
  }
```

In `_pickDate()`, after `_notifier.selectDate(picked);`:

```dart
    final endDate = ref.read(_provider).endDate;
    if (endDate != null) {
      _controllers.endDate.text = DateUtilsHelper.formatDate(endDate);
    }
```

And in `initState`, alongside the existing `_controllers.date.text` seed:

```dart
      _controllers.endDate.text = DateUtilsHelper.formatDate(initialDate);
```

Pass the same four arguments to `AppointmentFormFields` as in Step 3, reading
from the add-flow state (`state.endDate ?? state.selectedDate`, and guarding
the nullable times — `isOvernight` is false when either time is null).

- [ ] **Step 5: Verify the app builds and the analyzer is clean**

```bash
flutter analyze 2>&1 | grep -E "error -|warning -"
```
Expected: no output.

- [ ] **Step 6: Run the calendar test suite**

Run: `flutter test test/features/calendar/`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/calendar/widgets/
git commit -m "feat(calendar): wire the end-date picker into both form hosts"
```

---

### Task 10: The card renders a day counter

**Files:**
- Modify: `lib/features/calendar/widgets/cards/appointment_card.dart:46-96`
- Test: `test/features/calendar/appointment_card_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('a multi-day card shows the daily window and the counter',
      (tester) async {
    final appointment = AppointmentRecord(
      id: 'a1',
      title: 'Repipe',
      startTime: DateTime(2026, 8, 1, 9),
      endTime: DateTime(2026, 8, 5, 17),
    );
    await tester.pumpWidget(
      _cardHost(
        AppointmentCard(
          appointment: appointment,
          crew: const [],
          slice: sliceFor(appointment, DateTime(2026, 8, 3)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Day 3 of 5'), findsOneWidget);
    expect(find.textContaining('9:00 AM'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a night-shift card counts nights', (tester) async {
    final appointment = AppointmentRecord(
      id: 'a2',
      title: 'Nuit',
      startTime: DateTime(2026, 8, 1, 22),
      endTime: DateTime(2026, 8, 4, 6),
    );
    await tester.pumpWidget(
      _cardHost(
        AppointmentCard(
          appointment: appointment,
          crew: const [],
          slice: sliceFor(appointment, DateTime(2026, 8, 2)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Night 2 of 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single-day card is unchanged', (tester) async {
    final appointment = AppointmentRecord(
      id: 'a3',
      title: 'Water heater',
      startTime: DateTime(2026, 8, 1, 8, 30),
      endTime: DateTime(2026, 8, 1, 10),
    );
    await tester.pumpWidget(
      _cardHost(
        AppointmentCard(
          appointment: appointment,
          crew: const [],
          slice: sliceFor(appointment, DateTime(2026, 8, 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Day 1 of 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
```

Reuse the file's existing `_cardHost` harness (`ThemeNotifier` +
localization delegates). If none exists, build one following
`.claude/rules/testing.md`.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/calendar/appointment_card_test.dart`
Expected: FAIL — `No named parameter with the name 'slice'`.

- [ ] **Step 3: Add the parameter and the label builder**

Add to the constructor and fields:

```dart
  /// This card's day within a multi-day run. Null for surfaces that show a
  /// job once (history, client job history) rather than per day.
  final AppointmentDaySlice? slice;
```

Replace the `timeLabel` assignment (lines 92-95) with:

```dart
    final timeLabel = _timeLabel(context);
```

and add the method beside `_crewLabel`:

```dart
  /// The card's mono time line, scoped to the day this card represents.
  ///
  /// The stored times are a DAILY window, so every day of a run reads the same
  /// clock — only the counter moves. "All day" is reserved for [isAllDay] and
  /// is never borrowed to describe a timed job's middle day.
  String _timeLabel(BuildContext context) {
    final l10n = context.l10n;
    final window = slice;
    final base = appointment.isAllDay
        ? l10n.calendar_allDay
        : '${DateUtilsHelper.formatTime(window?.windowStart ?? appointment.startTime)} – '
              '${DateUtilsHelper.formatTime(window?.windowEnd ?? appointment.endTime)}';
    if (window == null || !window.isMultiDay) return base;
    final counter = window.isOvernight
        ? l10n.calendar_nightOfCount(window.dayIndex, window.dayCount)
        : l10n.calendar_dayOfCount(window.dayIndex, window.dayCount);
    return '$base · $counter';
  }
```

Add the import:

```dart
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/calendar/appointment_card_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/widgets/cards/appointment_card.dart test/features/calendar/appointment_card_test.dart
git commit -m "feat(calendar): AppointmentCard renders a day-scoped window and counter"
```

---

### Task 11: The calendar indexes by slice

**Files:**
- Modify: `lib/features/calendar/screens/main_calendar_screen.dart:179-208`
- Test: `test/features/calendar/main_calendar_screen_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('a job spanning three days appears on all three', (tester) async {
    // Build the screen with a single 3-day appointment in the range provider
    // override, following the existing harness in this file.
    final appointment = AppointmentRecord(
      id: 'a1',
      title: 'Repipe',
      startTime: DateTime(2026, 8, 1, 9),
      endTime: DateTime(2026, 8, 3, 17),
    );
    await tester.pumpWidget(_calendarHost(appointments: [appointment]));
    await tester.pumpAndSettle();

    // Day 2 is not the start day, yet the agenda must list the job.
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(find.text('Repipe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
```

Reuse this file's existing host helper; if it is named differently, adapt the
call rather than adding a second harness.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/calendar/main_calendar_screen_test.dart`
Expected: FAIL — `Repipe` not found on day 2.

- [ ] **Step 3: Replace the index (lines 179-208)**

```dart
  Map<DateTime, List<AppointmentDaySlice>>? _dayIndex;
  // Remembers which appointments list _dayIndex was last built from, so we
  // know when it needs rebuilding.
  List<AppointmentRecord>? _indexedAppointments;

  /// Rebuilds [_dayIndex] only when [source] is a different list instance than
  /// the one last indexed — the index is otherwise recomputed every rebuild.
  void _refreshDayIndex(List<AppointmentRecord> source) {
    if (identical(source, _indexedAppointments)) return;
    _indexedAppointments = source;
    _dayIndex = expandToDays(
      source,
      _appointmentRange,
      onSpanClamped: (record, days) => ref
          .read(loggerProvider)
          .warn(
            'APPT-RANGE appointment ${record.id} spans $days days, past the '
            '$maxAppointmentSpanDays-day cap — showing the first '
            '$maxAppointmentSpanDays',
          ),
    );
  }

  List<AppointmentDaySlice> _getEventsForDay(DateTime day) =>
      _dayIndex?[day.dateOnly] ?? const <AppointmentDaySlice>[];
```

- [ ] **Step 4: Update the consumers**

Every call site of `_getEventsForDay` now receives slices. For the crew dots,
read `slice.appointment`. For the agenda, pass the slice straight into
`AppointmentCard(appointment: slice.appointment, slice: slice, ...)`.

Run: `grep -n "_getEventsForDay" lib/features/calendar/screens/main_calendar_screen.dart lib/features/calendar/widgets/views/*.dart`
Expected: update every match. The analyzer will flag any you miss.

- [ ] **Step 5: Run the tests**

```bash
flutter test test/features/calendar/
flutter analyze 2>&1 | grep -E "error -|warning -"
```
Expected: all PASS, no analyzer output.

- [ ] **Step 6: Commit**

```bash
git add lib/features/calendar/screens/main_calendar_screen.dart lib/features/calendar/widgets/views/ test/features/calendar/main_calendar_screen_test.dart
git commit -m "feat(calendar): grid and agenda show a job on every day it spans"
```

---

### Task 12: Full-suite verification

- [ ] **Step 1: Run the whole suite**

Run: `flutter test`
Expected: all PASS. The pre-change baseline is 1451 tests; this plan adds ~25.

- [ ] **Step 2: Analyzer**

Run: `flutter analyze 2>&1 | grep -E "error -|warning -"`
Expected: no output.

- [ ] **Step 3: Check for untranslated keys**

Run: `cat lib/l10n/.gen/untranslated.json`
Expected: `{}` or no entry for any `calendar_` / `validation_` key added here.

- [ ] **Step 4: Scan for BOMs on touched files**

Run: `for f in $(git diff --name-only HEAD~11 -- '*.dart'); do head -c 3 "$f" | od -An -tx1 | grep -q 'ef bb bf' && echo "BOM: $f"; done`
Expected: no output.

- [ ] **Step 5: Device pass**

Run the app and confirm by hand:
1. Book a 3-day job — it appears on all three days in the grid and agenda.
2. Book a 2-night job 10 PM–6 AM — it shows on both nights, and **not** on the
   morning after the last one.
3. Turn All day on for a **client** job — it saves and reads "All day".
4. Turn Personal off on an all-day block — All day **stays on**.
5. Try a 20-day span — Save is refused with the span message.

---

### Task 13: Record the invariant changes and the mirror debt

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Rewrite the all-day invariant**

Find the bullet beginning **"An all-day block (`isAllDay`) stores real
instants"**. Replace the sentence beginning `**`setPersonal(value: false)` MUST
clear `isAllDay` too**` and its explanation with:

```markdown
  **`setPersonal(value: false)` MUST NOT clear `isAllDay`.** It used to — the
  switch was personal-only, so a surviving flag saved a midnight–23:59 *client*
  visit with no switch on screen to repair it. Since multi-day (2026-08-02) the
  all-day switch is rendered on **every** job, so that state is reachable,
  repairable and legitimate: a client visit can genuinely run whole days.
  Clearing the flag now discards a deliberate choice. The travel sweep still
  skips all-day records (no departure time to compute); the overdue sweep still
  gates on `isPersonal`, so an all-day CLIENT job does go overdue after its
  23:59 end, which is correct.
```

- [ ] **Step 2: Add the multi-day invariant**

Add a new bullet immediately after it:

```markdown
- **An appointment may span up to `maxAppointmentSpanDays` (14) days, and its
  two times are a DAILY WINDOW** — 9:00 AM–5:00 PM means 9–5 on each of those
  days, not one unbroken stretch. Consequences that must stay in sync:
  **`AppointmentDaySlice` (`calendar/domain/appointment_day_slice.dart`) is the
  ONE owner of day-scoping** — `sliceFor` / `expandToDays` / `lastWorkDayOf`;
  never re-derive a day index or a run length at a call site, the way the
  `displayStatusAt` ladder and `_who` were re-derived and drifted.
  **The end date names the last day the crew STARTS work**, never the morning
  an overnight run finishes, so the count is `end − start + 1` for day jobs and
  night shifts alike; a window whose end time is at or before its start time
  crosses midnight and counts **nights**.
  **There is deliberately no end-time-after-start-time validation** — that
  ordering IS a night shift.
  **`AppointmentDateRange.fetchStart` widens the query 14 days back and must
  stay a derived getter**, never a constructor field: `==` is keyed on
  `start`/`end`, and widening at a call site instead would fork a second
  Firestore listener for the same day.
  **Slices are generated per WORK day** — each day the window begins — not per
  calendar day the stored instant span touches; that is what keeps a night
  shift off the morning it ends.
```

- [ ] **Step 3: Record the mirror debt**

Add to the same bullet:

```markdown
  **NOT YET MIRRORED (owed by Plan 2):** the home widget, the Siri snapshot,
  `notification_messages.js`, `travel_utils.js` and `widget_payload_utils.js`
  still treat every job as single-day, so days 2+ of a run are invisible there.
  See `docs/plans/2026-08-02-multi-day-appointments.md` §8.
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: record the multi-day invariants and the off-screen mirror debt"
```

---

## Self-Review

**Spec coverage** — design doc §1 decisions 1-9: §2 no-schema-change (Task 1/4),
§3 slice unit (Task 1), §4 fetch (Task 4), §5 form + validator (Tasks 2, 3, 5-9),
§6 all-day everywhere (Tasks 6, 7, 8), §7 display (Tasks 10, 11), §8 mirrors
(deferred to Plan 2, recorded in Task 13), §9 rejected options (no work), §10
open items (unchanged). Decision 2's 14-day cap appears in Tasks 1, 3, 4.

**Type consistency** — `maxAppointmentSpanDays`, `calendarDaysBetween`,
`addCalendarDays`, `lastWorkDayOf`, `dayCountOf`, `isOvernightRecord`,
`isOvernightWindow`, `sliceFor`, `expandToDays` are each defined once (Tasks 1
and 2) and used with those exact names throughout. `AppointmentDaySlice`
exposes `dayIndex`/`dayCount`/`windowStart`/`windowEnd`/`isMultiDay`/
`isOvernight`, used consistently in Tasks 10 and 11.

**Known risk flagged, not hidden** — Task 4 Step 3 notes a possible circular
import between `appointment_day_slice.dart` and `appointment_record.dart` and
gives the exact remedy. Task 9 Steps 2 and 4 depend on each host file's existing
provider accessor, which differs between the two; both steps say to adapt rather
than assume a name.
