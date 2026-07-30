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

  testWidgets('exposes the month row as one labelled button', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CalendarHeaderBlock(
          monthLabel: 'August',
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
