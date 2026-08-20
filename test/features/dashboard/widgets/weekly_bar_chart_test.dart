import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:scheduling/features/dashboard/widgets/charts/weekly_bar_chart.dart';
import 'package:scheduling/l10n/l10n.dart';

/// Eight Mondays, the bucket count the dashboard always feeds this chart.
final _weeks = [
  for (var i = 0; i < 8; i++) DateTime(2026, 6, 1 + 7 * i),
];

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

BarChartData _dataOf(WidgetTester tester) =>
    tester.widget<BarChart>(find.byType(BarChart)).data;

void main() {
  // DateFormat.Md verifies the locale against intl's loaded date symbols.
  setUpAll(() => initializeDateFormatting('en'));

  testWidgets('draws one group per week and one rod per series', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        WeeklyBarChart(
          weekStarts: _weeks,
          series: [
            WeeklyBarSeries(
              values: List.filled(8, 3),
              color: Colors.blue,
              label: 'Booked',
            ),
            WeeklyBarSeries(
              values: List.filled(8, 1),
              color: Colors.green,
              label: 'Done',
            ),
          ],
        ),
      ),
    );

    final data = _dataOf(tester);
    expect(data.barGroups, hasLength(8));
    expect(data.barGroups.first.barRods, hasLength(2));
    // Two series share a group, so each rod is half as wide.
    expect(data.barGroups.first.barRods.first.width, 7);
  });

  testWidgets('a single series gets the full-width rod', (tester) async {
    await tester.pumpWidget(
      _wrap(
        WeeklyBarChart(
          weekStarts: _weeks,
          series: [
            WeeklyBarSeries(
              values: List.filled(8, 3),
              color: Colors.blue,
              label: 'Booked',
            ),
          ],
        ),
      ),
    );

    expect(_dataOf(tester).barGroups.first.barRods.single.width, 14);
  });

  testWidgets('the legend appears only for two series', (tester) async {
    await tester.pumpWidget(
      _wrap(
        WeeklyBarChart(
          weekStarts: _weeks,
          series: [
            WeeklyBarSeries(
              values: List.filled(8, 3),
              color: Colors.blue,
              label: 'Booked',
            ),
          ],
        ),
      ),
    );
    expect(find.text('Booked'), findsNothing);

    await tester.pumpWidget(
      _wrap(
        WeeklyBarChart(
          weekStarts: _weeks,
          series: [
            WeeklyBarSeries(
              values: List.filled(8, 3),
              color: Colors.blue,
              label: 'Booked',
            ),
            WeeklyBarSeries(
              values: List.filled(8, 1),
              color: Colors.green,
              label: 'Done',
            ),
          ],
        ),
      ),
    );
    expect(find.text('Booked'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('an all-zero series still gets a drawable axis', (tester) async {
    // maxY: 0 makes fl_chart divide by zero — every bucket empty is a normal
    // week for a small shop, not an edge case.
    await tester.pumpWidget(
      _wrap(
        WeeklyBarChart(
          weekStarts: _weeks,
          series: [
            WeeklyBarSeries(
              values: List.filled(8, 0),
              color: Colors.blue,
              label: 'Booked',
            ),
          ],
        ),
      ),
    );

    expect(_dataOf(tester).maxY, 1);
  });

  testWidgets('a short series pads with zero rather than throwing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        WeeklyBarChart(
          weekStarts: _weeks,
          series: const [
            WeeklyBarSeries(
              values: [4, 2],
              color: Colors.blue,
              label: 'Booked',
            ),
          ],
        ),
      ),
    );

    final groups = _dataOf(tester).barGroups;
    expect(groups.first.barRods.single.toY, 4);
    expect(groups.last.barRods.single.toY, 0);
  });

  testWidgets('speaks each series total instead of the bars', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(
        WeeklyBarChart(
          weekStarts: _weeks,
          series: const [
            WeeklyBarSeries(
              values: [1, 2, 3],
              color: Colors.blue,
              label: 'Booked',
            ),
            WeeklyBarSeries(
              values: [1, 1],
              color: Colors.green,
              label: 'Done',
            ),
          ],
        ),
      ),
    );

    expect(find.bySemanticsLabel('Booked: 6, Done: 2'), findsOneWidget);
    handle.dispose();
  });

  // The real labels are the status names the trends section passes.
  testWidgets('renders at 2x text on a narrow phone without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: WeeklyBarChart(
            weekStarts: _weeks,
            series: [
              WeeklyBarSeries(
                values: List.filled(8, 3),
                color: Colors.blue,
                label: 'Complete',
              ),
              WeeklyBarSeries(
                values: List.filled(8, 1),
                color: Colors.green,
                label: 'Cancelled',
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
