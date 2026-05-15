import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final firebaseStorageProvider = Provider<FirebaseStorage>(
  (ref) => FirebaseStorage.instance,
);

final firebaseAppCheckProvider = Provider<FirebaseAppCheck>(
  (ref) => FirebaseAppCheck.instance,
);

/// Streams the current auth user's UID. Emits null when signed out.
///
/// Stream providers that hit Firestore should watch this and key their
/// subscription on the uid so they re-build on logout/login. Without this,
/// the existing snapshot listener errors when auth drops and never recovers
/// after the user signs back in.
///
/// `.distinct()` matters: Firebase Auth emits on token refresh (~hourly) too,
/// not just sign-in/out. Without it, every refresh would tear down and rebuild
/// every Firestore listener that depends on this provider.
final authUidProvider = StreamProvider<String?>((ref) {
  return ref
      .watch(firebaseAuthProvider)
      .authStateChanges()
      .map((user) => user?.uid)
      .distinct();
});

extension AuthGatedRef on Ref {
  /// Current auth UID, or null when signed out. Watching this re-builds the
  /// consuming provider on logout/login so Firestore listeners get a fresh
  /// subscription with the new token instead of sticking in an error state.
  String? get authUid => watch(authUidProvider).valueOrNull;
}
