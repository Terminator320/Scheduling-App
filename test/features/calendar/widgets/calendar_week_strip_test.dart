import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/calendar/domain/month_grid.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_week_strip.dart';
import 'package:scheduling/l10n/l10n.dart';

// 16 May 2026 is a Saturday, so this week runs Sun 10 → Sat 16.
final _week = weekOf(DateTime(2026, 5, 16), weekStart: 0);
final _selected = DateTime(2026, 5, 16);
final _today = DateTime(2026, 5, 13);

Widget _wrap(Widget child, {double textScale = 1}) => MaterialApp(
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
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: Column(children: [child])),
    ),
  ),
);

CalendarWeekStrip _strip({
  ValueChanged<DateTime>? onDaySelected,
  List<Color?> Function(DateTime day)? dotColorsFor,
}) => CalendarWeekStrip(
  weekDays: _week,
  selectedDay: _selected,
  today: _today,
  onDaySelected: onDaySelected ?? (_) {},
  dotColorsFor: dotColorsFor ?? (_) => const [],
);

void main() {
  testWidgets('renders one cell per day of the week', (tester) async {
    await tester.pumpWidget(_wrap(_strip()));
    await tester.pumpAndSettle();

    for (final day in _week) {
      expect(
        find.text('${day.day}'),
        findsOneWidget,
        reason: 'day ${day.day} should appear exactly once',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a day reports that date floored to midnight', (
    tester,
  ) async {
    DateTime? picked;
    await tester.pumpWidget(
      _wrap(_strip(onDaySelected: (day) => picked = day)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('12'));
    expect(picked, DateTime(2026, 5, 12));
  });

  testWidgets('the selected day keeps its dot, like the month grid', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(_strip(dotColorsFor: (_) => const [Color(0xFF2E7D32)])),
    );
    await tester.pumpAndSettle();

    // Every day has work, so every one of the 7 cells shows a dot — the
    // selected day included. Suppressing it there made the day being looked
    // at the one day whose crew was invisible, which is the same reason the
    // month grid keeps its dots under the selection circle.
    expect(find.byKey(const ValueKey('calendar-strip-dot')), findsNWidgets(7));
  });

  testWidgets('a day whose job has no crew colour still gets its dot', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_strip(dotColorsFor: (_) => const [null])));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-strip-dot')), findsNWidgets(7));
    expect(tester.takeException(), isNull);
  });

  testWidgets('heightFor grows with the text scale', (tester) async {
    late double atNormal;
    late double atLarge;

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            atNormal = CalendarWeekStrip.heightFor(context);
            return _strip();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            atLarge = CalendarWeekStrip.heightFor(context);
            return _strip();
          },
        ),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(atLarge, greaterThan(atNormal));
  });

  testWidgets('lays out without overflow at 2x text scale', (tester) async {
    await tester.pumpWidget(_wrap(_strip(), textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
