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

/// How the picker must treat one offered assignee on the chosen date.
enum AssigneeOfferState {
  /// No clash — an ordinary tappable chip.
  free,

  /// A clash, and they are not on the job: dimmed, not tappable.
  unavailable,

  /// A clash, but they are already on the job — tappable, with a line saying
  /// so. Never dimmed.
  onTheJob,
}

/// Whether [employeeId] may be dimmed as unavailable.
///
/// Lives beside [mergeRetainedAssignees] and [offerableAssignees] because all
/// three answer the same question and must agree. The already-assigned test
/// WINS over the unavailable one, for the reason the merge exists: a chip that
/// can't be tapped can't be taken off, and an assignee who is active but merely
/// un-offered is NOT retained by [mergeRetainedAssignees] — they'd be silently
/// unassigned instead.
///
/// [alreadyAssignedIds] is the appointment's STORED assignees, and it is
/// checked ALONGSIDE the live selection rather than instead of it: keyed on the
/// selection alone, deselecting an unavailable stored assignee dims their chip
/// on the next rebuild and the toggle becomes one-way.
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

/// The name a chip and its availability line both show.
///
/// First name alone, unless another offered assignee shares it — then a last
/// initial, in BOTH places, so a chip and the line explaining it are obviously
/// one person. Two Marcs are exactly the case where a bare first name makes the
/// explanation useless.
String shortAssigneeName(String name, {required Iterable<String> among}) {
  final parts = name.trim().split(_nameGap);
  final first = parts.first;
  if (parts.length < 2 || first.isEmpty) return name.trim();
  var sharers = 0;
  for (final other in among) {
    final otherFirst = other.trim().split(_nameGap).first;
    if (otherFirst.toLowerCase() == first.toLowerCase()) sharers++;
  }
  return sharers > 1 ? '$first ${parts.last[0]}.' : first;
}

/// Hoisted: the picker resolves a short name per chip against every other
/// chip, so a per-call `RegExp` compiled quadratically on every rebuild.
final _nameGap = RegExp(r'\s+');
