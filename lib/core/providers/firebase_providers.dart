import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

/// Completion of the deferred Firebase bootstrap (P10): Crashlytics
/// collection setup and App Check activation continue in the background
/// after `runApp` instead of gating the first frame. `main()` overrides this
/// with the real activation future; anything that talks to Firestore awaits
/// it first so no request races App Check token issuance — `SplashScreen`
/// gates every signed-in surface, and `currentUserDocProvider` gates the
/// account-status listener. The default (already completed) keeps tests and
/// standalone containers working without an override.
final firebaseReadyProvider = FutureProvider<void>((ref) async {});

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final authUidProvider = StreamProvider<String?>((ref) {
  return ref
      .watch(firebaseAuthProvider)
      .authStateChanges()
      .map((user) => user?.uid)
      .distinct();
});

extension AuthGatedRef on Ref {
  String? get authUid => watch(authUidProvider).value;
}
