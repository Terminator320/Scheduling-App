import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/calendar/widgets/dialogs/series_scope_dialog.dart';
import 'package:scheduling/l10n/l10n.dart';

/// The scope dialog stacks a title, two radio options with a consequence line
/// each, and an action row — the tallest custom surface in the app, and the
/// first to run off a small screen at a large text scale.
///
/// BOTH vocabularies are pinned. The repeat copy overflowed by 178px here
/// before `AppDialogFrame` was made to scroll (2026-08-27) — the run copy
/// added that day was shorter and overflowed by less, so testing only the new
/// strings would have credited the fix to them and left the older, worse case
/// unpinned.
///
/// Local harness on purpose — there is deliberately no shared `_scaledHarness`
/// in this repo, each file owns its own. 260 logical px is the usual worst
/// case, and 2x text is what turns a comfortable label into an overflow.
Widget _harness({required Widget child, required Locale locale}) => MaterialApp(
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaQuery(
    data: const MediaQueryData(textScaler: TextScaler.linear(2)),
    child: Scaffold(body: child),
  ),
);

void main() {
  for (final locale in const [Locale('en'), Locale('fr')]) {
    testWidgets('the run scope dialog does not overflow in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(260, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _harness(
          locale: locale,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSeriesScopeDialog(
                context,
                title: context.l10n.calendar_applyChangesTo,
                contextLabel: context.l10n.calendar_runDayLabel(3, 5),
                thisOnlyLabel: context.l10n.calendar_editThisDayOnly,
                thisAndFutureLabel:
                    context.l10n.calendar_editThisAndFollowingDays,
                thisOnlyDetail: context.l10n.calendar_thisDayKeepsRun(
                  '5 August 2026',
                ),
                thisAndFutureDetail: context.l10n.calendar_remainingDaysThrough(
                  3,
                  '7 August 2026',
                ),
                primaryLabelFor: (_) => context.l10n.calendar_saveNDays(3),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('the repeat scope dialog does not overflow in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(260, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _harness(
          locale: locale,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSeriesScopeDialog(
                context,
                title: context.l10n.calendar_applyChangesTo,
                contextLabel: context.l10n.calendar_repeatsEveryLabel(
                  'EVERY 2 WEEKS',
                ),
                thisOnlyLabel: context.l10n.calendar_editThisVisitOnly,
                thisAndFutureLabel:
                    context.l10n.calendar_editThisAndFutureVisits,
                thisOnlyDetail: context.l10n.calendar_thisVisitKeepsSeries(
                  '5 August 2026',
                ),
                thisAndFutureDetail: context.l10n
                    .calendar_remainingVisitsThrough(3, '7 August 2026'),
                primaryLabelFor: (_) => context.l10n.calendar_saveNVisits(3),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
