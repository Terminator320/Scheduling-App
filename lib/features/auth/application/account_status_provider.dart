import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';

/// Single live snapshot of the signed-in user's `users/{uid}` doc. One
/// Firestore listener; name, disabled-status and role all derive from it
/// instead of each opening their own `where('uid').limit(1).snapshots()`.
final currentUserDocProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final uid = ref.watch(authUidProvider).valueOrNull;
  if (uid == null) return Stream.value(const {});
  return ref.watch(employeesRepositoryProvider).watchUserDoc(uid);
});

final accountDisabledProvider = Provider<AsyncValue<bool>>((ref) {
  return ref
      .watch(currentUserDocProvider)
      .whenData((doc) => (doc['status'] ?? '').toString().trim() == 'disabled');
});

/// Streams the signed-in user's role (e.g. `admin`, `employee`).
///
/// Emits an empty string when no user is signed in or the doc has no role.
/// Used by `main.dart` to detect live admin → employee demotion (H3).
final userRoleProvider = Provider<AsyncValue<String>>((ref) {
  return ref
      .watch(currentUserDocProvider)
      .whenData((doc) => (doc['role'] ?? '').toString().trim());
});

/// Whether a [currentUserDocProvider] emission means the signed-in user's
/// account doc was deleted server-side — as opposed to a transient empty
/// placeholder.
///
/// On a fresh sign-in `FirebaseAuth.currentUser` is set immediately, but the
/// `authStateChanges()` stream behind [authUidProvider] lags, so
/// [currentUserDocProvider] still serves the empty doc from its `uid == null`
/// branch; the reload into `watchUserDoc` then retains that empty value as
/// `AsyncLoading`'s previous data (an `AsyncData` flagged `isLoading`). Neither
/// is a deletion. A real deletion is a *settled* empty doc for an
/// already-resolved uid.
bool isAccountDeletionSignal({
  required bool isSignedIn,
  required String? resolvedUid,
  required AsyncValue<Map<String, dynamic>> docState,
}) {
  if (!isSignedIn || resolvedUid == null) return false;
  if (docState.isLoading) return false;
  final doc = docState.valueOrNull;
  return doc != null && doc.isEmpty;
}

/// The signed-in user's display name (empty until the doc loads).
final currentUserNameProvider = Provider<String>((ref) {
  final doc = ref.watch(currentUserDocProvider).valueOrNull;
  return (doc?['name'] ?? '').toString().trim();
});
