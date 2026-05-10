import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Repository contract for the `appointments` collection. Pure Dart.
///
/// `add` and `update` MUST set `createdAt` / `updatedAt` to server timestamps
/// at the implementation boundary (CLAUDE.md invariant).
abstract class AppointmentsRepository {
  /// Mints a new doc ID without writing — used so the photo uploader can
  /// patch a freshly-created appointment in the background.
  String newDocId();

  Future<AppointmentRecord?> getAppointmentById(String id);

  Future<void> addAppointment(AppointmentRecord appointment);

  Future<void> updateAppointment(AppointmentRecord appointment);

  Future<void> updateAppointmentPictures(
    String id,
    List<AppointmentImage> pictures,
  );

  Future<void> updateAppointmentStatus({
    required String id,
    required String status,
  });

  Future<void> deleteAppointment(String id);

  Stream<List<AppointmentRecord>> watchAll();

  /// Streams only the appointments whose `startTime` falls inside `range`.
  /// Used by the calendar so we never page the entire collection.
  Stream<List<AppointmentRecord>> watchInRange(AppointmentDateRange range);

  Stream<List<AppointmentRecord>> watchHistory();

  Stream<List<AppointmentRecord>> watchForEmployee(String employeeId);

  /// Returns the subset of `candidates` who already have a conflicting
  /// appointment in `[start, end)`. Used by the assignment picker.
  Future<List<EmployeeRecord>> findBusyEmployees({
    required List<EmployeeRecord> candidates,
    required DateTime start,
    required DateTime end,
  });
}
