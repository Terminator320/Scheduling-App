import 'package:scheduling/features/employees/domain/models/emergency_contact.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/new_account_credentials.dart';

abstract class EmployeesRepository {
  Stream<List<EmployeeRecord>> watchAllUsers();

  Stream<List<EmployeeRecord>> watchEmployees();

  Stream<List<EmployeeRecord>> watchAssignableUsers();

  /// Creates the employee's Firebase Auth account and their `users` doc, and
  /// returns the credentials to read out to them.
  ///
  /// Re-running this for someone who hasn't set up yet is the supported
  /// "they never signed in / they lost the password" path: it refreshes their
  /// editable fields and resets the password back to the shared default. It
  /// throws `EmployeesFailureEmailAlreadyExists` once they HAVE set up, so it
  /// can never reset a password someone chose.
  Future<NewAccountCredentials> createEmployeeAccount({
    required String name,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String colorValue,
    required String jobTitle,
    required bool isAdmin,
  });

  /// Deletes an employee account that has never been set up — both the `users`
  /// doc and the Firebase Auth account.
  ///
  /// Throws `EmployeesFailureAccountNoLongerPending` when the server refuses
  /// because the person completed setup in the meantime. There is no delete
  /// for a set-up account: disable is the only removal.
  Future<void> deleteEmployeeAccount(String docId);

  /// Activates the signed-in user's own account, carrying the setup profile
  /// and consent flags the server stamps onto the users doc.
  ///
  /// Call this only AFTER the password has actually been changed — the server
  /// cannot see the password, so the order is what makes "you must replace the
  /// default" true.
  Future<void> completeEmployeeSetup({
    String firstName,
    String lastName,
    String phone,
    bool termsAccepted,
    bool locationConsent,
  });

  /// Persists the editable fields of [employee] onto `users/{docId}`.
  ///
  /// The repository builds a field-scoped allowlist from the record — `uid` is
  /// rules-forbidden and `status` belongs to deactivate/reactivate, so neither
  /// is ever in the update map no matter what the record carries.
  Future<void> updateEmployee({
    required String docId,
    required EmployeeRecord employee,
  });

  /// Streams `users/{docId}/private/emergency`.
  ///
  /// Its own document, not two fields on the users doc: rules are
  /// document-level, and `/users` is readable by every active peer. Only an
  /// admin or the person themselves can read this path — see [EmergencyContact].
  /// Emits [EmergencyContact.empty] when the doc doesn't exist yet.
  Stream<EmergencyContact> watchEmergencyContact(String docId);

  /// Writes `users/{docId}/private/emergency`, and scrubs the legacy pair off
  /// the parent users doc in the same pass — see the implementation.
  Future<void> saveEmergencyContact(String docId, EmergencyContact contact);

  Future<UserUidMatch?> findUserByUid(String uid);

  Future<void> deactivateEmployee(String docId);

  Future<void> reactivateEmployee(String docId);

  /// Streams the signed-in user's `users/{uid}` doc — a single listener that
  /// covers name, status, and role.
  Stream<Map<String, dynamic>> watchUserDoc(String uid);
}

class UserUidMatch {
  const UserUidMatch({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;
}
