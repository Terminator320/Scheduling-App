// Sweeps every auth screen at every supported text scale on a small-phone
// viewport (375×667 — Pixel 4a / iPhone SE class) and asserts no
// RenderFlex overflow exceptions fire. Catches "render problem at Extra
// Large" regressions on the auth flow before they reach a device.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/auth/screens/create_account_screen.dart';
import 'package:scheduling/features/auth/screens/forgot_password_screen.dart';
import 'package:scheduling/features/auth/screens/login_screen.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/l10n/l10n.dart';

class _MockAuthService extends Mock implements AuthService {}

class _MockRepo extends Mock implements EmployeesRepository {}

// In-app text scales from text_size_screen.dart (Small / Medium / Large /
// XL) plus Android system-level 2.0× to catch the worst case.
const _scales = <double>[0.8, 1, 1.2, 1.4, 2];

// Small-phone viewport. The smallest physical phone in common use is
// ~375 logical width. Picking the smaller dimension exposes overflow
// most reliably without being unrealistic.
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
  });

  for (final scale in _scales) {
    testWidgets('Login renders at scale ${scale}x without overflow', (
      tester,
    ) async {
      await _pumpAtViewport(
        tester,
        _scaled(
          scale: scale,
          home: Login(authService: auth),
          overrides: [employeesRepositoryProvider.overrideWithValue(repo)],
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('CreateAccount renders at scale ${scale}x without overflow', (
      tester,
    ) async {
      await _pumpAtViewport(
        tester,
        _scaled(
          scale: scale,
          home: CreateAccountScreen(authService: auth),
        ),
      );
      expect(tester.takeException(), isNull);
    });

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
  }
}
