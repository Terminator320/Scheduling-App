import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_header_block.dart';
import 'package:scheduling/l10n/l10n.dart';

// Copies the ambient MediaQuery rather than building a fresh MediaQueryData, so
// the subtree keeps a real viewport size and only the top inset is forced.
Widget _wrap(Widget child, {double topInset = 47}) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: lightTheme(),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(padding: EdgeInsets.only(top: topInset)),
      child: Scaffold(body: Column(children: [child])),
    ),
  ),
);

void main() {
  testWidgets('renders the month, the year and a tappable month row', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      _wrap(
        CalendarHeaderBlock(
          monthLabel: 'August',
          monthLabelShort: 'Aug',
          yearLabel: '2026',
          onPickMonth: () => tapped++,
          routeButton: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SCHEDULE'), findsOneWidget);
    expect(find.text('August'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);

    await tester.tap(find.text('August'));
    expect(tapped, 1);
  });

  testWidgets('reserves the real status-bar inset, never a literal', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CalendarHeaderBlock(
          monthLabel: 'August',
          monthLabelShort: 'Aug',
          yearLabel: '2026',
          onPickMonth: () {},
          routeButton: const SizedBox.shrink(),
        ),
        topInset: 80,
      ),
    );
    await tester.pumpAndSettle();

    final label = tester.getTopLeft(find.text('SCHEDULE'));
    expect(label.dy, greaterThanOrEqualTo(80));
  });

  testWidgets('hosts the week strip when one is supplied', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CalendarHeaderBlock(
          monthLabel: 'August',
          monthLabelShort: 'Aug',
          yearLabel: '2026',
          onPickMonth: () {},
          routeButton: const SizedBox.shrink(),
          weekStrip: const Text('STRIP'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('STRIP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a month name that does not fit falls back to its abbreviation', (
    tester,
  ) async {
    // The label is chosen by MEASURING the row, not from a text-scale
    // threshold: the in-app XL setting is exactly 1.4, which the old `> 1.4`
    // gate missed by a hair, leaving "September" ellipsized into a stub.
    // Asserted against viewport width rather than a specific scale, because
    // the test font is much wider per glyph than the shipped one.
    Future<void> pumpAt(double width) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        _wrap(
          CalendarHeaderBlock(
            monthLabel: 'September',
            monthLabelShort: 'Sep',
            yearLabel: '2026',
            onPickMonth: () {},
            routeButton: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpAt(1400);
    expect(find.text('September'), findsOneWidget);
    expect(find.text('Sep'), findsNothing);

    await pumpAt(360);
    expect(find.text('Sep'), findsOneWidget);
    expect(find.text('September'), findsNothing);
    // The screen reader still gets the full month.
    expect(find.bySemanticsLabel('September 2026, Select date'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exposes the month row as one labelled button', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CalendarHeaderBlock(
          monthLabel: 'August',
          monthLabelShort: 'Aug',
          yearLabel: '2026',
          onPickMonth: () {},
          routeButton: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('August 2026, Select date'),
      findsOneWidget,
    );
  });
}
