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

/// The signed-in user's display name (empty until the doc loads).
final currentUserNameProvider = Provider<String>((ref) {
  final doc = ref.watch(currentUserDocProvider).valueOrNull;
  return (doc?['name'] ?? '').toString().trim();
});
