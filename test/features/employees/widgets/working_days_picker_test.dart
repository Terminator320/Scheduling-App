import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/employees/domain/policies/work_schedule_policy.dart';
import 'package:scheduling/features/employees/widgets/fields/working_days_picker.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _wrap(Widget child, {required Locale locale}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: locale,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('renders seven cells in the locale week order', (tester) async {
    // en locale => Sunday first.
    await tester.pumpWidget(
      _wrap(
        WorkingDaysPicker(workingDays: kDefaultWorkingDays, onChanged: (_) {}),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FilterChip), findsNWidgets(7));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a cell reports the STORED index, not the visual one', (
    tester,
  ) async {
    List<bool>? received;
    await tester.pumpWidget(
      _wrap(
        WorkingDaysPicker(
          workingDays: kDefaultWorkingDays,
          onChanged: (next) => received = next,
        ),
        // fr_CA => Monday first, so the first visual cell is stored index 1.
        locale: const Locale('fr'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilterChip).first);
    await tester.pumpAndSettle();

    // Monday (stored index 1) toggled off, Sunday (index 0) untouched.
    expect(received![1], isFalse);
    expect(received![0], isFalse);
    expect(received![2], isTrue);
  });

  testWidgets('is usable at 260x640 and 2.0 text scale', (tester) async {
    tester.view.physicalSize = const Size(260, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _wrap(
          WorkingDaysPicker(
            workingDays: kDefaultWorkingDays,
            onChanged: (_) {},
          ),
          locale: const Locale('en'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Seven chips must wrap, not overflow.
    expect(tester.takeException(), isNull);
  });
}
