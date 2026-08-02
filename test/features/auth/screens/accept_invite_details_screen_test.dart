import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/screens/accept_invite_details_screen.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/invite_preview.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockAuthService extends Mock implements AuthService {}

class _MockRepo extends Mock implements EmployeesRepository {}

const _email = 'newhire@example.com';
const _code = 'ABCDEFGHJKMN';

final _preview = InvitePreview(
  email: _email,
  firstName: 'Alex',
  lastName: 'Tremblay',
  role: 'employee',
  expiresAt: DateTime(2026, 8, 16),
);

Widget _wrap(AuthService auth, EmployeesRepository repo) {
  return ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(auth),
      employeesRepositoryProvider.overrideWithValue(repo),
    ],
    child: ThemeNotifier(
      themeMode: ThemeMode.light,
      toggleTheme: () {},
      textScale: 1,
      setTextScale: (_) {},
      setLanguage: (_) {},
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: lightTheme(),
        home: AcceptInviteDetailsScreen(
          code: _code,
          preview: _preview,
          authService: auth,
        ),
      ),
    ),
  );
}

/// Tall enough that the consent row and the submit button are laid out
/// without dragging the scroll view (P4 §8d).
Future<void> _pumpTall(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(420, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

Future<void> _fillForm(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'Alex');
  await tester.enterText(fields.at(1), 'Tremblay');
  await tester.enterText(fields.at(2), '5145551234');
  await tester.enterText(fields.at(3), 'Password1!');
  await tester.enterText(fields.at(4), 'Password1!');
  await tester.pumpAndSettle();
}

FilledButton _submitButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton).first);

void main() {
  late _MockAuthService auth;
  late _MockRepo repo;

  setUp(() {
    auth = _MockAuthService();
    repo = _MockRepo();
    when(() => auth.currentUser).thenReturn(null);
  });

  testWidgets('renders the invite banner with the role and expiry', (
    tester,
  ) async {
    await _pumpTall(tester, _wrap(auth, repo));

    expect(find.text("You're invited to join as Employee"), findsOneWidget);
    expect(find.textContaining('Expires'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the invite email locked, never as an editable field', (
    tester,
  ) async {
    await _pumpTall(tester, _wrap(auth, repo));

    expect(find.text(_email), findsOneWidget);
    expect(find.text('From invite'), findsOneWidget);

    // First, last, phone, password, confirm — and no email field among them.
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.length, 5);
    expect(
      fields.every((field) => field.controller?.text != _email),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('seeds the name fields from the invite', (tester) async {
    await _pumpTall(tester, _wrap(auth, repo));

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields[0].controller?.text, 'Alex');
    expect(fields[1].controller?.text, 'Tremblay');
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps Create account disabled until consent is ticked', (
    tester,
  ) async {
    await _pumpTall(tester, _wrap(auth, repo));
    await _fillForm(tester);

    expect(_submitButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const Key('inviteConsent')));
    await tester.pumpAndSettle();

    expect(_submitButton(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not sign up while required fields are empty', (
    tester,
  ) async {
    await _pumpTall(tester, _wrap(auth, repo));

    await tester.tap(find.byKey(const Key('inviteConsent')));
    await tester.pumpAndSettle();
    // Names are seeded from the invite, so clear them to trip the validator.
    await tester.enterText(find.byType(TextField).at(0), '');
    await tester.enterText(find.byType(TextField).at(1), '');
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    verifyNever(
      () => auth.signUpWithCode(
        email: any(named: 'email'),
        password: any(named: 'password'),
        code: any(named: 'code'),
      ),
    );
    expect(find.text('Name is required'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejects a password that fails the requirements', (tester) async {
    await _pumpTall(tester, _wrap(auth, repo));

    await tester.tap(find.byKey(const Key('inviteConsent')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(3), 'weak');
    await tester.enterText(find.byType(TextField).at(4), 'weak');
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    verifyNever(
      () => auth.signUpWithCode(
        email: any(named: 'email'),
        password: any(named: 'password'),
        code: any(named: 'code'),
      ),
    );
    expect(
      find.text("Password doesn't meet all the requirements below"),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejects a mismatched confirmation', (tester) async {
    await _pumpTall(tester, _wrap(auth, repo));

    await tester.tap(find.byKey(const Key('inviteConsent')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(3), 'Password1!');
    await tester.enterText(find.byType(TextField).at(4), 'Password2!');
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'submits the invite email, the profile and both consent flags true',
    (tester) async {
      when(
        () => auth.signUpWithCode(
          email: any(named: 'email'),
          password: any(named: 'password'),
          code: any(named: 'code'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          phone: any(named: 'phone'),
          termsAccepted: any(named: 'termsAccepted'),
          locationConsent: any(named: 'locationConsent'),
        ),
      ).thenAnswer((_) async {});

      await _pumpTall(tester, _wrap(auth, repo));
      await _fillForm(tester);
      await tester.tap(find.byKey(const Key('inviteConsent')));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton).first);
      await tester.pumpAndSettle();

      verify(
        () => auth.signUpWithCode(
          email: _email,
          password: 'Password1!',
          code: _code,
          firstName: 'Alex',
          lastName: 'Tremblay',
          // Stored formatted, per the phone invariant.
          phone: '(514) 555-1234',
          termsAccepted: true,
          locationConsent: true,
        ),
      ).called(1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirms the account and offers sign-in when the profile is not '
    'readable yet',
    (tester) async {
      when(
        () => auth.signUpWithCode(
          email: any(named: 'email'),
          password: any(named: 'password'),
          code: any(named: 'code'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          phone: any(named: 'phone'),
          termsAccepted: any(named: 'termsAccepted'),
          locationConsent: any(named: 'locationConsent'),
        ),
      ).thenAnswer((_) async {});

      await _pumpTall(tester, _wrap(auth, repo));
      await _fillForm(tester);
      await tester.tap(find.byKey(const Key('inviteConsent')));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton).first);
      await tester.pumpAndSettle();

      // currentUser is null, so resumeAfterSignUp reports no session.
      expect(
        find.text('Account created. You can now sign in.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('banners a dead code and offers to re-enter it', (tester) async {
    when(
      () => auth.signUpWithCode(
        email: any(named: 'email'),
        password: any(named: 'password'),
        code: any(named: 'code'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        phone: any(named: 'phone'),
        termsAccepted: any(named: 'termsAccepted'),
        locationConsent: any(named: 'locationConsent'),
      ),
    ).thenThrow(const AuthFailureInvalidSignupCode());

    await _pumpTall(tester, _wrap(auth, repo));
    await _fillForm(tester);
    await tester.tap(find.byKey(const Key('inviteConsent')));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    expect(find.textContaining("isn't valid"), findsOneWidget);
    expect(find.text('Re-enter code'), findsOneWidget);
    // The button is live again so the attempt can be retried.
    expect(_submitButton(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the strength meter once a password is typed', (
    tester,
  ) async {
    await _pumpTall(tester, _wrap(auth, repo));

    expect(find.text('Strong'), findsNothing);

    await tester.enterText(find.byType(TextField).at(3), 'Password1!');
    await tester.pumpAndSettle();

    expect(find.text('Strong'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the requirements checklist under the meter', (
    tester,
  ) async {
    await _pumpTall(tester, _wrap(auth, repo));

    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(find.text('A symbol (!@#%&*…)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
