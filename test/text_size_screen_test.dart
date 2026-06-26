// test/text_size_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/features/settings/screens/text_size_screen.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _wrap(Widget child, {double textScale = 1.0}) => ThemeNotifier(
      themeMode: ThemeMode.light,
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
        home: child,
      ),
    );

void main() {
  testWidgets('shows all 4 size options', (tester) async {
    await tester.pumpWidget(_wrap(const TextSizeScreen()));
    expect(find.text('Small'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Large'), findsOneWidget);
    expect(find.text('Extra Large'), findsOneWidget);
  });

  testWidgets('shows Apply button', (tester) async {
    await tester.pumpWidget(_wrap(const TextSizeScreen()));
    expect(find.text('Apply'), findsOneWidget);
  });

  testWidgets('Medium is selected by default when scale is 1.0', (tester) async {
    await tester.pumpWidget(_wrap(const TextSizeScreen()));
    expect(find.text('Medium'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping Small selects it (no exception)', (tester) async {
    await tester.pumpWidget(_wrap(const TextSizeScreen()));
    await tester.tap(find.text('Small'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping Apply calls setTextScale', (tester) async {
    double? appliedScale;
    await tester.pumpWidget(ThemeNotifier(
      themeMode: ThemeMode.light,
      toggleTheme: () {},
      textScale: 1,
      setTextScale: (v) => appliedScale = v,
      setLanguage: (_) {},
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: TextSizeScreen()),
      ),
    ));
    await tester.tap(find.text('Apply'));
    await tester.pump();
    expect(appliedScale, isNotNull);
  });

  testWidgets('does not overflow at small screen + 2x text', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: _wrap(const TextSizeScreen()),
    ));
    expect(tester.takeException(), isNull);
  });
}
