import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  Future<String> messageFor(WidgetTester tester, AuthFailure f) async {
    late String msg;
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
            msg = f.toLocalizedMessage(c);
            return const SizedBox();
          },
        ),
      ),
    );
    return msg;
  }

  testWidgets('invalid signup code message', (t) async {
    expect(
      await messageFor(t, const AuthFailureInvalidSignupCode()),
      contains("isn't valid"),
    );
  });
  testWidgets('expired signup code message', (t) async {
    expect(
      await messageFor(t, const AuthFailureSignupCodeExpired()),
      contains('expired'),
    );
  });
  testWidgets('email-mismatch signup code message', (t) async {
    expect(
      await messageFor(t, const AuthFailureSignupEmailMismatch()),
      contains('different email'),
    );
  });

  group('isExpected', () {
    test('user-correctable failures are expected', () {
      for (final failure in const <AuthFailure>[
        AuthFailureInvalidEmail(),
        AuthFailureUserDisabled(),
        AuthFailureUserNotFound(),
        AuthFailureWrongCredentials(),
        AuthFailureTooManyRequests(),
        AuthFailureNetwork(),
        AuthFailureEmailAlreadyInUse(),
        AuthFailureWeakPassword(),
        AuthFailureRequiresRecentLogin(),
        AuthFailureNotAuthorized(),
        AuthFailureInvalidSignupCode(),
        AuthFailureSignupCodeExpired(),
        AuthFailureSignupEmailMismatch(),
      ]) {
        expect(failure.isExpected, isTrue, reason: '${failure.runtimeType}');
      }
    });

    test('defects and misconfiguration are not expected', () {
      for (final failure in const <AuthFailure>[
        AuthFailureOperationNotAllowed(),
        AuthFailurePermissionDenied(),
        AuthFailureUnknown(),
        AuthFailureAccountCreationIncomplete(),
      ]) {
        expect(failure.isExpected, isFalse, reason: '${failure.runtimeType}');
      }
    });
  });
}
