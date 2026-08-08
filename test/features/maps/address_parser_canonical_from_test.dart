// Pins AddressParser.canonicalFrom — the street+apt precedence rule CLAUDE.md
// names as having exactly ONE owner.
//
// Every other member of that file was already tested (splitApt,
// combineAptAndStreet, formatForDisplay, canonicalToDisplay, toCanonical, plus
// a round-trip group); the one an invariant is written about was not. The rule
// has two answers for the same typed input depending on which field the apt
// came from, which is exactly the kind of thing a re-inlined copy gets wrong.

import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/maps/domain/address_parser.dart';

void main() {
  group('AddressParser.canonicalFrom', () {
    test('an explicit apt beats one embedded in the street text', () {
      // The rule in one line: the field the user just typed wins.
      expect(
        AddressParser.canonicalFrom(street: '12-1245 Rue Sherbrooke', apt: '9'),
        '9-1245 Rue Sherbrooke',
      );
    });

    test('a blank apt keeps the one embedded in the street', () {
      // Not "clears it" — clearing here would silently drop an apt number the
      // user never touched.
      expect(
        AddressParser.canonicalFrom(street: '12-1245 Rue Sherbrooke', apt: ''),
        '12-1245 Rue Sherbrooke',
      );
    });

    test('a whitespace-only apt counts as blank', () {
      expect(
        AddressParser.canonicalFrom(
          street: '12-1245 Rue Sherbrooke',
          apt: '   ',
        ),
        '12-1245 Rue Sherbrooke',
      );
    });

    test('an explicit apt is attached to a street that carries none', () {
      expect(
        AddressParser.canonicalFrom(street: '1245 Rue Sherbrooke', apt: '4B'),
        '4B-1245 Rue Sherbrooke',
      );
    });

    test('the apt lands on the first line of a multi-part address', () {
      expect(
        AddressParser.canonicalFrom(
          street: '1245 Rue Sherbrooke, Montréal, QC',
          apt: '4B',
        ),
        '4B-1245 Rue Sherbrooke, Montréal, QC',
      );
    });

    test('a leading # on the apt is dropped', () {
      expect(
        AddressParser.canonicalFrom(street: '1245 Rue Sherbrooke', apt: '#7'),
        '7-1245 Rue Sherbrooke',
      );
    });

    test('an empty street yields an empty address, apt or not', () {
      // An apt with nowhere to live must not be stored on its own.
      expect(AddressParser.canonicalFrom(street: '', apt: '4B'), '');
      expect(AddressParser.canonicalFrom(street: '   ', apt: ''), '');
    });

    test('the result round-trips back through splitApt', () {
      final stored = AddressParser.canonicalFrom(
        street: '1245 Rue Sherbrooke, Montréal',
        apt: '4B',
      );
      final parts = AddressParser.splitApt(stored);
      expect(parts?.apt, '4B');
      expect(parts?.street, '1245 Rue Sherbrooke, Montréal');
    });
  });
}
