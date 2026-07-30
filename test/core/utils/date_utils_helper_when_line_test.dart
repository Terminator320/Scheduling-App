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
}
