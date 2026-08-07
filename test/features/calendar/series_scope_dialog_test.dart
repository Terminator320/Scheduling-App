import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/calendar/widgets/dialogs/series_scope_dialog.dart';
import 'package:scheduling/l10n/l10n.dart';

const _thisOnly = 'This visit only';
const _thisAndFuture = 'This and all future visits';

/// Holds what the dialog popped, so a test can assert on it after settling.
class _Result {
  SeriesScopeChoice? choice;
}

/// Pumps a button that opens the dialog and records its result.
Future<_Result> _open(WidgetTester tester, {bool destructive = false}) async {
  final result = _Result();

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: lightTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result.choice = await showSeriesScopeDialog(
                  context,
                  title: 'Apply your changes to…',
                  contextLabel: 'REPEATS EVERY 2 WEEKS',
                  thisOnlyLabel: _thisOnly,
                  thisAndFutureLabel: _thisAndFuture,
                  thisOnlyDetail:
                      '5 Jan · the rest of the series keeps its old details',
                  thisAndFutureDetail: '12 remaining visits through 26 Jan',
                  primaryLabelFor: (choice) =>
                      choice == SeriesScopeChoice.thisOnly
                      ? 'Save this visit'
                      : 'Save 12 visits',
                  destructive: destructive,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('the primary label tracks the chosen scope', (tester) async {
    await _open(tester);

    expect(find.text('REPEATS EVERY 2 WEEKS'), findsOneWidget);
    expect(find.text('12 remaining visits through 26 Jan'), findsOneWidget);
    // This-visit-only is the default, so the safe verb leads.
    expect(find.text('Save this visit'), findsOneWidget);

    await tester.tap(find.text(_thisAndFuture));
    await tester.pumpAndSettle();

    expect(find.text('Save 12 visits'), findsOneWidget);
    expect(find.text('Save this visit'), findsNothing);
  });

  testWidgets('Back closes without a choice', (tester) async {
    final result = await _open(tester);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(result.choice, isNull);
  });

  testWidgets('the primary returns the selection', (tester) async {
    final result = await _open(tester);

    await tester.tap(find.text(_thisAndFuture));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save 12 visits'));
    await tester.pumpAndSettle();

    expect(result.choice, SeriesScopeChoice.thisAndFuture);
  });

  testWidgets('defaults to this-visit-only', (tester) async {
    final result = await _open(tester);

    await tester.tap(find.text('Save this visit'));
    await tester.pumpAndSettle();

    expect(result.choice, SeriesScopeChoice.thisOnly);
  });

  testWidgets('renders without an exception in the destructive variant', (
    tester,
  ) async {
    await _open(tester, destructive: true);

    expect(find.text(_thisOnly), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
