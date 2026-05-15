import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/employees/data/firebase_employees_repository.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

final employeesRepositoryProvider = Provider<EmployeesRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final auth = ref.watch(firebaseAuthProvider);
  return FirebaseEmployeesRepository(firestore, auth: auth);
});

/// Streams every user doc (no role filter). Used by appointment views that
/// need the full employee colour map.
///
/// The `ref.authUid` gate forces a fresh Firestore subscription on
/// logout/login — without it the listener errors when auth drops and Riverpod
/// keeps the error state across the next sign-in.
final allUsersStreamProvider = StreamProvider<List<EmployeeRecord>>((ref) {
  if (ref.authUid == null) return Stream.value(const []);
  return ref.watch(employeesRepositoryProvider).watchAllUsers();
});

/// Employees + admins (`role in {employee, admin}`).
final employeesStreamProvider = StreamProvider<List<EmployeeRecord>>((ref) {
  if (ref.authUid == null) return Stream.value(const []);
  return ref.watch(employeesRepositoryProvider).watchEmployees();
});

/// Active users only (assignment-eligible).
final assignableUsersStreamProvider = StreamProvider<List<EmployeeRecord>>((
  ref,
) {
  if (ref.authUid == null) return Stream.value(const []);
  return ref.watch(employeesRepositoryProvider).watchAssignableUsers();
});

/// Filters the watched employees list locally by name/email/phone.
final filteredEmployeesProvider = Provider.family<List<EmployeeRecord>, String>(
  (ref, query) {
    final list = ref.watch(employeesStreamProvider).asData?.value ?? const [];
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((e) {
      return e.name.toLowerCase().contains(q) ||
          e.email.toLowerCase().contains(q) ||
          e.phone.toLowerCase().contains(q);
    }).toList();
  },
);
