import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/clients/contact_export_launcher.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';

void main() {
  group('clientToContact', () {
    test('maps first/last name, both phones, email and address', () {
      const client = ClientRecord(
        id: '1',
        name: 'Acme Co',
        firstName: 'Jane',
        lastName: 'Doe',
        phone: '555-1234',
        mobile: '555-9999',
        email: 'jane@example.com',
        address: '123 Main St',
        city: 'Springfield',
        province: 'IL',
        postalCode: '62704',
        country: 'USA',
      );

      final contact = clientToContact(client);

      // Structured person name from firstName/lastName.
      expect(contact.name?.first, 'Jane');
      expect(contact.name?.last, 'Doe');
      // The customer/display name lands on the organization.
      expect(contact.organizations.single.name, 'Acme Co');
      // Phone and mobile are two separate entries.
      expect(contact.phones.map((p) => p.number), ['555-1234', '555-9999']);
      expect(contact.emails.single.address, 'jane@example.com');

      final address = contact.addresses.single;
      expect(address.street, '123 Main St');
      expect(address.city, 'Springfield');
      expect(address.state, 'IL');
      expect(address.postalCode, '62704');
      expect(address.country, 'USA');
      expect(address.formatted, '123 Main St, Springfield, IL, 62704, USA');
    });

    test('falls back to the display name when there is no first/last name', () {
      const client = ClientRecord(id: '2', name: 'Acme Co', phone: '555-0000');

      final contact = clientToContact(client);

      // Name-only client: display name seeds the contact name AND the org.
      expect(contact.name?.first, 'Acme Co');
      expect(contact.organizations.single.name, 'Acme Co');
      expect(contact.phones.single.number, '555-0000');
    });

    test('noFixedAddress client omits the address entirely', () {
      const client = ClientRecord(
        id: '3',
        name: 'Bob',
        address: '123 Main St',
        city: 'Springfield',
        noFixedAddress: true,
      );

      final contact = clientToContact(client);

      expect(contact.addresses, isEmpty);
    });

    test('empty optional fields produce empty property lists', () {
      const client = ClientRecord(id: '4', name: 'Solo');

      final contact = clientToContact(client);

      expect(contact.name?.first, 'Solo');
      expect(contact.phones, isEmpty);
      expect(contact.emails, isEmpty);
      expect(contact.addresses, isEmpty);
      expect(contact.organizations.single.name, 'Solo');
    });
  });
}
