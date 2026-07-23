import 'package:scheduling/features/employees/domain/models/employee_record.dart';

abstract class EmployeesRepository {
  Stream<List<EmployeeRecord>> watchAllUsers();

  Stream<List<EmployeeRecord>> watchEmployees();

  Stream<List<EmployeeRecord>> watchAssignableUsers();

  /// Creates invite, returns one-time signup code to show admin.
  Future<String> createEmployeeInvite({
    required String name,
    required String email,
    required String phone,
    required String colorValue,
  });

  /// Redeems signup code, activates the invite.
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

  Future<UserUidMatch?> findUserByUid(String uid);

  Future<void> deactivateEmployee(String docId);

  Future<void> reactivateEmployee(String docId);

  /// Streams signed-in user's `users/{uid}` doc (single listener for name, status, role).
  Stream<Map<String, dynamic>> watchUserDoc(String uid);
}

class UserUidMatch {
  const UserUidMatch({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;
}
