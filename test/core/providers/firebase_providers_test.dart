import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

/// Stands in for the five real `streamForUid` call sites. Every one of them
/// turns a null uid into its own signed-out answer, so a broken auth stream
/// that arrives as null is indistinguishable from a sign-out at all five —
/// including `account_status_provider`, which feeds `isAccountDeletionSignal`.
final _probeProvider = StreamProvider<String>(
  (ref) => streamForUid(ref, (uid) => Stream.value(uid ?? 'signed-out')),
);

void main() {
  test(
    'an auth-stream error propagates instead of reading as signed out',
    () async {
      final auth = _MockFirebaseAuth();
      when(auth.authStateChanges).thenAnswer(
        (_) =>
            Stream<User?>.error(FirebaseAuthException(code: 'internal-error')),
      );

      final container = ProviderContainer(
        retry: (retryCount, error) => null,
        overrides: [firebaseAuthProvider.overrideWithValue(auth)],
      );
      addTearDown(container.dispose);
      container
        ..listen(authUidProvider, (_, _) {})
        ..listen(_probeProvider, (_, _) {});
      await pumpEventQueue();

      final state = container.read(_probeProvider);
      expect(state.hasError, isTrue);
      expect(state.value, isNull);
    },
  );

  test('a settled null uid still reads as signed out', () async {
    final auth = _MockFirebaseAuth();
    when(
      auth.authStateChanges,
    ).thenAnswer((_) => Stream<User?>.value(null));

    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [firebaseAuthProvider.overrideWithValue(auth)],
    );
    addTearDown(container.dispose);
    container
      ..listen(authUidProvider, (_, _) {})
      ..listen(_probeProvider, (_, _) {});
    await pumpEventQueue();

    expect(container.read(_probeProvider).value, 'signed-out');
  });
}
