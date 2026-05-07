import 'package:scheduling/features/employees/domain/models/employee_record.dart';

abstract class EmployeesRepository {
  Stream<List<EmployeeRecord>> watchAllUsers();

  Stream<List<EmployeeRecord>> watchEmployees();

  Stream<List<EmployeeRecord>> watchAssignableUsers();

  Future<EmployeeRecord?> getEmployeeById(String docId);

  Future<void> addEmployee({
    required String name,
    required String email,
    required String phone,
    required String colorValue,
    required bool isAdmin,
  });

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
