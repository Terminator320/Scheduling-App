import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Repository contract for the `users` collection (employees + admins).
/// Pure Dart — no Firebase imports. Implementations live under `data/`.
///
/// All methods that take an email MUST normalize it (`.trim().toLowerCase()`)
/// at the implementation boundary — this is a CLAUDE.md invariant.
abstract class EmployeesRepository {
  Stream<List<EmployeeRecord>> watchAllUsers();

  /// Employees + admins (anyone with role in {'employee','admin'}).
  Stream<List<EmployeeRecord>> watchEmployees();

  /// Anyone with `status == 'active'` — used by appointment assignment.
  Stream<List<EmployeeRecord>> watchAssignableUsers();

  Future<EmployeeRecord?> getEmployeeById(String docId);

  /// Throws if an employee with the same normalized email already exists.
  Future<void> addEmployee({
    required String name,
    required String email,
    required String phone,
    required String colorValue,
    required bool isAdmin,
  });

  /// Throws if another employee already uses the normalized email.
  Future<void> updateEmployee({
    required String docId,
    required String name,
    required String email,
    required String phone,
    required String colorValue,
    bool? isAdmin,
  });

  Future<void> deleteEmployee(String docId);

  /// Looks up an `invited` employee by normalized email so a freshly-created
  /// Firebase Auth account can be linked to its pre-existing user doc on first
  /// sign-in.
  Future<InvitedEmployeeMatch?> findInvitedEmployeeByEmail(String email);

  /// Returns the doc ID + raw data for a user whose `uid` field matches.
  /// Used by `_resolveHome` in `main.dart` and by `SplashScreen`.
  Future<UserUidMatch?> findUserByUid(String uid);

  /// Cheap admin check used by login flows. Returns `false` if `uid` is empty
  /// or unknown.
  Future<bool> isUserAdmin(String uid);

  Future<void> activateEmployee({required String docId, required String uid});

  Future<void> deactivateEmployee(String docId);

  Future<void> reactivateEmployee(String docId);

  Stream<String> loggedInUserNameStream();
}

/// Result of looking up an `invited` employee by email.
class InvitedEmployeeMatch {
  const InvitedEmployeeMatch({required this.docId, required this.data});
  final String docId;
  final Map<String, dynamic> data;
}

/// Result of looking up a user doc by `uid` field.
class UserUidMatch {
  const UserUidMatch({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;
}
