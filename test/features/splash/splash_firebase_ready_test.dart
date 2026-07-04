import 'dart:async';

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
  testWidgets(
    'splash waits for the deferred Firebase bootstrap (firebaseReadyProvider) '
    'before deciding a route',
    (tester) async {
      final mockAuth = _MockFirebaseAuth();
      when(() => mockAuth.currentUser).thenReturn(null);
      final bootstrap = Completer<void>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(mockAuth),
            firebaseReadyProvider.overrideWith((ref) => bootstrap.future),
          ],
          child: MaterialApp(
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

      // Bootstrap still pending: the splash must not have routed anywhere.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('login-stub'), findsNothing);
      expect(find.byType(SplashScreen), findsOneWidget);

      bootstrap.complete();
      // One frame to resume _decideRoute, one for its post-frame navigation,
      // one to build the pushed route (bounded pumps: the splash progress
      // bar never settles).
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.text('login-stub'), findsOneWidget);
    },
  );
}
