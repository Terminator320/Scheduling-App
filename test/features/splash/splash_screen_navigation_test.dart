import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/splash/screens/splash_screen.dart';
import 'package:scheduling/routes/app_routes.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

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
}
