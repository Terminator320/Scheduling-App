import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/auth/domain/auth_failure.dart';
import 'package:scheduling/features/auth/screens/accept_invite_code_screen.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/auth/widgets/code_entry_boxes.dart';
import 'package:scheduling/features/employees/domain/models/invite_preview.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';

class _MockAuthService extends Mock implements AuthService {}

final _preview = InvitePreview(
  email: 'newhire@example.com',
  firstName: 'Alex',
  lastName: 'Tremblay',
  role: 'employee',
  expiresAt: DateTime(2026, 8, 16),
);

Widget _wrap(AuthService auth, {String initialCode = ''}) {
  return ProviderScope(
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
        home: AcceptInviteCodeScreen(
          authService: auth,
          initialCode: initialCode,
        ),
        // Stubbed so the push is observable without building the details
        // screen and its dependencies.
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(
            body: Text(
              settings.name == AppRoutes.acceptInviteDetails
                  ? 'DETAILS_REACHED'
                  : 'OTHER_ROUTE',
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField), code);
  await tester.pumpAndSettle();
}

void main() {
  late _MockAuthService auth;

  setUp(() {
    auth = _MockAuthService();
  });

  testWidgets('starts with the CTA disabled and labelled "Enter the code"', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(auth));
    await tester.pumpAndSettle();

    expect(find.text('Enter the code'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('relabels to Continue once all twelve characters are entered', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(auth));
    await tester.pumpAndSettle();

    await _enterCode(tester, 'ABCD-EFGH-JKMN');

    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Enter the code'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('prefills the boxes from a deep-linked code without submitting', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(auth, initialCode: 'abcd-efgh-jkmn'));
    await tester.pumpAndSettle();

    expect(find.text('Continue'), findsOneWidget);
    verifyNever(() => auth.previewInvite(any()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('previews the normalized code and pushes the details route', (
    tester,
  ) async {
    when(() => auth.previewInvite(any())).thenAnswer((_) async => _preview);

    await tester.pumpWidget(_wrap(auth));
    await tester.pumpAndSettle();

    await _enterCode(tester, 'abcd-efgh-jkmn');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    verify(() => auth.previewInvite('ABCDEFGHJKMN')).called(1);
    expect(find.text('DETAILS_REACHED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reddens every box and explains when the code is invalid', (
    tester,
  ) async {
    when(
      () => auth.previewInvite(any()),
    ).thenThrow(const AuthFailureInvalidSignupCode());

    await tester.pumpWidget(_wrap(auth));
    await tester.pumpAndSettle();

    await _enterCode(tester, 'ABCD-EFGH-JKMN');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(
      find.text("That code isn't valid. Check every character and try again."),
      findsOneWidget,
    );
    expect(find.text('DETAILS_REACHED'), findsNothing);

    final errorColor = lightTheme().colorScheme.error;
    final borders = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(CodeEntryBoxes),
            matching: find.byType(Container),
          ),
        )
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.border)
        .whereType<Border>()
        .toList();
    expect(borders.length, 12);
    expect(borders.every((border) => border.top.color == errorColor), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('distinguishes an expired code from an invalid one', (
    tester,
  ) async {
    when(
      () => auth.previewInvite(any()),
    ).thenThrow(const AuthFailureSignupCodeExpired());

    await tester.pumpWidget(_wrap(auth));
    await tester.pumpAndSettle();

    await _enterCode(tester, 'ABCD-EFGH-JKMN');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(
      find.text('That code has expired. Ask your admin for a fresh one.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('banners a rate-limit failure instead of reddening the boxes', (
    tester,
  ) async {
    when(
      () => auth.previewInvite(any()),
    ).thenThrow(const AuthFailureTooManyRequests());

    await tester.pumpWidget(_wrap(auth));
    await tester.pumpAndSettle();

    await _enterCode(tester, 'ABCD-EFGH-JKMN');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('Too many attempts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers the no-code help panel', (tester) async {
    await tester.pumpWidget(_wrap(auth));
    await tester.pumpAndSettle();

    expect(find.text("DON'T HAVE A CODE?"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
