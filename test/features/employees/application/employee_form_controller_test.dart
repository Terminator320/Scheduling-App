import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/employees/application/employee_form_controller.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/job_title.dart';
import 'package:scheduling/features/employees/domain/models/new_account_credentials.dart';

class _MockEmployeesRepo extends Mock implements EmployeesRepository {}

void main() {
  late _MockEmployeesRepo repo;
  late ProviderContainer container;

  setUpAll(() {
    registerFallbackValue(const EmployeeRecord(id: 'fallback'));
  });

  setUp(() {
    repo = _MockEmployeesRepo();
    container = ProviderContainer(
      overrides: [employeesRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
  });

  EmployeeFormController notifier() =>
      container.read(employeeFormControllerProvider.notifier);

  EmployeeFormActivity activity() =>
      container.read(employeeFormControllerProvider);

  Future<EmployeeSaveOutcome> create() => notifier().createAccount(
    const EmployeeRecord(
      id: '',
      name: 'Alex',
      firstName: 'Alex',
      email: 'alex@test.com',
      phone: '555-0001',
      color: Color(0x0000007B),
      role: 'admin',
      jobTitle: JobTitle.technician,
    ),
  );

  const edited = EmployeeRecord(
    id: 'e1',
    name: 'Alex',
    email: 'alex@test.com',
    phone: '555-0001',
    role: 'admin',
  );

  Future<EmployeeSaveOutcome> update() => notifier().updateEmployee(edited);

  group('createAccount', () {
    test('returns the sign-in credentials on success', () async {
      when(
        () => repo.createEmployeeAccount(
          name: any(named: 'name'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          email: any(named: 'email'),
          phone: any(named: 'phone'),
          colorValue: any(named: 'colorValue'),
          jobTitle: any(named: 'jobTitle'),
          isAdmin: any(named: 'isAdmin'),
        ),
      ).thenAnswer(
        (_) async => const NewAccountCredentials(
          email: 'alex@test.com',
          password: 'Welcome123!',
        ),
      );

      final outcome = await create();

      expect(outcome, isA<EmployeeAccountCreated>());
      expect(
        (outcome as EmployeeAccountCreated).credentials.password,
        'Welcome123!',
      );
      expect(activity().isSaving, isFalse);
    });

    test('surfaces a taken email as a field-level outcome', () async {
      when(
        () => repo.createEmployeeAccount(
          name: any(named: 'name'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          email: any(named: 'email'),
          phone: any(named: 'phone'),
          colorValue: any(named: 'colorValue'),
          jobTitle: any(named: 'jobTitle'),
          isAdmin: any(named: 'isAdmin'),
        ),
      ).thenThrow(const EmployeesFailureEmailAlreadyExists());

      expect(await create(), isA<EmployeeEmailInUse>());
      expect(activity().isSaving, isFalse);
    });

    test('reports other failures with the original error', () async {
      final boom = Exception('offline');
      when(
        () => repo.createEmployeeAccount(
          name: any(named: 'name'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          email: any(named: 'email'),
          phone: any(named: 'phone'),
          colorValue: any(named: 'colorValue'),
          jobTitle: any(named: 'jobTitle'),
          isAdmin: any(named: 'isAdmin'),
        ),
      ).thenThrow(boom);

      final outcome = await create();

      expect(outcome, isA<EmployeeSaveFailed>());
      expect((outcome as EmployeeSaveFailed).error, boom);
      expect(activity().isSaving, isFalse);
    });
  });

  group('updateEmployee', () {
    test('persists the edit and reports updated', () async {
      when(
        () => repo.updateEmployee(
          docId: any(named: 'docId'),
          employee: any(named: 'employee'),
        ),
      ).thenAnswer((_) async {});

      expect(await update(), isA<EmployeeUpdated>());
      verify(
        () => repo.updateEmployee(docId: 'e1', employee: edited),
      ).called(1);
      expect(activity().isSaving, isFalse);
    });

    test('reports failures with the original error', () async {
      when(
        () => repo.updateEmployee(
          docId: any(named: 'docId'),
          employee: any(named: 'employee'),
        ),
      ).thenThrow(Exception('offline'));

      expect(await update(), isA<EmployeeSaveFailed>());
      expect(activity().isSaving, isFalse);
    });
  });

  group('setEmployeeStatus', () {
    test('disables via deactivateEmployee', () async {
      when(() => repo.deactivateEmployee(any())).thenAnswer((_) async {});

      final outcome = await notifier().setEmployeeStatus(
        docId: 'e1',
        disable: true,
      );

      expect(outcome, isA<EmployeeStatusChanged>());
      verify(() => repo.deactivateEmployee('e1')).called(1);
      verifyNever(() => repo.reactivateEmployee(any()));
      expect(activity().isTogglingStatus, isFalse);
    });

    test('re-enables via reactivateEmployee', () async {
      when(() => repo.reactivateEmployee(any())).thenAnswer((_) async {});

      final outcome = await notifier().setEmployeeStatus(
        docId: 'e1',
        disable: false,
      );

      expect(outcome, isA<EmployeeStatusChanged>());
      verify(() => repo.reactivateEmployee('e1')).called(1);
    });

    test('reports failures with the original error', () async {
      when(() => repo.deactivateEmployee(any())).thenThrow(Exception('boom'));

      final outcome = await notifier().setEmployeeStatus(
        docId: 'e1',
        disable: true,
      );

      expect(outcome, isA<EmployeeStatusChangeFailed>());
      expect(activity().isTogglingStatus, isFalse);
    });
  });

  group('deleteAccount', () {
    test('reports deleted and clears the busy flag', () async {
      when(() => repo.deleteEmployeeAccount(any())).thenAnswer((_) async {});

      final outcome = await notifier().deleteAccount('doc-1');

      expect(outcome, isA<AccountDeleted>());
      verify(() => repo.deleteEmployeeAccount('doc-1')).called(1);
      expect(activity().isDeletingAccount, isFalse);
    });

    test('a server refusal is a failed outcome carrying the error', () async {
      // Someone finished setup while the admin was looking at the row.
      const refusal = EmployeesFailureAccountNoLongerPending();
      when(() => repo.deleteEmployeeAccount(any())).thenThrow(refusal);

      final outcome = await notifier().deleteAccount('doc-1');

      expect(outcome, isA<AccountDeleteFailed>());
      expect((outcome as AccountDeleteFailed).error, refusal);
      expect(activity().isDeletingAccount, isFalse);
    });

    test('reports other failures with the original error', () async {
      final boom = Exception('offline');
      when(() => repo.deleteEmployeeAccount(any())).thenThrow(boom);

      final outcome = await notifier().deleteAccount('doc-1');

      expect((outcome as AccountDeleteFailed).error, boom);
      expect(activity().isDeletingAccount, isFalse);
    });
  });
}
