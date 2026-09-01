import 'package:scheduling/features/calendar/domain/models/appointment_image.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/employees/domain/models/employee_record.dart';

abstract class AppointmentsRepository {
  /// Drops every cached appointment this repository is holding.
  ///
  /// The implementation is a process-scoped singleton, so its history search
  /// windows outlive the session that filled them — raw appointment maps
  /// carrying `clientName`, `clientPhone` and `address`. Sign-out and account
  /// exit call this through `deregisterThisDevice`, which is the single owner
  /// of "forget this session".
  void clearCaches();

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

  /// Adds [pictures] to `appointments/{id}/images`.
  ///
  /// Each document's id is derived from the photo, so a retry of a batch that
  /// partly landed rewrites the same documents rather than duplicating them —
  /// which is what a background upload arriving after a concurrent edit needs.
  Future<void> appendAppointmentPictures(
    String id,
    List<AppointmentImage> pictures,
  );

  /// Deletes [pictures] from `appointments/{id}/images`, by the same derived
  /// ids, leaving photos this caller never saw untouched.
  Future<void> removeAppointmentPictures(
    String id,
    List<AppointmentImage> pictures,
  );

  /// This appointment's photos.
  ///
  /// The `images` subcollection is the only store — the `pictures` array on the
  /// parent document went at the CONTRACT step. So an empty list means this job
  /// has no photos, full stop; during the migration it also meant "not
  /// backfilled yet, ask the array", and no caller should still be written that
  /// way.
  Future<List<AppointmentImage>> fetchAppointmentPictures(String id);

  /// Writes what the CREW recorded on site.
  ///
  /// Its own method, not a corner of `updateAppointment`: the rules branch
  /// behind it is `hasOnly(['fieldNotes', 'updatedAt'])`, so an assignee's
  /// write must carry those two keys and nothing else. Re-serializing the
  /// record here would be refused as an opaque `permission-denied`.
  Future<void> updateFieldNotes({required String id, required String notes});

  Future<void> updateAppointmentStatus({
    required String id,
    required String status,
  });

  /// Writes one status across several appointments in a single batch.
  ///
  /// The run half of a cancel: cancelling day 3 of a 5-day job with "this and
  /// the following days" has to close days 3, 4 and 5 together. One batch, so
  /// a run can never be left half-cancelled, and one shared `seriesOpId`, so
  /// the crew gets ONE push rather than one per day.
  Future<void> updateAppointmentStatuses({
    required List<String> ids,
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

  /// The live appointments standing in the way of [employeeIds] over
  /// [start]–[end], read ONCE.
  ///
  /// The same overlap scan [findBusyEmployees] runs, answering with the
  /// CLASHING RECORDS rather than the busy people — the assignee picker needs
  /// to say why someone can't take the job, and the time-off clash alert needs
  /// the jobs themselves so it can offer a swap on each.
  ///
  /// Both surfaces route through here rather than deciding for themselves: the
  /// picker reduces a live stream on top of the same rule
  /// (`clashingAppointments`), and if the two ever disagree the bug is that the
  /// rule lives in two places.
  ///
  /// [clientJobsOnly] drops personal blocks from the result. The alert passes
  /// it — "swap Marc for Nadia" on Marc's own dentist appointment is nonsense,
  /// so a personal block is a real clash for busy-ness and never a row in that
  /// dialog. The picker leaves it off.
  Future<List<AppointmentRecord>> findClashingAppointments({
    required List<String> employeeIds,
    required DateTime start,
    required DateTime end,
    String? excludeAppointmentId,
    bool clientJobsOnly,
  });
}
