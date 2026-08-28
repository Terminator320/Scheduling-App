import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';

void main() {
  group('AppointmentRecord', () {
    final start = DateTime(2026, 5, 9, 10);
    final end = DateTime(2026, 5, 9, 11);

    test('value equality works (freezed)', () {
      final a = AppointmentRecord(
        id: 'a1',
        title: 'Kitchen leak',
        startTime: start,
        endTime: end,
      );
      final b = AppointmentRecord(
        id: 'a1',
        title: 'Kitchen leak',
        startTime: start,
        endTime: end,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith returns a new value with updated fields', () {
      final original = AppointmentRecord(
        id: 'a1',
        title: 'old',
        startTime: start,
        endTime: end,
      );
      final updated = original.copyWith(title: 'new');

      expect(updated.id, 'a1');
      expect(updated.title, 'new');
      expect(original.title, 'old');
    });

    test('displayStatus returns terminal statuses verbatim', () {
      for (final s in ['done', 'completed', 'cancelled']) {
        final a = AppointmentRecord(
          id: 'a1',
          startTime: start,
          endTime: end,
          status: s,
        );
        expect(a.displayStatus, s);
      }
    });

    test('displayStatus shows in_progress while within the time window', () {
      final now = DateTime.now();
      final a = AppointmentRecord(
        id: 'a1',
        startTime: now.subtract(const Duration(minutes: 30)),
        endTime: now.add(const Duration(minutes: 30)),
      );
      expect(a.displayStatus, 'in_progress');
    });

    test('displayStatus shows overdue once the end time has passed', () {
      final past = DateTime.now().subtract(const Duration(hours: 2));
      final a = AppointmentRecord(
        id: 'a1',
        startTime: past,
        endTime: past.add(const Duration(hours: 1)),
      );
      expect(a.displayStatus, 'overdue');
    });

    test('displayStatus stays as configured before startTime', () {
      final future = DateTime.now().add(const Duration(hours: 1));
      final a = AppointmentRecord(
        id: 'a1',
        startTime: future,
        endTime: future.add(const Duration(hours: 1)),
        status: 'confirmed',
      );
      expect(a.displayStatus, 'confirmed');
    });

    test('toMap → fromMap roundtrip preserves DateTime fields', () {
      final original = AppointmentRecord(
        id: 'a1',
        title: 'Kitchen leak',
        startTime: start,
        endTime: end,
        clientId: 'c1',
        clientName: 'Acme',
        employeeIds: const ['e1', 'e2'],
        employeeNames: const ['Jane', 'Bob'],
      );
      final restored = AppointmentRecord.fromMap('a1', original.toMap());
      expect(restored, equals(original));
    });

    test('toMap → fromMap roundtrip preserves the repeat rule', () {
      final original = AppointmentRecord(
        id: 'a1',
        startTime: start,
        endTime: end,
        repeat: RepeatInterval.sixMonths,
        seriesId: 'series-1',
      );
      final restored = AppointmentRecord.fromMap('a1', original.toMap());
      expect(restored.repeat, RepeatInterval.sixMonths);
      expect(restored.seriesId, 'series-1');
    });

    test('toMap → fromMap roundtrip preserves the day-off flag', () {
      final original = AppointmentRecord(
        id: 'a1',
        startTime: start,
        endTime: end,
        isPersonal: true,
        isDayOff: true,
      );
      final restored = AppointmentRecord.fromMap('a1', original.toMap());
      expect(restored.isDayOff, isTrue);
      expect(restored.isTimeOff, isTrue);
    });

    test('a day off completes itself once its last day has passed', () {
      // Derived, never stored — there is no Complete button on a day off, so
      // the end of the span is what closes it.
      final dayOff = AppointmentRecord(
        id: 'a1',
        startTime: DateTime(2026, 5, 10),
        endTime: DateTime(2026, 5, 10, 23, 59),
        isPersonal: true,
        isDayOff: true,
      );
      expect(dayOff.displayStatusAt(DateTime(2026, 5, 10, 12)), 'pending');
      expect(dayOff.displayStatusAt(DateTime(2026, 5, 11)), 'done');
      // The STORED status never moves.
      expect(dayOff.status, 'pending');
    });

    test('an ordinary personal block still never derives a status', () {
      // The day-off branch must not swallow the isPersonal carve-out beneath
      // it: a dentist appointment past its end is not "done", and asking
      // "job finished?" about one is the wrong question.
      final personal = AppointmentRecord(
        id: 'a1',
        startTime: DateTime(2026, 5, 10, 9),
        endTime: DateTime(2026, 5, 10, 10),
        isPersonal: true,
      );
      expect(personal.displayStatusAt(DateTime(2026, 5, 11)), 'pending');
    });

    test('isTimeOff needs BOTH flags', () {
      // A client visit carrying a stray isDayOff — a console edit, an import —
      // must not vanish from the job counts with nothing on screen saying why.
      final strayFlag = AppointmentRecord(
        id: 'a1',
        startTime: start,
        endTime: end,
        isDayOff: true,
      );
      expect(strayFlag.isTimeOff, isFalse);
      expect(
        strayFlag.copyWith(isPersonal: true, isDayOff: false).isTimeOff,
        isFalse,
      );
    });

    test('fromMap defaults missing or unknown repeat to none', () {
      expect(
        AppointmentRecord.fromMap('a1', const {}).repeat,
        RepeatInterval.none,
      );
      expect(
        AppointmentRecord.fromMap('a1', const {'repeat': 'weekly'}).repeat,
        RepeatInterval.none,
      );
    });

    test('fromMap defaults missing required dates to now', () {
      // Required DateTime fields fall back to DateTime.now() — primarily so
      // legacy / corrupt docs still hydrate without throwing.
      final r = AppointmentRecord.fromMap('a1', const {});
      expect(r.id, 'a1');
      expect(r.title, '');
      expect(r.status, 'pending');
      expect(r.employeeIds, isEmpty);
    });

    group('run day fields', () {
      test('defaults to zero when the document carries neither', () {
        final record = AppointmentRecord.fromMap('a1', {
          'startTime': start,
          'endTime': end,
        });
        expect(record.dayIndex, 0);
        expect(record.dayCount, 0);
      });

      test('reads a stored pair', () {
        final record = AppointmentRecord.fromMap('a1', {
          'startTime': start,
          'endTime': end,
          'dayIndex': 3,
          'dayCount': 5,
        });
        expect(record.dayIndex, 3);
        expect(record.dayCount, 5);
      });

      test('a negative or unparseable value reads as zero, never throws', () {
        final record = AppointmentRecord.fromMap('a1', {
          'startTime': start,
          'endTime': end,
          'dayIndex': -2,
          'dayCount': 'five',
        });
        expect(record.dayIndex, 0);
        expect(record.dayCount, 0);
      });

      test('toMap emits the pair only for a run member', () {
        final single = AppointmentRecord(startTime: start, endTime: end);
        expect(single.toMap().containsKey('dayIndex'), isFalse);
        expect(single.toMap().containsKey('dayCount'), isFalse);

        final member = single.copyWith(dayIndex: 3, dayCount: 5);
        expect(member.toMap()['dayIndex'], 3);
        expect(member.toMap()['dayCount'], 5);
      });
    });
  });

  group('AppointmentDateRange.visibleMonth', () {
    test('starts a week before the 1st of the month', () {
      final focus = DateTime(2026, 5, 9);
      final range = AppointmentDateRange.visibleMonth(focus);
      expect(range.start, DateTime(2026, 4, 24));
    });

    test('ends a week after the 1st of the next month', () {
      final focus = DateTime(2026, 5, 9);
      final range = AppointmentDateRange.visibleMonth(focus);
      expect(range.end, DateTime(2026, 6, 8));
    });

    test('covers the maximum trail the grid can show', () {
      // The grid renders only the weeks the month occupies, so the worst trail
      // is 6 days and the ±7 window clears it by one. `month_grid_overscan_test`
      // walks every month at every week start to keep that true.
      final range = AppointmentDateRange.visibleMonth(DateTime(2026, 2, 10));
      expect(range.end.isAfter(DateTime(2026, 3, 7)), isTrue);
    });

    test('covers the maximum lead the grid can show', () {
      // 1 Aug 2026 is a Saturday: 6 lead cells reach back to 26 July.
      final range = AppointmentDateRange.visibleMonth(DateTime(2026, 8, 4));
      expect(range.start.isBefore(DateTime(2026, 7, 26)), isTrue);
    });

    test('two ranges over the same focused month are equal', () {
      final a = AppointmentDateRange.visibleMonth(DateTime(2026, 5));
      final b = AppointmentDateRange.visibleMonth(DateTime(2026, 5, 30));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('AppointmentDateRange.forCalendar', () {
    test('matches the month window while the selection is inside it', () {
      final range = AppointmentDateRange.forCalendar(
        focusedDay: DateTime(2026, 5, 9),
        selectedDay: DateTime(2026, 5, 20),
      );
      expect(range, AppointmentDateRange.visibleMonth(DateTime(2026, 5, 9)));
    });

    test('stretches back to a selection left behind by paging forward', () {
      // Paged three months on from a day picked in May: a month-only window
      // stops covering 20 May, and the agenda then reports "0 jobs" for it.
      final range = AppointmentDateRange.forCalendar(
        focusedDay: DateTime(2026, 8),
        selectedDay: DateTime(2026, 5, 20),
      );
      expect(range.start, DateTime(2026, 5, 20));
      expect(range.end, DateTime(2026, 9, 8));
    });

    test('stretches forward to a selection left behind by paging back', () {
      final range = AppointmentDateRange.forCalendar(
        focusedDay: DateTime(2026, 2),
        selectedDay: DateTime(2026, 5, 20),
      );
      expect(range.start, DateTime(2026, 1, 25));
      expect(range.end, DateTime(2026, 5, 21));
    });
  });

  group('AppointmentDateRange.forWeekBucketOf', () {
    test('every day of a bucket yields the SAME range', () {
      // The whole point: the day route re-scopes in Dart, so seven ◀/▶ taps
      // must share one listener instead of minting seven 15-day queries.
      final first = AppointmentDateRange.forWeekBucketOf(DateTime(2026, 8, 4));
      for (var i = 0; i < 7; i++) {
        final day = first.start.add(Duration(days: i));
        expect(AppointmentDateRange.forWeekBucketOf(day), first);
      }
    });

    test('spans exactly seven days', () {
      final range = AppointmentDateRange.forWeekBucketOf(DateTime(2026, 8, 4));
      expect(range.end.difference(range.start).inDays, 7);
    });

    test('an adjacent bucket is a different range', () {
      final a = AppointmentDateRange.forWeekBucketOf(DateTime(2026, 8, 4));
      final b = AppointmentDateRange.forWeekBucketOf(
        a.end.add(const Duration(days: 1)),
      );
      expect(a, isNot(b));
      expect(b.start, a.end);
    });

    test('buckets land on midnight across a DST boundary', () {
      // Drift here would both mis-bucket a day and fork a second listener for
      // the same documents, since the provider is keyed by range VALUE.
      for (final day in [DateTime(2026, 3, 8), DateTime(2026, 11)]) {
        final range = AppointmentDateRange.forWeekBucketOf(day);
        expect(range.start.hour, 0);
        expect(range.end.hour, 0);
      }
    });
  });

  group('AppointmentImage', () {
    test('value equality works', () {
      const a = AppointmentImage(url: 'u', storagePath: 'p');
      const b = AppointmentImage(url: 'u', storagePath: 'p');
      expect(a, equals(b));
    });

    test('toMap → fromMap roundtrip', () {
      final original = AppointmentImage(
        url: 'https://example.com/a.jpg',
        storagePath: 'appointments/a1/images/a.jpg',
        fileName: 'a.jpg',
        uploadedAt: DateTime(2026, 5, 9),
      );
      final restored = AppointmentImage.fromMap(original.toMap());
      expect(restored, equals(original));
    });


  });
}
