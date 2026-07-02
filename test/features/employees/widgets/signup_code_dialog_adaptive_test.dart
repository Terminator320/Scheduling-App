import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/employees/widgets/dialogs/signup_code_dialog.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _host(TargetPlatform platform) => MaterialApp(
  theme: ThemeData(platform: platform),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showSignupCodeDialog(
            context,
            name: 'Zoé',
            code: 'K7Q2-9MZ4-XR8T',
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows CupertinoAlertDialog with the code on iOS', (
    tester,
  ) async {
    await tester.pumpWidget(_host(TargetPlatform.iOS));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('K7Q2-9MZ4-XR8T'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows Material AlertDialog on Android', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.android));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.text('K7Q2-9MZ4-XR8T'), findsOneWidget);
  });

  testWidgets('copy action copies the code and flips to Copied on iOS', (
    tester,
  ) async {
    final clipboardWrites = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardWrites.add(
            (call.arguments as Map<Object?, Object?>)['text'] as String?,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(_host(TargetPlatform.iOS));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy code'));
    await tester.pumpAndSettle();

    expect(clipboardWrites, ['K7Q2-9MZ4-XR8T']);
    expect(find.text('Copied'), findsOneWidget);
  });
}
