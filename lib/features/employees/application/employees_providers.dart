import 'package:flutter/foundation.dart' show mapEquals;
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

/// Container-scoped mutable holders for the content-equality memo — each
/// container gets its own cache.
final _colorMapMemoProvider = Provider((ref) => _MapMemo<Color>());
final _nameMapMemoProvider = Provider((ref) => _MapMemo<String>());

class _MapMemo<V> {
  Map<String, V>? value;
}

// Memoized lookup maps — avoids re-allocating on every rebuild, and reuses
// the same instance when the content hasn't actually changed so watchers
// don't get notified for nothing.
Map<String, V> _memoizedEmployeeMap<V>(
  Ref ref,
  Provider<_MapMemo<V>> memoProvider,
  V Function(EmployeeRecord e) valueOf,
) {
  final memo = ref.watch(memoProvider);
  final employees = ref.watch(allUsersStreamProvider).asData?.value ?? const [];
  final next = {for (final e in employees) e.id: valueOf(e)};
  final previous = memo.value;
  if (previous != null && mapEquals(previous, next)) return previous;
  memo.value = next;
  return next;
}

final employeeColorMapProvider = Provider<Map<String, Color>>(
  (ref) => _memoizedEmployeeMap(ref, _colorMapMemoProvider, (e) => e.color),
);

final employeeNameMapProvider = Provider<Map<String, String>>(
  (ref) => _memoizedEmployeeMap(ref, _nameMapMemoProvider, (e) => e.name),
);

final employeesStreamProvider = StreamProvider<List<EmployeeRecord>>((ref) {
  if (ref.authUid == null) return Stream.value(const []);
  return ref.watch(employeesRepositoryProvider).watchEmployees();
});

typedef _EmployeeSearchEntry = ({
  EmployeeRecord employee,
  String text,
  String phoneDigits,
});

// Pre-normalized, memoized search index — per-keystroke filtering then only
// has to normalize the query, not every employee field.
final _employeeSearchIndexProvider = Provider<List<_EmployeeSearchEntry>>((
  ref,
) {
  final employees = ref.watch(allUsersStreamProvider).asData?.value ?? const [];
  return [
    for (final e in employees)
      (
        employee: e,
        text: ClientSearchPolicy.normalize('${e.name} ${e.email}'),
        phoneDigits: ClientSearchPolicy.digitsOnly(e.phone),
      ),
  ];
});

final filteredEmployeesProvider = Provider.autoDispose
    .family<List<EmployeeRecord>, String>(
      (ref, query) {
        final index = ref.watch(_employeeSearchIndexProvider);
        // Accent-folded + digits-only matching (mirrors client search).
        final q = ClientSearchPolicy.normalize(query);
        final qDigits = ClientSearchPolicy.digitsOnly(query);
        if (q.isEmpty && qDigits.isEmpty) {
          return [for (final entry in index) entry.employee];
        }
        return [
          for (final entry in index)
            if ((q.isNotEmpty && entry.text.contains(q)) ||
                (qDigits.isNotEmpty && entry.phoneDigits.contains(qDigits)))
              entry.employee,
        ];
      },
    );
