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
              onEditCompleted: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an admin gets an actionable edit button on a done job', (
    tester,
  ) async {
    var edited = 0;
    await tester.pumpWidget(
      _wrap(
        DetailsActionBar(
          hasStarted: true,
          isDone: true,
          isCancelled: false,
          isSaving: false,
          onMarkDone: () {},
          onCancel: () {},
          onEditCompleted: () => edited++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Cancel is hidden once a job is done, so a dead "Complete" button here
    // left the sheet with no action at all — and no way back off Complete,
    // since the status picker lives in the edit form.
    expect(find.text('Cancel Appointment'), findsNothing);
    expect(find.text('Edit completed job'), findsOneWidget);

    await tester.tap(find.text('Edit completed job'));
    await tester.pumpAndSettle();
    expect(edited, 1);
  });

  testWidgets('an employee gets the plain done indicator, not an edit button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        DetailsActionBar(
          hasStarted: true,
          isDone: true,
          isCancelled: false,
          isSaving: false,
          showCancel: false,
          onMarkDone: () {},
          onCancel: () {},
          onEditCompleted: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The rules let an assignee write `status:'done'` and nothing else, so an
    // editable control would only earn them an opaque permission-denied.
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('Edit completed job'), findsNothing);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
  });
}
