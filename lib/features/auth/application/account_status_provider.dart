import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';

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
