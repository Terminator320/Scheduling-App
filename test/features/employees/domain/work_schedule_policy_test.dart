import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/employees/domain/policies/work_schedule_policy.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  test('default week is Monday to Friday, Sunday-indexed', () {
    expect(kDefaultWorkingDays, [false, true, true, true, true, true, false]);
  });

  test('minutes round-trip through TimeOfDay', () {
    expect(minutesToTimeOfDay(480), const TimeOfDay(hour: 8, minute: 0));
    expect(minutesToTimeOfDay(1020), const TimeOfDay(hour: 17, minute: 0));
    expect(timeOfDayToMinutes(const TimeOfDay(hour: 17, minute: 30)), 1050);
  });

  test('out-of-range stored minutes clamp instead of throwing', () {
    expect(minutesToTimeOfDay(-5), const TimeOfDay(hour: 0, minute: 0));
    expect(minutesToTimeOfDay(5000), const TimeOfDay(hour: 23, minute: 59));
  });

  test('normalizeWorkingDays pads and truncates to seven', () {
    expect(normalizeWorkingDays([true, false]).length, 7);
    expect(normalizeWorkingDays([true, false])[0], isTrue);
    expect(normalizeWorkingDays(List.filled(9, true)).length, 7);
  });

  test('normalizeWorkingDays falls back to the default week when empty', () {
    expect(normalizeWorkingDays(const []), kDefaultWorkingDays);
  });

  group('orderedWorkingDays', () {
    // weekStart 0 = Sunday-first (en_US), 1 = Monday-first (fr_CA).
    test('Sunday-first leaves the stored order alone', () {
      final ordered = orderedWorkingDays(kDefaultWorkingDays, weekStart: 0);
      expect(ordered.map((e) => e.isWorking).toList(), kDefaultWorkingDays);
      expect(ordered.first.storedIndex, 0);
    });

    test('Monday-first rotates and keeps the stored index with each cell', () {
      final ordered = orderedWorkingDays(kDefaultWorkingDays, weekStart: 1);
      expect(ordered.first.storedIndex, 1);
      expect(ordered.first.isWorking, isTrue);
      expect(ordered.last.storedIndex, 0);
      expect(ordered.last.isWorking, isFalse);
    });
  });

  // The approved design renders the week as a phrase on the detail page; the
  // seven-cell grid survives only in the edit sheet.
  group('formatWorkingDays', () {
    late AppLocalizations l10n;
    // Sunday-indexed, matching storage AND weekdayAbbreviationsForLocale —
    // the labels never rotate, only weekStart changes.
    const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    setUp(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('a full week collapses to Every day', () {
      expect(
        formatWorkingDays(
          l10n,
          List.filled(7, true),
          weekStart: 0,
          labels: labels,
        ),
        'Every day',
      );
    });

    test('an empty week reports no days set', () {
      expect(
        formatWorkingDays(
          l10n,
          List.filled(7, false),
          weekStart: 0,
          labels: labels,
        ),
        'No working days set',
      );
    });

    test('a contiguous run becomes a range', () {
      expect(
        formatWorkingDays(
          l10n,
          kDefaultWorkingDays,
          weekStart: 0,
          labels: labels,
        ),
        'Mon – Fri',
      );
    });

    test('a broken set is listed', () {
      // Sun off, Mon on, Tue off, Wed on, Thu off, Fri on, Sat off.
      const alternating = [false, true, false, true, false, true, false];
      expect(
        formatWorkingDays(l10n, alternating, weekStart: 0, labels: labels),
        'Mon, Wed, Fri',
      );
    });

    test('a single day is just that day', () {
      const wedOnly = [false, false, false, true, false, false, false];
      expect(
        formatWorkingDays(l10n, wedOnly, weekStart: 0, labels: labels),
        'Wed',
      );
    });

    // Documented, accepted quirk: adjacency depends on where the locale puts
    // the week start. Both readings are truthful.
    test(
      'a weekend worker reads as a range only where the days are adjacent',
      () {
        const weekend = [true, false, false, false, false, false, true];
        expect(
          formatWorkingDays(l10n, weekend, weekStart: 1, labels: labels),
          'Sat – Sun',
        );
        expect(
          formatWorkingDays(l10n, weekend, weekStart: 0, labels: labels),
          'Sun, Sat',
        );
      },
    );
  });

  group('maxJobsLabel', () {
    late AppLocalizations l10n;

    setUp(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('0 is the no-cap wording, everything else is the number', () {
      // The picker's rows, the Team sheet's row and My details' row all state
      // this value; a re-spelled ternary let a change land on one screen only.
      expect(maxJobsLabel(l10n, 0), 'No cap');
      expect(maxJobsLabel(l10n, 1), '1');
      expect(maxJobsLabel(l10n, 12), '12');
    });
  });
}
