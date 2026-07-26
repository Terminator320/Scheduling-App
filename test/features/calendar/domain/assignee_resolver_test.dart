import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/assignee_resolver.dart';

void main() {
  group('mergeRetainedAssignees', () {
    test('keeps only the selection when every original is active', () {
      final result = mergeRetainedAssignees(
        originalIds: ['a', 'b'],
        originalNames: ['Ann', 'Bob'],
        selectedIds: ['a'],
        selectedNames: ['Ann'],
        activeIds: {'a', 'b'},
      );
      // 'b' was active and deselected — honored, not retained.
      expect(result.ids, ['a']);
      expect(result.names, ['Ann']);
    });

    test('re-appends an original assignee the picker never showed', () {
      // 'c' is disabled/removed (not active), so the picker couldn't show it —
      // dropping it would silently unassign and change visibility.
      final result = mergeRetainedAssignees(
        originalIds: ['a', 'c'],
        originalNames: ['Ann', 'Cid'],
        selectedIds: ['a'],
        selectedNames: ['Ann'],
        activeIds: {'a', 'b'},
      );
      expect(result.ids, ['a', 'c']);
      expect(result.names, ['Ann', 'Cid']);
    });

    test('does not re-append an original that is still selected', () {
      final result = mergeRetainedAssignees(
        originalIds: ['a'],
        originalNames: ['Ann'],
        selectedIds: ['a'],
        selectedNames: ['Ann'],
        activeIds: <String>{},
      );
      // 'a' is inactive but still selected — kept once, not duplicated.
      expect(result.ids, ['a']);
      expect(result.names, ['Ann']);
    });

    test('falls back to an empty name when originals are shorter', () {
      final result = mergeRetainedAssignees(
        originalIds: ['a', 'c'],
        originalNames: ['Ann'], // no name for 'c'
        selectedIds: <String>[],
        selectedNames: <String>[],
        activeIds: {'a'},
      );
      expect(result.ids, ['c']);
      expect(result.names, ['']);
    });

    test('newly selected active staff plus a retained inactive original', () {
      final result = mergeRetainedAssignees(
        originalIds: ['old'],
        originalNames: ['Olga'],
        selectedIds: ['new1', 'new2'],
        selectedNames: ['N1', 'N2'],
        activeIds: {'new1', 'new2'},
      );
      // The selection comes first, then the invisible original 'old' gets
      // appended after it.
      expect(result.ids, ['new1', 'new2', 'old']);
      expect(result.names, ['N1', 'N2', 'Olga']);
    });
  });
}
