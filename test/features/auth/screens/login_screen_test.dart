import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/auth/screens/login_screen.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockAuthService extends Mock implements AuthService {}

class _MockRepo extends Mock implements EmployeesRepository {}

Widget _wrap(AuthService auth, EmployeesRepository repo) {
  return ProviderScope(
    overrides: [employeesRepositoryProvider.overrideWithValue(repo)],
    child: ThemeNotifier(
      themeMode: ThemeMode.light,
      toggleTheme: () {},
      textScale: 1.0,
      setTextScale: (_) {},
      setLanguage: (_) {},
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: lightTheme(),
        home: Login(authService: auth),
      ),
    ),
  );
}

void main() {
  late _MockAuthService auth;
  late _MockRepo repo;

  setUp(() {
    auth = _MockAuthService();
    repo = _MockRepo();
  });

  testWidgets('renders email and password fields', (tester) async {
    await tester.pumpWidget(_wrap(auth, repo));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not call signIn when fields are empty', (tester) async {
    await tester.pumpWidget(_wrap(auth, repo));
    await tester.pumpAndSettle();

    // Submit-on-empty path: validators trip and we never hit the network.
    final signInButton = find.widgetWithText(FilledButton, 'Sign in');
    if (signInButton.evaluate().isEmpty) {
      // Fallback if l10n delegates aren't registered — find any FilledButton.
      await tester.tap(find.byType(FilledButton).first);
    } else {
      await tester.tap(signInButton);
    }
    await tester.pumpAndSettle();

    verifyNever(
      () => auth.signIn(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
