import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// Schema version; bump only alongside Swift `ScheduleSnapshot` decoder.
const scheduleSnapshotVersion = 1;

/// Days carried beyond today; Phase-2 date queries ("what's my schedule
/// Friday?") resolve against these buckets, and anything further out gets
/// "I only have your schedule for the next 7 days."
const scheduleSnapshotLookaheadDays = 7;

/// Defensive per-day cap — Siri reads at most one day out loud.
const scheduleSnapshotPerDayCap = 30;

/// Only fields the Siri intents speak (plus `id` for Phase-4 actions); excludes notes/phone/pictures since App Group is readable while locked.
Map<String, dynamic> _appointment(AppointmentRecord a) => {
  'id': a.id,
  'startMillis': a.startTime.millisecondsSinceEpoch,
  'endMillis': a.endTime.millisecondsSinceEpoch,
  'clientName': a.clientName,
  'address': a.address,
  'status': AppointmentStatus.storedRaw(a.status),
};

String _dayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Serializes the schedule the Siri App Intents extension answers from (pure,
/// unit-testable), carrying one bucket per day and excluding cancelled
/// visits and id-less records (Phase-4 write actions resolve by id).
Map<String, dynamic> buildScheduleSnapshot({
  required List<AppointmentRecord> appointments,
  required String role,
  required DateTime now,
}) {
  final startOfToday = now.dateOnly;
  final buckets = <String, List<AppointmentRecord>>{
    for (var i = 0; i <= scheduleSnapshotLookaheadDays; i++)
      _dayKey(
        DateTime(startOfToday.year, startOfToday.month, startOfToday.day + i),
      ): <AppointmentRecord>[],
  };

  for (final a in appointments) {
    if (a.id == null || a.id!.isEmpty) continue;
    if (AppointmentStatus.fromRaw(a.status).isCancelled) continue;
    buckets[_dayKey(a.startTime)]?.add(a);
  }

  return {
    'version': scheduleSnapshotVersion,
    'generatedAt': now.millisecondsSinceEpoch,
    'role': role,
    'days': [
      for (final entry in buckets.entries)
        {
          'date': entry.key,
          'appointments': [
            for (final a
                in (entry.value
                      ..sort((x, y) => x.startTime.compareTo(y.startTime)))
                    .take(
                      scheduleSnapshotPerDayCap,
                    ))
              _appointment(a),
          ],
        },
    ],
  };
}
