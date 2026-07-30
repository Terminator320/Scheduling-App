import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/sheets/form_sheet_frame.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: lightTheme(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('renders Cancel, the title and the primary verb', (tester) async {
    await tester.pumpWidget(
      _wrap(
        FormSheetFrame(
          title: 'New job',
          primaryLabel: 'Save',
          onPrimary: () {},
          children: const [Text('body')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('New job'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('fires the primary verb', (tester) async {
    var saved = 0;
    await tester.pumpWidget(
      _wrap(
        FormSheetFrame(
          title: 'New job',
          primaryLabel: 'Save',
          onPrimary: () => saved++,
          children: const [Text('body')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    expect(saved, 1);
  });

  testWidgets('swaps the primary verb for a spinner while busy', (
    tester,
  ) async {
    var saved = 0;
    await tester.pumpWidget(
      _wrap(
        FormSheetFrame(
          title: 'New job',
          primaryLabel: 'Save',
          isBusy: true,
          onPrimary: () => saved++,
          children: const [Text('body')],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Save'), findsNothing);
    // Busy disables the verb, so an in-flight save can't be double-submitted.
    await tester.tap(find.byType(FormSheetFrame), warnIfMissed: false);
    expect(saved, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a null onPrimary renders the verb disabled', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FormSheetFrame(
          title: 'New job',
          primaryLabel: 'Save',
          children: [Text('body')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<TextButton>(
      find.ancestor(of: find.text('Save'), matching: find.byType(TextButton)),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('Cancel pops the sheet by default', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const FormSheetFrame(
                title: 'New job',
                primaryLabel: 'Save',
                children: [Text('body')],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsNothing);
  });
}
