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
  });

  group('AppointmentDateRange.visibleMonth', () {
    test('starts two weeks before the 1st of the month', () {
      final focus = DateTime(2026, 5, 9);
      final range = AppointmentDateRange.visibleMonth(focus);
      expect(range.start, DateTime(2026, 4, 17));
    });

    test('ends two weeks after the 1st of the next month', () {
      final focus = DateTime(2026, 5, 9);
      final range = AppointmentDateRange.visibleMonth(focus);
      expect(range.end, DateTime(2026, 6, 15));
    });

    test('covers well past the maximum trail the grid can show', () {
      // The grid renders only the weeks the month occupies, so the real worst
      // trail is 6 days; the ±14 window is a deliberate superset.
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
      expect(range.end, DateTime(2026, 9, 15));
    });

    test('stretches forward to a selection left behind by paging back', () {
      final range = AppointmentDateRange.forCalendar(
        focusedDay: DateTime(2026, 2),
        selectedDay: DateTime(2026, 5, 20),
      );
      expect(range.start, DateTime(2026, 1, 18));
      expect(range.end, DateTime(2026, 5, 21));
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
