import 'package:scheduling/features/employees/domain/models/employee_record.dart';

/// The staff an assignee picker may OFFER: active crew, plus anyone active
/// already on the job whose title is no longer offerable (a dispatcher assigned
/// before that rule existed, so they can still be taken off).
///
/// Lives beside [mergeRetainedAssignees] because the two must agree, and the
/// dangerous case is the one this deliberately does NOT include. [active] is
/// the active-only stream, so a DISABLED assignee is absent from it and stays
/// unoffered — offering one renders a chip whose deselection looks like it
/// works and is then silently undone, since `mergeRetainedAssignees` re-appends
/// every original missing from the active set. Narrowing the active list is
/// what keeps that true; unioning the selection onto a pre-filtered list does
/// not.
///
/// [alreadyAssignedIds] is the appointment's STORED `employeeIds`, never the
/// live selection: keyed on the selection, deselecting a dispatcher removed
/// them from it, so their chip vanished on the next rebuild and the toggle was
/// one-way — an accidental tap could only be undone by abandoning the edit.
///
/// There is no personal-block carve-out (owner call, 2026-08-24): a dispatcher
/// is not offered on a personal block either, day off included. The exclusion
/// is about the person, not the kind of entry.
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

/// The denormalized name stored at position [index], or null when there isn't
/// one.
///
/// `employeeIds` and `employeeNames` are paired POSITIONALLY and the names list
/// can be shorter — a job assigned before names were denormalized, or a
/// partially-written doc. That bounds check was re-spelled at five call sites
/// with four different missing-name fallbacks; the fallbacks are legitimately
/// per-surface (the day route shows the id, the history filter shows nothing),
/// so this owns only the LOOKUP and returns null for "no name here", leaving
/// each caller to pick its own substitute.
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
