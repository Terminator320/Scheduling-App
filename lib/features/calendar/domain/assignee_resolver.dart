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
