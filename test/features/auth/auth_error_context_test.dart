import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/l10n/l10n.dart';

/// The context-sensitive legs of `toLocalizedMessageInContext`.
///
/// `AuthErrorContext.reauthentication` is passed by the two re-auth catch
/// sites — the delete-account flow and the self-service email change. That
/// each call site actually passes it is pinned separately (see
/// `test/features/settings/widgets/delete_account_flow_test.dart`); this file
/// pins the mapping those sites depend on.
void main() {
  Future<String> messageFor(
    WidgetTester tester,
    AuthFailure failure,
    AuthErrorContext context,
  ) async {
    late String message;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (c) {
            message = failure.toLocalizedMessageInContext(c, context);
            return const SizedBox();
          },
        ),
      ),
    );
    return message;
  }

  group('reauthentication context', () {
    testWidgets('a missing account asks the user to log in again', (t) async {
      expect(
        await messageFor(
          t,
          const AuthFailureUserNotFound(),
          AuthErrorContext.reauthentication,
        ),
        'Please log in again and retry',
      );
    });

    testWidgets('wrong credentials ask the user to log in again', (t) async {
      expect(
        await messageFor(
          t,
          const AuthFailureWrongCredentials(),
          AuthErrorContext.reauthentication,
        ),
        'Please log in again and retry',
      );
    });

    testWidgets('a missing account outside it names the email instead', (
      t,
    ) async {
      expect(
        await messageFor(
          t,
          const AuthFailureUserNotFound(),
          AuthErrorContext.login,
        ),
        'No account found with this email',
      );
    });
  });

  group('register context', () {
    testWidgets('a taken email tells the user how to recover', (t) async {
      expect(
        await messageFor(
          t,
          const AuthFailureEmailAlreadyInUse(),
          AuthErrorContext.register,
        ),
        contains('Sign in instead'),
      );
    });

    testWidgets('a taken email outside it stays the bare statement', (t) async {
      expect(
        await messageFor(
          t,
          const AuthFailureEmailAlreadyInUse(),
          AuthErrorContext.general,
        ),
        'An account with this email already exists',
      );
    });
  });
}
