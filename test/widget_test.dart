import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  testWidgets('French localizations load', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr', 'CA'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                Text(context.l10n.common_calendar),
                Text(context.l10n.common_language),
                Text(context.l10n.common_resetPassword),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Calendrier'), findsOneWidget);
    expect(find.text('Langue'), findsOneWidget);
    expect(find.text('Réinitialiser le mot de passe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
