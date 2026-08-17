import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/settings/widgets/sections/my_scheduling_section.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _harness(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('an admin sees the max-jobs row', (tester) async {
    await tester.pumpWidget(
      _harness(
        MySchedulingSection(isAdmin: true, maxJobsPerDay: 5, onChanged: (_) {}),
      ),
    );

    expect(find.byKey(const Key('myMaxJobsPerDay')), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('a technician sees nothing at all', (tester) async {
    // Hidden, not disabled: maxJobsPerDay is not on the self-service rules
    // allowlist, so an employee has no path here that could ever succeed. A
    // greyed control would only advertise a dead end.
    await tester.pumpWidget(
      _harness(
        MySchedulingSection(
          isAdmin: false,
          maxJobsPerDay: 5,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.byKey(const Key('myMaxJobsPerDay')), findsNothing);
    expect(find.text('SCHEDULING'), findsNothing);
  });

  testWidgets('zero renders as no cap, never as the number 0', (tester) async {
    await tester.pumpWidget(
      _harness(
        MySchedulingSection(isAdmin: true, maxJobsPerDay: 0, onChanged: (_) {}),
      ),
    );

    expect(find.text('0'), findsNothing);
  });

  testWidgets('picking a value reports it', (tester) async {
    // Tall viewport: the Material branch of showAdaptiveActionSheet is a
    // non-scrolling Column, so 13 options overflow the default 600x800 test
    // window. iOS — the only shipping platform — takes the Cupertino branch,
    // which scrolls its own actions, so this is a harness constraint rather
    // than a product one.
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    int? picked;
    await tester.pumpWidget(
      _harness(
        MySchedulingSection(
          isAdmin: true,
          maxJobsPerDay: 5,
          onChanged: (value) => picked = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('myMaxJobsPerDay')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8').last);
    await tester.pumpAndSettle();

    expect(picked, 8);
  });

  testWidgets('no overflow at 260px and 2x text', (tester) async {
    tester.view.physicalSize = const Size(260, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MySchedulingSection(
            isAdmin: true,
            maxJobsPerDay: 12,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
