# Per-Day Appointments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** SHIPPED — implemented 2026-08-27, released 1.53.0+82, rules
deployed 2026-08-29 (`77c6a66f`). Design doc:
`docs/plans/2026-08-27-per-day-appointments.md`.

**Goal:** A multi-day job books as one appointment per day, so marking day 1 complete no longer closes days 2–5.

**Architecture:** Each day becomes its own Firestore document, linked by `seriesId` (day 1's doc id) and carrying a stored `dayIndex`/`dayCount`. `AppointmentDaySlice` keeps owning day-scoping — the stored pair substitutes only the *label* it reports, never the runs-on test. Time off and personal blocks keep saving as one wide document. There is no migration: production holds zero open multi-day jobs.

**Tech Stack:** Flutter/Dart 3.10.7, Riverpod 3, Freezed, Firebase (Firestore + Cloud Functions on Node 24), jest, flutter_test.

**Design doc:** `docs/plans/2026-08-27-per-day-appointments.md` — read it before starting.

---

## File structure

**Dart — domain (pure, tested without Firebase):**
- `lib/features/calendar/domain/models/appointment_record.dart` — the two new fields, `fromMap`, `toMap`.
- `lib/features/calendar/domain/appointment_day_slice.dart` — the label substitution and the new run-expansion helper. Stays the ONE owner of day-scoping.

**Dart — application:**
- `lib/features/calendar/application/add_event_controller.dart` — expands a run into N records before writing.
- `lib/features/calendar/application/event_details_controller.dart` — cancel gains a scope.
- `lib/features/calendar/data/firebase_appointments_repository.dart` + `lib/features/calendar/domain/appointments_repository.dart` — batch status write.

**Dart — widgets:**
- `lib/features/calendar/widgets/sections/appointment_form_fields.dart` — hide repeat on multi-day, hide end date on a run member.
- `lib/features/calendar/widgets/fields/appointment_date_rows.dart` — a `showEndDate` flag.
- `lib/features/calendar/widgets/views/details_edit_body.dart` — run-flavoured scope copy on save and delete.
- `lib/features/calendar/widgets/views/details_view_body.dart` — cancel scope.
- `lib/features/calendar/widgets/dialogs/delete_appointment_dialog.dart` — run-flavoured delete copy.
- `lib/features/calendar/widgets/dialogs/cancel_appointment_dialog.dart` — **new**, the cancel twin of the delete dialog.

**Server:**
- `functions/day_slice_utils.js` — the same label substitution.
- `firestore.rules` — bounds on the two new fields.

**l10n:** `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`.

---

### Task 1: Store `dayIndex` and `dayCount` on the record

**Files:**
- Modify: `lib/features/calendar/domain/models/appointment_record.dart`
- Test: `test/features/calendar/appointment_record_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/features/calendar/appointment_record_test.dart` (inside the top-level `main()`):

```dart
  group('run day fields', () {
    test('defaults to zero when the document carries neither', () {
      final record = AppointmentRecord.fromMap('a1', {
        'startTime': Timestamp.fromDate(DateTime(2026, 8, 3, 9)),
        'endTime': Timestamp.fromDate(DateTime(2026, 8, 3, 17)),
      });
      expect(record.dayIndex, 0);
      expect(record.dayCount, 0);
    });

    test('reads a stored pair', () {
      final record = AppointmentRecord.fromMap('a1', {
        'startTime': Timestamp.fromDate(DateTime(2026, 8, 5, 9)),
        'endTime': Timestamp.fromDate(DateTime(2026, 8, 5, 17)),
        'dayIndex': 3,
        'dayCount': 5,
      });
      expect(record.dayIndex, 3);
      expect(record.dayCount, 5);
    });

    test('a negative or unparseable value reads as zero, never throws', () {
      final record = AppointmentRecord.fromMap('a1', {
        'startTime': Timestamp.fromDate(DateTime(2026, 8, 5, 9)),
        'endTime': Timestamp.fromDate(DateTime(2026, 8, 5, 17)),
        'dayIndex': -2,
        'dayCount': 'five',
      });
      expect(record.dayIndex, 0);
      expect(record.dayCount, 0);
    });

    test('toMap emits the pair only for a run member', () {
      final single = AppointmentRecord(
        startTime: DateTime(2026, 8, 3, 9),
        endTime: DateTime(2026, 8, 3, 17),
      );
      expect(single.toMap().containsKey('dayIndex'), isFalse);
      expect(single.toMap().containsKey('dayCount'), isFalse);

      final member = single.copyWith(dayIndex: 3, dayCount: 5);
      expect(member.toMap()['dayIndex'], 3);
      expect(member.toMap()['dayCount'], 5);
    });
  });
```

That file already exists — append the group, do not recreate it. Add the
`package:cloud_firestore/cloud_firestore.dart` import if `Timestamp` is not
already in scope there.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/calendar/appointment_record_test.dart`
Expected: FAIL — `The getter 'dayIndex' isn't defined for the class 'AppointmentRecord'`.

- [ ] **Step 3: Add the fields**

In `lib/features/calendar/domain/models/appointment_record.dart`, add these two parameters to the `const factory AppointmentRecord({...})` list, immediately after the `@Default('') String seriesId,` line:

```dart
    // This document's 1-based position in its multi-day RUN, and how many days
    // that run covers. A run is N documents sharing a [seriesId]; each is ONE
    // day, so this pair is the only thing that knows the run is longer than
    // the document.
    //
    // Zero on every single-day job and on the legacy WIDE documents written
    // before the split (three of them in production as of 2026-08-27), where
    // `startTime`/`endTime` still span the whole run and `AppointmentDaySlice`
    // derives the pair from that span. Zero is therefore not "missing data" —
    // it is the signal to derive, and `sliceFor` owns that branch.
    //
    // Read it through [AppointmentDaySlice.sliceFor], never directly: the
    // substitution rule has coherence guards this field cannot carry.
    @Default(0) int dayIndex,
    @Default(0) int dayCount,
```

In `fromMap`, add these two lines immediately after the `seriesId:` line:

```dart
      dayIndex: _parseCount(data['dayIndex']),
      dayCount: _parseCount(data['dayCount']),
```

In `toMap`, add these two entries immediately after `'seriesId': seriesId,`:

```dart
    // Omitted on a single-day job so the document stays as it always was, and
    // so an ordinary edit's `.update()` cannot write a 0 over a run member's
    // real pair.
    if (dayCount > 1) 'dayIndex': dayIndex,
    if (dayCount > 1) 'dayCount': dayCount,
```

- [ ] **Step 4: Regenerate Freezed and run the test**

Run: `dart run build_runner build --delete-conflicting-outputs`
Then: `flutter test test/features/calendar/appointment_record_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify the analyzer is still clean**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/calendar/domain/models/appointment_record.dart lib/features/calendar/domain/models/appointment_record.freezed.dart test/features/calendar/appointment_record_test.dart
git commit -m "feat(calendar): store dayIndex/dayCount on an appointment"
```

---

### Task 2: `sliceFor` substitutes the stored label only

**Files:**
- Modify: `lib/features/calendar/domain/appointment_day_slice.dart`
- Test: `test/features/calendar/domain/appointment_day_slice_test.dart`

The stored pair must reach the CARD and nothing else. `_dayIndexOn` answers two questions with one pair — "does this run on this day" and "what does the card say" — and only the second may be substituted. See the design doc's "The substitution is the LABEL only" section.

- [ ] **Step 1: Write the failing test**

Append to `test/features/calendar/domain/appointment_day_slice_test.dart` inside `main()`:

```dart
  group('stored run label', () {
    AppointmentRecord dayThreeOfFive() => AppointmentRecord(
      id: 'd3',
      startTime: DateTime(2026, 8, 5, 9),
      endTime: DateTime(2026, 8, 5, 17),
      seriesId: 'd1',
      dayIndex: 3,
      dayCount: 5,
    );

    test('a split day reports its stored position', () {
      final slice = sliceFor(dayThreeOfFive(), DateTime(2026, 8, 5));
      expect(slice, isNotNull);
      expect(slice!.dayIndex, 3);
      expect(slice.dayCount, 5);
      expect(slice.isMultiDay, isTrue);
    });

    test('the stored pair does NOT widen which days it runs on', () {
      final record = dayThreeOfFive();
      // The regression this guard exists for: reading dayCount 5 into the
      // range test would smear one document across five days, and runsOn is
      // the mandated re-scoping call on the drawer badge, the roster count
      // and the dashboard.
      expect(runsOn(record, DateTime(2026, 8, 5)), isTrue);
      expect(runsOn(record, DateTime(2026, 8, 6)), isFalse);
      expect(runsOn(record, DateTime(2026, 8, 9)), isFalse);
      expect(sliceFor(record, DateTime(2026, 8, 6)), isNull);
    });

    test('the window stays this day only', () {
      final slice = sliceFor(dayThreeOfFive(), DateTime(2026, 8, 5))!;
      expect(slice.windowStart, DateTime(2026, 8, 5, 9));
      expect(slice.windowEnd, DateTime(2026, 8, 5, 17));
    });

    test('a legacy wide document still derives its pair', () {
      final wide = AppointmentRecord(
        id: 'w1',
        startTime: DateTime(2026, 8, 3, 9),
        endTime: DateTime(2026, 8, 7, 17),
      );
      final slice = sliceFor(wide, DateTime(2026, 8, 5))!;
      expect(slice.dayIndex, 3);
      expect(slice.dayCount, 5);
    });

    test('an incoherent stored pair falls back to the derived one', () {
      final broken = AppointmentRecord(
        id: 'b1',
        startTime: DateTime(2026, 8, 5, 9),
        endTime: DateTime(2026, 8, 5, 17),
        dayIndex: 9,
        dayCount: 5,
      );
      final slice = sliceFor(broken, DateTime(2026, 8, 5))!;
      expect(slice.dayIndex, 1);
      expect(slice.dayCount, 1);
    });

    test('a stored pair on a WIDE document is ignored', () {
      // Only a console write can produce this. Honouring it would print the
      // same "Day 3 of 5" on all five days of the span.
      final wide = AppointmentRecord(
        id: 'w2',
        startTime: DateTime(2026, 8, 3, 9),
        endTime: DateTime(2026, 8, 7, 17),
        dayIndex: 3,
        dayCount: 5,
      );
      expect(sliceFor(wide, DateTime(2026, 8, 3))!.dayIndex, 1);
      expect(sliceFor(wide, DateTime(2026, 8, 5))!.dayIndex, 3);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/calendar/domain/appointment_day_slice_test.dart`
Expected: FAIL — the first test reports `dayIndex` as 1, not 3.

- [ ] **Step 3: Implement the substitution**

In `lib/features/calendar/domain/appointment_day_slice.dart`, replace the body of `sliceFor` with:

```dart
AppointmentDaySlice? sliceFor(AppointmentRecord appointment, DateTime day) {
  final index = _dayIndexOn(appointment, day);
  if (index == null) return null;
  final label = _storedRunLabel(appointment) ?? index;
  return _sliceAt(
    appointment,
    day: day.dateOnly,
    index: label.dayIndex,
    count: label.dayCount,
  );
}

/// The run position a SPLIT day carries on the document, or null when the
/// derived pair should be used instead.
///
/// **This is the LABEL only.** [_dayIndexOn] keeps owning "does this run on
/// this day", and must never see these numbers: a document storing
/// `dayCount: 5` would then claim to run on the five days after its own start,
/// smearing every run across the calendar — and `runsOn` is the mandated
/// re-scoping call on the drawer badge, the roster's jobs-today and the
/// dashboard's day reducer, so all three would inherit it.
///
/// Three conditions, each closing a different way a bad pair could render:
///  - the document's OWN window is one day. A wide document is a legacy or
///    console-written run whose span is the truth; honouring a stored pair
///    there prints the same "Day 3 of 5" on every day of the span.
///  - the pair is coherent (`1 <= dayIndex <= dayCount`), so a console edit
///    cannot produce "Day 9 of 5".
///  - the count is a real run within the cap, so it agrees with every other
///    day-scoping answer about how long a run may be.
({int dayIndex, int dayCount})? _storedRunLabel(AppointmentRecord a) {
  if (a.dayCount < 2 || a.dayCount > maxAppointmentSpanDays) return null;
  if (a.dayIndex < 1 || a.dayIndex > a.dayCount) return null;
  if (_clampedDayCount(a.startTime, a.endTime) != 1) return null;
  return (dayIndex: a.dayIndex, dayCount: a.dayCount);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/calendar/domain/appointment_day_slice_test.dart`
Expected: PASS, all tests in the file.

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/domain/appointment_day_slice.dart test/features/calendar/domain/appointment_day_slice_test.dart
git commit -m "feat(calendar): a split day reports its stored run position"
```

---

### Task 3: The run-expansion helper

**Files:**
- Modify: `lib/features/calendar/domain/appointment_day_slice.dart`
- Test: `test/features/calendar/domain/appointment_day_slice_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/features/calendar/domain/appointment_day_slice_test.dart` inside `main()`:

```dart
  group('expandRunWindows', () {
    test('a one-day window yields one pair unchanged', () {
      final windows = expandRunWindows(
        DateTime(2026, 8, 3, 9),
        DateTime(2026, 8, 3, 17),
      );
      expect(windows, hasLength(1));
      expect(windows.single.start, DateTime(2026, 8, 3, 9));
      expect(windows.single.end, DateTime(2026, 8, 3, 17));
    });

    test('a 5-day 9-to-5 window yields five one-day windows', () {
      final windows = expandRunWindows(
        DateTime(2026, 8, 3, 9),
        DateTime(2026, 8, 7, 17),
      );
      expect(windows, hasLength(5));
      expect(windows.first.start, DateTime(2026, 8, 3, 9));
      expect(windows.first.end, DateTime(2026, 8, 3, 17));
      expect(windows.last.start, DateTime(2026, 8, 7, 9));
      expect(windows.last.end, DateTime(2026, 8, 7, 17));
    });

    test('a night shift yields one window per NIGHT, ending the morning after',
        () {
      // 22:00 Aug 3 -> 06:00 Aug 5 is two nights: the end date names the last
      // day the crew STARTS work, so the run is Aug 3 and Aug 4.
      final windows = expandRunWindows(
        DateTime(2026, 8, 3, 22),
        DateTime(2026, 8, 5, 6),
      );
      expect(windows, hasLength(2));
      expect(windows.first.start, DateTime(2026, 8, 3, 22));
      expect(windows.first.end, DateTime(2026, 8, 4, 6));
      expect(windows.last.start, DateTime(2026, 8, 4, 22));
      expect(windows.last.end, DateTime(2026, 8, 5, 6));
    });

    test('an all-day multi-day block yields one midnight-to-23:59 window a day',
        () {
      final windows = expandRunWindows(
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 4, 23, 59),
      );
      expect(windows, hasLength(2));
      expect(windows.first.start, DateTime(2026, 8, 3));
      expect(windows.first.end, DateTime(2026, 8, 3, 23, 59));
      expect(windows.last.start, DateTime(2026, 8, 4));
      expect(windows.last.end, DateTime(2026, 8, 4, 23, 59));
    });

    test('a span past the cap clamps to maxAppointmentSpanDays', () {
      final windows = expandRunWindows(
        DateTime(2026, 8, 3, 9),
        DateTime(2027, 3, 12, 17),
      );
      expect(windows, hasLength(maxAppointmentSpanDays));
    });

    test('a corrupt pair whose end precedes its start yields one window', () {
      final windows = expandRunWindows(
        DateTime(2026, 8, 7, 9),
        DateTime(2026, 8, 3, 17),
      );
      expect(windows, hasLength(1));
      expect(windows.single.start, DateTime(2026, 8, 7, 9));
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/calendar/domain/appointment_day_slice_test.dart`
Expected: FAIL — `The function 'expandRunWindows' isn't defined`.

- [ ] **Step 3: Implement it**

Append to `lib/features/calendar/domain/appointment_day_slice.dart`:

```dart
/// A booked daily window split into ONE window per work day.
///
/// The create path's half of the day-scoping rules: [sliceFor] takes a wide
/// document apart for rendering, this takes a form's resolved span apart for
/// WRITING, and both have to agree about what a day of a run is. It lives here
/// rather than in the controller for that reason — a second spelling of "which
/// days does this run on" is the drift this file exists to prevent.
///
/// Each returned window carries the same time of day as the original,
/// composed as LOCAL wall clock (`DateTime(y, m, d, hour, minute)`), so a run
/// crossing a DST shift stays 9-to-5 on every day rather than sliding an hour.
/// An overnight window ends the following calendar morning, which is why the
/// count is nights rather than days for one.
///
/// Always returns at least one window, and never more than
/// [maxAppointmentSpanDays] — a corrupt pair whose end precedes its start
/// books the single day it started on rather than nothing at all.
List<({DateTime start, DateTime end})> expandRunWindows(
  DateTime start,
  DateTime end,
) {
  final count = _clampedDayCount(start, end);
  final days = count < 1 ? 1 : count;
  final firstDay = start.dateOnly;
  return [
    for (var i = 0; i < days; i++) _windowOn(addCalendarDays(firstDay, i), start, end),
  ];
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/calendar/domain/appointment_day_slice_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/domain/appointment_day_slice.dart test/features/calendar/domain/appointment_day_slice_test.dart
git commit -m "feat(calendar): expandRunWindows splits a booked span per work day"
```

---

### Task 4: The add flow writes one document per day

**Files:**
- Modify: `lib/features/calendar/application/add_event_controller.dart`
- Test: `test/features/calendar/add_event_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Open `test/features/calendar/add_event_controller_test.dart`, find the existing fake repository, and confirm it records the list passed to `addAppointments`. If it does not, add a `List<AppointmentRecord> addedBatch = [];` field assigned in that override. Then append inside `main()`:

```dart
  group('multi-day runs', () {
    test('a 3-day job writes three linked one-day documents', () async {
      final repo = FakeAppointmentsRepository();
      final container = buildContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(
        addEventControllerProvider(null).notifier,
      );

      await fillValidForm(
        notifier,
        date: DateTime(2026, 8, 3),
        endDate: DateTime(2026, 8, 5),
        start: const TimeOfDay(hour: 9, minute: 0),
        end: const TimeOfDay(hour: 17, minute: 0),
      );
      final outcome = await notifier.submit();

      expect(outcome, isA<AddEventSubmitted>());
      expect(repo.addedBatch, hasLength(3));

      final anchor = repo.addedBatch.first;
      expect(anchor.seriesId, anchor.id);
      for (var i = 0; i < 3; i++) {
        final day = repo.addedBatch[i];
        expect(day.seriesId, anchor.id, reason: 'every day shares the run id');
        expect(day.dayIndex, i + 1);
        expect(day.dayCount, 3);
        expect(day.startTime, DateTime(2026, 8, 3 + i, 9));
        expect(day.endTime, DateTime(2026, 8, 3 + i, 17));
        expect(day.status, 'pending');
      }
      expect(
        repo.addedBatch.map((a) => a.id).toSet(),
        hasLength(3),
        reason: 'each day is its own document',
      );
    });

    test('a one-day job still writes a single unlinked document', () async {
      final repo = FakeAppointmentsRepository();
      final container = buildContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(
        addEventControllerProvider(null).notifier,
      );

      await fillValidForm(
        notifier,
        date: DateTime(2026, 8, 3),
        endDate: DateTime(2026, 8, 3),
        start: const TimeOfDay(hour: 9, minute: 0),
        end: const TimeOfDay(hour: 17, minute: 0),
      );
      await notifier.submit();

      expect(repo.added, hasLength(1));
      expect(repo.added.single.seriesId, '');
      expect(repo.added.single.dayCount, 0);
    });

    test('a multi-day PERSONAL block stays one wide document', () async {
      final repo = FakeAppointmentsRepository();
      final container = buildContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(
        addEventControllerProvider(null).notifier,
      );

      notifier.setPersonal(true);
      await fillValidForm(
        notifier,
        date: DateTime(2026, 8, 3),
        endDate: DateTime(2026, 8, 7),
        start: const TimeOfDay(hour: 9, minute: 0),
        end: const TimeOfDay(hour: 17, minute: 0),
      );
      await notifier.submit();

      expect(repo.added, hasLength(1));
      expect(repo.added.single.startTime, DateTime(2026, 8, 3, 9));
      expect(repo.added.single.endTime, DateTime(2026, 8, 7, 17));
      expect(repo.added.single.dayCount, 0);
    });
  });
```

Adapt `buildContainer` / `fillValidForm` / `FakeAppointmentsRepository` to whatever the file already calls them — do not introduce a second harness.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/calendar/add_event_controller_test.dart`
Expected: FAIL — one document written instead of three.

- [ ] **Step 3: Implement the expansion**

In `lib/features/calendar/application/add_event_controller.dart`, add this
import beside the other calendar domain imports:

```dart
import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
```

Leave the `final appointment = AppointmentRecord(...)` construction exactly as
it is — including its `seriesId: repeat == RepeatInterval.none ? '' : docId`,
which still owns the repeat case. Then replace everything from the comment
`// The conflict check only covers the first occurrence` down to and including
the `return AddEventSubmitted(appointment, futureBookings: copies.length);`
line with this single block:

```dart
      // A multi-day JOB books one document per day, so each day carries its
      // own status and marking day 1 complete cannot close the rest. A
      // PERSONAL block does not split: nothing marks a day off complete, and a
      // fortnight of holiday fanned into 14 independently-cancellable rows
      // makes the clash alert and the availability reducer read 14 documents
      // where they now read one span.
      //
      // The run is linked by `seriesId` = day 1's doc id, the SAME field a
      // repeat uses. Safe only because the repeat picker is hidden on a
      // multi-day form, and it earns the push dedupe for free:
      // `diffAppointmentForNotifications` suppresses the "assigned" push for
      // any created document whose seriesId is not its own id, so a 5-day run
      // notifies the crew ONCE.
      final runWindows = isPersonal
          ? [(start: start, end: end)]
          : expandRunWindows(start, end);
      final dayCount = runWindows.length;

      final days = [
        for (var i = 0; i < dayCount; i++)
          appointment.copyWith(
            id: i == 0 ? docId : repo.newDocId(),
            startTime: runWindows[i].start,
            endTime: runWindows[i].end,
            // Overrides the repeat seed above only for a real run; a one-day
            // job keeps whatever the repeat picker chose.
            seriesId: dayCount > 1 ? docId : appointment.seriesId,
            // Zero on a single-day job, so its document is written exactly as
            // it always was and `sliceFor` keeps deriving its label.
            dayIndex: dayCount > 1 ? i + 1 : 0,
            dayCount: dayCount > 1 ? dayCount : 0,
          ),
      ];

      // A one-day job may still repeat; a multi-day one cannot, so these two
      // never both produce documents. The conflict check above already covered
      // every day of the run — it takes the whole span and filters through
      // `dailyWindowsOverlap` — but it still only covers the FIRST repeat
      // occurrence, exactly as before.
      final repeatCopies = dayCount > 1
          ? const <AppointmentRecord>[]
          : [
              for (final copyStart in repeat.occurrenceStartsAfter(start))
                days.first.copyWith(
                  id: repo.newDocId(),
                  startTime: copyStart,
                  endTime: occurrenceEnd(
                    originalStart: start,
                    originalEnd: end,
                    copyStart: copyStart,
                  ),
                ),
            ];

      final toWrite = [...days, ...repeatCopies];
      if (toWrite.length == 1) {
        await repo.addAppointment(toWrite.single);
      } else {
        await repo.addAppointments(toWrite);
      }

      // Photos stay on day 1: `images` is a per-document subcollection, and
      // photos taken on day 3 attach to day 3's own document afterwards.
      if (images.isNotEmpty) {
        uploader.uploadInBackground(appointmentId: docId, newImages: images);
      }

      return AddEventSubmitted(days.first, futureBookings: toWrite.length - 1);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/calendar/add_event_controller_test.dart`
Expected: PASS — including every pre-existing repeat test in the file.

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/application/add_event_controller.dart test/features/calendar/add_event_controller_test.dart
git commit -m "feat(calendar): a multi-day job books one appointment per day"
```

---

### Task 5: Hide the repeat picker on a multi-day form

**Files:**
- Modify: `lib/features/calendar/widgets/sections/appointment_form_fields.dart`
- Test: `test/features/calendar/widgets/sections/appointment_form_fields_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/features/calendar/widgets/sections/appointment_form_fields_test.dart`. It already exists and already has a local pump helper — reuse it rather than adding a second one; the name below is a placeholder for whatever that helper is called.

```dart
  testWidgets('the repeat picker is hidden once the job spans days', (
    tester,
  ) async {
    await pumpFormFields(
      tester,
      selectedDate: DateTime(2026, 8, 3),
      endDate: DateTime(2026, 8, 5),
    );
    expect(find.byType(RepeatIntervalPicker), findsNothing);
  });

  testWidgets('the repeat picker is offered on a one-day job', (tester) async {
    await pumpFormFields(
      tester,
      selectedDate: DateTime(2026, 8, 3),
      endDate: DateTime(2026, 8, 3),
    );
    expect(find.byType(RepeatIntervalPicker), findsOneWidget);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/calendar/widgets/sections/appointment_form_fields_test.dart`
Expected: FAIL — the picker is found on the multi-day form.

- [ ] **Step 3: Add the condition**

In `lib/features/calendar/widgets/sections/appointment_form_fields.dart`, replace:

```dart
            // --- Repeat: same panel as the date and times, so everything
            // about when the job happens reads as one block. Not offered on a
            // personal job.
            if (!isPersonal)
```

with:

```dart
            // --- Repeat: same panel as the date and times, so everything
            // about when the job happens reads as one block. Not offered on a
            // personal job.
            //
            // Nor on a MULTI-DAY one. A run's days are linked by `seriesId`,
            // the same field a repeat uses, so a repeating multi-day job would
            // make that field mean two things at once and force a third state
            // into the scope dialog ("the rest of this run" vs "this and
            // future weeks"). Owner call 2026-08-27: the business does not
            // book repeating multi-day work, so the ambiguity is removed
            // rather than modelled. Adding it back means a separate `runId`,
            // never overloading `seriesId` further.
            if (!isPersonal && !isMultiDay)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/calendar/widgets/sections/appointment_form_fields_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/widgets/sections/appointment_form_fields.dart test/features/calendar/widgets/sections/appointment_form_fields_test.dart
git commit -m "feat(calendar): no repeat picker on a multi-day job"
```

---

### Task 6: The run's length is fixed after booking

**Files:**
- Modify: `lib/features/calendar/widgets/fields/appointment_date_rows.dart`
- Modify: `lib/features/calendar/widgets/sections/appointment_form_fields.dart`
- Test: `test/features/calendar/widgets/sections/appointment_form_fields_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()`:

```dart
  testWidgets('a run member does not offer an end date', (tester) async {
    await pumpFormFields(
      tester,
      selectedDate: DateTime(2026, 8, 5),
      endDate: DateTime(2026, 8, 5),
      isRunMember: true,
    );
    expect(find.text('End date'), findsNothing);
  });

  testWidgets('an ordinary job still offers an end date', (tester) async {
    await pumpFormFields(
      tester,
      selectedDate: DateTime(2026, 8, 5),
      endDate: DateTime(2026, 8, 5),
    );
    expect(find.text('End date'), findsOneWidget);
  });
```

Add an `isRunMember` parameter (defaulting to `false`) to the local `pumpFormFields` helper, forwarded to `AppointmentFormFields`. Use whatever string the end-date row's label actually renders — check `calendar_endDate` in `lib/l10n/app_en.arb` and match it exactly.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/calendar/widgets/sections/appointment_form_fields_test.dart`
Expected: FAIL — `isRunMember` is not a parameter of `AppointmentFormFields`.

- [ ] **Step 3: Add the flag through both widgets**

In `lib/features/calendar/widgets/fields/appointment_date_rows.dart`, add to the constructor parameter list (after `this.endTrailingLabel,`):

```dart
    this.showEndDate = true,
```

and as a field after `endTrailingLabel`:

```dart
  /// Whether the END date row is offered at all.
  ///
  /// False on a member of a multi-day RUN: each day is its own appointment, so
  /// there is no end date to move — the run's length is fixed at booking
  /// (owner call 2026-08-27). Shortening a run is cancelling its tail through
  /// the scope dialog; extending it is a second booking. The alternative,
  /// letting day 1 reshape the run, deletes and recreates the trailing
  /// documents and so destroys exactly the per-day statuses and photos the
  /// split exists to create.
  final bool showEndDate;
```

In that file's `build`, the end row is rendered in BOTH branches of the
narrow/wide layout, so the flag has to short-circuit ahead of them. Replace:

```dart
        // Start and end share one row until the screen is too narrow to read
        // both. The dropdown spans the full panel either way — it belongs to
        // the pair, not to one half of the row.
        if (context.isNarrowWidth) ...[
```

with:

```dart
        // Start and end share one row until the screen is too narrow to read
        // both. The dropdown spans the full panel either way — it belongs to
        // the pair, not to one half of the row.
        //
        // A run member has no end row in either layout, so the test comes
        // first: each day of a run IS one appointment, and its length is not
        // editable.
        if (!widget.showEndDate)
          startRow
        else if (context.isNarrowWidth) ...[
```

Nothing else in the file changes — `_open` can only ever become `_OpenRow.end`
by tapping a row that is no longer built, and `InlineMonthCalendar` below reads
the same `_open`.

In `lib/features/calendar/widgets/sections/appointment_form_fields.dart`, add a `required this.isRunMember,` constructor parameter with the field:

```dart
  /// This appointment is one day of a multi-day RUN. The edit form then hides
  /// the end date (the run's length is fixed at booking) — the add form never
  /// sets it.
  final bool isRunMember;
```

and pass it through in `_dateRows`:

```dart
        showEndDate: !isRunMember,
```

Then update both call sites. In `lib/features/calendar/widgets/sheets/add_appointment_sheet.dart` pass `isRunMember: false`. In `lib/features/calendar/widgets/views/details_edit_body.dart` pass `isRunMember: widget.appointment.dayCount > 1`.

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/features/calendar/widgets/sections/appointment_form_fields_test.dart`
Expected: PASS.
Run: `flutter analyze`
Expected: `No issues found!` — if a call site was missed it fails here with a missing-argument error.

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/widgets/fields/appointment_date_rows.dart lib/features/calendar/widgets/sections/appointment_form_fields.dart lib/features/calendar/widgets/sheets/add_appointment_sheet.dart lib/features/calendar/widgets/views/details_edit_body.dart test/features/calendar/widgets/sections/appointment_form_fields_test.dart
git commit -m "feat(calendar): a run member's length is fixed after booking"
```

---

### Task 7: Run-flavoured copy for the edit and delete scope dialogs

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_fr.arb`
- Modify: `lib/features/calendar/widgets/views/details_edit_body.dart`
- Modify: `lib/features/calendar/widgets/dialogs/delete_appointment_dialog.dart`

The dialog widget itself needs no change — it is fully parameterized by labels.

- [ ] **Step 1: Add the EN keys**

In `lib/l10n/app_en.arb`, add beside the existing `calendar_editThisVisitOnly` block:

```json
  "calendar_runDayLabel": "DAY {index} OF {count}",
  "@calendar_runDayLabel": {
    "description": "Mono all-caps context label at the top of the scope dialog for one day of a multi-day run, e.g. DAY 3 OF 5.",
    "placeholders": { "index": { "type": "int" }, "count": { "type": "int" } }
  },
  "calendar_editThisDayOnly": "Save this day only",
  "@calendar_editThisDayOnly": {
    "description": "Edit dialog option: apply the edit to only the opened day of a multi-day run"
  },
  "calendar_editThisAndFollowingDays": "Save this and the following days",
  "@calendar_editThisAndFollowingDays": {
    "description": "Edit dialog option: apply the edit to the opened day plus the rest of the run"
  },
  "calendar_thisDayKeepsRun": "{date} — the rest of the run keeps its old details",
  "@calendar_thisDayKeepsRun": {
    "description": "Consequence line under the this-day-only option in the run-scope dialog.",
    "placeholders": { "date": { "type": "String" } }
  },
  "calendar_remainingDaysThrough": "{count, plural, =1{1 remaining day through {date}} other{{count} remaining days through {date}}}",
  "@calendar_remainingDaysThrough": {
    "description": "Consequence line under the this-and-following option in the run-scope dialog.",
    "placeholders": { "count": { "type": "int" }, "date": { "type": "String" } }
  },
  "calendar_saveThisDay": "Save this day",
  "@calendar_saveThisDay": {
    "description": "Primary button label in the run-scope dialog when only this day is selected."
  },
  "calendar_saveNDays": "{count, plural, =1{Save 1 day} other{Save {count} days}}",
  "@calendar_saveNDays": {
    "description": "Primary button label in the run-scope dialog when this day and the following ones are selected.",
    "placeholders": { "count": { "type": "int" } }
  },
  "calendar_deleteThisDayOnly": "Delete this day only",
  "@calendar_deleteThisDayOnly": {
    "description": "Delete dialog option: delete only the opened day of a multi-day run"
  },
  "calendar_deleteThisAndFollowingDays": "Delete this and the following days",
  "@calendar_deleteThisAndFollowingDays": {
    "description": "Delete dialog option: delete the opened day plus the rest of the run"
  },
  "calendar_deleteRunScopeMessage": "Delete this day only, or this day and the rest of the run?",
  "@calendar_deleteRunScopeMessage": {
    "description": "Body of the delete dialog for one day of a multi-day run"
  },
  "calendar_cancelThisDayOnly": "Cancel this day only",
  "@calendar_cancelThisDayOnly": {
    "description": "Cancel dialog option: cancel only the opened day of a multi-day run"
  },
  "calendar_cancelThisAndFollowingDays": "Cancel this and the following days",
  "@calendar_cancelThisAndFollowingDays": {
    "description": "Cancel dialog option: cancel the opened day plus the rest of the run"
  },
  "calendar_cancelRunScopeMessage": "Cancel this day only, or this day and the rest of the run?",
  "@calendar_cancelRunScopeMessage": {
    "description": "Body of the cancel dialog for one day of a multi-day run"
  },
```

- [ ] **Step 2: Add the FR keys**

In `lib/l10n/app_fr.arb`, add (values only — the template owns the metadata). **Type the accented characters directly; never `\u` escapes.**

```json
  "calendar_runDayLabel": "JOUR {index} SUR {count}",
  "calendar_editThisDayOnly": "Enregistrer cette journée uniquement",
  "calendar_editThisAndFollowingDays": "Enregistrer cette journée et les suivantes",
  "calendar_thisDayKeepsRun": "{date} — le reste du chantier garde ses anciens détails",
  "calendar_remainingDaysThrough": "{count, plural, =1{1 journée restante jusqu'au {date}} other{{count} journées restantes jusqu'au {date}}}",
  "calendar_saveThisDay": "Enregistrer cette journée",
  "calendar_saveNDays": "{count, plural, =1{Enregistrer 1 journée} other{Enregistrer {count} journées}}",
  "calendar_deleteThisDayOnly": "Supprimer cette journée uniquement",
  "calendar_deleteThisAndFollowingDays": "Supprimer cette journée et les suivantes",
  "calendar_deleteRunScopeMessage": "Supprimer cette journée uniquement, ou cette journée et le reste du chantier ?",
  "calendar_cancelThisDayOnly": "Annuler cette journée uniquement",
  "calendar_cancelThisAndFollowingDays": "Annuler cette journée et les suivantes",
  "calendar_cancelRunScopeMessage": "Annuler cette journée uniquement, ou cette journée et le reste du chantier ?",
```

- [ ] **Step 3: Regenerate and confirm no drift**

The repo has a hook that runs `flutter gen-l10n` on an ARB edit — do not run it manually. Confirm the result:

Run: `cat lib/l10n/.gen/untranslated.json`
Expected: none of the new keys appear.
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Use the run copy on save**

In `lib/features/calendar/widgets/views/details_edit_body.dart`, inside `_resolveSeriesScope`, replace the `showSeriesScopeDialog(...)` call with:

```dart
    // A run member and a repeat occurrence take the same dialog with different
    // words: one is "the rest of this job", the other "the visits after this
    // one". They can never both apply — the repeat picker is hidden on a
    // multi-day form.
    final isRun = appointment.dayCount > 1;
    final choice = await showSeriesScopeDialog(
      context,
      title: context.l10n.calendar_applyChangesTo,
      contextLabel: isRun
          ? context.l10n.calendar_runDayLabel(
              appointment.dayIndex,
              appointment.dayCount,
            )
          : context.l10n.calendar_repeatsEveryLabel(
              repeatIntervalLabel(context.l10n, state.repeat).toUpperCase(),
            ),
      thisOnlyLabel: isRun
          ? context.l10n.calendar_editThisDayOnly
          : context.l10n.calendar_editThisVisitOnly,
      thisAndFutureLabel: isRun
          ? context.l10n.calendar_editThisAndFollowingDays
          : context.l10n.calendar_editThisAndFutureVisits,
      thisOnlyDetail: isRun
          ? context.l10n.calendar_thisDayKeepsRun(
              DateUtilsHelper.formatDate(appointment.startTime),
            )
          : context.l10n.calendar_thisVisitKeepsSeries(
              DateUtilsHelper.formatDate(appointment.startTime),
            ),
      thisAndFutureDetail: outlook.last == null
          ? null
          : (isRun
                ? context.l10n.calendar_remainingDaysThrough(
                    outlook.count,
                    DateUtilsHelper.formatDate(outlook.last!),
                  )
                : context.l10n.calendar_remainingVisitsThrough(
                    outlook.count,
                    DateUtilsHelper.formatDate(outlook.last!),
                  )),
      primaryLabelFor: (choice) => switch ((isRun, choice)) {
        (true, SeriesScopeChoice.thisOnly) => context.l10n.calendar_saveThisDay,
        (true, _) => context.l10n.calendar_saveNDays(outlook.count),
        (false, SeriesScopeChoice.thisOnly) =>
          context.l10n.calendar_saveThisVisit,
        (false, _) => context.l10n.calendar_saveNVisits(outlook.count),
      },
    );
```

- [ ] **Step 5: Use the run copy on delete**

In `lib/features/calendar/widgets/dialogs/delete_appointment_dialog.dart`, replace the whole function with:

```dart
/// Shows a delete confirmation for appointments.
///
/// One day of a multi-day RUN and one occurrence of a repeat both offer
/// 'this one only' or 'this and the ones after it', in their own words. A null
/// result means the user cancelled.
Future<SeriesScopeChoice?> showDeleteAppointmentDialog(
  BuildContext context, {
  required bool isSeries,
  bool isRun = false,
}) async {
  final l = context.l10n;
  if (!isSeries) {
    final confirmed = await showConfirmDialog(
      context,
      title: l.calendar_deleteAppointment,
      message: l.calendar_areYouSureYouWantToDeleteThisJob,
      confirmLabel: l.common_delete,
    );
    return confirmed ? SeriesScopeChoice.thisOnly : null;
  }
  return showSeriesScopeDialog(
    context,
    title: l.calendar_deleteAppointment,
    thisOnlyLabel: isRun
        ? l.calendar_deleteThisDayOnly
        : l.calendar_deleteThisVisitOnly,
    thisAndFutureLabel: isRun
        ? l.calendar_deleteThisAndFollowingDays
        : l.calendar_deleteThisAndFutureVisits,
    // The scope IS the verb here, so this site keeps its own copy rather than
    // switching the label on the selection.
    primaryLabelFor: (_) => l.calendar_deleteAppointment,
    thisOnlyDetail: isRun
        ? l.calendar_deleteRunScopeMessage
        : l.calendar_deleteSeriesScopeMessage,
    destructive: true,
  );
}
```

Then at its call site in `details_edit_body.dart` (around line 441), pass the new flag:

```dart
      isRun: widget.appointment.dayCount > 1,
```

- [ ] **Step 6: Pin the run copy against overflow**

The run labels are the longest strings the dialog renders in either language
("Enregistrer cette journée et les suivantes"), and the dialog puts a
consequence line under each. Create
`test/features/calendar/widgets/dialogs/series_scope_dialog_overflow_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/series_scope_dialog.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Local harness — there is deliberately no shared `_scaledHarness` in this
/// repo; each file owns its own. 260 logical px is the usual worst case, and
/// 2x text is what turns a comfortable label into an overflow.
Widget _harness({required Widget child, Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(body: child),
      ),
    );

void main() {
  for (final locale in const [Locale('en'), Locale('fr')]) {
    testWidgets('the run scope dialog does not overflow in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(260, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _harness(
          locale: locale,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSeriesScopeDialog(
                context,
                title: context.l10n.calendar_applyChangesTo,
                contextLabel: context.l10n.calendar_runDayLabel(3, 5),
                thisOnlyLabel: context.l10n.calendar_editThisDayOnly,
                thisAndFutureLabel:
                    context.l10n.calendar_editThisAndFollowingDays,
                thisOnlyDetail: context.l10n.calendar_thisDayKeepsRun(
                  '5 August 2026',
                ),
                thisAndFutureDetail: context.l10n.calendar_remainingDaysThrough(
                  3,
                  '7 August 2026',
                ),
                primaryLabelFor: (_) => context.l10n.calendar_saveNDays(3),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
```

Run: `flutter test test/features/calendar/widgets/dialogs/series_scope_dialog_overflow_test.dart`
Expected: PASS. A `FlutterError` naming a `RenderFlex` overflow means a label
needs shortening in the ARB — fix the string, not the test.

- [ ] **Step 7: Run the calendar tests and the analyzer**

Run: `flutter test test/features/calendar`
Expected: PASS.
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_fr.arb lib/features/calendar/widgets/views/details_edit_body.dart lib/features/calendar/widgets/dialogs/delete_appointment_dialog.dart test/features/calendar/widgets/dialogs/series_scope_dialog_overflow_test.dart
git commit -m "feat(calendar): run-flavoured copy for the edit and delete scope dialogs"
```

---

### Task 8: Cancelling a day can take the rest of the run

**Files:**
- Modify: `lib/features/calendar/domain/appointments_repository.dart`
- Modify: `lib/features/calendar/data/firebase_appointments_repository.dart`
- Test: `test/features/calendar/firebase_appointments_repository_status_test.dart`

This is the one genuinely new write path. Repository half first.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/features/calendar/firebase_appointments_repository_status_test.dart`, using the file's existing `FakeFirebaseFirestore` harness:

```dart
  group('updateAppointmentStatuses', () {
    test('writes the status to every id in one batch', () async {
      final repo = buildRepository();
      await seedAppointment(repo, id: 'd1', status: 'pending');
      await seedAppointment(repo, id: 'd2', status: 'pending');
      await seedAppointment(repo, id: 'd3', status: 'pending');

      await repo.updateAppointmentStatuses(
        ids: ['d1', 'd2'],
        status: 'cancelled',
      );

      expect(await statusOf(repo, 'd1'), 'cancelled');
      expect(await statusOf(repo, 'd2'), 'cancelled');
      expect(await statusOf(repo, 'd3'), 'pending');
    });

    test('rejects a status off the allowlist', () {
      final repo = buildRepository();
      expect(
        () => repo.updateAppointmentStatuses(ids: ['d1'], status: 'overdue'),
        throwsArgumentError,
      );
    });

    test('an empty id list writes nothing', () async {
      final repo = buildRepository();
      await seedAppointment(repo, id: 'd1', status: 'pending');
      await repo.updateAppointmentStatuses(ids: [], status: 'cancelled');
      expect(await statusOf(repo, 'd1'), 'pending');
    });
  });
```

Match `buildRepository` / `seedAppointment` / `statusOf` to the helpers the file already has.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/calendar/firebase_appointments_repository_status_test.dart`
Expected: FAIL — `The method 'updateAppointmentStatuses' isn't defined`.

- [ ] **Step 3: Add the interface method**

In `lib/features/calendar/domain/appointments_repository.dart`, add immediately after the existing `updateAppointmentStatus` declaration:

```dart
  /// Writes one status across several appointments in a single batch.
  ///
  /// The run half of a cancel: cancelling day 3 of a 5-day job with "this and
  /// the following days" has to close days 3, 4 and 5 together. One batch, so
  /// a partial run cannot be left half-cancelled.
  Future<void> updateAppointmentStatuses({
    required List<String> ids,
    required String status,
  });
```

- [ ] **Step 4: Implement it**

In `lib/features/calendar/data/firebase_appointments_repository.dart`, add after `updateAppointmentStatus`:

```dart
  @override
  Future<void> updateAppointmentStatuses({
    required List<String> ids,
    required String status,
  }) async {
    final trimmed = status.trim();
    if (!_allowedStatuses.contains(trimmed)) {
      throw ArgumentError.value(
        status,
        'status',
        'must be one of $_allowedStatuses',
      );
    }
    if (ids.isEmpty) return;
    // One shared op id, so the whole batch coalesces into ONE push instead of
    // one per day — the same claim `updateAppointments` and `rewriteSeries`
    // make. Minted for a cancel only, matching `updateAppointmentStatus`.
    final opId = _newSeriesOpId();
    final batch = _appointments.firestore.batch();
    for (final id in ids) {
      batch.update(_appointments.doc(id), {
        'status': trimmed,
        if (trimmed == 'cancelled') 'seriesOpId': opId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    _invalidateSearchCache();
  }
```

- [ ] **Step 5: Update every other implementation of the interface**

Run: `flutter analyze`
Expected: errors naming each fake/mock repository in `test/` that is now missing the method. Add this override to each one it names, following that file's existing style:

```dart
  @override
  Future<void> updateAppointmentStatuses({
    required List<String> ids,
    required String status,
  }) async {
    for (final id in ids) {
      await updateAppointmentStatus(id: id, status: status);
    }
  }
```

Re-run `flutter analyze` until it reports `No issues found!`.

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test test/features/calendar/firebase_appointments_repository_status_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/calendar/domain/appointments_repository.dart lib/features/calendar/data/firebase_appointments_repository.dart test/
git commit -m "feat(calendar): batch status write for cancelling a run's tail"
```

---

### Task 9: The cancel action offers the run scope

**Files:**
- Modify: `lib/features/calendar/application/event_details_controller.dart`
- Create: `lib/features/calendar/widgets/dialogs/cancel_appointment_dialog.dart`
- Modify: `lib/features/calendar/widgets/views/details_view_body.dart`
- Test: `test/features/calendar/event_details_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/features/calendar/event_details_controller_test.dart`:

```dart
  group('per-day completion', () {
    test('marking one day done leaves the rest of the run untouched', () async {
      final repo = FakeAppointmentsRepository();
      final run = [
        for (var i = 1; i <= 5; i++)
          AppointmentRecord(
            id: 'd$i',
            seriesId: 'd1',
            dayIndex: i,
            dayCount: 5,
            startTime: DateTime(2026, 8, 2 + i, 9),
            endTime: DateTime(2026, 8, 2 + i, 17),
          ),
      ];
      repo.seedSeries('d1', run);
      final container = buildContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(
        eventDetailsControllerProvider(EventDetailsKey(run[2])).notifier,
      );

      final outcome = await notifier.markAsDone(run[2]);

      expect(outcome, isA<EventDetailsActionOk>());
      expect(repo.statuses['d3'], 'done');
      // THE regression this whole change exists to prevent. Do not delete.
      expect(repo.statuses['d1'], isNull);
      expect(repo.statuses['d2'], isNull);
      expect(repo.statuses['d4'], isNull);
      expect(repo.statuses['d5'], isNull);
    });

    test('cancelling with the run scope closes this day and the ones after',
        () async {
      final repo = FakeAppointmentsRepository();
      final run = [
        for (var i = 1; i <= 5; i++)
          AppointmentRecord(
            id: 'd$i',
            seriesId: 'd1',
            dayIndex: i,
            dayCount: 5,
            startTime: DateTime(2026, 8, 2 + i, 9),
            endTime: DateTime(2026, 8, 2 + i, 17),
          ),
      ];
      repo.seedSeries('d1', run);
      final container = buildContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(
        eventDetailsControllerProvider(EventDetailsKey(run[2])).notifier,
      );

      final outcome = await notifier.cancelAppointment(
        run[2],
        includeFuture: true,
      );

      expect(outcome, isA<EventDetailsActionOk>());
      expect(repo.statuses['d3'], 'cancelled');
      expect(repo.statuses['d4'], 'cancelled');
      expect(repo.statuses['d5'], 'cancelled');
      expect(repo.statuses['d1'], isNull);
      expect(repo.statuses['d2'], isNull);
    });

    test('cancelling without the run scope closes only this day', () async {
      final repo = FakeAppointmentsRepository();
      final run = [
        for (var i = 1; i <= 3; i++)
          AppointmentRecord(
            id: 'd$i',
            seriesId: 'd1',
            dayIndex: i,
            dayCount: 3,
            startTime: DateTime(2026, 8, 2 + i, 9),
            endTime: DateTime(2026, 8, 2 + i, 17),
          ),
      ];
      repo.seedSeries('d1', run);
      final container = buildContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(
        eventDetailsControllerProvider(EventDetailsKey(run[0])).notifier,
      );

      await notifier.cancelAppointment(run[0]);

      expect(repo.statuses['d1'], 'cancelled');
      expect(repo.statuses['d2'], isNull);
      expect(repo.statuses['d3'], isNull);
    });

    test('a second cancel while one is in flight is skipped, not queued',
        () async {
      final repo = FakeAppointmentsRepository();
      final single = AppointmentRecord(
        id: 'x1',
        startTime: DateTime(2026, 8, 5, 9),
        endTime: DateTime(2026, 8, 5, 17),
      );
      final container = buildContainer(repo);
      addTearDown(container.dispose);
      final notifier = container.read(
        eventDetailsControllerProvider(EventDetailsKey(single)).notifier,
      )..setSaving(busy: true);

      expect(
        await notifier.cancelAppointment(single),
        isA<EventDetailsActionBusy>(),
      );
    });
  });
```

Add `Map<String, String> statuses` and a `seedSeries` method to the file's fake repository if they are not there, recording `updateAppointmentStatus` and `updateAppointmentStatuses` writes and backing `getSeries`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/calendar/event_details_controller_test.dart`
Expected: FAIL — `cancelAppointment` takes no `includeFuture` argument.

- [ ] **Step 3: Give cancel a scope**

In `lib/features/calendar/application/event_details_controller.dart`, replace `cancelAppointment` with:

```dart
  /// Writes `status: 'cancelled'`. With [includeFuture], also cancels the
  /// non-terminal days of this run that come after it, in one batch.
  ///
  /// Mark-done deliberately has no such option: closing one day and leaving
  /// the rest open is the entire reason a run is separate documents.
  Future<EventDetailsActionOutcome> cancelAppointment(
    AppointmentRecord appointment, {
    bool includeFuture = false,
  }) async {
    final id = appointment.id;
    if (id == null) {
      return EventDetailsActionFailed(StateError('appointment has no id'));
    }
    if (!includeFuture || appointment.seriesId.isEmpty) {
      return _setStatusOnRepo(appointment, 'cancelled');
    }
    // Same reentrancy guard the single-document path uses, set synchronously
    // before the first await so a double-tap cannot pay for getSeries and the
    // batch twice.
    if (state.isSaving) return const EventDetailsActionBusy();
    state = state.copyWith(isSaving: true);
    // Resolved before the first await — Riverpod 3 throws on `ref.read` from
    // an unmounted consumer.
    final repo = ref.read(appointmentsRepositoryProvider);
    final logger = ref.read(loggerProvider);
    try {
      final series = await repo.getSeries(appointment.seriesId);
      final futureIds = futureSeriesIds(
        series,
        excludeId: id,
        after: appointment.startTime,
      );
      await repo.updateAppointmentStatuses(
        ids: [id, ...futureIds],
        status: 'cancelled',
      );
      if (ref.mounted) state = state.copyWith(isSaving: false);
      return const EventDetailsActionOk();
    } catch (e, st) {
      logger.warn('APPT-STATUS cancel run tail failed', e, st);
      if (ref.mounted) state = state.copyWith(isSaving: false);
      return EventDetailsActionFailed(e);
    }
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/calendar/event_details_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Add the cancel dialog**

Create `lib/features/calendar/widgets/dialogs/cancel_appointment_dialog.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:scheduling/features/calendar/widgets/dialogs/series_scope_dialog.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';

/// Shows a cancel confirmation for an appointment.
///
/// The twin of `showDeleteAppointmentDialog`, and separate from it for the
/// same reason the two actions are separate: cancelling keeps the job in
/// history, deleting does not. One day of a multi-day RUN offers the run
/// scope; anything else is a plain confirm. A null result means the user
/// backed out.
Future<SeriesScopeChoice?> showCancelAppointmentDialog(
  BuildContext context, {
  required bool isRun,
}) async {
  final l = context.l10n;
  if (!isRun) {
    final confirmed = await showConfirmDialog(
      context,
      title: l.calendar_cancelAppointment,
      message: l.calendar_cancelledJobsAreSavedToHistory,
      confirmLabel: l.calendar_cancelAppointment,
    );
    return confirmed ? SeriesScopeChoice.thisOnly : null;
  }
  return showSeriesScopeDialog(
    context,
    title: l.calendar_cancelAppointment,
    thisOnlyLabel: l.calendar_cancelThisDayOnly,
    thisAndFutureLabel: l.calendar_cancelThisAndFollowingDays,
    // The scope IS the verb here, so this site keeps one label rather than
    // switching it on the selection — same shape as the delete dialog.
    primaryLabelFor: (_) => l.calendar_cancelAppointment,
    thisOnlyDetail: l.calendar_cancelRunScopeMessage,
    destructive: true,
  );
}
```

- [ ] **Step 6: Wire it into the detail view**

In `lib/features/calendar/widgets/views/details_view_body.dart`, add the import:

```dart
import 'package:scheduling/features/calendar/widgets/dialogs/cancel_appointment_dialog.dart';
```

and replace the body of `_onCancel` with:

```dart
    final choice = await showCancelAppointmentDialog(
      context,
      isRun: appointment.dayCount > 1,
    );
    if (choice == null || !context.mounted) return;
    final outcome = await notifier.cancelAppointment(
      appointment,
      includeFuture: choice == SeriesScopeChoice.thisAndFuture,
    );
    if (!context.mounted) return;
    _onStatusOutcome(
      context,
      ref,
      outcome,
      successMessage: context.l10n.common_appointmentCancelled,
    );
```

Add the `series_scope_dialog.dart` import if `SeriesScopeChoice` is not already in scope, and drop the now-unused `showConfirmDialog` import if nothing else in the file uses it.

- [ ] **Step 7: Run the calendar tests and the analyzer**

Run: `flutter test test/features/calendar`
Expected: PASS.
Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add lib/features/calendar/application/event_details_controller.dart lib/features/calendar/widgets/dialogs/cancel_appointment_dialog.dart lib/features/calendar/widgets/views/details_view_body.dart test/features/calendar/event_details_controller_test.dart
git commit -m "feat(calendar): cancelling a run day can take the rest of the run"
```

---

### Task 10: Mirror the label substitution server-side

**Files:**
- Modify: `functions/day_slice_utils.js`
- Test: `functions/__tests__/day_slice_utils.test.js`

The Dart and JS day-slice rules are hand-mirrored and their tests share worked examples on purpose. Task 2's rule has to land here or the widget, the Siri snapshot and the push text will disagree with the card about which day of a run a document is.

- [ ] **Step 1: Write the failing test**

Append to `functions/__tests__/day_slice_utils.test.js`:

```js
describe("stored run label", () => {
  const dayThreeOfFive = () => ({
    startTime: new Date("2026-08-05T13:00:00Z"),
    endTime: new Date("2026-08-05T21:00:00Z"),
    seriesId: "d1",
    dayIndex: 3,
    dayCount: 5,
  });
  const aug5 = new Date("2026-08-05T16:00:00Z").getTime();
  const aug6 = new Date("2026-08-06T16:00:00Z").getTime();

  test("a split day reports its stored position", () => {
    const slice = sliceForDay(dayThreeOfFive(), aug5);
    expect(slice.dayIndex).toBe(3);
    expect(slice.dayCount).toBe(5);
    expect(slice.isMultiDay).toBe(true);
  });

  test("the stored pair does not widen which days it runs on", () => {
    expect(sliceForDay(dayThreeOfFive(), aug6)).toBeNull();
  });

  test("dayCountOf still reports the document's own length", () => {
    // travel_utils gates the Live Activity on this being 1, so a split day
    // must read as a one-day job and get its own card.
    expect(dayCountOf(dayThreeOfFive())).toBe(1);
  });

  test("a legacy wide document still derives its pair", () => {
    const wide = {
      startTime: new Date("2026-08-03T13:00:00Z"),
      endTime: new Date("2026-08-07T21:00:00Z"),
    };
    const slice = sliceForDay(wide, aug5);
    expect(slice.dayIndex).toBe(3);
    expect(slice.dayCount).toBe(5);
  });

  test("an incoherent stored pair falls back to the derived one", () => {
    const broken = {...dayThreeOfFive(), dayIndex: 9};
    const slice = sliceForDay(broken, aug5);
    expect(slice.dayIndex).toBe(1);
    expect(slice.dayCount).toBe(1);
  });

  test("a stored pair on a WIDE document is ignored", () => {
    const wide = {
      startTime: new Date("2026-08-03T13:00:00Z"),
      endTime: new Date("2026-08-07T21:00:00Z"),
      dayIndex: 3,
      dayCount: 5,
    };
    expect(sliceForDay(wide, new Date("2026-08-03T16:00:00Z").getTime())
        .dayIndex).toBe(1);
  });
});
```

Add `dayCountOf` to the file's existing `require` destructuring if it is not already imported.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd functions && npx jest __tests__/day_slice_utils.test.js`
Expected: FAIL — the first test reports `dayIndex` as 1.

- [ ] **Step 3: Implement the substitution**

In `functions/day_slice_utils.js`, add before `sliceForDay`:

```js
/**
 * The run position a SPLIT day carries on the document, or null when the
 * derived pair should be used.
 *
 * Hand-mirror of `_storedRunLabel` in
 * `lib/features/calendar/domain/appointment_day_slice.dart` — change both
 * together; the jest cases here reuse that suite's worked examples so a
 * divergence fails rather than ships.
 *
 * **The LABEL only.** The index/range test below stays derived: reading a
 * stored `dayCount: 5` into it would make one document claim to run on the
 * five days after its own start, and the widget probes every record against
 * every day of its window.
 * @param {!Object} r
 * @param {!{startMs: number, endMs: number, overnight: boolean}} w The
 *   already-resolved window, threaded in rather than re-resolved — see the
 *   window-taking rule at the top of this module.
 * @return {?{dayIndex: number, dayCount: number}}
 */
function storedRunLabel(r, w) {
  const index = Number(r.dayIndex);
  const count = Number(r.dayCount);
  if (!Number.isInteger(index) || !Number.isInteger(count)) return null;
  if (count < 2 || count > MAX_APPOINTMENT_SPAN_DAYS) return null;
  if (index < 1 || index > count) return null;
  // A wide document is a legacy or console-written run whose SPAN is the
  // truth; honouring a stored pair there prints one day's label on all of them.
  if (dayCountOfWindow(w) !== 1) return null;
  return {dayIndex: index, dayCount: count};
}
```

Then in `sliceForDay`, after the existing `if (index < 1 || index > count) return null;` line, insert:

```js
  const label = storedRunLabel(r, w) || {dayIndex: index, dayCount: count};
```

and change the returned object's two fields to read from it:

```js
    dayIndex: label.dayIndex,
    dayCount: label.dayCount,
    ...
    isMultiDay: label.dayCount > 1,
```

leaving `windowStartMs`, `windowEndMs` and `isOvernight` exactly as they are.

- [ ] **Step 4: Run the tests and the linter**

Run: `cd functions && npx jest __tests__/day_slice_utils.test.js`
Expected: PASS.
Run: `cd functions && npm test`
Expected: the full jest suite passes.
Run: `cd functions && npm run lint`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add functions/day_slice_utils.js functions/__tests__/day_slice_utils.test.js
git commit -m "feat(functions): mirror the stored run label in day_slice_utils"
```

---

### Task 11: Bound the new fields in the rules

**Files:**
- Modify: `firestore.rules`
- Test: `test/core/security/appointment_span_rules_test.dart`

The security tests here read `firestore.rules` back **as text** — Dart and CEL
cannot share a constant, so a text assertion is the only mechanism keeping the
two equal (`text_limits_test.dart` and `self_service_rules_test.dart` police
their hand-mirrors the same way). There is no emulator in this suite; do not
introduce one.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/core/security/appointment_span_rules_test.dart`,
reusing the `rules` and `bodyOf` helpers already declared at the top of it:

```dart
  group('the run day fields are bounded, not merely type-checked', () {
    // `dayIndex`/`dayCount` are what a card reads to say "Day 3 of 5". An
    // `is int` alone would let a client write "Day 900 of 4000" — the Dart
    // `_storedRunLabel` and JS `storedRunLabel` both refuse an incoherent
    // pair, but the rules are the last line of defence.
    test('both fields are present in the appointment validator', () {
      final body = bodyOf('isValidAppointmentData') ?? '';
      expect(body, contains('dayIndex'));
      expect(body, contains('dayCount'));
    });

    test('each is an int floored at 1', () {
      final body = bodyOf('isValidAppointmentData') ?? '';
      expect(body, contains('d.dayIndex is int'));
      expect(body, contains('d.dayIndex >= 1'));
      expect(body, contains('d.dayCount is int'));
      expect(body, contains('d.dayCount >= 1'));
    });

    test('each is capped at maxAppointmentSpanDays', () {
      // A run can never have more days than its span may cover, so this cap
      // and isValidAppointmentSpan's move together.
      final body = bodyOf('isValidAppointmentData') ?? '';
      expect(body, contains('d.dayIndex <= $maxAppointmentSpanDays'));
      expect(body, contains('d.dayCount <= $maxAppointmentSpanDays'));
    });

    test('both stay optional, so an ordinary job still saves', () {
      // The appointment validator has no `hasOnly`; every clause is
      // absent-or-valid. A required field here would reject every one-day job
      // and every document written before the split.
      final body = bodyOf('isValidAppointmentData') ?? '';
      expect(body, contains("!('dayIndex' in d.keys())"));
      expect(body, contains("!('dayCount' in d.keys())"));
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/security/appointment_span_rules_test.dart`
Expected: FAIL — `Expected: contains 'dayIndex'`.

- [ ] **Step 3: Add the bounds**

In `firestore.rules`, inside `isValidAppointmentData(d)`, add these clauses
immediately before the final `employeeNames` clause, keeping the `&&` chain
intact:

```
        // A day of a multi-day RUN: N documents sharing a seriesId, each one
        // day long, linked by this pair. Bounded rather than merely
        // type-checked so a client cannot write "Day 900 of 4000" — the Dart
        // `_storedRunLabel` and the JS `storedRunLabel` both refuse an
        // incoherent pair, but the rules are the last line of defence and an
        // unbounded int here would reach every read surface's model.
        //
        // The cap is `maxAppointmentSpanDays` in
        // `lib/features/calendar/domain/appointment_day_slice.dart` — the same
        // 14 `isValidAppointmentSpan` bounds, so a run can never have more days
        // than its span may cover. Pinned as text by
        // `appointment_span_rules_test.dart`; the two caps move together.
        //
        // Absent-or-valid like every clause here: the validator has no
        // `hasOnly`, and a required field would reject every one-day job and
        // every document written before the split.
        && (!('dayIndex' in d.keys())
            || (d.dayIndex is int && d.dayIndex >= 1 && d.dayIndex <= 14))
        && (!('dayCount' in d.keys())
            || (d.dayCount is int && d.dayCount >= 1 && d.dayCount <= 14))
```

- [ ] **Step 4: Run the security tests**

Run: `flutter test test/core/security`
Expected: PASS, including the pre-existing span and status tests.

- [ ] **Step 5: Commit**

```bash
git add firestore.rules test/core/security/appointment_span_rules_test.dart
git commit -m "feat(rules): bound the run day fields on an appointment"
```

---

### Task 12: Record the rules in the docs that own them

**Files:**
- Modify: `.claude/rules/appointments.md`
- Modify: `docs/plans/2026-08-27-per-day-appointments.md`

- [ ] **Step 1: Add the rule**

In `.claude/rules/appointments.md`, immediately after the bullet beginning **"An appointment may span up to `maxAppointmentSpanDays` (14) days"**, add:

```markdown
- **A multi-day JOB is N appointments, one per day; a multi-day PERSONAL block
  is still ONE wide document.** (2026-08-27, designed in
  `docs/plans/2026-08-27-per-day-appointments.md`.) One document carries one
  `status`, so a wide job closed entirely when the crew marked day 1 complete.
  The days of a run share `seriesId` — day 1's doc id, the SAME field a repeat
  uses — and each carries a stored `dayIndex`/`dayCount`. That overload is safe
  only because **the repeat picker is hidden on a multi-day form**; the two
  mechanics must never coexist, or "this and the following" means two things.
  Re-adding repeating multi-day work means a separate `runId`, never another
  meaning for `seriesId`.
  **The stored pair is the LABEL ONLY, and that is the whole trap.**
  `_dayIndexOn` answers both "does this run on this day" and "what does the
  card say"; feeding a stored `dayCount: 5` into the first makes day 3's
  document claim the five days after its own start, and `runsOn` is the
  mandated re-scoping call on the drawer badge, the roster's jobs-today and the
  dashboard's day reducer, so all three inherit it at once. `sliceFor`
  substitutes into the slice it RETURNS; `_dayIndexOn` stays purely derived.
  The substitution additionally requires the document's own window to be one
  day, so a stored pair on a legacy wide doc cannot print one day's label on
  all of them. Hand-mirrored by `storedRunLabel` in
  `functions/day_slice_utils.js`; the two test suites share worked examples.
  **`AppointmentDaySlice` is NOT legacy.** It stays the live representation for
  time off and personal blocks, which deliberately do not split — nothing marks
  a day off complete, and a fortnight of holiday fanned into 14
  independently-cancellable rows makes the clash alert and the availability
  reducer read 14 documents where they now read one span.
  **A run's LENGTH is fixed at booking** (the end-date row is hidden on a run
  member): shortening is cancelling the tail through the scope dialog,
  extending is a second booking. Letting day 1 reshape the run through
  `rewrite` would delete and recreate the trailing documents, destroying
  exactly the per-day statuses and photos the split exists to create.
  **Mark-complete never asks scope**; edit, cancel and delete all do, through
  the same `SeriesScopeDialog` with run-flavoured copy.
  Photos stay on day 1 of a run (the `images` subcollection belongs to one
  document); photos taken on day 3 attach to day 3's own document.
  No migration was needed — prod held ZERO open multi-day jobs on 2026-08-27
  (`functions/scripts/count-multi-day-appointments.js`), and the three wide
  documents that exist keep rendering through the derived branch.
```

- [ ] **Step 2: Mark the design doc implemented**

In `docs/plans/2026-08-27-per-day-appointments.md`, change the header line:

```markdown
**Status:** designed, not implemented
```

to:

```markdown
**Status:** implemented 2026-08-27; not yet deployed (rules) or shipped (app)
```

- [ ] **Step 3: Full verification**

Run: `flutter analyze`
Expected: `No issues found!`
Run: `flutter test`
Expected: all pass.
Run: `cd functions && npm run lint && npm test`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add .claude/rules/appointments.md docs/plans/2026-08-27-per-day-appointments.md
git commit -m "docs(calendar): record the per-day appointment rules"
```

---

## After the plan

`firestore.rules` needs deploying before an app build that writes the new fields — a write carrying `dayIndex`/`dayCount` is rejected by the live rules until then. Follow `docs/DEPLOYMENT.md`: backend first, then the app build. `firestore.indexes.json` is unchanged, and no function signature moved, so this is a rules-only deploy:

```
firebase deploy --only firestore:rules
```

Re-run `node functions/scripts/count-multi-day-appointments.js` immediately before shipping. If it now reports open multi-day WORK runs, they were booked between the design and the release; let them finish as wide documents or rebook them by hand.
