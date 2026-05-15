import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';

// Two-provider pattern: _authUidProvider wraps authStateChanges() so that
// accountDisabledProvider re-subscribes when the user signs in or out.
// Using firebaseAuthProvider.currentUser directly would be a point-in-time
// read that only re-evaluates on Riverpod lifecycle changes, not on auth events.

/// Streams the current auth user's UID. Emits null when signed out.
final _authUidProvider = StreamProvider<String?>((ref) {
  return ref
      .watch(firebaseAuthProvider)
      .authStateChanges()
      .map((user) => user?.uid);
});

/// Emits true when the currently-logged-in user's Firestore status is 'disabled'.
/// Re-evaluates reactively on every auth-state change.
final accountDisabledProvider = StreamProvider<bool>((ref) {
  final uid = ref.watch(_authUidProvider).valueOrNull;
  if (uid == null) return Stream.value(false);

  return ref
      .watch(employeesRepositoryProvider)
      .watchUserStatus(uid)
      .map((status) => status == 'disabled');
});
