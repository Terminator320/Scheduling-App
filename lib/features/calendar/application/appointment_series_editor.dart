import 'package:scheduling/features/calendar/application/event_series_helpers.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// Result of a series rewrite: the updated record, plus how many future
/// bookings were created and how many old ones were removed.
typedef SeriesRewriteResult = ({
  AppointmentRecord updated,
  int futureBookings,
  int removedBookings,
});

/// Handles series-level appointment mechanics backed by the repo: rewriting
/// a series, and applying an edit to all future occurrences.
class AppointmentSeriesEditor {
  const AppointmentSeriesEditor(this._repo);

  final AppointmentsRepository _repo;

  /// Called when the repeat interval changes. Rewrites the series by dropping
  /// the old future occurrences and booking the new cadence, all atomically.
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

  /// The "apply to all" option: propagates the edited details to this visit
  /// and to its future non-terminal siblings in the series.
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
        // Normalize each sibling's status so a legacy or unknown value doesn't get rejected.
        status: AppointmentStatus.storedRaw(v.status),
      );
    }).toList();
    await _repo.updateAppointments([updated, ...propagated]);
    return propagated.length;
  }
}
