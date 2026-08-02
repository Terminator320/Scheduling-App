import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Outcome of an employee save, whether an invite or an edit — the form maps
/// this to a notice, an error, or a navigation action.
sealed class EmployeeSaveOutcome {
  const EmployeeSaveOutcome();
}

/// Edit persisted.
class EmployeeUpdated extends EmployeeSaveOutcome {
  const EmployeeUpdated();
}

/// The invite was created. [code] is the one-time signup code to show the
/// admin once.
class EmployeeInvited extends EmployeeSaveOutcome {
  const EmployeeInvited(this.code);
  final String code;
}

/// The invite email is already taken — a field error, not a notice.
class EmployeeEmailInUse extends EmployeeSaveOutcome {
  const EmployeeEmailInUse(this.failure);
  final EmployeesFailureEmailAlreadyExists failure;
}

class EmployeeSaveFailed extends EmployeeSaveOutcome {
  const EmployeeSaveFailed(this.error);
  final Object error;
}

/// Outcome of a disable/enable toggle.
sealed class EmployeeStatusOutcome {
  const EmployeeStatusOutcome();
}

class EmployeeStatusChanged extends EmployeeStatusOutcome {
  const EmployeeStatusChanged();
}

class EmployeeStatusChangeFailed extends EmployeeStatusOutcome {
  const EmployeeStatusChangeFailed(this.error);
  final Object error;
}

/// Busy flags for the employee form/detail surfaces — these drive the Save
/// button and the status button spinners.
@immutable
class EmployeeFormActivity {
  const EmployeeFormActivity({
    this.isSaving = false,
    this.isTogglingStatus = false,
  });

  final bool isSaving;
  final bool isTogglingStatus;

  EmployeeFormActivity copyWith({bool? isSaving, bool? isTogglingStatus}) {
    return EmployeeFormActivity(
      isSaving: isSaving ?? this.isSaving,
      isTogglingStatus: isTogglingStatus ?? this.isTogglingStatus,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EmployeeFormActivity &&
      other.isSaving == isSaving &&
      other.isTogglingStatus == isTogglingStatus;

  @override
  int get hashCode => Object.hash(isSaving, isTogglingStatus);
}

/// Handles employee create/update/status, shared by the form sheet and the
/// details view. The employees list streams straight from Firestore, so
/// there's no need for a refresh bump here like the paginated clients list
/// needs.
class EmployeeFormController extends Notifier<EmployeeFormActivity> {
  @override
  EmployeeFormActivity build() => const EmployeeFormActivity();

  /// Creates an invite. The one-time signup code rides back on the outcome
  /// so the caller can show it to the admin.
  Future<EmployeeSaveOutcome> inviteEmployee({
    required String name,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String colorValue,
    required String jobTitle,
    required bool isAdmin,
  }) {
    return _save(
      (repo) async => EmployeeInvited(
        await repo.createEmployeeInvite(
          name: name,
          firstName: firstName,
          lastName: lastName,
          email: email,
          phone: phone,
          colorValue: colorValue,
          jobTitle: jobTitle,
          isAdmin: isAdmin,
        ),
      ),
    );
  }

  /// Persists an edit to an existing employee.
  Future<EmployeeSaveOutcome> updateEmployee(EmployeeRecord employee) {
    return _save((repo) async {
      await repo.updateEmployee(docId: employee.id, employee: employee);
      return const EmployeeUpdated();
    });
  }

  Future<EmployeeSaveOutcome> _save(
    Future<EmployeeSaveOutcome> Function(EmployeesRepository repo) write,
  ) async {
    // Resolve dependencies before the first await. The sheet can be
    // dismissed mid-save, and using the Ref of a disposed notifier throws in
    // Riverpod 3.
    final repo = ref.read(employeesRepositoryProvider);
    final logger = ref.read(loggerProvider);
    state = state.copyWith(isSaving: true);
    try {
      return await write(repo);
    } catch (e, st) {
      if (e is EmployeesFailureEmailAlreadyExists) {
        return EmployeeEmailInUse(e);
      }
      logger.warn('EMP-CREATE saveEmployee failed', e, st);
      return EmployeeSaveFailed(e);
    } finally {
      if (ref.mounted) state = state.copyWith(isSaving: false);
    }
  }

  /// Disables ([disable] true) or re-enables the employee's account.
  Future<EmployeeStatusOutcome> setEmployeeStatus({
    required String docId,
    required bool disable,
  }) async {
    // Resolved before the first await — see _save.
    final repo = ref.read(employeesRepositoryProvider);
    final logger = ref.read(loggerProvider);
    state = state.copyWith(isTogglingStatus: true);
    try {
      if (disable) {
        await repo.deactivateEmployee(docId);
      } else {
        await repo.reactivateEmployee(docId);
      }
      return const EmployeeStatusChanged();
    } catch (e, st) {
      logger.warn('EMP-STATUS toggleEmployeeStatus failed', e, st);
      return EmployeeStatusChangeFailed(e);
    } finally {
      if (ref.mounted) state = state.copyWith(isTogglingStatus: false);
    }
  }
}

final employeeFormControllerProvider =
    NotifierProvider.autoDispose<EmployeeFormController, EmployeeFormActivity>(
      EmployeeFormController.new,
    );
