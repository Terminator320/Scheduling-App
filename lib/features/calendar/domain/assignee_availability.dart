import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/appointment_status_values.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// What the assignee picker needs to explain who can't take the job.
///
/// [whenLabel] arrives already localized — the nobody-free sentence names the
/// span, and the span is resolved by the host that keys the availability read.
class AssigneeAvailability {
  const AssigneeAvailability({
    this.clashes = const {},
    this.alreadyAssignedIds = const {},
    this.whenLabel = '',
  });

  /// No date picked yet, or the lookup hasn't settled: nothing is dimmed.
  static const none = AssigneeAvailability();

  /// The one record standing in each assignee's way, keyed by employee doc id
  /// — see [clashesByAssignee]. `isTimeOff` is what splits the sentence and
  /// the figure the picker shows: time off says "away" and has no clock, so it
  /// renders a date range where a booked job renders its window.
  final Map<String, AppointmentRecord> clashes;

  /// The appointment's STORED assignees, never the live selection. Deselecting
  /// an unavailable stored assignee must not dim their chip, or the toggle is
  /// one-way — the same trap `offerableAssignees` documents.
  final Set<String> alreadyAssignedIds;

  final String whenLabel;
}

/// The appointments in [appointments] that stand in the way of a job running
/// [start]–[end].
///
/// The ONE owner of "is this a clash", shared by the picker's live reduction
/// and the repository's one-shot read so the two surfaces can never answer the
/// same question differently.
///
/// - [excludeAppointmentId] drops the record being edited, or its own
///   assignees read as clashing with themselves.
/// - Terminal-status jobs are not a clash, matching `findBusyEmployees`.
/// - [clientJobsOnly] drops personal blocks. The time-off clash alert needs it:
///   a swap must never be offered on someone else's dentist appointment. The
///   picker leaves it off — booking time off is exactly how a person is made to
///   read as unavailable.
/// - [windowUnknownIds] names records whose stored times did not parse, and
///   they clash UNCONDITIONALLY. Fail toward reporting: a legacy or
///   console-written row with no usable times must not quietly disappear from
///   a booking check, because `AppointmentRecord` substitutes a placeholder
///   instant that would silently fail the overlap. Only the repository can
///   tell — it is the one reader that sees the raw map — so it passes the set
///   in rather than the rule guessing from a normalized record. Every other
///   test still applies to them.
List<AppointmentRecord> clashingAppointments({
  required Iterable<AppointmentRecord> appointments,
  required DateTime start,
  required DateTime end,
  String? excludeAppointmentId,
  bool clientJobsOnly = false,
  Set<String> windowUnknownIds = const {},
}) {
  return [
    for (final a in appointments)
      if (a.id != excludeAppointmentId &&
          !isTerminalStatusRaw(a.status) &&
          !(clientJobsOnly && a.isPersonal) &&
          (windowUnknownIds.contains(a.id) ||
              dailyWindowsOverlap(
                aStart: a.startTime,
                aEnd: a.endTime,
                bStart: start,
                bEnd: end,
              )))
        a,
  ];
}

/// One clash per assignee, restricted to [employeeIds].
///
/// Time off wins over a booked job when someone has both: "Marc is off" is the
/// truer sentence, and the picker only has room for one line per person.
/// Otherwise the earliest clash wins, so the figure names the first thing in
/// the way.
Map<String, AppointmentRecord> clashesByAssignee({
  required Iterable<AppointmentRecord> clashes,
  required Iterable<String> employeeIds,
}) {
  final wanted = employeeIds.toSet();
  final byAssignee = <String, AppointmentRecord>{};
  for (final appointment in clashes) {
    for (final id in appointment.employeeIds) {
      if (!wanted.contains(id)) continue;
      final existing = byAssignee[id];
      if (existing != null && !_supersedes(appointment, existing)) continue;
      byAssignee[id] = appointment;
    }
  }
  return byAssignee;
}

bool _supersedes(AppointmentRecord candidate, AppointmentRecord existing) {
  if (candidate.isTimeOff != existing.isTimeOff) return candidate.isTimeOff;
  return candidate.startTime.isBefore(existing.startTime);
}
