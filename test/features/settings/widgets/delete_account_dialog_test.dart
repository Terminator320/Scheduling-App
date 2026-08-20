import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/settings/widgets/dialogs/delete_account_dialog.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/shared/widgets/dialogs/confirm_dialog.dart';

Future<bool?> _showConfirm(WidgetTester tester, {required bool isAdmin}) async {
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              // Mirrors the composition in settings_screen._confirmDeleteAccount.
              onPressed: () async {
                result = await showConfirmDialog(
                  context,
                  title: context.l10n.settings_deleteAccountConfirmTitle,
                  confirmLabel: context.l10n.settings_deletePermanently,
                  content: DeleteAccountWarningContent(isAdmin: isAdmin),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('delete-account confirm dialog', () {
    testWidgets('shows admin warning when isAdmin = true', (tester) async {
      await _showConfirm(tester, isAdmin: true);
      expect(find.text('Delete account?'), findsOneWidget);
      expect(
        find.textContaining('admin'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides admin warning when isAdmin = false', (tester) async {
      await _showConfirm(tester, isAdmin: false);
      expect(find.text('Delete account?'), findsOneWidget);
      expect(
        find.textContaining('admin'),
        findsNothing,
      );
    });

    testWidgets('Cancel returns false', (tester) async {
      await _showConfirm(tester, isAdmin: false);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Delete account?'), findsNothing);
    });

    testWidgets('Delete permanently button is present', (tester) async {
      await _showConfirm(tester, isAdmin: false);
      expect(find.text('Delete permanently'), findsOneWidget);
    });
  });

  group('DeleteAccountReauthDialog', () {
    testWidgets('shows password field with obscured text by default', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await showDialog<String>(
                      context: context,
                      builder: (_) => const DeleteAccountReauthDialog(),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
      expect(find.text('Confirm your password'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Delete permanently is disabled until a password is entered',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      await showDialog<String>(
                        context: context,
                        builder: (_) => const DeleteAccountReauthDialog(),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Delete permanently'),
        );
        expect(button.onPressed, isNull);

        await tester.enterText(find.byType(TextField), 'hunter2');
        await tester.pumpAndSettle();

        final enabledButton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Delete permanently'),
        );
        expect(enabledButton.onPressed, isNotNull);
      },
    );

    testWidgets('empty keyboard submit keeps the dialog open', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await showDialog<String>(
                      context: context,
                      builder: (_) => const DeleteAccountReauthDialog(),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Confirm your password'), findsOneWidget);
    });

    testWidgets('renders the Cupertino variant on iOS', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showCupertinoDialog<String>(
                      context: context,
                      builder: (_) => const DeleteAccountReauthDialog(),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      final field = tester.widget<CupertinoTextField>(
        find.byType(CupertinoTextField),
      );
      expect(field.obscureText, isTrue);

      await tester.enterText(find.byType(CupertinoTextField), 'hunter2');
      // The destructive action is null-gated on `_hasPassword`, so the rebuild
      // that enables it has to land before the tap.
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      expect(result, 'hunter2');
    });
  });
}
