// Pins AddressParser.streetOnly / composeFull — the street-vs-locality split.
//
// `streetOnly` hand-mirrors `streetFromAddress` (functions/wave/mappers.js), so
// the worked examples here are deliberately the same ones that file's tests
// use: a divergence between the two spellings has to fail a test on one side.
//
// The pair exists because `clients/{id}.address` holds BOTH shapes — the Wave
// import writes a street line, the app wrote the full picked string — so every
// read has to reduce before it recomposes or a legacy doc renders its city
// twice.

import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/maps/domain/address_parser.dart';

void main() {
  group('AddressParser.streetOnly', () {
    test('strips the locality tail the structured fields already carry', () {
      expect(
        AddressParser.streetOnly(
          '1234 Rue Principale, Montréal, QC H2X 1Y4, Canada',
          city: 'Montréal',
          province: 'QC',
          postalCode: 'H2X 1Y4',
          country: 'Canada',
        ),
        '1234 Rue Principale',
      );
    });

    test('keeps a street whose own second segment is not a locality', () {
      // The reason this strips from the TAIL rather than splitting on the first
      // comma: "Building A" is part of the address, not the city.
      expect(
        AddressParser.streetOnly(
          '100 Main St, Building A, Montréal, QC H2X 1Y4, Canada',
          city: 'Montréal',
          province: 'QC',
          postalCode: 'H2X 1Y4',
          country: 'Canada',
        ),
        '100 Main St, Building A',
      );
    });

    test('is idempotent — an already-reduced street passes through', () {
      // This is what makes it safe to apply to a collection holding both
      // shapes, and what lets it run on every read without a backfill first.
      expect(
        AddressParser.streetOnly(
          '1234 Rue Principale',
          city: 'Montréal',
          province: 'QC',
          postalCode: 'H2X 1Y4',
          country: 'Canada',
        ),
        '1234 Rue Principale',
      );
    });

    test('keeps the apt prefix on the canonical stored form', () {
      expect(
        AddressParser.streetOnly(
          '4-1234 Rue Principale, Montréal, QC H2X 1Y4, Canada',
          city: 'Montréal',
          province: 'QC',
          postalCode: 'H2X 1Y4',
          country: 'Canada',
        ),
        '4-1234 Rue Principale',
      );
    });

    test('matches a province and postal code joined in one segment', () {
      expect(
        AddressParser.streetOnly(
          '55 Boulevard Saint-Laurent, Laval, QC H7N 1A1',
          city: 'Laval',
          province: 'QC',
          postalCode: 'H7N 1A1',
        ),
        '55 Boulevard Saint-Laurent',
      );
    });

    test('matches regardless of case and inner spacing', () {
      expect(
        AddressParser.streetOnly(
          '12 Rue Ontario,  MONTREAL , qc,  h2x   1y4',
          city: 'Montreal',
          province: 'QC',
          postalCode: 'H2X 1Y4',
        ),
        '12 Rue Ontario',
      );
    });

    test('with no locality fields it keeps the first segment', () {
      // A legacy doc that never had the structured fields: there is nothing to
      // identify a tail with, so fall back rather than guess. Mirrors the JS.
      expect(
        AddressParser.streetOnly('77 Rue Peel, Montréal, QC'),
        '77 Rue Peel',
      );
    });

    test('never strips the last remaining segment', () {
      // A street that IS the city name must not reduce to nothing.
      expect(
        AddressParser.streetOnly('Montréal', city: 'Montréal'),
        'Montréal',
      );
    });

    test('an empty address stays empty', () {
      expect(AddressParser.streetOnly('', city: 'Montréal'), '');
    });
  });

  group('AddressParser.composeFull', () {
    test('rejoins the parts around the street', () {
      expect(
        AddressParser.composeFull(
          '4-1234 Rue Principale',
          city: 'Montréal',
          province: 'QC',
          postalCode: 'H2X 1Y4',
          country: 'Canada',
        ),
        '1234 Rue Principale #4, Montréal, QC H2X 1Y4, Canada',
      );
    });

    test('a legacy full-string doc renders identically, not doubled', () {
      // The whole reason composeFull reduces before it rejoins. Same expected
      // string as the test above, from the other stored shape.
      expect(
        AddressParser.composeFull(
          '4-1234 Rue Principale, Montréal, QC H2X 1Y4, Canada',
          city: 'Montréal',
          province: 'QC',
          postalCode: 'H2X 1Y4',
          country: 'Canada',
        ),
        '1234 Rue Principale #4, Montréal, QC H2X 1Y4, Canada',
      );
    });

    test('omits parts that are missing', () {
      expect(
        AddressParser.composeFull('1234 Rue Principale', city: 'Montréal'),
        '1234 Rue Principale, Montréal',
      );
    });

    test('with no locality fields it is just the displayed street', () {
      expect(
        AddressParser.composeFull('4-1234 Rue Principale'),
        '1234 Rue Principale #4',
      );
    });

    test('an empty address with locality fields yields no leading comma', () {
      expect(
        AddressParser.composeFull('', city: 'Montréal', province: 'QC'),
        'Montréal, QC',
      );
    });

    test('everything empty stays empty', () {
      expect(AddressParser.composeFull(''), '');
    });

    test('composing an already-composed value is stable', () {
      // Guards the case a caller passes a value that has been through here
      // once — the reduce step has to catch it the same way it catches a
      // legacy doc.
      const city = 'Montréal';
      const province = 'QC';
      const postalCode = 'H2X 1Y4';
      const country = 'Canada';
      final once = AddressParser.composeFull(
        '4-1234 Rue Principale',
        city: city,
        province: province,
        postalCode: postalCode,
        country: country,
      );
      expect(
        AddressParser.composeFull(
          once,
          city: city,
          province: province,
          postalCode: postalCode,
          country: country,
        ),
        once,
      );
    });
  });
}
