import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('counter shows 0/max initially and updates while typing', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        LabeledTextField(
          label: 'Notes',
          controller: controller,
          optional: true,
          maxLength: 4000,
          showCounter: true,
        ),
      ),
    );
    expect(find.text('0/4000'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pumpAndSettle();

    expect(find.text('5/4000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('warning appears when the character limit is hit', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        LabeledTextField(
          label: 'Notes',
          controller: controller,
          optional: true,
          maxLength: 5,
          showCounter: true,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pumpAndSettle();
    expect(find.text('Maximum character limit reached'), findsNothing);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pumpAndSettle();

    expect(find.text('Maximum character limit reached'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('counter is hidden by default', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        LabeledTextField(
          label: 'Notes',
          controller: controller,
          maxLength: 4000,
        ),
      ),
    );

    expect(find.text('0/4000'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
