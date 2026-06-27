import 'package:scheduling/features/employees/domain/models/employee_record.dart';

abstract class EmployeesRepository {
  Stream<List<EmployeeRecord>> watchAllUsers();

  Stream<List<EmployeeRecord>> watchEmployees();

  Stream<List<EmployeeRecord>> watchAssignableUsers();

  /// Creates an invite via the createEmployeeInvite callable; returns the
  /// one-time signup code to show the admin once.
  Future<String> createEmployeeInvite({
    required String name,
    required String email,
    required String phone,
    required String colorValue,
  });

  /// Redeems a signup code for the current user (activates the invite).
  Future<void> redeemSignupCode(String code);

  Future<void> updateEmployee({
    required String docId,
    required String name,
    required String email,
    required String phone,
    required String colorValue,
    bool? isAdmin,
  });

  Future<void> deleteEmployee(String docId);

  Future<InvitedEmployeeMatch?> findInvitedEmployeeForCurrentUser();

  Future<UserUidMatch?> findUserByUid(String uid);

  Future<void> activateEmployee({required String docId, required String uid});

  Future<void> deactivateEmployee(String docId);

  Future<void> reactivateEmployee(String docId);

  /// Streams the signed-in user's `users/{uid}` doc data (empty map when
  /// none). One listener feeds name + status + role so the app doesn't open
  /// three separate snapshot listeners on the same document.
  Stream<Map<String, dynamic>> watchUserDoc(String uid);
}

class InvitedEmployeeMatch {
  const InvitedEmployeeMatch({required this.docId, required this.data});
  final String docId;
  final Map<String, dynamic> data;
}

class UserUidMatch {
  const UserUidMatch({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;
}
