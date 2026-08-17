import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/settings/widgets/sections/my_availability_section.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/feedback/warning_note.dart';

Widget _harness(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

const _fiveDayWeek = [false, true, true, true, true, true, false];

Widget _section({
  Set<int> conflictDays = const {},
  AvailabilityChanged? onChanged,
  bool onCall = false,
}) => MyAvailabilitySection(
  workingDays: _fiveDayWeek,
  workStartMinutes: 480,
  workEndMinutes: 1020,
  onCall: onCall,
  conflictDays: conflictDays,
  onChanged: onChanged ?? (_, _, _, {required onCall}) {},
);

void main() {
  testWidgets('toggling on-call applies immediately', (tester) async {
    // No save bar here, deliberately — unlike the identity section above it.
    bool? applied;
    await tester.pumpWidget(
      _harness(
        _section(
          onChanged: (_, _, _, {required onCall}) => applied = onCall,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('myOnCall')));
    await tester.pumpAndSettle();

    expect(applied, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toggling a working day applies immediately', (tester) async {
    List<bool>? applied;
    await tester.pumpWidget(
      _harness(
        _section(onChanged: (days, _, _, {required onCall}) => applied = days),
      ),
    );

    await tester.tap(find.byType(FilterChip).first);
    await tester.pumpAndSettle();

    expect(applied, isNotNull);
    expect(applied!.length, 7);
  });

  testWidgets('a conflicting day renders the amber warning', (tester) async {
    await tester.pumpWidget(_harness(_section(conflictDays: const {1})));

    expect(find.byType(WarningNote), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no warning when nothing conflicts', (tester) async {
    await tester.pumpWidget(_harness(_section()));

    expect(find.byType(WarningNote), findsNothing);
  });

  testWidgets('the warning names every conflicting day', (tester) async {
    await tester.pumpWidget(_harness(_section(conflictDays: const {1, 3})));

    final note = tester.widget<WarningNote>(find.byType(WarningNote));
    // Sunday-indexed and UNROTATED: 1 is Monday, 3 is Wednesday. A
    // display-ordered label list here would silently name the wrong days.
    expect(note.message, contains('Mon'));
    expect(note.message, contains('Wed'));
  });

  testWidgets('no overflow at 260px and 2x text', (tester) async {
    tester.view.physicalSize = const Size(260, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _section(conflictDays: const {1, 3}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
