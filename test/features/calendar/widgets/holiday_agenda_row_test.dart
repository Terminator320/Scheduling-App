import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/calendar/domain/holidays.dart';
import 'package:scheduling/features/calendar/widgets/views/holiday_agenda_row.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: lightTheme(),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

Widget _rowsFor(DateTime day) => Column(
  children: [
    for (final holiday in holidaysOn(day)) HolidayAgendaRow(holiday: holiday),
  ],
);

void main() {
  testWidgets('a statutory day names itself and tags HOLIDAY', (tester) async {
    await tester.pumpWidget(_wrap(_rowsFor(DateTime(2026, 6, 24))));
    await tester.pumpAndSettle();

    expect(find.text('Saint-Jean-Baptiste'), findsOneWidget);
    expect(find.text('Québec statutory holiday'), findsOneWidget);
    expect(find.text('HOLIDAY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Greek Orthodox day tags OBSERVANCE, not HOLIDAY', (
    tester,
  ) async {
    // It is not a statutory holiday, and the tag is where that distinction
    // lives — the grid marker only carries a hue.
    await tester.pumpWidget(_wrap(_rowsFor(DateTime(2026, 4, 12))));
    await tester.pumpAndSettle();

    expect(find.text('Orthodox Easter'), findsOneWidget);
    expect(find.text('Greek Orthodox'), findsOneWidget);
    expect(find.text('OBSERVANCE'), findsOneWidget);
    expect(find.text('HOLIDAY'), findsNothing);
  });

  testWidgets('the construction holiday carries NO caption', (tester) async {
    // Owner call: the headline says everything, so the row does not repeat it
    // as a caption or count progress through the run.
    await tester.pumpWidget(_wrap(_rowsFor(DateTime(2026, 7, 22))));
    await tester.pumpAndSettle();

    expect(find.text('Construction holiday'), findsOneWidget);
    expect(find.text('HOLIDAY'), findsOneWidget);
    expect(find.text('Québec statutory holiday'), findsNothing);
    expect(find.text('Greek Orthodox'), findsNothing);
  });

  testWidgets('a coincidence day renders BOTH rows', (tester) async {
    // 2028 is one of the years the two Easters land together, so April 14
    // carries both Good Fridays. The grid can only show one hue; the agenda
    // must not lose the other.
    await tester.pumpWidget(_wrap(_rowsFor(DateTime(2028, 4, 14))));
    await tester.pumpAndSettle();

    expect(find.text('Good Friday'), findsOneWidget);
    expect(find.text('Orthodox Good Friday'), findsOneWidget);
    expect(find.byType(HolidayAgendaRow), findsNWidgets(2));
  });

  testWidgets('an ordinary day renders nothing', (tester) async {
    await tester.pumpWidget(_wrap(_rowsFor(DateTime(2026, 4, 7))));
    await tester.pumpAndSettle();

    expect(find.byType(HolidayAgendaRow), findsNothing);
  });

  testWidgets('survives a small viewport at 2x text', (tester) async {
    tester.view.physicalSize = const Size(260, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _rowsFor(DateTime(2026, 6, 24)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
