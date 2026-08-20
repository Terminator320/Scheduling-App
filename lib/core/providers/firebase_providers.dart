import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

/// Deferred Firebase bootstrap. main() overrides this with App Check
/// activation, so Firestore can await it before running.
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

/// Opens a stream once the auth uid has SETTLED, forwarding a uid error rather
/// than swallowing it.
///
/// The tri-state unwrap this replaces was spelled out at six providers, and
/// each copy had to get the same three branches right: an errored uid must
/// propagate (a `.value` read reports "signed out" for a broken auth stream),
/// a LOADING uid must wait rather than resolve to null, and a settled uid goes
/// straight through. [build] keeps each site's own per-null-uid behaviour, so
/// nothing is flattened away — one site returns an empty list, another opens a
/// different query.
Stream<T> streamForUid<T>(Ref ref, Stream<T> Function(String? uid) build) {
  final uidState = ref.watch(authUidProvider);
  if (uidState.hasError) {
    return Stream.error(
      uidState.error!,
      uidState.stackTrace ?? StackTrace.current,
    );
  }
  if (uidState.isLoading) {
    return Stream.fromFuture(ref.watch(authUidProvider.future)).asyncExpand(build);
  }
  return build(uidState.value);
}
