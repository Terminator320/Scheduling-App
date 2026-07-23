import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Single live snapshot of the signed-in user's `users/{uid}` doc for name, status, and role.
final currentUserDocProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) return Stream.value(const {});
  final repository = ref.watch(employeesRepositoryProvider);
  // P10: this is the app's first Firestore listener, so hold it until the
  // deferred App Check activation completes (failures logged elsewhere).
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

/// True only for populated→empty transition; first-seen empty (sign-in lag, pre-activation) is bootstrap, not deletion — use [previous] to distinguish.
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
  // Only populated→empty counts; `previous?.value` retains data across loading blips.
  final previousDoc = previous?.value;
  return previousDoc != null && previousDoc.isNotEmpty;
}

/// True for settled empty doc (never populated) with a signed-in uid; ambiguous with pre-activation, resolved by [confirmColdStartDeletion] via AuthCache.
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
  // Populated previous = live transition (owned by isAccountDeletionSignal); cold-start = empty from start.
  final previousDoc = previous?.value;
  return previousDoc == null || previousDoc.isEmpty;
}

/// Confirms cold-start deletion: empty doc + warm AuthCache match (cache written post-sign-in, cleared post-signout, never on fresh signup).
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
    // Fails safe but silently on keystore error (disables kick-out without signal).
    (logger ?? AppLogger()).warn('ACCOUNT-EXIT warm cache read failed', e, st);
    return false;
  }
}

/// The signed-in user's display name, empty until doc loads.
final currentUserNameProvider = Provider<String>((ref) {
  final doc = ref.watch(currentUserDocProvider).value;
  return (doc?['name'] ?? '').toString().trim();
});
