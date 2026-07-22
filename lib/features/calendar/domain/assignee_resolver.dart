/// Merges an appointment edit's picker selection with the original assignees
/// the active picker never showed, so a save can't silently unassign — and
/// thereby change who can see — a visit.
///
/// The employee picker only lists ACTIVE staff, so an original assignee that is
/// neither active nor currently selected was invisible to the editor and could
/// not have been deselected on purpose; it must be re-appended verbatim. An
/// active assignee that the user actually deselected is correctly dropped (it's
/// in [activeIds], so it isn't retained). [originalNames] is index-aligned with
/// [originalIds]; a missing name falls back to empty. Load-bearing invariant —
/// appointment visibility keys on `employeeIds` (see CLAUDE.md).
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
      retainedNames.add(i < originalNames.length ? originalNames[i] : '');
    }
  }
  return (
    ids: [...selectedIds, ...retainedIds],
    names: [...selectedNames, ...retainedNames],
  );
}
