// Behavioural cover for AccountSetupScreen — the P4c first-sign-in flow where
// an invited employee replaces the shared starting password and activates
// their own account. The screen was previously only swept for overflow, so
// every gate below could be deleted with a green suite.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/connectivity/connectivity_providers.dart';
import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/auth/application/sign_in_controller.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/screens/account_setup_screen.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/employees/domain/policies/starting_password_policy.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';

class _MockAuthService extends Mock implements AuthService {}
class _MockUser extends Mock implements User {}

class _StubSignInController extends SignInController {
  _StubSignInController(this._resumeOutcome);

  final SignInOutcome _resumeOutcome;

  @override
  SignInState build() => const SignInState();

  @override
  Future<SignInOutcome> resumeAfterSignUp() async => _resumeOutcome;
}

/// A password that satisfies every requirement and is NOT the shared default.
const _chosen = 'Chosen1!pass';

Widget _harness({
  required AuthService auth,
  bool offline = false,
  SignInOutcome? resumeOutcome,
}) {
  return ProviderScope(
    overrides: [
      isOfflineProvider.overrideWithValue(offline),
      if (resumeOutcome != null)
        signInControllerProvider.overrideWith(
          () => _StubSignInController(resumeOutcome),
        ),
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
        routes: {
          AppRoutes.login: (_) =>
              const Scaffold(body: Text('login screen')),
          AppRoutes.mainCalendar: (_) =>
              const Scaffold(body: Text('main calendar')),
        },
        home: AccountSetupScreen(authService: auth),
      ),
    ),
  );
}

/// Fills the four required fields. Leaves consent untouched.
Future<void> _fillForm(
  WidgetTester tester, {
  String password = _chosen,
}) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'Alex');
  await tester.enterText(fields.at(1), 'Tremblay');
  await tester.enterText(fields.at(3), password);
  await tester.enterText(fields.at(4), password);
  await tester.pumpAndSettle();
}

Future<void> _consent(WidgetTester tester) async {
  final box = find.byType(Checkbox).first;
  await tester.ensureVisible(box);
  await tester.pumpAndSettle();
  await tester.tap(box);
  await tester.pumpAndSettle();
}

