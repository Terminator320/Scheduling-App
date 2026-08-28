import 'package:scheduling/features/calendar/application/event_series_helpers.dart';
import 'package:scheduling/features/calendar/domain/appointments_repository.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/calendar/domain/models/repeat_interval.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// Result counts for a repeat-series rewrite.
typedef SeriesRewriteResult = ({
  AppointmentRecord updated,
  int futureBookings,
  int removedBookings,
});

typedef SeriesRewritePlan = ({
  AppointmentRecord updated,
  List<String> deleteIds,
  List<AppointmentRecord> copies,
});

typedef SeriesPropagatePlan = ({
  AppointmentRecord updated,
  List<AppointmentRecord> propagated,
});

/// Plans and commits series rewrites or future-occurrence propagation.
class AppointmentSeriesEditor {
  const AppointmentSeriesEditor(this._repo);

  final AppointmentsRepository _repo;

  Future<SeriesRewritePlan> planRewrite({
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
          // New repeat copies start without photo subcollection documents.
        ),
    ];
    return (updated: withSeries, deleteIds: deleteIds, copies: copies);
  }

  Future<SeriesRewriteResult> commitRewrite(SeriesRewritePlan plan) async {
    await _repo.rewriteSeries(
      updated: plan.updated,
      deleteIds: plan.deleteIds,
      copies: plan.copies,
    );
    return (
      updated: plan.updated,
      futureBookings: plan.copies.length,
      removedBookings: plan.deleteIds.length,
    );
  }

  Future<SeriesPropagatePlan> planPropagate({
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
        // Editable schedule flags travel with the propagated instants.
        isAllDay: updated.isAllDay,
        isPersonal: updated.isPersonal,
        isDayOff: updated.isDayOff,
        startTime: copyStart,
        endTime: occurrenceEnd(
          originalStart: start,
          originalEnd: end,
          copyStart: copyStart,
        ),
        // Normalize each sibling's status so legacy values stay writable.
        status: AppointmentStatus.storedRaw(v.status),
      );
    }).toList();
    return (updated: updated, propagated: propagated);
  }

  Future<int> commitPropagate(SeriesPropagatePlan plan) async {
    await _repo.updateAppointments([plan.updated, ...plan.propagated]);
    return plan.propagated.length;
  }
}
