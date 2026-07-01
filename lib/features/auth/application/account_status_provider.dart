import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';

/// Single live snapshot of the signed-in user's `users/{uid}` doc. One
/// Firestore listener; name, disabled-status and role all derive from it
/// instead of each opening their own `where('uid').limit(1).snapshots()`.
final currentUserDocProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final uid = ref.watch(authUidProvider).value;
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
/// Used by `main.dart` to detect live admin-to-employee demotion (H3).
final userRoleProvider = Provider<AsyncValue<String>>((ref) {
  return ref
      .watch(currentUserDocProvider)
      .whenData((doc) => (doc['role'] ?? '').toString().trim());
});

/// Whether a [currentUserDocProvider] transition means the signed-in user's
/// account doc was deleted server-side, as opposed to a transient empty
/// placeholder.
///
/// A real deletion is a *settled* empty doc that follows a previously-populated
/// one — a populated→empty transition for an already-resolved uid. An empty doc
/// that was never populated is a bootstrap window, not a deletion: the fresh
/// sign-in lag (where [authUidProvider] serves the `uid == null` empty branch
/// before `watchUserDoc` resolves) and the invited-signup window (signed in
/// before `redeemSignupCode` activates the doc) both start empty and only later
/// become populated. A cold-start already-deleted account is caught earlier by
/// `SplashScreen`'s `!isActive` sign-out, so this live listener only needs to
/// catch the runtime transition. [previous] is the prior emission from
/// `ref.listen`.
bool isAccountDeletionSignal({
  required bool isSignedIn,
  required String? resolvedUid,
  required AsyncValue<Map<String, dynamic>>? previous,
  required AsyncValue<Map<String, dynamic>> docState,
}) {
  if (!isSignedIn || resolvedUid == null) return false;
  if (docState.isLoading) return false;
  final doc = docState.value;
  if (doc == null || doc.isNotEmpty) return false;
  // Only a populated→empty transition is a deletion; the last known doc must
  // have had data. `previous?.value` keeps the retained data even across a
  // loading blip, so a real delete that momentarily reloads is still caught.
  final previousDoc = previous?.value;
  return previousDoc != null && previousDoc.isNotEmpty;
}

/// The signed-in user's display name (empty until the doc loads).
final currentUserNameProvider = Provider<String>((ref) {
  final doc = ref.watch(currentUserDocProvider).value;
  return (doc?['name'] ?? '').toString().trim();
});
