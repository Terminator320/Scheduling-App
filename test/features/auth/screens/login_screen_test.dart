import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/theme/theme_notifier.dart';
import 'package:scheduling/core/theme/themes.dart';
import 'package:scheduling/features/auth/screens/login_screen.dart';
import 'package:scheduling/features/auth/services/auth_service.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/l10n/l10n.dart';
import 'package:scheduling/routes/app_routes.dart';

class _MockAuthService extends Mock implements AuthService {}

class _MockRepo extends Mock implements EmployeesRepository {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockUser extends Mock implements User {}

Widget _wrap(AuthService auth, EmployeesRepository repo) {
  return ProviderScope(
    overrides: [employeesRepositoryProvider.overrideWithValue(repo)],
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
        home: Login(authService: auth),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: Text(
              settings.name == AppRoutes.mainCalendar
                  ? 'CALENDAR_REACHED'
                  : 'OTHER_ROUTE',
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late _MockAuthService auth;
  late _MockRepo repo;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
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

  testWidgets(
    'signs in on a single tap when the first authorized read races the '
    'auth-token propagation (permission-denied) and the retry succeeds',
    (tester) async {
      final credential = _MockUserCredential();
      final user = _MockUser();
      when(() => user.uid).thenReturn('u1');
      when(() => user.emailVerified).thenReturn(true);
      when(() => credential.user).thenReturn(user);
      when(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => credential);
      var reads = 0;
      when(() => repo.findUserByUid('u1')).thenAnswer((_) async {
        reads++;
        if (reads == 1) {
          // First read after sign-in: token not yet propagated to Firestore.
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          );
        }
        return const UserUidMatch(
          id: 'doc1',
          data: <String, dynamic>{
            'name': 'Active User',
            'email': 'user@test.com',
            'status': 'active',
            'role': 'admin',
            'uid': 'u1',
          },
        );
      });

      await tester.pumpWidget(_wrap(auth, repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'user@test.com');
      await tester.enterText(find.byType(TextField).at(1), 'password123');

      await tester.tap(find.byType(FilledButton).first);
      await tester.pumpAndSettle();

      // A single tap lands on the calendar — no banner error, no second tap.
      expect(find.text('CALENDAR_REACHED'), findsOneWidget);
      expect(reads, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'routes to calendar when the profile is found on first read',
    (tester) async {
      final credential = _MockUserCredential();
      final user = _MockUser();
      when(() => user.uid).thenReturn('u1');
      when(() => credential.user).thenReturn(user);
      when(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => credential);
      when(() => repo.findUserByUid('u1')).thenAnswer(
        (_) async => const UserUidMatch(
          id: 'doc1',
          data: <String, dynamic>{
            'name': 'Active User',
            'email': 'user@test.com',
            'status': 'active',
            'role': 'admin',
            'uid': 'u1',
          },
        ),
      );

      await tester.pumpWidget(_wrap(auth, repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'user@test.com');
      await tester.enterText(find.byType(TextField).at(1), 'password123');

      await tester.tap(find.byType(FilledButton).first);
      await tester.pumpAndSettle();

      expect(find.text('CALENDAR_REACHED'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'signs out and shows no-profile error when findUserByUid returns null',
    (tester) async {
      final credential = _MockUserCredential();
      final user = _MockUser();
      when(() => user.uid).thenReturn('u1');
      when(() => credential.user).thenReturn(user);
      when(
        () => auth.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => credential);
      when(() => repo.findUserByUid('u1')).thenAnswer((_) async => null);
      when(() => auth.signOut()).thenAnswer((_) async {});

      await tester.pumpWidget(_wrap(auth, repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'user@test.com');
      await tester.enterText(find.byType(TextField).at(1), 'password123');

      await tester.tap(find.byType(FilledButton).first);
      await tester.pumpAndSettle();

      verify(() => auth.signOut()).called(1);
      expect(find.text('CALENDAR_REACHED'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
