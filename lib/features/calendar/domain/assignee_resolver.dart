import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// Returns active staff the picker may offer, including active stored assignees.
List<EmployeeRecord> offerableAssignees({
  required List<EmployeeRecord> active,
  required Iterable<String> alreadyAssignedIds,
}) {
  final assignedIds = alreadyAssignedIds.toSet();
  return [
    for (final e in active)
      if (e.isAssignable || assignedIds.contains(e.id)) e,
  ];
}

/// Returns the denormalized assignee name at [index], if present.
String? assigneeNameAt(List<String> employeeNames, int index) =>
    index >= 0 && index < employeeNames.length ? employeeNames[index] : null;

/// Merges the picker's selection with any original assignees the picker
/// couldn't show, so they don't get silently unassigned.
({List<String> ids, List<String> names}) mergeRetainedAssignees({
  required List<String> originalIds,
  required List<String> originalNames,
  required List<String> selectedIds,
  required List<String> selectedNames,
  required Set<String> activeIds,
}) {
  final retainedIds = <String>[];
  final retainedNames = <String>[];
  for (var i = 0; i < originalIds.length; i++) {
    final origId = originalIds[i];
    if (!activeIds.contains(origId) && !selectedIds.contains(origId)) {
      retainedIds.add(origId);
      retainedNames.add(assigneeNameAt(originalNames, i) ?? '');
    }
  }
  return (
    ids: [...selectedIds, ...retainedIds],
    names: [...selectedNames, ...retainedNames],
  );
}

/// How the picker must treat one offered assignee on the chosen date.
enum AssigneeOfferState {
  /// No clash — an ordinary tappable chip.
  free,

  /// A clash, and they are not on the job: dimmed, not tappable.
  unavailable,

  /// A clash, but already assigned and still tappable.
  onTheJob,
}

/// Returns whether [employeeId] is free, unavailable, or already on this job.
AssigneeOfferState assigneeOfferState({
  required String employeeId,
  required Set<String> clashingIds,
  required Set<String> selectedIds,
  required Set<String> alreadyAssignedIds,
}) {
  if (!clashingIds.contains(employeeId)) return AssigneeOfferState.free;
  return selectedIds.contains(employeeId) ||
          alreadyAssignedIds.contains(employeeId)
      ? AssigneeOfferState.onTheJob
      : AssigneeOfferState.unavailable;
}

/// Short display name, disambiguated by last initial when first names repeat.
String shortAssigneeName(String name, {required Map<String, int> among}) {
  final parts = name.trim().split(_nameGap);
  final first = parts.first;
  if (parts.length < 2 || first.isEmpty) return name.trim();
  final sharers = among[first.toLowerCase()] ?? 0;
  return sharers > 1 ? '$first ${parts.last[0]}.' : first;
}

/// Tallies lowercased first names for [shortAssigneeName].
Map<String, int> firstNameTally(Iterable<String> names) {
  final tally = <String, int>{};
  for (final name in names) {
    final first = name.trim().split(_nameGap).first.toLowerCase();
    if (first.isEmpty) continue;
    tally[first] = (tally[first] ?? 0) + 1;
  }
  return tally;
}

/// Shared whitespace splitter for assignee-name helpers.
final _nameGap = RegExp(r'\s+');
