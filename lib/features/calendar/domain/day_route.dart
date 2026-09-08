import 'package:scheduling/features/calendar/domain/appointment_day_slice.dart';
import 'package:scheduling/features/calendar/domain/appointment_status_values.dart';
import 'package:scheduling/features/calendar/domain/assignee_resolver.dart';
import 'package:scheduling/features/calendar/domain/models/appointment_record.dart';

/// The render-ready slice of one day: who is on it, which assignee is showing,
/// that assignee's jobs in driving order, and the addresses to navigate.
class DayRoute {
  const DayRoute({
    required this.assigneeEntries,
    required this.employeeId,
    required this.jobs,
    required this.stops,
  });

  /// Distinct assignees for the day, `id -> display name`, sorted by name.
  /// Empty for a technician, who never sees the picker.
  final List<MapEntry<String, String>> assigneeEntries;

  /// The assignee the day is rendered for, after re-validating the selection
  /// against who actually has work today.
  final String employeeId;

  final List<AppointmentDaySlice> jobs;

  /// Addresses for the navigation hand-off — open jobs with an address, in the
  /// same order as [jobs].
  final List<String> stops;
}

/// Derives [DayRoute] from the day's appointments.
///
/// Pure, and extracted from `DayRouteScreen` for that reason: this is 70-odd
/// lines of rules — the cancelled filter, the day re-scoping, the positional
/// `employeeNames` pairing, the admin assignee filter and the open-with-address
/// stop rule — that were reachable only through a widget test. Two of them
/// (`runsOn` via [sliceFor], and [assigneeNameAt]) are documented invariants
/// with owners elsewhere, so they deserve to be assertable without pumping a
/// screen.
///
/// The identity memo stays in the `State`: it keys on `widget`/`State` fields
/// this function does not have, and caching here would make a pure function
/// stateful for one caller's benefit.
///
/// [selectedEmployeeId] is the admin's current pick; it is returned unchanged
/// when it still has work, and replaced by the first assignee when it does not,
/// so the picker can never show a person with an empty day. For a technician
/// ([isAdmin] false) [ownEmployeeId] is returned and no filtering by pick
/// happens — the employee-visibility rule has already narrowed the stream.
DayRoute buildDayRoute({
  required List<AppointmentRecord> source,
  required Map<String, String> nameMap,
  required DateTime day,
  required bool isAdmin,
  required String ownEmployeeId,
  required String selectedEmployeeId,
}) {
  // Re-scope the range stream to this day.
  final daySlices =
      source
          .where((a) => !isCancelledStatusRaw(a.status))
          .map((a) => sliceFor(a, day))
          .nonNulls
          .toList()
        // Sort defensively to keep numbering and the route in driving order.
        ..sort((a, b) => a.windowStart.compareTo(b.windowStart));

  // Include removed employees by falling back to denormalized names.
  final assigneeEntries = isAdmin
      ? _assigneesWithJobs(daySlices, nameMap)
      : const <MapEntry<String, String>>[];

  final employeeId = _resolveEmployeeId(
    assigneeIds: [for (final e in assigneeEntries) e.key],
    isAdmin: isAdmin,
    ownEmployeeId: ownEmployeeId,
    selectedEmployeeId: selectedEmployeeId,
  );

  // Admins filter the day list to the picked assignee.
  final jobs = isAdmin
      ? daySlices
            .where((s) => s.appointment.employeeIds.contains(employeeId))
            .toList()
      : daySlices;
  final stops = jobs
      .where(
        (s) =>
            !isTerminalStatusRaw(s.appointment.status) &&
            s.appointment.address.trim().isNotEmpty,
      )
      .map((s) => s.appointment.address)
      .toList();

  return DayRoute(
    assigneeEntries: assigneeEntries,
    employeeId: employeeId,
    jobs: jobs,
    stops: stops,
  );
}

/// Distinct assignees for the selected day, by display name.
///
/// The name falls back through the live roster, then the appointment's own
/// denormalized `employeeNames`, then the raw id — which is how someone removed
/// from the roster still appears on a day they worked. The positional pairing
/// goes through [assigneeNameAt], the one owner of that bounds check.
List<MapEntry<String, String>> _assigneesWithJobs(
  List<AppointmentDaySlice> daySlices,
  Map<String, String> nameMap,
) {
  final byId = <String, String>{};
  for (final slice in daySlices) {
    final a = slice.appointment;
    for (var i = 0; i < a.employeeIds.length; i++) {
      final id = a.employeeIds[i];
      if (id.isEmpty) continue;
      byId.putIfAbsent(
        id,
        () => nameMap[id] ?? assigneeNameAt(a.employeeNames, i) ?? id,
      );
    }
  }
  return byId.entries.toList()
    ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
}

/// Keeps an admin's selection valid for the current day.
String _resolveEmployeeId({
  required List<String> assigneeIds,
  required bool isAdmin,
  required String ownEmployeeId,
  required String selectedEmployeeId,
}) {
  if (!isAdmin) return ownEmployeeId;
  if (assigneeIds.isEmpty) return selectedEmployeeId;
  return assigneeIds.contains(selectedEmployeeId)
      ? selectedEmployeeId
      : assigneeIds.first;
}
