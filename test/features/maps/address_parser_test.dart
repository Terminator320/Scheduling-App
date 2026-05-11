import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/maps/domain/address_parser.dart';

void main() {
  group('AddressParser.splitApt', () {
    test('returns null for empty / whitespace input', () {
      expect(AddressParser.splitApt(''), isNull);
      expect(AddressParser.splitApt('   '), isNull);
    });

    test('returns null when no apt indicator is present', () {
      expect(AddressParser.splitApt('1245 Rue de Bleury, Montréal, QC'), isNull);
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
      final r = AddressParser.splitApt('1245 Rue de Bleury #3406, Montréal, QC');
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

    test('inserts apt before the first comma when street has trailing parts', () {
      expect(
        AddressParser.combineAptAndStreet(
          '1245 Rue de Bleury, Montréal, QC H3B 0A8',
          '12',
        ),
        '12-1245 Rue de Bleury, Montréal, QC H3B 0A8',
      );
    });

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
