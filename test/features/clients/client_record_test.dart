import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/models/client_type.dart';

void main() {
  group('ClientRecord', () {
    test('value equality works (freezed)', () {
      const a = ClientRecord(
        id: 'c1',
        name: 'Acme',
        firstName: 'Jane',
        phone: '514-555-0101',
        email: 'jane@acme.com',
      );
      const b = ClientRecord(
        id: 'c1',
        name: 'Acme',
        firstName: 'Jane',
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

    test('displayName returns name', () {
      expect(
        const ClientRecord(id: 'c1', name: 'Acme Co').displayName,
        'Acme Co',
      );
      expect(const ClientRecord(id: 'c1', name: 'Jane').displayName, 'Jane');
    });

    test('toMap → fromMap roundtrip preserves user-owned data', () {
      const original = ClientRecord(
        id: 'c1',
        name: 'Acme',
        firstName: 'Jane',
        lastName: 'Doe',
        address: '123 Main St',
        apt: '4B',
        city: 'Montreal',
        province: 'QC',
        country: 'Canada',
        postalCode: 'H3B 0A8',
        phone: '514-555-0101',
        mobile: '514-555-0199',
        email: 'jane@acme.com',
        contacts: [
          ClientContact(name: 'Bob', phone: '514-555-0102', email: 'b@a.com'),
        ],
      );

      final restored = ClientRecord.fromMap(original.id, original.toMap());

      expect(restored, equals(original));
    });

    test('fromMap defaults missing fields to empty/null', () {
      final r = ClientRecord.fromMap('c1', const {});
      expect(r.id, 'c1');
      expect(r.name, '');
      expect(r.firstName, '');
      expect(r.lastName, '');
      expect(r.mobile, '');
      expect(r.contacts, isEmpty);
      expect(r.waveCustomerId, isNull);
      expect(r.waveSyncState, '');
      expect(r.waveSyncError, isNull);
    });

    test('fromMap reads the function-owned Wave projection fields', () {
      final r = ClientRecord.fromMap('c1', const {
        'name': 'Jane',
        'waveCustomerId': 'wave-123',
        'wave': {'syncState': 'synced', 'syncError': null},
      });
      expect(r.waveCustomerId, 'wave-123');
      expect(r.waveSyncState, 'synced');
      expect(r.waveSyncError, isNull);

      final errored = ClientRecord.fromMap('c2', const {
        'name': 'Bob',
        'wave': {'syncState': 'error', 'syncError': 'boom'},
      });
      expect(errored.waveSyncState, 'error');
      expect(errored.waveSyncError, 'boom');
    });

    test('fromMap falls back to legacy businessName when name is empty', () {
      // A pre-Wave-reshape business-only doc: businessName set, name empty.
      final r = ClientRecord.fromMap('c1', const {
        'name': '',
        'businessName': 'Acme Industries',
        'phone': '514-555-0101',
      });
      expect(r.name, 'Acme Industries');
      expect(r.displayName, 'Acme Industries');
    });

    test('fromMap prefers name over legacy businessName when both set', () {
      final r = ClientRecord.fromMap('c1', const {
        'name': 'Jane Doe',
        'businessName': 'Acme Industries',
      });
      expect(r.name, 'Jane Doe');
    });

    test('toMap never emits the function-owned Wave fields', () {
      const c = ClientRecord(
        id: 'c1',
        name: 'Jane',
        waveCustomerId: 'wave-123',
        waveSyncState: 'synced',
        waveSyncError: 'boom',
      );
      final map = c.toMap();
      expect(map.containsKey('waveCustomerId'), isFalse);
      expect(map.containsKey('wave'), isFalse);
      expect(map.containsKey('waveSyncState'), isFalse);
      expect(map.containsKey('waveSyncError'), isFalse);
    });

    test('toMap trims whitespace on all fields', () {
      const c = ClientRecord(
        id: 'c1',
        name: '  Acme  ',
        firstName: '  Jane  ',
        lastName: '  Doe  ',
        address: '  123 Main  ',
        phone: '  514  ',
        mobile: '  438  ',
        email: '  jane@acme.com  ',
      );
      final map = c.toMap();
      expect(map['name'], 'Acme');
      expect(map['firstName'], 'Jane');
      expect(map['lastName'], 'Doe');
      expect(map['address'], '123 Main');
      expect(map['phone'], '514');
      expect(map['mobile'], '438');
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

    group('createdAt', () {
      test('fromMap parses a DateTime createdAt', () {
        final record = ClientRecord.fromMap('c1', {
          'name': 'Alice',
          'createdAt': DateTime(2026, 7, 1, 10, 30),
        });
        expect(record.createdAt, DateTime(2026, 7, 1, 10, 30));
      });

      test('fromMap defaults createdAt to null when absent', () {
        expect(ClientRecord.fromMap('c2', {'name': 'Bob'}).createdAt, isNull);
      });

      test('toMap never emits createdAt (function-owned server timestamp)', () {
        final record = ClientRecord.fromMap('c3', {
          'name': 'Carol',
          'createdAt': DateTime(2026, 7),
        });
        expect(record.toMap().containsKey('createdAt'), isFalse);
      });
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

  group('ClientRecord P3 fields', () {
    test('fromMap reads every new field', () {
      final record = ClientRecord.fromMap('c1', {
        'name': 'Acme',
        'type': 'commercial',
        'tags': ['vip', 'net30'],
        'accessNotes': 'Gate code 1234',
        'onSiteManager': 'Dana',
        'billingTerms': 'Net 30',
        'autoInvoice': true,
        'archived': true,
        'jobCount': 7,
      });

      expect(record.type, ClientType.commercial);
      expect(record.tags, ['vip', 'net30']);
      expect(record.accessNotes, 'Gate code 1234');
      expect(record.onSiteManager, 'Dana');
      expect(record.billingTerms, 'Net 30');
      expect(record.autoInvoice, isTrue);
      expect(record.archived, isTrue);
      expect(record.jobCount, 7);
    });

    test('a legacy doc with none of the new fields defaults safely', () {
      final record = ClientRecord.fromMap('c2', {'name': 'Old'});

      expect(record.type, ClientType.unset);
      expect(record.tags, isEmpty);
      expect(record.accessNotes, '');
      expect(record.onSiteManager, '');
      expect(record.billingTerms, '');
      expect(record.autoInvoice, isFalse);
      // Absent means not archived — the Dart-side filter is `!(archived ?? false)`.
      expect(record.archived, isFalse);
      expect(record.jobCount, isNull);
    });

    test('tags drops non-string and blank entries', () {
      final record = ClientRecord.fromMap('c3', {
        'tags': ['vip', 42, '', '  ', 'net30'],
      });

      expect(record.tags, ['vip', 'net30']);
    });

    test('toMap emits the user-owned new fields', () {
      final map = const ClientRecord(
        id: 'c4',
        name: 'Acme',
        type: ClientType.propertyManagement,
        tags: ['vip'],
        accessNotes: 'Side door',
        onSiteManager: 'Dana',
        billingTerms: 'Net 15',
        autoInvoice: true,
        archived: true,
      ).toMap();

      expect(map['type'], 'property_mgmt');
      expect(map['tags'], ['vip']);
      expect(map['accessNotes'], 'Side door');
      expect(map['onSiteManager'], 'Dana');
      expect(map['billingTerms'], 'Net 15');
      expect(map['autoInvoice'], true);
      expect(map['archived'], true);
    });

    test('toMap never emits the function-owned fields', () {
      final map = const ClientRecord(
        id: 'c5',
        name: 'Acme',
        jobCount: 9,
        waveCustomerId: 'wave-1',
      ).toMap();

      expect(map.containsKey('jobCount'), isFalse);
      expect(map.containsKey('waveCustomerId'), isFalse);
      expect(map.containsKey('wave'), isFalse);
    });

    test('toMap self-heals archived on an older doc', () {
      final map = ClientRecord.fromMap('c6', {'name': 'Old'}).toMap();

      expect(map['archived'], false);
    });
  });
}
