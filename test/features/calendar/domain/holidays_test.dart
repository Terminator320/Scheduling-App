import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/holidays.dart';

/// `y-m-d` as a bare local date, matching what the calendar hands in.
DateTime _d(int y, int m, int day) => DateTime(y, m, day);

/// Every holiday name landing on [day], in the order the module emits them.
List<HolidayName> _namesOn(DateTime day) =>
    holidaysOn(day).map((h) => h.name).toList();

void main() {
  // ---------------------------------------------------------------------
  // The two computus algorithms. These are the only non-trivial arithmetic
  // in the module and the only part that can drift silently, so both are
  // pinned by a table of known dates rather than a single spot check.
  // ---------------------------------------------------------------------
  group('gregorianEaster', () {
    // Published Western Easter Sundays.
    const known = {
      2024: [3, 31],
      2025: [4, 20],
      2026: [4, 5],
      2027: [3, 28],
      2028: [4, 16],
      2029: [4, 1],
      2030: [4, 21],
      2031: [4, 13],
      2032: [3, 28],
      2033: [4, 17],
      2034: [4, 9],
      2035: [3, 25],
    };

    for (final entry in known.entries) {
      test('${entry.key} falls on ${entry.value[0]}/${entry.value[1]}', () {
        expect(
          gregorianEaster(entry.key),
          _d(entry.key, entry.value[0], entry.value[1]),
        );
      });
    }

    test('always lands on a Sunday', () {
      for (var year = 2020; year <= 2060; year++) {
        expect(
          gregorianEaster(year).weekday,
          DateTime.sunday,
          reason: 'Gregorian Easter $year',
        );
      }
    });
  });

  group('orthodoxEaster', () {
    // Published Orthodox Pascha, already converted to the Gregorian calendar.
    const known = {
      2024: [5, 5],
      2025: [4, 20],
      2026: [4, 12],
      2027: [5, 2],
      2028: [4, 16],
      2029: [4, 8],
      2030: [4, 28],
      2031: [4, 13],
      2032: [5, 2],
      2033: [4, 24],
      2034: [4, 9],
      2035: [4, 29],
    };

    for (final entry in known.entries) {
      test('${entry.key} falls on ${entry.value[0]}/${entry.value[1]}', () {
        expect(
          orthodoxEaster(entry.key),
          _d(entry.key, entry.value[0], entry.value[1]),
        );
      });
    }

    test('always lands on a Sunday', () {
      for (var year = 2020; year <= 2060; year++) {
        expect(
          orthodoxEaster(year).weekday,
          DateTime.sunday,
          reason: 'Orthodox Easter $year',
        );
      }
    });

    test('never falls before the Gregorian one', () {
      for (var year = 2020; year <= 2060; year++) {
        expect(
          orthodoxEaster(year).isBefore(gregorianEaster(year)),
          isFalse,
          reason: 'Orthodox Easter $year',
        );
      }
    });
  });

  // ---------------------------------------------------------------------
  // The nth-weekday and shifting rules. Each of these is a case where the
  // obvious implementation is wrong in some years but right in the one you
  // would spot-check.
  // ---------------------------------------------------------------------
  group('Journée nationale des patriotes', () {
    test('is the Monday STRICTLY BEFORE May 25, so 2026 is the 18th', () {
      // May 25 2026 is itself a Monday. "On or before" would give the 25th.
      expect(_d(2026, 5, 25).weekday, DateTime.monday);
      expect(_namesOn(_d(2026, 5, 18)), contains(HolidayName.patriotes));
      expect(_namesOn(_d(2026, 5, 25)), isNot(contains(HolidayName.patriotes)));
    });

    test('is the Monday before May 25 when the 25th is not a Monday', () {
      expect(_d(2027, 5, 25).weekday, DateTime.tuesday);
      expect(_namesOn(_d(2027, 5, 24)), contains(HolidayName.patriotes));
    });

    test('always lands on a Monday within May 18-24', () {
      for (var year = 2020; year <= 2060; year++) {
        final day = holidaysForYear(
          year,
        ).firstWhere((h) => h.name == HolidayName.patriotes).date;
        expect(day.weekday, DateTime.monday, reason: 'patriotes $year');
        expect(day.month, DateTime.may, reason: 'patriotes $year');
        expect(day.day, inInclusiveRange(18, 24), reason: 'patriotes $year');
      }
    });
  });

  group('Fête du Canada', () {
    test('is July 1 in an ordinary year', () {
      expect(_namesOn(_d(2026, 7, 1)), contains(HolidayName.canadaDay));
    });

    test('shifts to July 2 when July 1 falls on a Sunday', () {
      expect(_d(2029, 7, 1).weekday, DateTime.sunday);
      expect(_namesOn(_d(2029, 7, 1)), isNot(contains(HolidayName.canadaDay)));
      expect(_namesOn(_d(2029, 7, 2)), contains(HolidayName.canadaDay));
    });
  });

  group('fixed and nth-weekday days', () {
    test('New Year is January 1', () {
      expect(_namesOn(_d(2026, 1, 1)), contains(HolidayName.newYear));
    });

    test('Fête nationale is June 24', () {
      expect(_namesOn(_d(2026, 6, 24)), contains(HolidayName.nationalHoliday));
    });

    test('Fête nationale shifts to June 25 when June 24 is a Sunday', () {
      // The Loi sur la fête nationale carries the same Sunday rule the LNT
      // gives July 1, and 2029 is the year that proves the two must agree:
      // June 24 AND July 1 are both Sundays, so shifting one and not the
      // other answered the same question two ways in one year.
      expect(_d(2029, 6, 24).weekday, DateTime.sunday);
      expect(
        _namesOn(_d(2029, 6, 24)),
        isNot(contains(HolidayName.nationalHoliday)),
      );
      expect(
        _namesOn(_d(2029, 6, 25)),
        contains(HolidayName.nationalHoliday),
      );
    });

    test('Christmas is December 25', () {
      expect(_namesOn(_d(2026, 12, 25)), contains(HolidayName.christmas));
    });

    test('Labour Day is the first Monday of September', () {
      expect(_namesOn(_d(2026, 9, 7)), contains(HolidayName.labourDay));
      expect(_namesOn(_d(2026, 9, 1)), isNot(contains(HolidayName.labourDay)));
    });

    test('Thanksgiving is the second Monday of October', () {
      expect(_namesOn(_d(2026, 10, 12)), contains(HolidayName.thanksgiving));
      expect(
        _namesOn(_d(2026, 10, 5)),
        isNot(contains(HolidayName.thanksgiving)),
      );
    });
  });

  // ---------------------------------------------------------------------
  // Easter-derived days, in both calendars.
  // ---------------------------------------------------------------------
  group('Easter-derived days', () {
    test('Québec marks Good Friday and Easter Monday, not Easter Sunday', () {
      expect(_namesOn(_d(2026, 4, 3)), contains(HolidayName.goodFriday));
      expect(_namesOn(_d(2026, 4, 6)), contains(HolidayName.easterMonday));
      // Easter Sunday itself is not in the statutory list.
      expect(
        holidaysOn(_d(2026, 4, 5)).where((h) => h.set == HolidaySet.statutory),
        isEmpty,
      );
    });

    test('the Greek set marks Friday, Πάσχα itself, and Monday', () {
      expect(
        _namesOn(_d(2026, 4, 10)),
        contains(HolidayName.orthodoxGoodFriday),
      );
      expect(_namesOn(_d(2026, 4, 12)), contains(HolidayName.orthodoxEaster));
      expect(
        _namesOn(_d(2026, 4, 13)),
        contains(HolidayName.orthodoxEasterMonday),
      );
    });
  });

  // ---------------------------------------------------------------------
  // The construction holiday: a 14-day run, and the rule everyone gets wrong.
  // ---------------------------------------------------------------------
  group('construction holiday', () {
    // Published CCQ shutdown start dates. The widely-repeated "Sunday after
    // the third Saturday of July" is right for 2024-2026 and WRONG for 2022
    // and 2023, which is why the table reaches back that far.
    const knownStarts = {
      2022: [7, 24],
      2023: [7, 23],
      2024: [7, 21],
      2025: [7, 20],
      2026: [7, 19],
    };

    for (final entry in knownStarts.entries) {
      test('${entry.key} starts on ${entry.value[0]}/${entry.value[1]}', () {
        expect(
          constructionHolidayStart(entry.key),
          _d(entry.key, entry.value[0], entry.value[1]),
        );
      });
    }

    test('starts on a Sunday and runs 14 days', () {
      for (var year = 2020; year <= 2060; year++) {
        final start = constructionHolidayStart(year);
        expect(start.weekday, DateTime.sunday, reason: 'construction $year');

        final days = holidaysForYear(
          year,
        ).where((h) => h.set == HolidaySet.construction).toList();
        expect(days, hasLength(14), reason: 'construction $year');
        expect(days.first.date, start, reason: 'construction $year');
        expect(
          days.last.date,
          _d(start.year, start.month, start.day + 13),
          reason: 'construction $year',
        );
      }
    });

    test('crosses the July/August boundary every year', () {
      // Load-bearing for rendering: the tail always lands on off-month cells,
      // so that is the normal case rather than an edge one.
      for (var year = 2020; year <= 2060; year++) {
        final start = constructionHolidayStart(year);
        final end = _d(start.year, start.month, start.day + 13);
        expect(start.month, DateTime.july, reason: 'construction $year');
        expect(end.month, DateTime.august, reason: 'construction $year');
      }
    });

    test('marks every day of the run, ends included', () {
      expect(
        _namesOn(_d(2026, 7, 19)),
        contains(HolidayName.constructionHoliday),
      );
      expect(
        _namesOn(_d(2026, 7, 26)),
        contains(HolidayName.constructionHoliday),
      );
      expect(
        _namesOn(_d(2026, 8, 1)),
        contains(HolidayName.constructionHoliday),
      );
      expect(
        _namesOn(_d(2026, 7, 18)),
        isNot(contains(HolidayName.constructionHoliday)),
      );
      expect(
        _namesOn(_d(2026, 8, 2)),
        isNot(contains(HolidayName.constructionHoliday)),
      );
    });

    test('never overlaps a statutory day', () {
      // Canada Day always falls before the run starts, so a shutdown day can
      // never also carry a statutory rule and no cell shows two hues.
      for (var year = 2020; year <= 2060; year++) {
        final start = constructionHolidayStart(year);
        for (var i = 0; i < 14; i++) {
          final day = _d(start.year, start.month, start.day + i);
          expect(
            holidaysOn(day).where((h) => h.set == HolidaySet.statutory),
            isEmpty,
            reason: 'construction $year day $i',
          );
        }
      }
    });
  });

  // ---------------------------------------------------------------------
  // Coincidence years: the two Easters land on the SAME date roughly one
  // year in three, so a day can carry two holidays at once.
  // ---------------------------------------------------------------------
  group('coincidence years', () {
    test('2028 carries both Good Fridays on one day', () {
      expect(gregorianEaster(2028), orthodoxEaster(2028));
      final names = _namesOn(_d(2028, 4, 14));
      expect(names, contains(HolidayName.goodFriday));
      expect(names, contains(HolidayName.orthodoxGoodFriday));
    });

    test('the statutory set wins the marker on a shared day', () {
      expect(markerSetOn(_d(2028, 4, 14)), HolidaySet.statutory);
    });

    test(
      'Πάσχα keeps the Orthodox marker, since Québec skips Easter Sunday',
      () {
        expect(markerSetOn(_d(2028, 4, 16)), HolidaySet.orthodox);
      },
    );

    test('an ordinary day has no marker', () {
      expect(markerSetOn(_d(2026, 4, 7)), isNull);
      expect(holidaysOn(_d(2026, 4, 7)), isEmpty);
    });
  });

  group('holidaysOn', () {
    test('ignores the time of day', () {
      final noon = DateTime(2026, 6, 24, 12, 30);
      expect(_namesOn(noon), contains(HolidayName.nationalHoliday));
    });

    test('resolves the year from the day, not a cached one', () {
      // A December view scrolled into January must still answer correctly.
      expect(_namesOn(_d(2027, 1, 1)), contains(HolidayName.newYear));
      expect(_namesOn(_d(2025, 1, 1)), contains(HolidayName.newYear));
    });
  });
}
