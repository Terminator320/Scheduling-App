import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/clear_text_button.dart';
import 'package:scheduling/shared/widgets/fields/dictation_mic_button.dart';
import 'package:scheduling/shared/widgets/fields/labeled_text_field.dart';

void main() {
  late TextEditingController controller;

  setUp(() => controller = TextEditingController());
  tearDown(() => controller.dispose());

  Widget harness(Widget child) => ProviderScope(
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  testWidgets('enableDictation shows the mic AND keeps the clear button', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        LabeledTextField(
          label: 'Notes',
          controller: controller,
          enableDictation: true,
        ),
      ),
    );
    expect(find.byType(DictationMicButton), findsOneWidget);
    expect(find.byType(ClearTextButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default field has no mic', (tester) async {
    await tester.pumpWidget(
      harness(LabeledTextField(label: 'Name', controller: controller)),
    );
    expect(find.byType(DictationMicButton), findsNothing);
    expect(find.byType(ClearTextButton), findsOneWidget);
  });

  testWidgets('readOnly field has no mic even with enableDictation', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        LabeledTextField(
          label: 'Picker',
          controller: controller,
          readOnly: true,
          enableDictation: true,
        ),
      ),
    );
    expect(find.byType(DictationMicButton), findsNothing);
  });

  testWidgets('a custom suffixIcon wins over dictation', (tester) async {
    await tester.pumpWidget(
      harness(
        LabeledTextField(
          label: 'Custom',
          controller: controller,
          enableDictation: true,
          suffixIcon: const Icon(Icons.search),
        ),
      ),
    );
    expect(find.byType(DictationMicButton), findsNothing);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });
}
