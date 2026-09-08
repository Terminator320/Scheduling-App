import 'package:scheduling/features/calendar/domain/appointment_status_values.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';

/// Pure helpers for reasoning about an appointment series, extracted for testability.

/// Ids of the non-terminal siblings that come AFTER [anchor], excluding it.
List<String> futureSeriesIds(
  List<AppointmentRecord> series, {
  required String excludeId,
  required DateTime after,
  AppointmentRecord? anchor,
}) => [
  for (final a in futureSeriesRecords(
    series,
    excludeId: excludeId,
    after: after,
    anchor: anchor,
  ))
    a.id!,
];

/// Non-terminal siblings after [anchor], excluding [excludeId], for propagation.
///
/// **What "after" means depends on which axis the siblings share.** A repeat
/// series is ordered in TIME, so a later occurrence is one starting later. A
/// multi-day RUN is ordered by its stored `dayIndex`, and that is the only
/// ordering that survives an edit: a run member's start date is editable, so
/// moving day 1 forward past its siblings made "this and the following days"
/// select nothing and report success, while the same action on day 4 swept up
/// the moved day 1. Pass [anchor] — the record the scope was chosen on — and a
/// run compares day positions; without it, or on a repeat series, the
/// comparison stays on `startTime` exactly as before.
List<AppointmentRecord> futureSeriesRecords(
  List<AppointmentRecord> series, {
  required String excludeId,
  required DateTime after,
  AppointmentRecord? anchor,
}) {
  // Only a coherent run pair may switch axes; anything else is a repeat series
  // or a legacy wide document, where time is the right ordering.
  final runIndex = (anchor != null && anchor.hasRunLabels)
      ? anchor.dayIndex
      : null;
  return [
    for (final a in series)
      if (a.id != null &&
          a.id != excludeId &&
          !isTerminalStatusRaw(a.status) &&
          (runIndex == null
              ? a.startTime.isAfter(after)
              : a.hasRunLabels && a.dayIndex > runIndex))
        a,
  ];
}

/// [date]'s calendar day carrying [timeSource]'s time of day.
DateTime withTimeOfDay(DateTime date, DateTime timeSource) => DateTime(
  date.year,
  date.month,
  date.day,
  timeSource.hour,
  timeSource.minute,
);

/// A minimal client built from an appointment's denormalized fields, used as a
/// validation fallback when the full client record hasn't loaded yet.
ClientRecord placeholderClient(AppointmentRecord a) => ClientRecord(
  id: a.clientId,
  name: a.clientName,
  phone: a.clientPhone,
  address: a.address,
);

/// How much of a series a "this and following" save would touch — the anchor
/// plus the siblings [futureSeriesRecords] will actually write.
///
/// It lives beside that selection, and derives FROM it, because the dialog's
/// number and the write have to agree. Counted independently they did not:
/// a terminal sibling was counted but never written, and on a multi-day RUN
/// the count compared `startTime` while the write compared `dayIndex`, so the
/// figure the admin confirmed was not the number that changed. `last` is the
/// latest instant among them, for the dialog's "through the 26th" line.
({int count, DateTime? last}) seriesOutlook(
  List<AppointmentRecord> series, {
  required AppointmentRecord anchor,
  required String excludeId,
}) {
  final future = futureSeriesRecords(
    series,
    excludeId: excludeId,
    after: anchor.startTime,
    anchor: anchor,
  );
  var last = anchor.startTime;
  for (final occurrence in future) {
    if (occurrence.startTime.isAfter(last)) last = occurrence.startTime;
  }
  // The anchor is the visit being saved, so it is always written and always
  // counts — which is why this can never report zero.
  return (count: future.length + 1, last: last);
}
