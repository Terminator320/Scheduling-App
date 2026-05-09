// test/settings_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/features/settings/screens/settings_screen.dart';
import 'package:scheduling/l10n/app_localizations.dart';

Widget _wrap({double textScale = 1.0, bool isDark = false}) => ThemeNotifier(
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      toggleTheme: () {},
      textScale: textScale,
      setTextScale: (_) {},
      setLanguage: (_) {},
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsScreen(name: 'Test User', email: 'test@example.com'),
      ),
    );

void main() {
  testWidgets('shows Appearance section header', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.textContaining('APPEARANCE'), findsOneWidget);
  });

  testWidgets('shows Account section header', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.textContaining('ACCOUNT'), findsOneWidget);
  });

  testWidgets('shows Dark Mode label', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.textContaining('Dark Mode'), findsOneWidget);
  });

  testWidgets('shows Text Size label', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.textContaining('Text Size'), findsOneWidget);
  });

  testWidgets('shows Language label', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.textContaining('Language'), findsOneWidget);
  });

  testWidgets('shows EN and FR language buttons', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('FR'), findsOneWidget);
  });

  testWidgets('does not show a Slider widget', (tester) async {
    await tester.pumpWidget(_wrap());
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('shows current text scale label next to Text Size', (tester) async {
    await tester.pumpWidget(_wrap(textScale: 1.0));
    expect(find.text('Medium'), findsOneWidget);
  });

  testWidgets('does not overflow at small screen + 2x text', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
      child: _wrap(),
    ));
    expect(tester.takeException(), isNull);
  });
}
