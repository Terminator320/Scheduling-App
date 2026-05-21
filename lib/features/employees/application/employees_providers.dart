import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/employees/data/firebase_employees_repository.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

final employeesRepositoryProvider = Provider<EmployeesRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  final auth = ref.watch(firebaseAuthProvider);
  return FirebaseEmployeesRepository(firestore, auth: auth);
});

// Routes by role so non-admin sessions don't fire `watchAllUsers`, which
// targets the unconstrained `users` query rule and would otherwise log a
// PERMISSION_DENIED listener error every time a non-admin opens the calendar
// or appointment history. Admins get the full list (invited + disabled
// included, needed for the admin employees screen). Non-admins fall back to
// the assignable (status=='active') stream — sufficient for the calendar's
// employee color map.
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

final assignableUsersStreamProvider = StreamProvider<List<EmployeeRecord>>((
  ref,
) {
  if (ref.authUid == null) return Stream.value(const []);
  return ref.watch(employeesRepositoryProvider).watchAssignableUsers();
});

final filteredEmployeesProvider = Provider.family<List<EmployeeRecord>, String>(
  (ref, query) {
    // Admin employees list shows all users (active + disabled + invited) so
    // a disabled employee remains reachable for re-enable. EmployeeCard
    // already renders a StatusChip for each, so the visual distinction is
    // handled in the tile, not by hiding the row.
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
