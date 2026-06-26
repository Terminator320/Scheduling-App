import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/shared/widgets/sheets/sheet_widgets.dart';

void main() {
  Future<void> pumpShortSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FormSheetScaffold(
            title: 'New Appointment',
            children: [SizedBox(height: 24)],
          ),
        ),
      ),
    );
  }

  testWidgets('FormSheetScaffold opens taller on short phone heights', (
    tester,
  ) async {
    await pumpShortSheet(tester);

    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );

    expect(sheet.initialChildSize, 0.82);
    expect(sheet.minChildSize, 0.58);
    expect(sheet.maxChildSize, 0.98);
  });
}

