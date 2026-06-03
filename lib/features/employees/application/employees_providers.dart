import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/employees/data/firebase_employees_repository.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

final employeesRepositoryProvider = Provider<EmployeesRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return FirebaseEmployeesRepository(firestore);
});


final allUsersStreamProvider = StreamProvider<List<EmployeeRecord>>((ref) {
  if (ref.authUid == null) return Stream.value(const []);
  final repo = ref.watch(employeesRepositoryProvider);
  final role = ref.watch(userRoleProvider).valueOrNull;
  if (role == 'admin') return repo.watchAllUsers();
  return repo.watchAssignableUsers();
});

final employeesStreamProvider = StreamProvider<List<EmployeeRecord>>((ref) {
  if (ref.authUid == null) return Stream.value(const []);
  return ref.watch(employeesRepositoryProvider).watchEmployees();
});

final filteredEmployeesProvider = Provider.family<List<EmployeeRecord>, String>(
  (ref, query) {

    final list = ref.watch(allUsersStreamProvider).asData?.value ?? const [];
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((e) {
      return e.name.toLowerCase().contains(q) ||
          e.email.toLowerCase().contains(q) ||
          e.phone.toLowerCase().contains(q);
    }).toList();
  },
);
