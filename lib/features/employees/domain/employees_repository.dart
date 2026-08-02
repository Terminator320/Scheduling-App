import 'package:scheduling/features/employees/domain/models/employee_record.dart';
import 'package:scheduling/features/employees/domain/models/invite_preview.dart';

abstract class EmployeesRepository {
  Stream<List<EmployeeRecord>> watchAllUsers();

  Stream<List<EmployeeRecord>> watchEmployees();

  Stream<List<EmployeeRecord>> watchAssignableUsers();

  /// Creates an invite and returns the one-time signup code to show the admin.
  Future<String> createEmployeeInvite({
    required String name,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String colorValue,
    required String jobTitle,
    required bool isAdmin,
  });

  /// Deletes a still-pending invite and its signup code.
  ///
  /// Throws `EmployeesFailureInviteNoLongerPending` when the server refuses
  /// because the invite was redeemed or revoked in the meantime.
  Future<void> revokeInvite(String inviteDocId);

  /// Resolves what an unredeemed [code] was issued for, so the acceptance
  /// screen can show the invited email without the holder having an account.
  Future<InvitePreview> previewInvite(String code);

  /// Redeems a signup code and activates the invite, carrying the acceptance
  /// profile and consent flags the server stamps onto the users doc.
  Future<void> redeemSignupCode(
    String code, {
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
