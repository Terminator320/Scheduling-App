import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/data/auth_cache.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/splash/screens/splash_screen.dart';
import 'package:scheduling/routes/app_routes.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

/// Hands the fast path an ADMIN record. `AuthCache` cannot produce one today —
/// it never stores a role — which is exactly why sourcing the role from it
/// would fail nothing.
class _AdminAuthCache extends Fake implements AuthCache {
  @override
  Future<EmployeeRecord?> loadIfMatch(String uid) async => const EmployeeRecord(
    id: 'doc1',
    name: 'Admin',
    role: 'admin',
    status: 'active',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'signed-out cold start reaches login without navigating during build',
    (tester) async {
      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.currentUser).thenReturn(null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [firebaseAuthProvider.overrideWithValue(mockAuth)],
          child: MaterialApp(
            // Mirrors OnboardingGate: SplashScreen mounts during a build,
            // so initState runs mid-build — the path that wedged the Navigator.
            home: const SplashScreen(),
            onGenerateRoute: (settings) {
              if (settings.name == AppRoutes.login) {
                return MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('login-stub')),
                );
              }
              return null;
            },
          ),
        ),
      );

      // Bounded pumps: progress bar never settles (pumpAndSettle would hang); one extra frame lets _decideRoute await firebaseReadyProvider (P10) first.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('login-stub'), findsOneWidget);
    },
  );

  testWidgets('the warm-cache fast path routes with least privilege', (
    tester,
  ) async {
    // Role is never read from device storage — always Firestore. The live role
    // stream upgrades an admin a frame later; the cache hit must not.
    final mockAuth = _MockFirebaseAuth();
    final user = _MockUser();
    when(() => user.uid).thenReturn('u1');
    when(() => mockAuth.currentUser).thenReturn(user);

    MainCalendarArgs? args;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(mockAuth),
          authCacheProvider.overrideWithValue(_AdminAuthCache()),
        ],
        child: MaterialApp(
          home: const SplashScreen(),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.mainCalendar) {
              args = settings.arguments as MainCalendarArgs?;
              return MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('calendar-stub')),
              );
            }
            return null;
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('calendar-stub'), findsOneWidget);
    expect(args?.employeeId, 'doc1');
    expect(args?.isAdmin, isFalse);
  });
}
