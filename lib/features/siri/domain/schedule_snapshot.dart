import 'package:scheduling/core/utils/date_utils_helper.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';
import 'package:scheduling/shared/widgets/feedback/status_chip.dart';

/// Schema version of the snapshot payload. The Swift App Intents extension
/// rejects anything it doesn't know rather than mis-decoding it, so bump this
/// only alongside the Swift `ScheduleSnapshot` decoder.
const scheduleSnapshotVersion = 1;

/// Days carried beyond today. Phase-2 date queries ("what's my schedule
/// Friday?") resolve against these buckets; anything further out is answered
/// "I only have your schedule for the next 7 days."
const scheduleSnapshotLookaheadDays = 7;

/// Defensive per-day cap — Siri reads at most one day out loud.
const scheduleSnapshotPerDayCap = 30;

/// Only the fields the Siri intents actually speak (plus `id`, which Phase-4
/// write actions resolve their target by). Notes, phone, pictures and materials
/// are deliberately left out: the App Group container stays readable while the
/// device is locked, so every field here is at-rest PII at a weaker protection
/// class than the rest of the app's data.
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

/// Serializes the schedule the Siri App Intents extension answers from into the
/// JSON written to the App Group. Pure — unit-testable.
///
/// Carries one bucket per day from today through
/// [scheduleSnapshotLookaheadDays] out, using **device-local** day boundaries
/// (matching the widget payload builder). Cancelled visits are excluded, and
/// records without a Firestore doc id are dropped — Phase-4 write actions
/// resolve their target by `id`, so an id-less entry is unactionable.
///
/// [role] is carried through so the extension can word its answers ("your
/// schedule" vs. the whole business's) without re-deriving the caller's role.
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
