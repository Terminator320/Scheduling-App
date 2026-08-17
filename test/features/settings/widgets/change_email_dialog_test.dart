import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/settings/widgets/dialogs/change_email_dialog.dart';
import 'package:scheduling/l10n/l10n.dart';

Widget _harness(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Future<void> _fill(
  WidgetTester tester, {
  required String email,
  required String confirm,
  String password = 'hunter22',
}) async {
  await tester.enterText(find.byKey(const Key('newEmail')), email);
  await tester.enterText(find.byKey(const Key('confirmEmail')), confirm);
  await tester.enterText(find.byKey(const Key('reauthPassword')), password);
  await tester.pumpAndSettle();
}

void main() {
  // The body reports a draft that is non-null ONLY when the request is
  // complete and self-consistent; the enclosing FormSheetFrame gates its Save
  // on exactly that. Asserting on the draft tests the contract directly.
  late ChangeEmailDraft? draft;

  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    draft = null;
    await tester.pumpWidget(
      _harness(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: ChangeEmailDialogBody(
            currentEmail: 'theo@example.com',
            onDraftChanged: (value) => draft = value,
          ),
        ),
      ),
    );
  }

  testWidgets('no draft on an empty form', (tester) async {
    await pump(tester);

    expect(draft, isNull);
  });

  testWidgets('no draft while the two addresses differ', (tester) async {
    // The Admin SDK sets the address with no proof of control, so a typo means
    // the person cannot sign in. Typing it twice is the guard.
    await pump(tester);
    await _fill(
      tester,
      email: 'theo.new@example.com',
      confirm: 'theo.nwe@example.com',
    );

    expect(draft, isNull);
    expect(find.text("The two addresses don't match."), findsOneWidget);
  });

  testWidgets('a draft appears once both match and a password is given', (
    tester,
  ) async {
    await pump(tester);
    await _fill(
      tester,
      email: 'theo.new@example.com',
      confirm: 'theo.new@example.com',
    );

    expect(draft, isNotNull);
  });

  testWidgets('no draft without a password', (tester) async {
    // Re-auth is not optional: an unattended unlocked phone changing the
    // sign-in address is the account-takeover primitive.
    await pump(tester);
    await _fill(
      tester,
      email: 'theo.new@example.com',
      confirm: 'theo.new@example.com',
      password: '',
    );

    expect(draft, isNull);
  });

  testWidgets('no draft when the address is unchanged', (tester) async {
    await pump(tester);
    await _fill(
      tester,
      email: 'theo@example.com',
      confirm: 'theo@example.com',
    );

    expect(draft, isNull);
  });

  testWidgets('no mismatch error until the confirm field has content', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('newEmail')), 'a@b.com');
    await tester.pumpAndSettle();

    expect(find.text("The two addresses don't match."), findsNothing);
  });

  testWidgets('addresses compare case- and whitespace-insensitively', (
    tester,
  ) async {
    // The callable lowercases anyway, so a case-only difference is not a typo.
    await pump(tester);
    await _fill(
      tester,
      email: ' Theo.New@Example.com ',
      confirm: 'theo.new@example.com',
    );

    expect(draft, isNotNull);
  });

  testWidgets('the draft carries a normalized address and a raw password', (
    tester,
  ) async {
    await pump(tester);
    await _fill(
      tester,
      email: ' Theo.New@Example.com ',
      confirm: 'theo.new@example.com',
      password: '  Hunter22  ',
    );

    expect(draft!.email, 'theo.new@example.com');
    // NOT normalized — reauthenticateWithPassword trims it, and lowercasing a
    // password would be a bug.
    expect(draft!.password, '  Hunter22  ');
  });

  testWidgets('a completed draft is revoked when the form is broken again', (
    tester,
  ) async {
    await pump(tester);
    await _fill(
      tester,
      email: 'theo.new@example.com',
      confirm: 'theo.new@example.com',
    );
    expect(draft, isNotNull);

    await tester.enterText(find.byKey(const Key('reauthPassword')), '');
    await tester.pumpAndSettle();

    expect(draft, isNull);
  });

  testWidgets('the password field opts out of IME personalized learning', (
    tester,
  ) async {
    // Every password field here has a Show/Hide toggle, so obscureText is not
    // a safe proxy — the instant it is tapped the field renders plain text
    // that a third-party keyboard could retain and cloud-sync.
    await pump(tester);

    final field = tester.widget<TextField>(
      find.byKey(const Key('reauthPassword')),
    );
    expect(field.enableIMEPersonalizedLearning, isFalse);
    expect(field.obscureText, isTrue);
  });

  testWidgets('revealing the password keeps the IME opt-out', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('reauthPasswordToggle')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('reauthPassword')),
    );
    expect(field.obscureText, isFalse);
    expect(field.enableIMEPersonalizedLearning, isFalse);
  });

  testWidgets('no overflow at 260px and 2x text', (tester) async {
    tester.view.physicalSize = const Size(260, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pump(tester, textScale: 2);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
