import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/fields/app_search_bar.dart';

Widget _localized({required Widget body, Locale? locale}) => MaterialApp(
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: body),
);

void main() {
  testWidgets('AppSearchBar calls onChanged when typing', (tester) async {
    var result = '';
    await tester.pumpWidget(
      _localized(
        body: AppSearchBar(
          onChanged: (v) => result = v,
          hintText: 'Search clients...',
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Sarah');
    expect(result, 'Sarah');
  });

  testWidgets('AppSearchBar shows explicit hint text', (tester) async {
    await tester.pumpWidget(
      _localized(
        body: AppSearchBar(onChanged: (_) {}, hintText: 'Search employees...'),
      ),
    );
    expect(find.text('Search employees...'), findsOneWidget);
  });

  testWidgets('AppSearchBar falls back to the localized default hint', (
    tester,
  ) async {
    await tester.pumpWidget(_localized(body: AppSearchBar(onChanged: (_) {})));
    expect(find.text('Search...'), findsOneWidget);

    await tester.pumpWidget(
      _localized(
        body: AppSearchBar(onChanged: (_) {}),
        locale: const Locale('fr'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rechercher...'), findsOneWidget);
  });

  testWidgets('AppSearchBar preferredSize height is 60 at scale 1', (
    tester,
  ) async {
    final bar = AppSearchBar(onChanged: (_) {});
    expect(bar.preferredSize.height, 60);
  });

  testWidgets('AppSearchBar preferredSize grows with the text scaler', (
    tester,
  ) async {
    final unscaled = AppSearchBar(onChanged: (_) {});
    final scaled = AppSearchBar(
      onChanged: (_) {},
      textScaler: const TextScaler.linear(2),
    );
    // The field portion doubles; the fixed margins don't.
    expect(
      scaled.preferredSize.height,
      unscaled.preferredSize.height + 44,
    );
  });

  testWidgets('AppSearchBar does not overflow at 2x text on phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _localized(
          body: AppBar(bottom: AppSearchBar(onChanged: (_) {})),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
