import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';

/// Outcome of an employee save (invite or edit). The form only maps these to
/// notices, field errors and navigation; the persistence flow lives in
/// [EmployeeFormController].
sealed class EmployeeSaveOutcome {
  const EmployeeSaveOutcome();
}

/// Edit persisted.
class EmployeeUpdated extends EmployeeSaveOutcome {
  const EmployeeUpdated();
}

/// Invite created; [code] is the one-time signup code to show the admin once.
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

/// Outcome of an employee delete.
sealed class EmployeeDeleteOutcome {
  const EmployeeDeleteOutcome();
}

class EmployeeDeleted extends EmployeeDeleteOutcome {
  const EmployeeDeleted();
}

class EmployeeDeleteFailed extends EmployeeDeleteOutcome {
  const EmployeeDeleteFailed(this.error);
  final Object error;
}

/// Busy flags for the employee form/detail surfaces — drive the Save spinner
/// and the status/delete button spinners while a mutation is in flight.
@immutable
class EmployeeFormActivity {
  const EmployeeFormActivity({
    this.isSaving = false,
    this.isTogglingStatus = false,
    this.isDeleting = false,
  });

  final bool isSaving;
  final bool isTogglingStatus;
  final bool isDeleting;

  EmployeeFormActivity copyWith({
    bool? isSaving,
    bool? isTogglingStatus,
    bool? isDeleting,
  }) {
    return EmployeeFormActivity(
      isSaving: isSaving ?? this.isSaving,
      isTogglingStatus: isTogglingStatus ?? this.isTogglingStatus,
      isDeleting: isDeleting ?? this.isDeleting,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EmployeeFormActivity &&
      other.isSaving == isSaving &&
      other.isTogglingStatus == isTogglingStatus &&
      other.isDeleting == isDeleting;

  @override
  int get hashCode => Object.hash(isSaving, isTogglingStatus, isDeleting);
}

/// Employee create/update/status/delete orchestration shared by the form
/// sheet and the details view, with a typed outcome per operation. The
/// employees list streams from Firestore, so no refresh bump is needed here
/// (unlike the paginated clients list). Validation stays in the widgets via
/// `EmployeeFormValidator`.
class EmployeeFormController extends Notifier<EmployeeFormActivity> {
  @override
  EmployeeFormActivity build() => const EmployeeFormActivity();

  /// Creates an invite; the one-time signup code rides back on the outcome.
  Future<EmployeeSaveOutcome> inviteEmployee({
    required String name,
    required String email,
    required String phone,
    required String colorValue,
  }) {
    return _save(
      (repo) async => EmployeeInvited(
        await repo.createEmployeeInvite(
          name: name,
          email: email,
          phone: phone,
          colorValue: colorValue,
        ),
      ),
    );
  }

  /// Persists an edit to an existing employee.
  Future<EmployeeSaveOutcome> updateEmployee({
    required String docId,
    required String name,
    required String email,
    required String phone,
    required String colorValue,
    required bool isAdmin,
  }) {
    return _save((repo) async {
      await repo.updateEmployee(
        docId: docId,
        name: name,
        email: email,
        phone: phone,
        colorValue: colorValue,
        isAdmin: isAdmin,
      );
      return const EmployeeUpdated();
    });
  }

  Future<EmployeeSaveOutcome> _save(
    Future<EmployeeSaveOutcome> Function(EmployeesRepository repo) write,
  ) async {
    // Resolve dependencies before the first await: the sheet can be dismissed
    // mid-save, and using the Ref of a disposed notifier throws in Riverpod 3.
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

  /// Deletes the employee's users doc. On success [state] stays deleting so
  /// the details surface keeps its spinner while its host pops/clears it.
  Future<EmployeeDeleteOutcome> deleteEmployee(String docId) async {
    // Resolved before the first await — see _save.
    final repo = ref.read(employeesRepositoryProvider);
    final logger = ref.read(loggerProvider);
    state = state.copyWith(isDeleting: true);
    try {
      await repo.deleteEmployee(docId);
      return const EmployeeDeleted();
    } catch (e, st) {
      logger.warn('EMP-DEL deleteEmployee failed', e, st);
      if (ref.mounted) state = state.copyWith(isDeleting: false);
      return EmployeeDeleteFailed(e);
    }
  }
}

final employeeFormControllerProvider =
    NotifierProvider.autoDispose<EmployeeFormController, EmployeeFormActivity>(
      EmployeeFormController.new,
    );
