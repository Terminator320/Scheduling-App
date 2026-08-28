import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/policies/employee_name_policy.dart';

final AppLogger _accountStatusLogger = AppLogger();

/// Watches the signed-in user's account document.
final currentUserDocProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final repository = ref.watch(employeesRepositoryProvider);
  // Wait for deferred App Check before the first Firestore listener.
  final firebaseReady = ref
      .watch(firebaseReadyProvider.future)
      .catchError((Object _) {});

  Stream<Map<String, dynamic>> watchDoc(String? uid) {
    if (uid == null) return Stream.value(const {});
    return Stream.fromFuture(
      firebaseReady,
    ).asyncExpand((_) => repository.watchUserDoc(uid));
  }

  return streamForUid(ref, watchDoc);
});

/// Returns null while the account doc is unsettled.
({bool signedIn, String role, String status})? readAccountGateInputs(
  Ref ref,
  FirebaseAuth auth,
) {
  final docState = ref.read(currentUserDocProvider);
  if (docState.isLoading || docState.hasError) return null;
  final doc = docState.value ?? const <String, dynamic>{};
  return (
    signedIn: auth.currentUser != null,
    role: (doc['role'] ?? '').toString().trim(),
    status: (doc['status'] ?? '').toString().trim(),
  );
}

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

/// True only when the doc goes from populated to empty.
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
  // Previous data separates deletion from bootstrap lag.
  final previousDoc = previous?.value;
  return previousDoc != null && previousDoc.isNotEmpty;
}

/// True for an empty first-settled doc that needs cache confirmation.
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
  // Populated previous data is handled by isAccountDeletionSignal.
  final previousDoc = previous?.value;
  return previousDoc == null || previousDoc.isEmpty;
}

/// Confirms a cold-start deletion against AuthCache.
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
    // Keystore failures disable the kick-out silently.
    (logger ?? _accountStatusLogger).warn(
      'ACCOUNT-EXIT warm cache read failed',
      e,
      st,
    );
    return false;
  }
}

/// The signed-in user's display name, empty until doc loads.
final currentUserNameProvider = Provider<String>((ref) {
  final doc = ref.watch(currentUserDocProvider).value;
  if (doc == null) return '';
  return displayEmployeeName(
    firstName: (doc['firstName'] ?? '').toString(),
    lastName: (doc['lastName'] ?? '').toString(),
    name: (doc['name'] ?? '').toString(),
    email: (doc['email'] ?? '').toString(),
  );
});
