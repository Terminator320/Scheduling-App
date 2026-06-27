import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/screens/create_account_screen.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockAuthService extends Mock implements AuthService {}

Widget _wrap(AuthService auth, {String? initialEmail}) {
  return ThemeNotifier(
    themeMode: ThemeMode.light,
    toggleTheme: () {},
    textScale: 1,
    setTextScale: (_) {},
    setLanguage: (_) {},
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: lightTheme(),
      home: CreateAccountScreen(authService: auth, initialEmail: initialEmail),
    ),
  );
}

void main() {
  late _MockAuthService auth;

  setUp(() {
    auth = _MockAuthService();
  });

  testWidgets('renders email, password, confirm-password, and code fields', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(auth));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not call signUpWithCode when fields are empty', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(auth));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    verifyNever(
      () => auth.signUpWithCode(
        email: any<String>(named: 'email'),
        password: any<String>(named: 'password'),
        code: any<String>(named: 'code'),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows banner when signup code is invalid', (tester) async {
    when(
      () => auth.signUpWithCode(
        email: any(named: 'email'),
        password: any(named: 'password'),
        code: any(named: 'code'),
      ),
    ).thenThrow(const AuthFailureInvalidSignupCode());

    await tester.pumpWidget(_wrap(auth));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'test@example.com');
    await tester.enterText(fields.at(1), 'Password1!');
    await tester.enterText(fields.at(2), 'Password1!');
    await tester.enterText(fields.at(3), 'BADCODE');

    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    expect(find.textContaining("isn't valid"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
