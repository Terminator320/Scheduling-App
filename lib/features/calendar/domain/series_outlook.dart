import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// How much of a repeating series a "this and all future visits" action would
/// touch, counted from [from] inclusive. Pure, so the dialog's consequence line
/// is testable without a repository.
({int count, DateTime? last}) seriesOutlook(
  List<AppointmentRecord> series,
  DateTime from,
) {
  var count = 0;
  DateTime? last;
  for (final occurrence in series) {
    if (occurrence.startTime.isBefore(from)) continue;
    count++;
    // Scan for the max rather than trusting the order — callers hand us
    // whatever the repository returned.
    if (last == null || occurrence.startTime.isAfter(last)) {
      last = occurrence.startTime;
    }
  }
  return (count: count, last: last);
}
