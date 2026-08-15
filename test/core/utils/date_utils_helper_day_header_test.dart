import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:scheduling/core/utils/date_utils_helper.dart';

/// The day header must come from the locale SKELETON, never a hardcoded
/// `'EEEE, MMMM d'` pattern. English passes either way — French is the case
/// that caught it, having rendered "mercredi, août 5" instead of
/// "mercredi 5 août".
void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_CA');
    await initializeDateFormatting('fr_CA');
  });

  tearDown(() => Intl.defaultLocale = 'en_CA');

  test('English puts the month before the day number', () {
    Intl.defaultLocale = 'en_CA';
    expect(
      DateUtilsHelper.formatDayHeader(DateTime(2026, 8, 5)),
      'Wednesday, August 5',
    );
  });

  test('French puts the day number before the month, with no comma', () {
    Intl.defaultLocale = 'fr_CA';
    expect(
      DateUtilsHelper.formatDayHeader(DateTime(2026, 8, 5)),
      'mercredi 5 août',
    );
  });
}
