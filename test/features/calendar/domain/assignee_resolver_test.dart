import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/assignee_resolver.dart';

void main() {
  // I12: `assigneeNameAt` owns the positional bounds check at six call sites,
  // and the edit sheet's result flows into `mergeRetainedAssignees` and is
  // WRITTEN BACK to Firestore — yet it had no direct coverage, only whatever
  // its callers happened to exercise.
  group('assigneeNameAt', () {
    test('returns the name at the paired position', () {
      expect(assigneeNameAt(const ['Ada', 'Bea'], 0), 'Ada');
      expect(assigneeNameAt(const ['Ada', 'Bea'], 1), 'Bea');
    });

    test('returns null past the end — a shorter names list', () {
      // The real shape: a job assigned before names were denormalized, or a
      // partially-written doc. Null means "no name here", and each caller
      // picks its own substitute.
      expect(assigneeNameAt(const ['Ada'], 1), isNull);
      expect(assigneeNameAt(const [], 0), isNull);
    });

    test('returns null for a negative index rather than throwing', () {
      expect(assigneeNameAt(const ['Ada'], -1), isNull);
    });

    test('an empty stored name is a NAME, not a gap', () {
      // Distinct from null on purpose: the caller substitutes only when there
      // is no entry at all, never when the entry is blank.
      expect(assigneeNameAt(const [''], 0), '');
    });
  });

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
