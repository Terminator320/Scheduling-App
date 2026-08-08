import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/widgets/views/details_action_bar.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets(
    'details action bar does not overflow at phone width with 2x text',
    (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _wrap(
            DetailsActionBar(
              hasStarted: true,
              isDone: false,
              isCancelled: false,
              isSaving: false,
              onMarkDone: () {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('done appointment hides the cancel button', (tester) async {
    await tester.pumpWidget(
      _wrap(
        DetailsActionBar(
          hasStarted: true,
          isDone: true,
          isCancelled: false,
          isSaving: false,
          onMarkDone: () {},
          onCancel: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('Cancel Appointment'), findsNothing);
  });

  testWidgets('done appointment offers Edit in place of the indicator', (
    tester,
  ) async {
    var edits = 0;
    await tester.pumpWidget(
      _wrap(
        DetailsActionBar(
          hasStarted: true,
          isDone: true,
          isCancelled: false,
          isSaving: false,
          onMarkDone: () {},
          onCancel: () {},
          onEdit: () => edits++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The inert "Complete" indicator gives way to the edit action.
    expect(find.text('Complete'), findsNothing);
    await tester.tap(find.text('Edit'));
    expect(edits, 1);
  });
}
