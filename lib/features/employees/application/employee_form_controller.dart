import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scheduling/core/logging/app_logger.dart';
import 'package:scheduling/features/employees/application/employees_providers.dart';
import 'package:scheduling/features/employees/domain/employees_failure.dart';
import 'package:scheduling/features/employees/domain/employees_repository.dart';
import 'package:scheduling/features/employees/domain/models/emergency_contact.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/new_account_credentials.dart';

/// Outcome of an employee save, whether an invite or an edit — the form maps
/// this to a notice, an error, or a navigation action.
sealed class EmployeeSaveOutcome {
  const EmployeeSaveOutcome();
}

/// Edit persisted.
class EmployeeUpdated extends EmployeeSaveOutcome {
  const EmployeeUpdated();
}

/// The account was created (or re-provisioned). [credentials] are what the
/// admin reads out — the email and the starting password the server set.
class EmployeeAccountCreated extends EmployeeSaveOutcome {
  const EmployeeAccountCreated(this.credentials);
  final NewAccountCredentials credentials;
}

/// The email already belongs to an account that has finished setup — a field
/// error, not a notice.
class EmployeeEmailInUse extends EmployeeSaveOutcome {
  const EmployeeEmailInUse(this.failure);
  final EmployeesFailureEmailAlreadyExists failure;
}

class EmployeeSaveFailed extends EmployeeSaveOutcome {
  const EmployeeSaveFailed(this.error);
  final Object error;
}

/// A write the reentrancy guard skipped because one is already in flight.
/// Nothing committed and nothing failed, so this surfaces NOTHING — no notice
/// either way. It used to be reported as `EmployeeSaveFailed(SocketException)`,
/// which `composeErrorNotice` classifies by TYPE and rendered as "you appear to
/// be offline" on a double-tap while perfectly online. Same shape as
/// EventDetailsActionBusy.
class EmployeeSaveBusy extends EmployeeSaveOutcome {
  const EmployeeSaveBusy();
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

/// Outcome of revoking a pending invite.
sealed class AccountDeleteOutcome {
  const AccountDeleteOutcome();
}

class AccountDeleted extends AccountDeleteOutcome {
  const AccountDeleted();
}

class AccountDeleteFailed extends AccountDeleteOutcome {
  const AccountDeleteFailed(this.error);
  final Object error;
}

/// Busy flags for the employee form/detail surfaces — these drive the Save
/// button and the status button spinners.
@immutable
class EmployeeFormActivity {
  const EmployeeFormActivity({
    this.isSaving = false,
    this.isTogglingStatus = false,
    this.isDeletingAccount = false,
  });

  final bool isSaving;
  final bool isTogglingStatus;
  final bool isDeletingAccount;

  EmployeeFormActivity copyWith({
    bool? isSaving,
    bool? isTogglingStatus,
    bool? isDeletingAccount,
  }) {
    return EmployeeFormActivity(
      isSaving: isSaving ?? this.isSaving,
      isTogglingStatus: isTogglingStatus ?? this.isTogglingStatus,
      isDeletingAccount: isDeletingAccount ?? this.isDeletingAccount,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EmployeeFormActivity &&
      other.isSaving == isSaving &&
      other.isTogglingStatus == isTogglingStatus &&
      other.isDeletingAccount == isDeletingAccount;

  @override
  int get hashCode =>
      Object.hash(isSaving, isTogglingStatus, isDeletingAccount);
}

/// Handles employee create/update/status, shared by the form sheet and the
/// details view. The employees list streams straight from Firestore, so
/// there's no need for a refresh bump here like the paginated clients list
/// needs.
class EmployeeFormController extends Notifier<EmployeeFormActivity> {
  @override
  EmployeeFormActivity build() => const EmployeeFormActivity();

  /// Creates the employee's account. The credentials ride back on the outcome
  /// so the caller can show them to the admin.
  ///
  /// Takes the whole record on purpose. The server's re-provision branch
  /// UPDATES the pending doc's editable fields with whatever it is handed, so
  /// a call site that omits one silently wipes it — passing a record closes
  /// that trap at the CALL SITES, which is where it kept being sprung.
  ///
  /// It does not close it here: the destructuring below is still by hand, so a
  /// new pending-user field added to the server's update set has to be added
  /// to this one place too, with no compile error if it isn't. One place, not
  /// four — but not zero.
  Future<EmployeeSaveOutcome> createAccount(EmployeeRecord employee) {
    return _save(
      (repo) async => EmployeeAccountCreated(
        await repo.createEmployeeAccount(
          name: employee.name,
          firstName: employee.firstName,
          lastName: employee.lastName,
          email: employee.email,
          phone: employee.phone,
          colorValue: employee.color.toARGB32().toString(),
          jobTitle: employee.jobTitle.raw,
          isAdmin: employee.isAdmin,
        ),
      ),
    );
  }

  /// Persists an edit to an existing employee.
  ///
  /// [emergency] rides along because it is a second write to a different path
  /// (`users/{id}/private/emergency`) that the one Save button owns — routing
  /// it through the same `_save` keeps one in-flight flag and one error path,
  /// so a failure on either write surfaces once. Pass null to leave it alone.
  Future<EmployeeSaveOutcome> updateEmployee(
    EmployeeRecord employee, {
    EmergencyContact? emergency,
  }) {
    return _save((repo) async {
      await repo.updateEmployee(docId: employee.id, employee: employee);
      if (emergency != null) {
        await repo.saveEmergencyContact(employee.id, emergency);
      }
      return const EmployeeUpdated();
    });
  }

  Future<EmployeeSaveOutcome> _save(
    Future<EmployeeSaveOutcome> Function(EmployeesRepository repo) write,
  ) async {
    // Reentrancy guard, synchronously first: the sheet's primary button only
    // disables on the next frame, so a double-tap otherwise starts a second
    // concurrent write. PendingInviteTile checks isSaving at its call site;
    // owning it here covers the two person sheets too.
    if (state.isSaving) {
      return const EmployeeSaveBusy();
    }
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

  /// Deletes an account that has never been set up — the users doc and the
  /// Firebase Auth account both.
  ///
  /// A server refusal (the person finished setup while the admin was looking
  /// at the row) is a *failed* outcome, not a silent success — the live stream
  /// will have flipped the row to Active by the time the notice lands.
  Future<AccountDeleteOutcome> deleteAccount(String docId) async {
    // Resolved before the first await — see _save.
    final repo = ref.read(employeesRepositoryProvider);
    final logger = ref.read(loggerProvider);
    state = state.copyWith(isDeletingAccount: true);
    try {
      await repo.deleteEmployeeAccount(docId);
      return const AccountDeleted();
    } catch (e, st) {
      logger.warn('EMP-DELETE deleteEmployeeAccount failed', e, st);
      return AccountDeleteFailed(e);
    } finally {
      if (ref.mounted) state = state.copyWith(isDeletingAccount: false);
    }
  }
}

final employeeFormControllerProvider =
    NotifierProvider.autoDispose<EmployeeFormController, EmployeeFormActivity>(
      EmployeeFormController.new,
    );
