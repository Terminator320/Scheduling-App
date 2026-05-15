import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';

/// Emits true when the signed-in user's Firestore status is 'disabled'.
/// Re-evaluates reactively on every auth-state change via [authUidProvider].
final accountDisabledProvider = StreamProvider<bool>((ref) {
  final uid = ref.watch(authUidProvider).valueOrNull;
  // Signed-out users aren't "disabled" — the route guard handles auth itself,
  // so emitting false avoids a spurious account-disabled snackbar during logout.
  if (uid == null) return Stream.value(false);

  return ref
      .watch(employeesRepositoryProvider)
      .watchUserStatus(uid)
      .map((status) => status == 'disabled');
});
