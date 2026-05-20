import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/auth/screens/forgot_password_screen.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockAuthService extends Mock implements AuthService {}

Widget _wrap(AuthService authService, {String? initialEmail}) {
  return ThemeNotifier(
    themeMode: ThemeMode.light,
    toggleTheme: () {},
    textScale: 1.0,
    setTextScale: (_) {},
    setLanguage: (_) {},
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: lightTheme(),
      home: ForgotPasswordScreen(
        authService: authService,
        initialEmail: initialEmail,
      ),
    ),
  );
}

void main() {
  late _MockAuthService auth;

  setUp(() {
    auth = _MockAuthService();
  });

  testWidgets('renders email field and send button', (tester) async {
    await tester.pumpWidget(_wrap(auth));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('Send'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows validation error for invalid email', (tester) async {
    await tester.pumpWidget(_wrap(auth, initialEmail: 'not-an-email'));
    await tester.pumpAndSettle();

    // Tap the Send button. textContaining('Send') will hit both the heading
    // and the button — tap the last one (the FilledButton).
    await tester.tap(find.textContaining('Send').last);
    await tester.pumpAndSettle();

    verifyNever(() => auth.sendPasswordResetEmail(any()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('calls AuthService.sendPasswordResetEmail on submit', (
    tester,
  ) async {
    when(() => auth.sendPasswordResetEmail(any())).thenAnswer((_) async {});

    await tester.pumpWidget(_wrap(auth, initialEmail: 'user@example.com'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Send').last);
    await tester.pumpAndSettle();

    verify(() => auth.sendPasswordResetEmail('user@example.com')).called(1);
    expect(tester.takeException(), isNull);
  });
}
