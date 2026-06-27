import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
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
  final role = ref.watch(userRoleProvider).value;
  if (role == 'admin') return repo.watchAllUsers();
  return repo.watchAssignableUsers();
});

// Derived lookup maps, memoized so build() callers don't re-allocate them on
// every rebuild; they recompute only when the users stream emits.
final employeeColorMapProvider = Provider<Map<String, Color>>((ref) {
  final employees = ref.watch(allUsersStreamProvider).asData?.value ?? const [];
  return {for (final e in employees) e.id: e.color};
});

final employeeNameMapProvider = Provider<Map<String, String>>((ref) {
  final employees = ref.watch(allUsersStreamProvider).asData?.value ?? const [];
  return {for (final e in employees) e.id: e.name};
});

final employeesStreamProvider = StreamProvider<List<EmployeeRecord>>((ref) {
  if (ref.authUid == null) return Stream.value(const []);
  return ref.watch(employeesRepositoryProvider).watchEmployees();
});

final filteredEmployeesProvider = Provider.autoDispose
    .family<List<EmployeeRecord>, String>(
      (ref, query) {
        final list =
            ref.watch(allUsersStreamProvider).asData?.value ?? const [];
        // Accent-folded text + digits-only phone matching — same rule as the
        // client search, so accented names and formatted phone numbers still match.
        final q = ClientSearchPolicy.normalize(query);
        final qDigits = ClientSearchPolicy.digitsOnly(query);
        if (q.isEmpty && qDigits.isEmpty) return list;
        return list.where((e) {
          final text = ClientSearchPolicy.normalize('${e.name} ${e.email}');
          final phoneDigits = ClientSearchPolicy.digitsOnly(e.phone);
          final matchesText = q.isNotEmpty && text.contains(q);
          final matchesPhone =
              qDigits.isNotEmpty && phoneDigits.contains(qDigits);
          return matchesText || matchesPhone;
        }).toList();
      },
    );
