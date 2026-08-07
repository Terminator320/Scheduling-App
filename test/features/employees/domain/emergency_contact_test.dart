import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/employees/domain/models/emergency_contact.dart';

void main() {
  group('EmergencyContact', () {
    test('fromMap reads both fields', () {
      final contact = EmergencyContact.fromMap(const {
        'contact': 'Marie Roy',
        'phone': '(514) 555-0199',
      });

      expect(contact.contact, 'Marie Roy');
      expect(contact.phone, '(514) 555-0199');
    });

    test('a missing doc reads as empty rather than throwing', () {
      expect(EmergencyContact.fromMap(null), EmergencyContact.empty);
      expect(EmergencyContact.fromMap(null).isEmpty, isTrue);
    });

    test('absent keys default to empty strings', () {
      final contact = EmergencyContact.fromMap(const {});

      expect(contact.contact, '');
      expect(contact.phone, '');
      expect(contact.isEmpty, isTrue);
    });

    test('either field alone makes it non-empty', () {
      expect(const EmergencyContact(contact: 'Marie').isNotEmpty, isTrue);
      expect(const EmergencyContact(phone: '555-0199').isNotEmpty, isTrue);
    });

    test('whitespace-only values still count as empty', () {
      // Otherwise the detail view renders a blank row for a contact nobody
      // actually entered.
      expect(
        const EmergencyContact(contact: '   ', phone: '  ').isEmpty,
        isTrue,
      );
    });

    test('toMap trims, so a whitespace edit round-trips to empty', () {
      final map = const EmergencyContact(
        contact: '  Marie Roy  ',
        phone: '  555-0199 ',
      ).toMap();

      expect(map['contact'], 'Marie Roy');
      expect(map['phone'], '555-0199');
    });

    test('value equality holds', () {
      const a = EmergencyContact(contact: 'Marie', phone: '555');
      const b = EmergencyContact(contact: 'Marie', phone: '555');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