/// The consent row and the CTA sit below the fold at the test viewport.
Future<void> _submit(WidgetTester tester) async {
  final button = find.byType(FilledButton).last;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  late _MockAuthService auth;

  setUp(() {
    auth = _MockAuthService();
    when(() => auth.currentUser).thenReturn(null);
    // Verified by default so the existing gates are exercised in isolation;
    // the verification gate has its own group below.
    when(() => auth.isEmailVerified).thenReturn(true);
    when(() => auth.sendVerificationEmail()).thenAnswer((_) async {});
    when(() => auth.refreshEmailVerified()).thenAnswer((_) async => false);
    when(
      () => auth.completeAccountSetup(
        newPassword: any(named: 'newPassword'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        phone: any(named: 'phone'),
        termsAccepted: any(named: 'termsAccepted'),
        locationConsent: any(named: 'locationConsent'),
      ),
    ).thenAnswer((_) async {});
  });

  group('the consent gate', () {
    testWidgets('a keyboard submit without consent does not activate', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(auth: auth));
      await tester.pumpAndSettle();
      await _fillForm(tester);

      // Submitting from the confirm field reaches _finishSetup directly,
      // without consulting the disabled CTA — which is exactly why the gate
      // is enforced inside _finishSetup and not only on the button.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      verifyNever(
        () => auth.completeAccountSetup(
          newPassword: any(named: 'newPassword'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          phone: any(named: 'phone'),
          termsAccepted: any(named: 'termsAccepted'),
          locationConsent: any(named: 'locationConsent'),
        ),
      );
    });

    testWidgets('consent is passed through as true once given', (tester) async {
      await tester.pumpWidget(_harness(auth: auth));
      await tester.pumpAndSettle();
      await _fillForm(tester);
      await _consent(tester);

      await _submit(tester);

      final call = verify(
        () => auth.completeAccountSetup(
          newPassword: captureAny(named: 'newPassword'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          phone: any(named: 'phone'),
          termsAccepted: captureAny(named: 'termsAccepted'),
          locationConsent: captureAny(named: 'locationConsent'),
        ),
      )..called(1);
      expect(call.captured[0], _chosen);
      // The server stamps the consent timestamps only when these are true, so
      // a flow that activates without them mints an account with no record.
      expect(call.captured[1], isTrue);
      expect(call.captured[2], isTrue);
    });
  });

  group('the terms link in the consent row', () {
    testWidgets('the sentence carries a tappable "terms of service" run', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(auth: auth));
      await tester.pumpAndSettle();

      // Ticking this box stamps termsAcceptedAt, so the agreement has to be
      // reachable from the row that records the acceptance. The link is a
      // TextSpan run inside the checkbox title, found by locating the run that
      // carries a recognizer rather than by matching the copy.
      final title = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('setupConsent')),
          matching: find.byType(Text),
        ),
      );
      final spans = <InlineSpan>[];
      title.textSpan!.visitChildren((span) {
        spans.add(span);
        return true;
      });
      final linked = spans.whereType<TextSpan>().where(
        (s) => s.recognizer != null,
      );

      expect(
        linked,
        hasLength(1),
        reason: 'exactly one run of the consent sentence should be a link',
      );
      // The link text must be a real run of the sentence, not empty — an ARB
      // drift that stops the link text appearing in the sentence falls back to
      // one plain unlinked span, which this would catch.
      expect(linked.single.text, isNotEmpty);
    });
  });

  group('the starting-password gate', () {
    testWidgets('refuses the shared default even though it is "strong"', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(auth: auth));
      await tester.pumpAndSettle();
      // Welcome123! satisfies length, upper, lower, digit and symbol, so the
      // strength checklist alone waves it through. Accepting it would leave
      // the person permanently active on a password every admin knows.
      await _fillForm(tester, password: kDefaultStartingPassword);
      await _consent(tester);

      await _submit(tester);

      verifyNever(
        () => auth.completeAccountSetup(
          newPassword: any(named: 'newPassword'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          phone: any(named: 'phone'),
          termsAccepted: any(named: 'termsAccepted'),
          locationConsent: any(named: 'locationConsent'),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the email-verification gate', () {
    setUp(() => when(() => auth.isEmailVerified).thenReturn(false));

    testWidgets('a keyboard submit while unverified does not activate', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(auth: auth));
      await tester.pumpAndSettle();
      await _fillForm(tester);
      await _consent(tester);

      // The server refuses without email_verified, so letting this through
      // could only produce a failure the person cannot act on from here.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      verifyNever(
        () => auth.completeAccountSetup(
          newPassword: any(named: 'newPassword'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          phone: any(named: 'phone'),
          termsAccepted: any(named: 'termsAccepted'),
          locationConsent: any(named: 'locationConsent'),
        ),
      );
    });

    testWidgets('a successful check clears the gate and activates', (
      tester,
    ) async {
      when(() => auth.refreshEmailVerified()).thenAnswer((_) async => true);
      await tester.pumpWidget(_harness(auth: auth));
      await tester.pumpAndSettle();
      await _fillForm(tester);
      await _consent(tester);

      final check = find.byKey(const Key('checkVerification'));
      await tester.ensureVisible(check);
      await tester.pumpAndSettle();
      await tester.tap(check);
      await tester.pumpAndSettle();

      await _submit(tester);

      verify(
        () => auth.completeAccountSetup(
          newPassword: any(named: 'newPassword'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          phone: any(named: 'phone'),
          termsAccepted: any(named: 'termsAccepted'),
          locationConsent: any(named: 'locationConsent'),
        ),
      ).called(1);
    });

    testWidgets('the panel is gone once the address is verified', (
      tester,
    ) async {
      when(() => auth.isEmailVerified).thenReturn(true);
      await tester.pumpWidget(_harness(auth: auth));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('checkVerification')), findsNothing);
      expect(find.byKey(const Key('sendVerificationEmail')), findsNothing);
    });

    testWidgets(
      'check verification cannot start while sending the email is already in flight',
      (tester) async {
        final sendCompleter = Completer<void>();
        when(() => auth.sendVerificationEmail()).thenAnswer(
          (_) => sendCompleter.future,
        );

        await tester.pumpWidget(_harness(auth: auth));
        await tester.pumpAndSettle();

        final send = find.byKey(const Key('sendVerificationEmail'));
        final check = find.byKey(const Key('checkVerification'));
        await tester.ensureVisible(send);
        await tester.pumpAndSettle();

        await tester.tap(send);
        await tester.pump();
        await tester.tap(check, warnIfMissed: false);
        await tester.pump();

        verifyNever(() => auth.refreshEmailVerified());

        sendCompleter.complete();
        await tester.pumpAndSettle();
      },
    );
  });

  group('the offline guard', () {
    testWidgets('does not call the server while offline', (tester) async {
      await tester.pumpWidget(_harness(auth: auth, offline: true));
      await tester.pumpAndSettle();
      await _fillForm(tester);
      await _consent(tester);

      await _submit(tester);

      // An awaited write offline never resolves until the connection returns,
      // so the button would just spin.
      verifyNever(
        () => auth.completeAccountSetup(
          newPassword: any(named: 'newPassword'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          phone: any(named: 'phone'),
          termsAccepted: any(named: 'termsAccepted'),
          locationConsent: any(named: 'locationConsent'),
        ),
      );
    });
  });

  group('the setup sign-out path', () {
    testWidgets(
      'log out stays disabled while a verification request is in flight',
      (tester) async {
        final user = _MockUser();
        when(() => user.email).thenReturn('a@b.com');
        when(() => auth.currentUser).thenReturn(user);
        when(() => auth.isEmailVerified).thenReturn(false);
        final sendCompleter = Completer<void>();
        when(() => auth.sendVerificationEmail()).thenAnswer(
          (_) => sendCompleter.future,
        );

        await tester.pumpWidget(_harness(auth: auth));
        await tester.pumpAndSettle();

        final send = find.byKey(const Key('sendVerificationEmail'));
        await tester.ensureVisible(send);
        await tester.pumpAndSettle();
        await tester.tap(send);
        await tester.pump();

        final logOut = find.widgetWithText(TextButton, 'Log out');
        expect(tester.widget<TextButton>(logOut).onPressed, isNull);

        await tester.tap(logOut, warnIfMissed: false);
        await tester.pump();
        verifyNever(() => auth.signOut());

        sendCompleter.complete();
        await tester.pumpAndSettle();

        expect(tester.widget<TextButton>(logOut).onPressed, isNotNull);
      },
    );

    testWidgets('shows a recoverable error if sign-out fails', (tester) async {
      when(() => auth.signOut()).thenThrow(Exception('sign-out failed'));
      await tester.pumpWidget(_harness(auth: auth));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Log out'));
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong, please try again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('post-setup recovery', () {
    testWidgets('a pending resume routes back to login for a clean retry', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          auth: auth,
          resumeOutcome: const SignInProfilePending(),
        ),
      );
      await tester.pumpAndSettle();
      await _fillForm(tester);
      await _consent(tester);

      await _submit(tester);
      await tester.pumpAndSettle();

      expect(find.text('login screen'), findsOneWidget);
    });

    testWidgets(
      'unexpected resume outcomes re-enable the screen instead of leaving it stuck loading',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            auth: auth,
            resumeOutcome: const SignInError(AuthFailureUnknown()),
          ),
        );
        await tester.pumpAndSettle();
        await _fillForm(tester);
        await _consent(tester);

        await _submit(tester);

        expect(
          find.text('Something went wrong, please try again'),
          findsOneWidget,
        );
        final button = tester.widget<FilledButton>(find.byType(FilledButton).last);
        expect(button.onPressed, isNotNull);
      },
    );
  });
}
