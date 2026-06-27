import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

abstract class AppointmentsRepository {
  String newDocId();

  Future<AppointmentRecord?> getAppointmentById(String id);

  Future<void> addAppointment(AppointmentRecord appointment);

  /// Creates every appointment in [appointments] atomically (all-or-nothing).
  Future<void> addAppointments(List<AppointmentRecord> appointments);

  /// All appointments belonging to one repeat series.
  Future<List<AppointmentRecord>> getSeries(String seriesId);

  /// Atomically rewrites a repeat series: saves [updated], deletes the docs
  /// in [deleteIds], and creates [copies] — all-or-nothing.
  Future<void> rewriteSeries({
    required AppointmentRecord updated,
    required List<String> deleteIds,
    required List<AppointmentRecord> copies,
  });

  Future<void> updateAppointment(AppointmentRecord appointment);

  /// Atomically updates every appointment in [appointments] (all-or-nothing).
  /// Used to propagate an edit across this visit and its future series siblings.
  Future<void> updateAppointments(List<AppointmentRecord> appointments);

  Future<void> updateAppointmentPictures(
    String id,
    List<AppointmentImage> pictures,
  );

  Future<void> updateAppointmentStatus({
    required String id,
    required String status,
  });

  Future<void> deleteAppointment(String id);

  /// Deletes every appointment in [ids] atomically (all-or-nothing).
  Future<void> deleteAppointments(List<String> ids);

  Stream<List<AppointmentRecord>> watchInRange(AppointmentDateRange range);

  /// One newest-first page of terminal (done/cancelled) appointments.
  /// [after] is the last record of the previous page (cursor); null for the
  /// first page.
  Future<List<AppointmentRecord>> fetchHistoryPage({
    required int limit,
    AppointmentRecord? after,
  });

  /// Searches terminal (done/cancelled) appointments across the database — not
  /// just the pages already loaded into the list — by client name, client
  /// phone, or employee name. Scans the most-recent window of history and
  /// returns the matches newest-first.
  Future<List<AppointmentRecord>> searchHistory(String query);

  Stream<List<AppointmentRecord>> watchForEmployeeInRange(
    String employeeId,
    AppointmentDateRange range,
  );

  Future<List<EmployeeRecord>> findBusyEmployees({
    required List<EmployeeRecord> candidates,
    required DateTime start,
    required DateTime end,
  });
}
