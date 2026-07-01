import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';

Widget _host(TargetPlatform platform) => MaterialApp(
  theme: ThemeData(platform: platform),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showConfirmDialog(
            context,
            title: 'Delete?',
            confirmLabel: 'Delete',
            message: 'Are you sure?',
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows CupertinoAlertDialog on iOS', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.iOS));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows Material AlertDialog on Android', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.android));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
