import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:scheduling/features/calendar/domain/month_grid.dart';
import 'package:scheduling/features/dashboard/domain/dashboard_stats.dart';
import 'package:scheduling/features/dashboard/widgets/charts/daily_load_chart.dart';
import 'package:scheduling/features/employees/widgets/fields/work_schedule_pickers.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Monday 2026-07-06 through Sunday 2026-07-12 — one whole week, so every
/// weekday index is exercised and a rotation of any size shifts at least one
/// label onto the wrong date.
final _week = [
  for (var i = 0; i < 7; i++) DateTime(2026, 7, 6 + i),
];

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  // `weekdayAbbreviationsForLocale` reads intl's date symbols, which the
  // localization delegate only loads once a MaterialApp has pumped — and these
  // tests resolve labels while building the tree, before that happens.
  setUpAll(() => initializeDateFormatting('en'));

  group('DailyLoadChart', () {
    testWidgets('labels every bar with its own weekday', (tester) async {
      // The whole hazard in one assertion: `weekdayLabels` is Sunday-indexed
      // and UNROTATED, so handing it a display-ordered list would still render
      // seven plausible labels — just attached to the wrong dates.
      await tester.pumpWidget(
        _wrap(
          DailyLoadChart(
            days: [
              for (final day in _week) DayLoad(day: day, count: 1, capacity: 0),
            ],
            weekdayLabels: weekdayAbbreviationsForLocale('en'),
          ),
        ),
      );

      final labels = weekdayAbbreviationsForLocale('en');
      for (final day in _week) {
        final expected = labels[sundayIndexOf(day)];
        expect(
          find.text(expected),
          findsOneWidget,
          reason: '${day.toIso8601String()} should be labelled $expected',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a Sunday bar is labelled Sunday, not Saturday', (
      tester,
    ) async {
      // The off-by-one this indexing invites: Sunday is stored index 0 but
      // sits last in a Monday-first display order.
      await tester.pumpWidget(
        _wrap(
          DailyLoadChart(
            days: [
              DayLoad(day: DateTime(2026, 7, 12), count: 3, capacity: 0),
            ],
            weekdayLabels: weekdayAbbreviationsForLocale('en'),
          ),
        ),
      );

      expect(find.text('Sun'), findsOneWidget);
      expect(find.text('Sat'), findsNothing);
    });
  });

  group('joinWeekdayNames', () {
    late BuildContext context;

    Future<void> pumpContext(WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    }

    testWidgets('resolves Sunday-indexed numbers to the right names', (
      tester,
    ) async {
      await pumpContext(tester);

      expect(joinWeekdayNames(context, {0}), 'Sun');
      expect(joinWeekdayNames(context, {6}), 'Sat');
      expect(joinWeekdayNames(context, {3}), 'Wed');
    });

    testWidgets('orders by stored index, not by insertion', (tester) async {
      await pumpContext(tester);

      expect(joinWeekdayNames(context, {5, 1, 3}), 'Mon, Wed, Fri');
    });

    testWidgets('an empty set names nothing', (tester) async {
      await pumpContext(tester);

      expect(joinWeekdayNames(context, const {}), '');
    });
  });
}
