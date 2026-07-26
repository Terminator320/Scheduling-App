import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Keeps a single live snapshot of the signed-in user's `users/{uid}` doc, covering
/// their name, status, and role.
final currentUserDocProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) return Stream.value(const {});
  final repository = ref.watch(employeesRepositoryProvider);
  // P10: this is the app's first Firestore listener, so we hold it until the
  // deferred App Check activation finishes. Any failures there get logged
  // elsewhere.
  final firebaseReady = ref
      .watch(firebaseReadyProvider.future)
      .catchError((Object _) {});
  return Stream.fromFuture(
    firebaseReady,
  ).asyncExpand((_) => repository.watchUserDoc(uid));
});

final accountDisabledProvider = Provider<AsyncValue<bool>>((ref) {
  return ref
      .watch(currentUserDocProvider)
      .whenData((doc) => (doc['status'] ?? '').toString().trim() == 'disabled');
});

/// Streams the signed-in user's role (admin/employee), empty when signed out.
final userRoleProvider = Provider<AsyncValue<String>>((ref) {
  return ref
      .watch(currentUserDocProvider)
      .whenData((doc) => (doc['role'] ?? '').toString().trim());
});

/// True only when the doc goes from populated to empty. A first-seen empty doc
/// (sign-in lag, or before activation) is just a bootstrap window, not a
/// deletion — that's why we look at [previous] to tell the two apart.
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
  // Only a populated→empty transition counts here. `previous?.value` keeps the
  // last known data across loading blips, which is what lets us tell the two apart.
  final previousDoc = previous?.value;
  return previousDoc != null && previousDoc.isNotEmpty;
}

/// True when there's a signed-in uid but the doc has settled empty and was never
/// populated. That's ambiguous with pre-activation, so [confirmColdStartDeletion]
/// resolves it using AuthCache.
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
  // If the previous doc was populated, that's a live transition and
  // isAccountDeletionSignal already owns it. This function only covers the
  // cold-start case, where the doc was empty from the very start.
  final previousDoc = previous?.value;
  return previousDoc == null || previousDoc.isEmpty;
}

/// Confirms a cold-start deletion by checking for an empty doc plus a warm
/// AuthCache match. The cache is written right after sign-in, cleared on
/// sign-out, and never written on a fresh signup.
Future<bool> confirmColdStartDeletion({
  required bool isSignedIn,
  required String? resolvedUid,
  required AsyncValue<Map<String, dynamic>>? previous,
  required AsyncValue<Map<String, dynamic>> docState,
  required Future<EmployeeRecord?> Function(String uid) loadWarmCache,
  AppLogger? logger,
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
  } catch (e, st) {
    // If the keystore read fails, we fail safe but silently — this just
    // disables the kick-out with no visible signal to the user.
    (logger ?? AppLogger()).warn('ACCOUNT-EXIT warm cache read failed', e, st);
    return false;
  }
}

/// The signed-in user's display name, empty until doc loads.
final currentUserNameProvider = Provider<String>((ref) {
  final doc = ref.watch(currentUserDocProvider).value;
  return (doc?['name'] ?? '').toString().trim();
});
