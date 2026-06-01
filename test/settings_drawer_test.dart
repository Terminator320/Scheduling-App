// test/settings_drawer_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/features/settings/widgets/views/settings_drawer.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/primitives/app_avatar.dart';

Widget _wrap(Widget child) => ThemeNotifier(
      themeMode: ThemeMode.light,
      toggleTheme: () {},
      textScale: 1,
      setTextScale: (_) {},
      setLanguage: (_) {},
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          endDrawer: child,
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows AppAvatar in drawer header', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsDrawer(
      isAdmin: true,
      employeeId: 'e1',
      userName: 'George Vogas',
      email: 'george@vogas.net',
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AppAvatar), findsOneWidget);
  });

  testWidgets('shows user name in drawer header', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsDrawer(
      isAdmin: true,
      employeeId: 'e1',
      userName: 'George Vogas',
      email: 'george@vogas.net',
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('George Vogas'), findsOneWidget);
  });

  testWidgets('shows Admin role badge when isAdmin', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsDrawer(
      isAdmin: true,
      employeeId: 'e1',
      userName: 'George Vogas',
      email: 'george@vogas.net',
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('does not show UserAccountsDrawerHeader', (tester) async {
    await tester.pumpWidget(_wrap(const SettingsDrawer(
      isAdmin: true,
      employeeId: 'e1',
      userName: 'George Vogas',
      email: 'george@vogas.net',
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(UserAccountsDrawerHeader), findsNothing);
  });
}
