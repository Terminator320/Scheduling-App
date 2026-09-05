import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/calendar/domain/policies/previous_address_policy.dart';

void main() {
  group('groupPreviousAddresses', () {
    test('two or more units on one street group under it', () {
      final grouped = groupPreviousAddresses(const [
        '1751 rue Richardson unit 404',
        '1751 rue Richardson unit 210',
        '1751 rue Richardson unit 118',
      ]);
      expect(grouped.sharedStreet, '1751 rue Richardson');
      expect(grouped.rows.map((r) => r.unit).toList(), ['404', '210', '118']);
    });

    test('order is preserved, newest first as given', () {
      final grouped = groupPreviousAddresses(const [
        '1751 rue Richardson unit 404',
        '1751 rue Richardson unit 210',
      ]);
      expect(grouped.rows.first.unit, '404');
    });

    test('different streets do not group', () {
      final grouped = groupPreviousAddresses(const [
        '1250 boul. LaSalle',
        "88 rue de l'Église",
      ]);
      expect(grouped.sharedStreet, isNull);
      expect(grouped.rows.map((r) => r.full).toList(), [
        '1250 boul. LaSalle',
        "88 rue de l'Église",
      ]);
    });

    // The mis-grouping guard: one street shared but one address has no unit,
    // so a reader could not tell the rows apart in a unit column.
    test('a street shared by an address with no unit does not group', () {
      final grouped = groupPreviousAddresses(const [
        '1751 rue Richardson unit 404',
        '1751 rue Richardson',
      ]);
      expect(grouped.sharedStreet, isNull);
    });

    test('a single address never groups', () {
      final grouped = groupPreviousAddresses(const ['1751 rue Richardson unit 404']);
      expect(grouped.sharedStreet, isNull);
      expect(grouped.rows.single.full, '1751 rue Richardson unit 404');
    });

    test('two units on one street plus an unrelated address does not group', () {
      final grouped = groupPreviousAddresses(const [
        '1751 rue Richardson unit 404',
        '1751 rue Richardson unit 210',
        '1250 boul. LaSalle',
      ]);
      expect(grouped.sharedStreet, isNull);
    });

    test('duplicate units collapse to one row', () {
      final grouped = groupPreviousAddresses(const [
        '1751 rue Richardson unit 404',
        '1751 rue Richardson unit 404',
        '1751 rue Richardson unit 210',
      ]);
      expect(grouped.rows, hasLength(2));
    });

    test('blank entries are dropped', () {
      final grouped = groupPreviousAddresses(const ['', '   ', '1250 boul. LaSalle']);
      expect(grouped.rows, hasLength(1));
    });

    test('an empty list yields no rows and no street', () {
      final grouped = groupPreviousAddresses(const []);
      expect(grouped.rows, isEmpty);
      expect(grouped.sharedStreet, isNull);
    });
  });
}
