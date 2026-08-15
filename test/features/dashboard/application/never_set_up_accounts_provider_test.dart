import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/dashboard/application/dashboard_providers.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

EmployeeRecord _user(
  String id, {
  required String status,
  DateTime? createdAt,
}) => EmployeeRecord(
  id: id,
  name: 'Person $id',
  email: '$id@example.com',
  status: status,
  createdAt: createdAt,
);

/// Both roster streams are overridden, and that is deliberate: the active-only
/// stream carries the active users alone, exactly as `watchEmployees()` does in
/// production. Swapping `allUsersStreamProvider` for `employeesStreamProvider`
/// in the provider under test therefore empties the list and fails these tests,
/// which is the regression this file exists to catch.
ProviderContainer _container(List<EmployeeRecord> allUsers) {
  final active = [
    for (final u in allUsers)
      if (u.status == 'active') u,
  ];
  final container = ProviderContainer(
    overrides: [
      allUsersStreamProvider.overrideWith((_) => Stream.value(allUsers)),
      employeesStreamProvider.overrideWith((_) => Stream.value(active)),
    ],
  )..listen(neverSetUpAccountsProvider, (_, _) {});
  addTearDown(container.dispose);
  return container;
}

List<String> _listed(ProviderContainer container) => [
  for (final u in container.read(neverSetUpAccountsProvider).requireValue) u.id,
];

void main() {
  test('lists an invited account and omits an active one', () async {
    final container = _container([
      _user('invited', status: 'invited', createdAt: DateTime(2026, 8)),
      _user('working', status: 'active', createdAt: DateTime(2026, 8, 2)),
    ]);
    await container.read(allUsersStreamProvider.future);

    expect(_listed(container), ['invited']);
  });

  test('a disabled or unknown status is not an invited account', () async {
    final container = _container([
      _user('off', status: 'disabled'),
      _user('blank', status: ''),
    ]);
    await container.read(allUsersStreamProvider.future);

    expect(_listed(container), isEmpty);
  });

  test('lists oldest first', () async {
    final container = _container([
      _user('newer', status: 'invited', createdAt: DateTime(2026, 8, 5)),
      _user('older', status: 'invited', createdAt: DateTime(2026, 8)),
    ]);
    await container.read(allUsersStreamProvider.future);

    expect(_listed(container), ['older', 'newer']);
  });

  test(
    'an account with no createdAt sorts last rather than dropping out',
    () async {
      // `createdAt` is function-owned and absent on legacy docs — "unknown age"
      // must never become "not shown", or the warning under-reports the accounts
      // still sitting on the shared starting password.
      final container = _container([
        _user('unknown', status: 'invited'),
        _user('newer', status: 'invited', createdAt: DateTime(2026, 8, 5)),
        _user('older', status: 'invited', createdAt: DateTime(2026, 8)),
      ]);
      await container.read(allUsersStreamProvider.future);

      expect(_listed(container), ['older', 'newer', 'unknown']);
    },
  );
}
