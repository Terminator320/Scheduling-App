import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/core/providers/firebase_providers.dart';
import 'package:scheduling/features/auth/application/account_status_provider.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

class _MockEmployeesRepo extends Mock implements EmployeesRepository {}

void main() {
  late _MockEmployeesRepo repo;

  setUp(() {
    repo = _MockEmployeesRepo();
    when(repo.watchAllUsers).thenAnswer((_) => Stream.value(const <EmployeeRecord>[]));
    when(
      repo.watchAssignableUsers,
    ).thenAnswer((_) => Stream.value(const <EmployeeRecord>[]));
  });

  test('waits for the account doc before choosing the admin roster stream', () async {
    final docs = StreamController<Map<String, dynamic>>();
    addTearDown(docs.close);
    final container = ProviderContainer(
      overrides: [
        authUidProvider.overrideWith((ref) => Stream.value('uid-1')),
        currentUserDocProvider.overrideWith((ref) => docs.stream),
        employeesRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    container.listen(allUsersStreamProvider, (_, _) {});
    await pumpEventQueue();
    verifyNever(repo.watchAllUsers);
    verifyNever(repo.watchAssignableUsers);

    docs.add(const {'role': 'admin', 'status': 'active'});
    await pumpEventQueue();

    verify(repo.watchAllUsers).called(1);
    verifyNever(repo.watchAssignableUsers);
  });

  test('waits for the account doc before choosing the employee roster stream', () async {
    final docs = StreamController<Map<String, dynamic>>();
    addTearDown(docs.close);
    final container = ProviderContainer(
      overrides: [
        authUidProvider.overrideWith((ref) => Stream.value('uid-1')),
        currentUserDocProvider.overrideWith((ref) => docs.stream),
        employeesRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    container.listen(allUsersStreamProvider, (_, _) {});
    await pumpEventQueue();
    verifyNever(repo.watchAllUsers);
    verifyNever(repo.watchAssignableUsers);

    docs.add(const {'role': 'employee', 'status': 'active'});
    await pumpEventQueue();

    verify(repo.watchAssignableUsers).called(1);
    verifyNever(repo.watchAllUsers);
  });

  test('employeesStream waits for auth uid before opening the active roster stream', () async {
    final auth = StreamController<String?>();
    addTearDown(auth.close);
    when(
      repo.watchEmployees,
    ).thenAnswer((_) => Stream.value(const <EmployeeRecord>[]));
    final container = ProviderContainer(
      overrides: [
        authUidProvider.overrideWith((ref) => auth.stream),
        employeesRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    container.listen(employeesStreamProvider, (_, _) {});
    await pumpEventQueue();
    verifyNever(repo.watchEmployees);

    auth.add('uid-1');
    await pumpEventQueue();

    verify(repo.watchEmployees).called(1);
  });
}
