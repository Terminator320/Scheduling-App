import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';

void main() {
  group('AddressParser.splitApt', () {
    test('returns null for empty / whitespace input', () {
      expect(AddressParser.splitApt(''), isNull);
      expect(AddressParser.splitApt('   '), isNull);
    });

    test('returns null when no apt indicator is present', () {
      expect(
        AddressParser.splitApt('1245 Rue de Bleury, Montréal, QC'),
        isNull,
      );
    });

    test('parses canonical "Apt 12 - 1245 Main" form', () {
      final r = AddressParser.splitApt('Apt 12 - 1245 Main St');
      expect(r?.apt, '12');
      expect(r?.street, '1245 Main St');
    });

    test('parses labeled prefix forms', () {
      for (final raw in [
        'apt 4B, 1245 Main St',
        'unit 4B - 1245 Main St',
        '#4B - 1245 Main St',
      ]) {
        final r = AddressParser.splitApt(raw);
        expect(r, isNotNull, reason: raw);
        expect(r!.apt, '4B', reason: raw);
        expect(r.street, '1245 Main St', reason: raw);
      }
    });

    test('parses bare-dash form', () {
      final r = AddressParser.splitApt('12 - 1245 Main St');
      expect(r?.apt, '12');
      expect(r?.street, '1245 Main St');
    });

    test('parses trailing-unit form', () {
      final r = AddressParser.splitApt(
        '1245 Rue de Bleury #3406, Montréal, QC',
      );
      expect(r?.apt, '3406');
      expect(r?.street, '1245 Rue de Bleury, Montréal, QC');
    });
  });

  group('AddressParser.combineAptAndStreet', () {
    test('returns street unchanged when apt is empty', () {
      expect(AddressParser.combineAptAndStreet('1245 Main', ''), '1245 Main');
    });

    test('returns empty when both inputs are empty', () {
      expect(AddressParser.combineAptAndStreet('', ''), '');
    });

    test('prepends apt to single-line street', () {
      expect(
        AddressParser.combineAptAndStreet('1245 Main', '12'),
        '12-1245 Main',
      );
    });

    test(
      'inserts apt before the first comma when street has trailing parts',
      () {
        expect(
          AddressParser.combineAptAndStreet(
            '1245 Rue de Bleury, Montréal, QC H3B 0A8',
            '12',
          ),
          '12-1245 Rue de Bleury, Montréal, QC H3B 0A8',
        );
      },
    );

    test('strips an embedded unit token from the street first', () {
      expect(
        AddressParser.combineAptAndStreet('1245 Main #99, Montréal', '12'),
        '12-1245 Main, Montréal',
      );
    });

    test('strips leading # from apt', () {
      expect(
        AddressParser.combineAptAndStreet('1245 Main', '#12'),
        '12-1245 Main',
      );
    });
  });

  group('AddressParser.formatForDisplay', () {
    test('returns street unchanged when apt is empty', () {
      expect(AddressParser.formatForDisplay('1234 Main', ''), '1234 Main');
    });

    test('returns empty when both inputs are empty', () {
      expect(AddressParser.formatForDisplay('', ''), '');
    });

    test('appends #apt to single-line street', () {
      expect(AddressParser.formatForDisplay('1234 Main', '5'), '1234 Main #5');
    });

    test(
      'inserts #apt before the first comma when street has trailing parts',
      () {
        expect(
          AddressParser.formatForDisplay(
            '1234 Rue Saint-Denis, Montréal, QC H2X 3J5',
            '5',
          ),
          '1234 Rue Saint-Denis #5, Montréal, QC H2X 3J5',
        );
      },
    );

    test('strips an embedded unit token from the street first', () {
      expect(
        AddressParser.formatForDisplay('1234 Main #99, Montréal', '5'),
        '1234 Main #5, Montréal',
      );
    });

    test('strips leading # from apt', () {
      expect(AddressParser.formatForDisplay('1234 Main', '#5'), '1234 Main #5');
    });
  });

  group('AddressParser.canonicalToDisplay', () {
    test('returns stored value unchanged when no apt prefix is present', () {
      expect(
        AddressParser.canonicalToDisplay('1234 Main, Montréal, QC'),
        '1234 Main, Montréal, QC',
      );
    });

    test('converts canonical apt-prefix to display form', () {
      expect(
        AddressParser.canonicalToDisplay(
          '5-1234 Rue Saint-Denis, Montréal, QC',
        ),
        '1234 Rue Saint-Denis #5, Montréal, QC',
      );
    });

    test('converts single-line canonical form to display form', () {
      expect(AddressParser.canonicalToDisplay('12-1245 Main'), '1245 Main #12');
    });
  });

  group('AddressParser.toCanonical', () {
    test('returns trimmed input unchanged when no apt is present', () {
      expect(
        AddressParser.toCanonical('  1234 Main, Montréal, QC  '),
        '1234 Main, Montréal, QC',
      );
    });

    test('canonicalizes a display-form address', () {
      expect(
        AddressParser.toCanonical('1234 Rue Saint-Denis #5, Montréal, QC'),
        '5-1234 Rue Saint-Denis, Montréal, QC',
      );
    });

    test('is idempotent on canonical input', () {
      const stored = '5-1234 Rue Saint-Denis, Montréal, QC';
      expect(AddressParser.toCanonical(stored), stored);
    });
  });

  group('AddressParser canonical ↔ display round-trip', () {
    // Round-trip must be lossless, or editing an existing record silently
    // rewrites the stored string.
    test('canonical → display → canonical is lossless', () {
      for (final stored in const [
        '5-1234 Main',
        '12-1245 Rue de Bleury, Montréal, QC H3B 0A8',
        '4B-1245 Main St, Montréal',
      ]) {
        final display = AddressParser.canonicalToDisplay(stored);
        final parts = AddressParser.splitApt(display);
        expect(parts, isNotNull, reason: stored);
        expect(
          AddressParser.combineAptAndStreet(parts!.street, parts.apt),
          stored,
          reason: stored,
        );
      }
    });
  });

  group('map-launcher apt stripping (AddressParser.splitApt contract)', () {
    test(
      'display and canonical forms of the same address strip to identical nav street',
      () {
        const canonical = '5-1234 Rue Saint-Denis, Montréal, QC H2X 3J5';
        const display = '1234 Rue Saint-Denis #5, Montréal, QC H2X 3J5';
        final navFromCanonical =
            AddressParser.splitApt(canonical)?.street ?? canonical;
        final navFromDisplay =
            AddressParser.splitApt(display)?.street ?? display;
        expect(navFromCanonical, navFromDisplay);
      },
    );

    test('plain street with no apt passes through splitApt unchanged', () {
      const plain = '1234 Rue Saint-Denis, Montréal, QC H2X 3J5';
      final nav = AddressParser.splitApt(plain)?.street ?? plain;
      expect(nav, plain);
    });
  });

  group('AddressParser coordinate-fallback pass-through', () {
    // A GPS-derived "lat,lng" string (reverse-geocoding fallback) must pass
    // through every canonicalization helper unchanged.
    const coordinate = '45.5017,-73.5673';

    test('splitApt does not treat it as an apt-prefixed address', () {
      expect(AddressParser.splitApt(coordinate), isNull);
    });

    test('toCanonical returns it unchanged', () {
      expect(AddressParser.toCanonical(coordinate), coordinate);
    });

    test('canonicalToDisplay returns it unchanged', () {
      expect(AddressParser.canonicalToDisplay(coordinate), coordinate);
    });
  });

  group('AddressParser.parse', () {
    test('extracts postal code, province, country, city from full address', () {
      final f = AddressParser.parse(
        '1245 Rue de Bleury, Montréal, QC H3B 0A8, Canada',
      );
      expect(f.postalCode, 'H3B 0A8');
      expect(f.province, 'QC');
      expect(f.country, 'Canada');
      expect(f.city, 'Montréal');
    });

    test('infers Canada when last part contains the postal code', () {
      final f = AddressParser.parse('1245 Rue de Bleury, Montréal, QC H3B 0A8');
      expect(f.country, 'Canada');
      expect(f.postalCode, 'H3B 0A8');
    });

    test('returns nullable fields when address is empty', () {
      final f = AddressParser.parse('');
      expect(f.apt, isNull);
      expect(f.street, isNull);
      expect(f.city, isNull);
      expect(f.province, isNull);
      expect(f.country, isNull);
      expect(f.postalCode, isNull);
    });

    test('skips numeric "city" candidates (street numbers)', () {
      // When there are only two parts and the second contains a digit, the
      // parser should not pick it as a city.
      final f = AddressParser.parse('1245 Main St, H3B 0A8');
      expect(f.city, isNull);
    });
  });
}
