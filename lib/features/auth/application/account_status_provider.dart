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
