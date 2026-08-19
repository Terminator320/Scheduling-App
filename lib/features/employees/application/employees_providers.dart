import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/clients/domain/policies/client_search_policy.dart';
import 'package:scheduling/features/employees/data/firebase_employees_repository.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/policies/employee_name_policy.dart';

final employeesRepositoryProvider = Provider<EmployeesRepository>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return FirebaseEmployeesRepository(firestore);
});

final allUsersStreamProvider = StreamProvider<List<EmployeeRecord>>((ref) {
  final repo = ref.watch(employeesRepositoryProvider);

  Stream<List<EmployeeRecord>> streamForRole(String? uid, String role) {
    if (uid == null) return Stream.value(const []);
    if (role == 'admin') return repo.watchAllUsers();
    return repo.watchAssignableUsers();
  }

  final uidState = ref.watch(authUidProvider);
  if (uidState.hasError) {
    return Stream.error(
      uidState.error!,
      uidState.stackTrace ?? StackTrace.current,
    );
  }
  if (uidState.isLoading) {
    return Stream.fromFuture(
      ref.watch(authUidProvider.future),
    ).asyncExpand((uid) async* {
      if (uid == null) {
        yield const <EmployeeRecord>[];
        return;
      }
      final doc = await ref.watch(currentUserDocProvider.future);
      final role = (doc['role'] ?? '').toString().trim();
      yield* streamForRole(uid, role);
    });
  }

  final uid = uidState.value;
  if (uid == null) return Stream.value(const []);

  final docState = ref.watch(currentUserDocProvider);
  if (docState.hasError) {
    return Stream.error(
      docState.error!,
      docState.stackTrace ?? StackTrace.current,
    );
  }
  if (docState.isLoading) {
    return Stream.fromFuture(
      ref.watch(currentUserDocProvider.future),
    ).asyncExpand(
      (doc) => streamForRole(uid, (doc['role'] ?? '').toString().trim()),
    );
  }
  return streamForRole(
    uid,
    (docState.value?['role'] ?? '').toString().trim(),
  );
});

/// Container-scoped mutable holders for the content-equality memo — each
/// container gets its own cache.
final _colorMapMemoProvider = Provider((ref) => _MapMemo<Color>());
final _nameMapMemoProvider = Provider((ref) => _MapMemo<String>());

class _MapMemo<V> {
  Map<String, V>? value;
}

String _displayName(EmployeeRecord employee) => displayEmployeeName(
  firstName: employee.firstName,
  lastName: employee.lastName,
  name: employee.name,
  email: employee.email,
);

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
  (ref) =>
      _memoizedEmployeeMap(ref, _nameMapMemoProvider, _displayName),
);

/// Active employees only.
///
/// `autoDispose`, because its consumers are transient — the two appointment
/// sheets and the Dashboard. Without it, opening the add-appointment sheet
/// ONCE attached a second live `users` listener (alongside the always-on
/// `watchAllUsers()`) for the rest of the session.
///
/// Deliberately NOT derived from `allUsersStreamProvider`: that one includes
/// invited and disabled accounts for admin roster surfaces, while this one is
/// active employees only for crew-picking surfaces. That distinction is
/// load-bearing; keep it.
final employeesStreamProvider =
    StreamProvider.autoDispose<List<EmployeeRecord>>((ref) {
      final uidState = ref.watch(authUidProvider);
      if (uidState.hasError) {
        return Stream.error(
          uidState.error!,
          uidState.stackTrace ?? StackTrace.current,
        );
      }
      if (uidState.isLoading) {
        return Stream.fromFuture(
          ref.watch(authUidProvider.future),
        ).asyncExpand((uid) {
          if (uid == null) return Stream.value(const <EmployeeRecord>[]);
          return ref.watch(employeesRepositoryProvider).watchEmployees();
        });
      }
      if (uidState.value == null) return Stream.value(const []);
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
        text: ClientSearchPolicy.normalize('${_displayName(e)} ${e.email}'),
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
