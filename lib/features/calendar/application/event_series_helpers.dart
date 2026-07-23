import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart'
    show AppointmentStatus;

/// Pure helpers for reasoning about an appointment series, extracted for testability.

/// Ids of non-terminal series visits after [after], excluding [excludeId].
List<String> futureSeriesIds(
  List<AppointmentRecord> series, {
  required String excludeId,
  required DateTime after,
}) => [
  for (final a in futureSeriesRecords(
    series,
    excludeId: excludeId,
    after: after,
  ))
    a.id!,
];

/// Non-terminal series visits after [after], excluding [excludeId], for propagation.
List<AppointmentRecord> futureSeriesRecords(
  List<AppointmentRecord> series, {
  required String excludeId,
  required DateTime after,
}) => [
  for (final a in series)
    if (a.id != null &&
        a.id != excludeId &&
        a.startTime.isAfter(after) &&
        !AppointmentStatus.fromRaw(a.status).isTerminal)
      a,
];

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
