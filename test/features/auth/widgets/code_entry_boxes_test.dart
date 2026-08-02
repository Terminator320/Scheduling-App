import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/auth/widgets/code_entry_boxes.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _wrap(TextEditingController controller, {bool hasError = false}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: lightTheme(),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: CodeEntryBoxes(
          controller: controller,
          hasError: hasError,
          onChanged: (_) {},
        ),
      ),
    ),
  );
}

/// The twelve painted boxes — every bordered [Container] inside the widget.
List<Border> _boxBorders(WidgetTester tester) {
  return tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(CodeEntryBoxes),
          matching: find.byType(Container),
        ),
      )
      .map((container) => container.decoration)
      .whereType<BoxDecoration>()
      .map((decoration) => decoration.border)
      .whereType<Border>()
      .toList();
}

void main() {
  late TextEditingController controller;

  setUp(() {
    controller = TextEditingController();
  });

  tearDown(() {
    controller.dispose();
  });

  testWidgets('paints twelve boxes', (tester) async {
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    expect(_boxBorders(tester).length, 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing fills the boxes left to right', (tester) async {
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pumpAndSettle();

    // Uppercased as typed, and only the first three boxes carry a glyph.
    expect(controller.text, 'ABC');
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text(''), findsNWidgets(9));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pasting a dashed twelve-character code fills all twelve boxes', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'abcd-efgh-jkmn');
    await tester.pumpAndSettle();

    expect(controller.text, 'ABCDEFGHJKMN');
    // No box is left empty.
    expect(find.text(''), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caps a pasted code longer than twelve characters', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ABCD-EFGH-JKMN-PQRS');
    await tester.pumpAndSettle();

    expect(controller.text, 'ABCDEFGHJKMN');
    expect(tester.takeException(), isNull);
  });

  testWidgets('backspace clears the last filled box', (tester) async {
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ABC');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(controller.text, 'AB');
    expect(find.text('C'), findsNothing);
    expect(find.text(''), findsNWidgets(10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reddens every box when the code is rejected', (tester) async {
    await tester.pumpWidget(_wrap(controller, hasError: true));
    await tester.pumpAndSettle();

    final errorColor = lightTheme().colorScheme.error;
    final borders = _boxBorders(tester);
    expect(borders.length, 12);
    expect(
      borders.every((border) => border.top.color == errorColor),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('speaks the twelve boxes as one field', (tester) async {
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ABC');
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Signup code, 3 of 12 characters entered'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
