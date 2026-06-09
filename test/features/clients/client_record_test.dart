import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';

void main() {
  group('ClientRecord', () {
    test('value equality works (freezed)', () {
      const a = ClientRecord(
        id: 'c1',
        businessName: 'Acme',
        name: 'Jane',
        phone: '514-555-0101',
        email: 'jane@acme.com',
      );
      const b = ClientRecord(
        id: 'c1',
        businessName: 'Acme',
        name: 'Jane',
        phone: '514-555-0101',
        email: 'jane@acme.com',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith returns a new value with updated fields', () {
      const original = ClientRecord(id: 'c1', name: 'Jane');
      final updated = original.copyWith(name: 'Janet');

      expect(updated.id, 'c1');
      expect(updated.name, 'Janet');
      expect(original.name, 'Jane'); // immutable
    });

    test('displayName prefers businessName, falls back to name', () {
      expect(
        const ClientRecord(
          id: 'c1',
          businessName: 'Acme',
          name: 'Jane',
        ).displayName,
        'Acme',
      );
      expect(
        const ClientRecord(id: 'c1', name: 'Jane').displayName,
        'Jane',
      );
    });

    test('toMap → fromMap roundtrip preserves data', () {
      const original = ClientRecord(
        id: 'c1',
        businessName: 'Acme',
        name: 'Jane',
        address: '123 Main St',
        apt: '4B',
        city: 'Montreal',
        province: 'QC',
        country: 'Canada',
        postalCode: 'H3B 0A8',
        phone: '514-555-0101',
        email: 'jane@acme.com',
        contacts: [
          ClientContact(name: 'Bob', phone: '514-555-0102', email: 'b@a.com'),
        ],
      );

      final restored = ClientRecord.fromMap(original.id, original.toMap());

      expect(restored, equals(original));
    });

    test('fromMap defaults missing fields to empty', () {
      final r = ClientRecord.fromMap('c1', const {});
      expect(r.id, 'c1');
      expect(r.businessName, '');
      expect(r.name, '');
      expect(r.contacts, isEmpty);
    });

    test('toMap trims whitespace on all fields', () {
      const c = ClientRecord(
        id: 'c1',
        businessName: '  Acme  ',
        name: '  Jane  ',
        address: '  123 Main  ',
        phone: '  514  ',
        email: '  jane@acme.com  ',
      );
      final map = c.toMap();
      expect(map['businessName'], 'Acme');
      expect(map['name'], 'Jane');
      expect(map['address'], '123 Main');
      expect(map['phone'], '514');
      expect(map['email'], 'jane@acme.com');
    });

    test('noFixedAddress defaults to false and roundtrips through maps', () {
      final defaulted = ClientRecord.fromMap('c1', const {});
      expect(defaulted.noFixedAddress, isFalse);

      const original = ClientRecord(
        id: 'c1',
        name: 'City Hall',
        noFixedAddress: true,
      );
      final restored = ClientRecord.fromMap(original.id, original.toMap());
      expect(restored.noFixedAddress, isTrue);
      expect(restored, equals(original));
    });
  });

  group('ClientContact', () {
    test('value equality works', () {
      const a = ClientContact(name: 'Bob', phone: '1', email: 'b@a.com');
      const b = ClientContact(name: 'Bob', phone: '1', email: 'b@a.com');
      expect(a, equals(b));
    });

    test('toMap → fromMap roundtrip', () {
      const original = ClientContact(
        name: 'Bob',
        phone: '514-555-0102',
        email: 'b@a.com',
      );
      final restored = ClientContact.fromMap(original.toMap());
      expect(restored, equals(original));
    });
  });
}
