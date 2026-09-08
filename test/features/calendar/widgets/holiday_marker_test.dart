import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:scheduling/core/theme/design_tokens.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/calendar/domain/holidays.dart';
import 'package:scheduling/features/calendar/widgets/fields/inline_month_calendar.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_day_circle.dart';
import 'package:scheduling/features/calendar/widgets/views/calendar_month_grid.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _wrap(Widget child) => MaterialApp(
  // The real theme, because the rule's hues live on the AppPalette extension.
  theme: lightTheme(),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Widget _grid({
  required DateTime month,
  required DateTime selectedDay,
  required DateTime today,
}) => CalendarMonthGrid(
  month: month,
  selectedDay: selectedDay,
  today: today,
  onDaySelected: (_) {},
  dotColorsFor: (_) => const [],
  countFor: (_) => 0,
);

/// June 2026 — Saint-Jean on the 24th, and Canada Day trailing into the grid
/// as an OFF-MONTH cell on July 1.
Widget _june({DateTime? selectedDay}) => _grid(
  month: DateTime(2026, 6),
  selectedDay: selectedDay ?? DateTime(2026, 6, 10),
  today: DateTime(2026, 6, 17),
);

double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The rules the grid actually painted, in render order.
List<Color?> _ruleColors(WidgetTester tester) => tester
    .widgetList<Container>(find.byKey(calendarHolidayRuleKey))
    .map((c) => (c.decoration! as BoxDecoration).color)
    .toList();

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_CA');
  });

  group('holidayRuleColorFor', () {
    final light = lightTheme();
    final dark = darkTheme();

    test('an ordinary day gets no rule', () {
      expect(
        holidayRuleColorFor(
          theme: light,
          set: null,
          isSelected: false,
          isFaint: false,
        ),
        isNull,
      );
    });

    test('each set has its own hue', () {
      final statutory = holidayRuleColorFor(
        theme: light,
        set: HolidaySet.statutory,
        isSelected: false,
        isFaint: false,
      );
      final orthodox = holidayRuleColorFor(
        theme: light,
        set: HolidaySet.orthodox,
        isSelected: false,
        isFaint: false,
      );
      final construction = holidayRuleColorFor(
        theme: light,
        set: HolidaySet.construction,
        isSelected: false,
        isFaint: false,
      );

      expect(statutory, AppColors.holidayStatutory);
      expect(orthodox, AppColors.holidayOrthodox);
      expect(construction, AppColors.holidayConstruction);
      expect({statutory, orthodox, construction}, hasLength(3));
    });

    test('the dark theme lifts every hue', () {
      for (final set in HolidaySet.values) {
        final onLight = holidayRuleColorFor(
          theme: light,
          set: set,
          isSelected: false,
          isFaint: false,
        );
        final onDark = holidayRuleColorFor(
          theme: dark,
          set: set,
          isSelected: false,
          isFaint: false,
        );
        expect(onDark, isNot(onLight), reason: '$set');
      }
    });

    test('a SELECTED day goes onPrimary, whatever the set', () {
      // The hue would muddy against the primary-blue selection fill, so the
      // rule goes white there and the agenda row carries the colour instead.
      for (final set in HolidaySet.values) {
        expect(
          holidayRuleColorFor(
            theme: light,
            set: set,
            isSelected: true,
            isFaint: false,
          ),
          light.colorScheme.onPrimary,
          reason: '$set',
        );
      }
    });

    test('an OFF-MONTH day fades the rule with the number', () {
      final faint = holidayRuleColorFor(
        theme: light,
        set: HolidaySet.statutory,
        isSelected: false,
        isFaint: true,
      );
      expect(faint!.a, lessThan(1.0));
      expect(faint.r, AppColors.holidayStatutory.r);
    });

    test('a selected day KEEPS a lifted hue when asked to', () {
      // The picker has no agenda row beneath it to name the holiday, so the
      // rule must still say which kind of day it is.
      for (final set in HolidaySet.values) {
        final kept = holidayRuleColorFor(
          theme: light,
          set: set,
          isSelected: true,
          isFaint: false,
          keepHueWhenSelected: true,
        )!;
        expect(kept, isNot(light.colorScheme.onPrimary), reason: '$set');
      }
    });

    test('the three kept hues stay distinguishable from each other', () {
      // The whole point of lifting rather than whitening: lift far enough and
      // all three converge on white and the category is lost anyway.
      final kept = [
        for (final set in HolidaySet.values)
          holidayRuleColorFor(
            theme: light,
            set: set,
            isSelected: true,
            isFaint: false,
            keepHueWhenSelected: true,
          )!,
      ];
      expect(kept.toSet(), hasLength(HolidaySet.values.length));
    });

    test('a kept hue clears 3:1 against the selection fill', () {
      // A non-text graphic's WCAG bar, and the reason the lift factor is what
      // it is — the rule is 2px on a saturated blue.
      for (final set in HolidaySet.values) {
        final kept = holidayRuleColorFor(
          theme: light,
          set: set,
          isSelected: true,
          isFaint: false,
          keepHueWhenSelected: true,
        )!;
        expect(
          _contrast(kept, light.colorScheme.primary),
          greaterThanOrEqualTo(3),
          reason: '$set',
        );
      }
    });

    test('selection beats faintness', () {
      expect(
        holidayRuleColorFor(
          theme: light,
          set: HolidaySet.statutory,
          isSelected: true,
          isFaint: true,
        ),
        light.colorScheme.onPrimary,
      );
    });
  });

  group('the month grid paints the rule', () {
    testWidgets('on a statutory day, and not on ordinary ones', (tester) async {
      await tester.pumpWidget(_wrap(_june()));
      await tester.pumpAndSettle();

      // June 2026 shows exactly two: Saint-Jean (Jun 24) and Canada Day
      // (Jul 1, off-month).
      expect(_ruleColors(tester), hasLength(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('faded on the off-month Canada Day cell', (tester) async {
      await tester.pumpWidget(_wrap(_june()));
      await tester.pumpAndSettle();

      final colors = _ruleColors(tester);
      final opaque = colors.where((c) => c!.a == 1.0);
      final faded = colors.where((c) => c!.a < 1.0);
      expect(opaque, hasLength(1), reason: 'Saint-Jean is in-month');
      expect(faded, hasLength(1), reason: 'Canada Day trails off-month');
    });

    testWidgets('in onPrimary when the holiday is the selected day', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_june(selectedDay: DateTime(2026, 6, 24))),
      );
      await tester.pumpAndSettle();

      final scheme = Theme.of(
        tester.element(find.byType(CalendarMonthGrid)),
      ).colorScheme;
      expect(_ruleColors(tester), contains(scheme.onPrimary));
    });

    testWidgets('names the holiday in the semantics label', (tester) async {
      // The rule is colour-only, so the label is what carries its meaning —
      // the same reasoning that puts the appointment count there.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(_june()));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(
          RegExp('Wednesday, June 24, 2026.*Saint-Jean-Baptiste', dotAll: true),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('names BOTH holidays on a coincidence day', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          _grid(
            month: DateTime(2028, 4),
            selectedDay: DateTime(2028, 4, 20),
            today: DateTime(2028, 4, 20),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(
          RegExp('Good Friday.*Orthodox Good Friday', dotAll: true),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });


  testWidgets('a month with no holiday paints none', (tester) async {

      await tester.pumpWidget(
        _wrap(
          _grid(
            month: DateTime(2026, 2),
            selectedDay: DateTime(2026, 2, 10),
            today: DateTime(2026, 2, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(calendarHolidayRuleKey), findsNothing);
    });
  });

  group('InlineMonthCalendar', () {
    testWidgets('a SELECTED holiday keeps its hue in the picker', (
      tester,
    ) async {
      // The form's date picker has no agenda row beneath it, so unlike the
      // grid the selected day must not flatten to onPrimary — this is the one
      // surface where the marker can stop a mis-booking rather than report it.
      final theme = lightTheme();
      await tester.pumpWidget(
        _wrap(
          InlineMonthCalendar(
            // Saint-Jean, selected.
            selectedDate: DateTime(2026, 6, 24),
            firstDate: DateTime(2026),
            lastDate: DateTime(2027),
            today: DateTime(2026, 6, 17),
            onDateSelected: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final painted = _ruleColors(tester);
      expect(painted, isNotEmpty);
      expect(painted, contains(isNot(theme.colorScheme.onPrimary)));
    });
  });
}
