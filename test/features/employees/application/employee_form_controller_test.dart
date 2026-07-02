import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:scheduling/features/employees/application/employee_form_controller.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';

class _MockEmployeesRepo extends Mock implements EmployeesRepository {}

void main() {
  late _MockEmployeesRepo repo;
  late ProviderContainer container;

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
    email: 'alex@test.com',
    phone: '555-0001',
    colorValue: '123',
  );

  Future<EmployeeSaveOutcome> update() => notifier().updateEmployee(
    docId: 'e1',
    name: 'Alex',
    email: 'alex@test.com',
    phone: '555-0001',
    colorValue: '123',
    isAdmin: true,
  );

  group('inviteEmployee', () {
    test('returns the one-time signup code on success', () async {
      when(
        () => repo.createEmployeeInvite(
          name: any(named: 'name'),
          email: any(named: 'email'),
          phone: any(named: 'phone'),
          colorValue: any(named: 'colorValue'),
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
          email: any(named: 'email'),
          phone: any(named: 'phone'),
          colorValue: any(named: 'colorValue'),
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
          email: any(named: 'email'),
          phone: any(named: 'phone'),
          colorValue: any(named: 'colorValue'),
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
          name: any(named: 'name'),
          email: any(named: 'email'),
          phone: any(named: 'phone'),
          colorValue: any(named: 'colorValue'),
          isAdmin: any(named: 'isAdmin'),
        ),
      ).thenAnswer((_) async {});

      expect(await update(), isA<EmployeeUpdated>());
      verify(
        () => repo.updateEmployee(
          docId: 'e1',
          name: 'Alex',
          email: 'alex@test.com',
          phone: '555-0001',
          colorValue: '123',
          isAdmin: true,
        ),
      ).called(1);
      expect(activity().isSaving, isFalse);
    });

    test('reports failures with the original error', () async {
      when(
        () => repo.updateEmployee(
          docId: any(named: 'docId'),
          name: any(named: 'name'),
          email: any(named: 'email'),
          phone: any(named: 'phone'),
          colorValue: any(named: 'colorValue'),
          isAdmin: any(named: 'isAdmin'),
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

  group('deleteEmployee', () {
    test('deletes and stays busy so the host can pop the surface', () async {
      when(() => repo.deleteEmployee(any())).thenAnswer((_) async {});

      final outcome = await notifier().deleteEmployee('e1');

      expect(outcome, isA<EmployeeDeleted>());
      verify(() => repo.deleteEmployee('e1')).called(1);
      expect(activity().isDeleting, isTrue);
    });

    test('reports failures and resets the busy flag', () async {
      when(() => repo.deleteEmployee(any())).thenThrow(Exception('boom'));

      final outcome = await notifier().deleteEmployee('e1');

      expect(outcome, isA<EmployeeDeleteFailed>());
      expect(activity().isDeleting, isFalse);
    });
  });
}
