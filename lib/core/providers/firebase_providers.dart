import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

/// Deferred Firebase bootstrap; main() overrides with App Check activation so Firestore awaits it.
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
