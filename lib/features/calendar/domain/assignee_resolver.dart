/// Merge picker selection with unseen original assignees to prevent silent unassignment.
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
