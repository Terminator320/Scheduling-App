// Sweeps every auth screen at every text scale on a 375×667 small-phone
// viewport, catching RenderFlex overflow ("render problem at Extra Large")
// before it reaches a device.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/auth/screens/account_setup_screen.dart';
import 'package:scheduling/features/auth/screens/forgot_password_screen.dart';
import 'package:scheduling/features/auth/screens/login_screen.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockAuthService extends Mock implements AuthService {}

class _MockRepo extends Mock implements EmployeesRepository {}

class _MockUser extends Mock implements User {}

// Long enough to wrap. LockedEmailPanel renders the address as a Text
// rather than a disabled field precisely so it wraps instead of truncating
// at large scale — which only gets exercised if the panel is built at all,
// and it is built only when currentUser has an email.
const _longEmail = 'genevieve.beauchamp-tremblay@plomberie-eau-secours.example.com';

// In-app text scales from text_size_screen.dart (Small / Medium / Large /
// XL) plus Android system-level 2.0× to catch the worst case.
const _scales = <double>[0.8, 1, 1.2, 1.4, 2];

// Smallest physical phone in common use is ~375 logical width, so picking
// that dimension exposes overflow most reliably.
const _viewport = Size(375, 667);

Widget _scaled({
  required Widget home,
  required double scale,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: ThemeNotifier(
      themeMode: ThemeMode.light,
      toggleTheme: () {},
      textScale: scale,
      setTextScale: (_) {},
      setLanguage: (_) {},
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: lightTheme(),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: home,
      ),
    ),
  );
}

Future<void> _pumpAtViewport(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = _viewport * tester.view.devicePixelRatio;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

void main() {
  late _MockAuthService auth;
  late _MockRepo repo;

  setUp(() {
    auth = _MockAuthService();
    repo = _MockRepo();
    final user = _MockUser();
    when(() => user.email).thenReturn(_longEmail);
    when(() => auth.currentUser).thenReturn(user);
  });

  for (final scale in _scales) {
    testWidgets('Login renders at scale ${scale}x without overflow', (
      tester,
    ) async {
      await _pumpAtViewport(
        tester,
        _scaled(
          scale: scale,
          home: const Login(),
          overrides: [
            authServiceProvider.overrideWithValue(auth),
            employeesRepositoryProvider.overrideWithValue(repo),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'AccountSetup renders at scale ${scale}x without overflow',
      (tester) async {
        await _pumpAtViewport(
          tester,
          _scaled(
            scale: scale,
            home: AccountSetupScreen(authService: auth),
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'AccountSetup with a typed password renders at scale ${scale}x '
      'without overflow',
      (tester) async {
        await _pumpAtViewport(
          tester,
          _scaled(
            scale: scale,
            home: AccountSetupScreen(authService: auth),
          ),
        );
        // The strength meter and the requirements checklist only render once
        // something is typed, so the empty screen never sweeps them.
        await tester.enterText(find.byType(TextField).at(3), 'Aa1!aaaa');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('ForgotPassword renders at scale ${scale}x without overflow', (
      tester,
    ) async {
      await _pumpAtViewport(
        tester,
        _scaled(
          scale: scale,
          home: ForgotPasswordScreen(authService: auth),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'ForgotPassword sent state renders at scale ${scale}x without overflow',
      (tester) async {
        when(() => auth.sendPasswordResetEmail(any())).thenAnswer((_) async {});
        await _pumpAtViewport(
          tester,
          _scaled(
            scale: scale,
            home: ForgotPasswordScreen(
              authService: auth,
              initialEmail: 'user@example.com',
            ),
          ),
        );
        await tester.tap(find.byType(FilledButton).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
