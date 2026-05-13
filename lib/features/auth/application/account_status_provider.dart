import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';

final accountDisabledProvider = StreamProvider<bool>((ref) {
  final user = ref.watch(firebaseAuthProvider).currentUser;
  if (user == null) return Stream.value(false);

  return ref
      .watch(employeesRepositoryProvider)
      .watchUserStatus(user.uid)
      .map((status) => status == 'disabled');
});
