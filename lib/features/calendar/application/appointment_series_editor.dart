import 'package:scheduling/features/calendar/application/event_series_helpers.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// Outcome of a series rewrite: record, future bookings count, removed count.
typedef SeriesRewriteResult = ({
  AppointmentRecord updated,
  int futureBookings,
  int removedBookings,
});

/// Repo-driven series mechanics: rewrite and apply-to-all-future operations.
class AppointmentSeriesEditor {
  const AppointmentSeriesEditor(this._repo);

  final AppointmentsRepository _repo;

  /// Repeat changed: rewrite series, drop old future, book new cadence atomically.
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

  /// Apply-to-all: propagate edited details to this visit and future non-terminal siblings.
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
        // Canonicalize each sibling's status to avoid legacy value rejection.
        status: AppointmentStatus.storedRaw(v.status),
      );
    }).toList();
    await _repo.updateAppointments([updated, ...propagated]);
    return propagated.length;
  }
}
