import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/employees/application/employee_form_controller.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

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

  Future<EmployeeSaveOutcome> invite() => notifier().inviteEmployee(
    name: 'Alex',
    firstName: 'Alex',
    lastName: '',
    email: 'alex@test.com',
    phone: '555-0001',
    colorValue: '123',
    jobTitle: 'technician',
    isAdmin: true,
  );

  const edited = EmployeeRecord(
    id: 'e1',
    name: 'Alex',
    email: 'alex@test.com',
    phone: '555-0001',
    role: 'admin',
  );

  Future<EmployeeSaveOutcome> update() => notifier().updateEmployee(edited);

  group('inviteEmployee', () {
    test('returns the one-time signup code on success', () async {
      when(
        () => repo.createEmployeeInvite(
          name: any(named: 'name'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          email: any(named: 'email'),
          phone: any(named: 'phone'),
          colorValue: any(named: 'colorValue'),
          jobTitle: any(named: 'jobTitle'),
          isAdmin: any(named: 'isAdmin'),
        ),
      ).thenAnswer((_) async => 'CODE-42');

      final outcome = await invite();

      expect(outcome, isA<EmployeeInvited>());
      expect((outcome as EmployeeInvited).code, 'CODE-42');
      expect(activity().isSaving, isFalse);
    });

    test('surfaces a taken email as a field-level outcome', () async {
      when(
        () => repo.createEmployeeInvite(
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

      expect(await invite(), isA<EmployeeEmailInUse>());
      expect(activity().isSaving, isFalse);
    });

    test('reports other failures with the original error', () async {
      final boom = Exception('offline');
      when(
        () => repo.createEmployeeInvite(
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

      final outcome = await invite();

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

  group('revokeInvite', () {
    test('reports revoked and clears the busy flag', () async {
      when(() => repo.revokeInvite(any())).thenAnswer((_) async {});

      final outcome = await notifier().revokeInvite('invite-1');

      expect(outcome, isA<InviteRevoked>());
      verify(() => repo.revokeInvite('invite-1')).called(1);
      expect(activity().isRevoking, isFalse);
    });

    test('a server refusal is a failed outcome carrying the error', () async {
      const refusal = EmployeesFailureInviteNoLongerPending();
      when(() => repo.revokeInvite(any())).thenThrow(refusal);

      final outcome = await notifier().revokeInvite('invite-1');

      expect(outcome, isA<InviteRevokeFailed>());
      expect((outcome as InviteRevokeFailed).error, refusal);
      expect(activity().isRevoking, isFalse);
    });

    test('reports other failures with the original error', () async {
      final boom = Exception('offline');
      when(() => repo.revokeInvite(any())).thenThrow(boom);

      final outcome = await notifier().revokeInvite('invite-1');

      expect((outcome as InviteRevokeFailed).error, boom);
      expect(activity().isRevoking, isFalse);
    });
  });
}
