import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Single live snapshot of the signed-in user's `users/{uid}` doc. One
/// Firestore listener; name, disabled-status and role all derive from it
/// instead of each opening their own `where('uid').limit(1).snapshots()`.
final currentUserDocProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) return Stream.value(const {});
  final repository = ref.watch(employeesRepositoryProvider);
  // P10: this is the first Firestore listener the app opens (it starts with
  // the account-status listeners in main.dart), so hold it until the
  // deferred App Check activation completes. Activation failures are logged
  // elsewhere; don't let them kill the account-status stream.
  final firebaseReady = ref
      .watch(firebaseReadyProvider.future)
      .catchError((Object _) {});
  return Stream.fromFuture(firebaseReady)
      .asyncExpand((_) => repository.watchUserDoc(uid));
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
/// become populated. A cold-start already-deleted account never produces the
/// populated→empty transition (the warm-cache splash path skips the
/// authoritative read entirely); that case is covered separately by
/// [confirmColdStartDeletion]. [previous] is the prior emission from
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

/// Whether a [currentUserDocProvider] emission has the *shape* of a
/// cold-start deletion (C3): a settled, clean empty doc for a signed-in,
/// resolved uid that was never seen populated this session.
///
/// The shape alone is ambiguous — the create-account / signup-code-redemption
/// window (signed in, `users` doc not activated yet) looks identical — so
/// this is only a candidate check. [confirmColdStartDeletion] resolves the
/// ambiguity with the warm `AuthCache` discriminator. A transient
/// permission-denied (or any stream error) surfaces as an `AsyncError`, not
/// as an empty doc, and is never a candidate; the repository's `watchUserDoc`
/// additionally filters the transient empty from-cache snapshot, so an empty
/// emission here is a server-confirmed clean read.
bool isColdStartDeletionCandidate({
  required bool isSignedIn,
  required String? resolvedUid,
  required AsyncValue<Map<String, dynamic>>? previous,
  required AsyncValue<Map<String, dynamic>> docState,
}) {
  if (!isSignedIn || resolvedUid == null) return false;
  if (docState.isLoading || docState.hasError) return false;
  final doc = docState.value;
  if (doc == null || doc.isNotEmpty) return false;
  // A populated previous doc is the live populated→empty transition, owned
  // by [isAccountDeletionSignal]; the cold-start case is empty-from-the-start.
  final previousDoc = previous?.value;
  return previousDoc == null || previousDoc.isEmpty;
}

/// Confirms a cold-start server-side deletion (C3): the users doc read is a
/// settled clean empty ([isColdStartDeletionCandidate]) *and* the device
/// holds a warm `AuthCache` identity for the uid.
///
/// The warm cache is the discriminator between "deleted while the app was
/// closed" and the legitimate signed-in-with-no-doc windows: it is written
/// only after a completed sign-in (the splash saves it once the users doc
/// was seen active) and cleared on every sign-out, so a fresh
/// create-account/redeem session always starts with a cold cache and is
/// never flagged. [loadWarmCache] is `AuthCache.loadIfMatch` in production;
/// a cache read failure (keystore flakiness) fails safe to "not a deletion".
Future<bool> confirmColdStartDeletion({
  required bool isSignedIn,
  required String? resolvedUid,
  required AsyncValue<Map<String, dynamic>>? previous,
  required AsyncValue<Map<String, dynamic>> docState,
  required Future<EmployeeRecord?> Function(String uid) loadWarmCache,
}) async {
  if (!isColdStartDeletionCandidate(
    isSignedIn: isSignedIn,
    resolvedUid: resolvedUid,
    previous: previous,
    docState: docState,
  )) {
    return false;
  }
  try {
    return await loadWarmCache(resolvedUid!) != null;
  } catch (_) {
    return false;
  }
}

/// The signed-in user's display name (empty until the doc loads).
final currentUserNameProvider = Provider<String>((ref) {
  final doc = ref.watch(currentUserDocProvider).value;
  return (doc?['name'] ?? '').toString().trim();
});
