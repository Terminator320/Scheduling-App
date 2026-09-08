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

/// The "Start job" slot (2026-09-01).
void main() {
  testWidgets('an open, not-yet-started job offers Start above Complete', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        DetailsActionBar(
          isDone: false,
          isCancelled: false,
          isSaving: false,
          onMarkDone: () {},
          onCancel: () {},
          onStart: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final start = tester.getTopLeft(find.text('Start job'));
    final done = tester.getTopLeft(find.text('Mark as complete'));
    expect(start.dy, lessThan(done.dy));
  });

  testWidgets('a job already in progress has nothing to start', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        DetailsActionBar(
          isDone: false,
          isCancelled: false,
          isInProgress: true,
          isSaving: false,
          onMarkDone: () {},
          onCancel: () {},
          onStart: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Start job'), findsNothing);
    expect(find.text('Mark as complete'), findsOneWidget);
  });

  testWidgets('a surface that may not start the job gets no button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        DetailsActionBar(
          isDone: false,
          isCancelled: false,
          isSaving: false,
          onMarkDone: () {},
          onCancel: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Start job'), findsNothing);
  });

  testWidgets('a closed job offers no Start either way', (tester) async {
    for (final (done, cancelled) in const [(true, false), (false, true)]) {
      await tester.pumpWidget(
        _wrap(
          DetailsActionBar(
            isDone: done,
            isCancelled: cancelled,
            isSaving: false,
            onMarkDone: () {},
            onCancel: () {},
            onStart: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Start job'), findsNothing);
    }
  });

  testWidgets('tapping Start fires the callback once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        DetailsActionBar(
          isDone: false,
          isCancelled: false,
          isSaving: false,
          onMarkDone: () {},
          onCancel: () {},
          onStart: () => taps++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start job'));
    await tester.pumpAndSettle();

    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Start is disabled while another action is saving', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        DetailsActionBar(
          isDone: false,
          isCancelled: false,
          isSaving: true,
          onMarkDone: () {},
          onCancel: () {},
          onStart: () => taps++,
        ),
      ),
    );
    // A plain pump: the busy spinner animates, so settle would never return.
    await tester.pump();
    await tester.tap(find.text('Start job'), warnIfMissed: false);
    await tester.pump();

    expect(taps, 0);
  });
}
