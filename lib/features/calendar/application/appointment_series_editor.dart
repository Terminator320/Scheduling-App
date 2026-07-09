import 'package:scheduling/features/calendar/application/event_series_helpers.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// Outcome of a series rewrite: the series-stamped record plus how many future
/// occurrences were booked and how many old ones were removed.
typedef SeriesRewriteResult = ({
  AppointmentRecord updated,
  int futureBookings,
  int removedBookings,
});

/// Repo-driven series mechanics for the appointment editor — the rewrite and
/// apply-to-all-future operations, extracted from `EventDetailsController` so
/// the controller keeps orchestration and these stay focused and testable.
class AppointmentSeriesEditor {
  const AppointmentSeriesEditor(this._repo);

  final AppointmentsRepository _repo;

  /// The repeat rule changed — rewrite the series like a real calendar: drop
  /// the old future visits and book the new cadence in one atomic batch.
  /// Done/cancelled visits are kept as records; copies start 'pending' without
  /// sharing pictures. Returns the series-stamped record plus the counts.
  Future<SeriesRewriteResult> rewrite({
    required AppointmentRecord updated,
    required AppointmentRecord appointment,
    required String id,
    required DateTime start,
    required DateTime end,
    required RepeatInterval repeat,
  }) async {
    final seriesId = appointment.seriesId.isEmpty ? id : appointment.seriesId;
    final withSeries = updated.copyWith(seriesId: seriesId);
    final existing = appointment.seriesId.isEmpty
        ? const <AppointmentRecord>[]
        : await _repo.getSeries(seriesId);
    final deleteIds = futureSeriesIds(existing, excludeId: id, after: start);
    final copies = [
      for (final copyStart in repeat.occurrenceStartsAfter(start))
        withSeries.copyWith(
          id: _repo.newDocId(),
          startTime: copyStart,
          endTime: occurrenceEnd(
            originalStart: start,
            originalEnd: end,
            copyStart: copyStart,
          ),
          status: 'pending',
          pictures: const [],
        ),
    ];
    await _repo.rewriteSeries(
      updated: withSeries,
      deleteIds: deleteIds,
      copies: copies,
    );
    return (
      updated: withSeries,
      futureBookings: copies.length,
      removedBookings: deleteIds.length,
    );
  }

  /// Apply-to-all: propagate the edited details and time-of-day to this visit
  /// and every future non-terminal sibling, keeping each sibling's own calendar
  /// date so the schedule isn't disturbed. Status stays per-visit (never
  /// propagated) and each visit keeps its own pictures. Past and done/cancelled
  /// visits are left untouched. Returns the number of siblings updated.
  Future<int> propagate({
    required AppointmentRecord updated,
    required AppointmentRecord appointment,
    required String id,
    required DateTime start,
    required DateTime end,
  }) async {
    final series = await _repo.getSeries(appointment.seriesId);
    final siblings = futureSeriesRecords(
      series,
      excludeId: id,
      after: appointment.startTime,
    );
    final propagated = siblings.map((v) {
      final copyStart = withTimeOfDay(v.startTime, start);
      return v.copyWith(
        title: updated.title,
        clientId: updated.clientId,
        clientName: updated.clientName,
        clientPhone: updated.clientPhone,
        address: updated.address,
        employeeIds: updated.employeeIds,
        employeeNames: updated.employeeNames,
        notes: updated.notes,
        materialsNeeded: updated.materialsNeeded,
        repeat: updated.repeat,
        startTime: copyStart,
        endTime: occurrenceEnd(
          originalStart: start,
          originalEnd: end,
          copyStart: copyStart,
        ),
        // Canonicalize each sibling's own status (never propagate the edited
        // visit's) so a legacy value like the retired 'confirmed' isn't
        // re-written verbatim and rejected by the status allowlist rule.
        status: AppointmentStatus.fromRaw(v.status).raw,
      );
    }).toList();
    await _repo.updateAppointments([updated, ...propagated]);
    return propagated.length;
  }
}
