import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/app_bars/app_header_pair.dart';

const _delegates = <LocalizationsDelegate<Object?>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

Widget _wrap(Widget child, {double textScale = 1.0}) => MaterialApp(
  localizationsDelegates: _delegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: lightTheme(),
  builder: (context, inner) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: inner ?? const SizedBox.shrink(),
  ),
  home: Scaffold(appBar: AppBar(actions: [child])),
);

Widget _wrapWithDrawer(Widget child) => MaterialApp(
  localizationsDelegates: _delegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: lightTheme(),
  home: Scaffold(
    appBar: AppBar(actions: [child]),
    endDrawer: const Drawer(child: Text('drawer-content')),
  ),
);

void main() {
  testWidgets('the calendar pill and menu button meet the 48px tap minimum', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const AppHeaderPair()));
    for (final finder in [
      find.byTooltip('Calendar'),
      find.byTooltip('Open menu'),
    ]) {
      final size = tester.getSize(finder);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('tapping the menu button opens the end drawer', (tester) async {
    await tester.pumpWidget(_wrapWithDrawer(const AppHeaderPair()));
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    expect(find.text('drawer-content'), findsOneWidget);
  });

  testWidgets('the pair survives text scale 2.0 without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const AppHeaderPair(), textScale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
