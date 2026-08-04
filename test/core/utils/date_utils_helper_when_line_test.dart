import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:scheduling/core/utils/date_utils_helper.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_CA');
    await initializeDateFormatting('fr_CA');
  });

  tearDown(() => Intl.defaultLocale = 'en_CA');

  test('renders an uppercase day, date, month and an en-dashed time range', () {
    Intl.defaultLocale = 'en_CA';
    final line = DateUtilsHelper.formatWhenLine(
      DateTime(2026, 8, 4, 10, 30),
      DateTime(2026, 8, 4, 12),
    );
    expect(line, contains('TUE'));
    expect(line, contains('AUG'));
    expect(line, contains('·'));
    expect(line, contains('–'));
    expect(line, isNot(contains('Aug')));
  });

  test('follows the active locale', () {
    Intl.defaultLocale = 'fr_CA';
    final line = DateUtilsHelper.formatWhenLine(
      DateTime(2026, 8, 4, 10, 30),
      DateTime(2026, 8, 4, 12),
    );
    expect(line, contains('AOÛT'));
  });

  test('names both ends of a multi-day run', () {
    Intl.defaultLocale = 'en_CA';
    final line = DateUtilsHelper.formatWhenLine(
      DateTime(2026, 8, 4, 9),
      DateTime(2026, 8, 8, 17),
      lastDay: DateTime(2026, 8, 8),
    );
    // Day 1 alone gave no hint the job ran four more days.
    expect(line, contains('TUE 4 AUG'));
    expect(line, contains('SAT 8 AUG'));
  });

  test('a single-day run still shows one date', () {
    Intl.defaultLocale = 'en_CA';
    final line = DateUtilsHelper.formatWhenLine(
      DateTime(2026, 8, 4, 9),
      DateTime(2026, 8, 4, 17),
      lastDay: DateTime(2026, 8, 4),
    );
    expect('–'.allMatches(line).length, 1); // the time range dash only
  });

  test('an all-day block spanning days keeps its label', () {
    Intl.defaultLocale = 'en_CA';
    final line = DateUtilsHelper.formatWhenLine(
      DateTime(2026, 8, 4),
      DateTime(2026, 8, 6, 23, 59),
      allDayLabel: 'All day',
      lastDay: DateTime(2026, 8, 6),
    );
    expect(line, contains('TUE 4 AUG'));
    expect(line, contains('THU 6 AUG'));
    expect(line, contains('ALL DAY'));
  });
}
