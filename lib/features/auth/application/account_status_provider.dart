import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';

final accountDisabledProvider = StreamProvider<bool>((ref) {
  final uid = ref.watch(authUidProvider).valueOrNull;
  if (uid == null) return Stream.value(false);

  return ref
      .watch(employeesRepositoryProvider)
      .watchUserStatus(uid)
      .map((status) => status == 'disabled');
});

/// Streams the signed-in user's role (e.g. `admin`, `employee`).
///
/// Emits an empty string when no user is signed in or the doc has no role.
/// Used by `main.dart` to detect live admin → employee demotion (H3).
final userRoleProvider = StreamProvider<String>((ref) {
  final uid = ref.watch(authUidProvider).valueOrNull;
  if (uid == null) return Stream.value('');

  return ref.watch(employeesRepositoryProvider).watchUserRole(uid);
});
