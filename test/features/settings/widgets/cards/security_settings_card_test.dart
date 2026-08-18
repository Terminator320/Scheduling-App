import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/settings/widgets/cards/security_settings_card.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _harness({
  required bool enabled,
  bool isBusy = false,
  Future<void> Function({required bool value})? onToggleAppLock,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SecuritySettingsCard(
        enabled: enabled,
        isBusy: isBusy,
        onToggleAppLock:
            onToggleAppLock ?? ({required value}) async {},
      ),
    ),
  );
}

void main() {
  testWidgets('disables the app-lock switch while its write is in flight', (
    tester,
  ) async {
    var calls = 0;

    await tester.pumpWidget(
      _harness(
        enabled: true,
        isBusy: true,
        onToggleAppLock: ({required value}) async {
          calls += 1;
        },
      ),
    );

    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.onChanged, isNull);
    expect(calls, 0);
  });
}
