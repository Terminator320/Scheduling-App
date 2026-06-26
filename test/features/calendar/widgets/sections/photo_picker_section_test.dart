import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/widgets/sections/photo_picker_section.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  Future<void> pumpSection(
    WidgetTester tester, {
    required Widget child,
  }) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pump();
  }

  testWidgets('editing photo strip exposes add-more as an InkWell surface', (
    tester,
  ) async {
    await pumpSection(
      tester,
      child: PhotoPickerSection(
        existingImages: const [],
        newImages: const [],
        failedCount: 1,
        isEditing: true,
        onPickImages: () {},
        onRemoveExisting: (_) {},
        onRemoveNew: (_) {},
      ),
    );

    expect(find.widgetWithText(InkWell, 'Add more'), findsOneWidget);
  });

  testWidgets('upload failures expose retry as a TextButton', (tester) async {
    await pumpSection(
      tester,
      child: PhotoPickerSection(
        existingImages: const [],
        newImages: const [],
        failedCount: 1,
        isEditing: true,
        onPickImages: () {},
        onRemoveExisting: (_) {},
        onRemoveNew: (_) {},
        onRetry: () {},
      ),
    );

    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });
}

