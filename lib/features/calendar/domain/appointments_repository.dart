import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

abstract class AppointmentsRepository {
  String newDocId();

  Future<AppointmentRecord?> getAppointmentById(String id);

  /// How many not-yet-started jobs this employee is still assigned to.
  ///
  /// Backs the disable-confirmation caption. An aggregate `count()` rather than
  /// a fetch — nothing needs the documents, only the number.
  Future<int> countFutureAssignments(String employeeId);

  Future<void> addAppointment(AppointmentRecord appointment);

  /// Creates every appointment in [appointments] atomically (all-or-nothing).
  Future<void> addAppointments(List<AppointmentRecord> appointments);

  /// All appointments belonging to one repeat series.
  Future<List<AppointmentRecord>> getSeries(String seriesId);

  /// Atomically rewrites a series — saves, deletes, and creates all happen
  /// in one batch.
  Future<void> rewriteSeries({
    required AppointmentRecord updated,
    required List<String> deleteIds,
    required List<AppointmentRecord> copies,
  });

  Future<void> updateAppointment(AppointmentRecord appointment);

  /// Atomically update series to propagate edit across visit and future siblings.
  Future<void> updateAppointments(List<AppointmentRecord> appointments);

  /// Appends [pictures] to the appointment's stored pictures using a
  /// server-side union instead of rewriting the whole array. That way a
  /// background upload landing after a concurrent edit can't clobber photos
  /// it never saw, and the edit can't clobber the upload either.
  Future<void> appendAppointmentPictures(
    String id,
    List<AppointmentImage> pictures,
  );

  /// Remove pictures via arrayRemove, leaving concurrent appends intact.
  Future<void> removeAppointmentPictures(
    String id,
    List<AppointmentImage> pictures,
  );

  /// This appointment's photos, read from the `images` subcollection.
  ///
  /// Phase 1 of moving photos off the parent document: every appointment read
  /// carried its whole photo array, and the calendar reads up to 1000
  /// appointments at a time while only the detail sheet ever shows a photo.
  ///
  /// Returns an EMPTY list both for an appointment with no photos and for one
  /// whose photos have not been backfilled yet, so a caller must treat empty
  /// as "ask the array" rather than "there are none" until the backfill has
  /// run everywhere. [AppointmentRecord.pictures] is still populated and is
  /// still the fallback.
  Future<List<AppointmentImage>> fetchAppointmentPictures(String id);

  Future<void> updateAppointmentStatus({
    required String id,
    required String status,
  });

  Future<void> deleteAppointment(String id);

  /// Deletes every appointment in [ids] atomically (all-or-nothing).
  Future<void> deleteAppointments(List<String> ids);

  Stream<List<AppointmentRecord>> watchInRange(AppointmentDateRange range);

  /// The same query as [watchInRange], read ONCE.
  ///
  /// For a window of settled history — closed weeks that cannot change while
  /// the screen is up, so paying for a live listener over them buys nothing.
  /// The dashboard's trend charts are the caller.
  Future<List<AppointmentRecord>> fetchInRange(AppointmentDateRange range);

  /// One newest-first page of terminal appointments. Pass [after] as the
  /// cursor to continue from, or null to start from the beginning.
  Future<List<AppointmentRecord>> fetchHistoryPage({
    required int limit,
    AppointmentRecord? after,
  });

  /// Search terminal appointments by client/employee name or phone, newest-first.
  Future<List<AppointmentRecord>> searchHistory(String query);

  /// This client's appointments in any status, newest-first.
  ///
  /// [limit] is the page size used internally while collecting the full
  /// history.
  Future<List<AppointmentRecord>> fetchClientHistory({
    required String clientId,
    int limit,
  });

  /// Fires after local writes so search providers invalidate stale results immediately.
  Stream<void> get onLocalWrite;

  Stream<List<AppointmentRecord>> watchForEmployeeInRange(
    String employeeId,
    AppointmentDateRange range,
  );

  /// [excludeAppointmentId] drops one doc from the overlap scan — an edit must
  /// not collide with the very appointment being edited. It excludes by doc id,
  /// not by series, so a genuine clash with a sibling occurrence still surfaces.
  Future<List<EmployeeRecord>> findBusyEmployees({
    required List<EmployeeRecord> candidates,
    required DateTime start,
    required DateTime end,
    String? excludeAppointmentId,
  });
}
