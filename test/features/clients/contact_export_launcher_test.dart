import 'package:flutter_test/flutter_test.dart';
import 'package:scheduling/features/clients/contact_export_launcher.dart';
import 'package:scheduling/features/clients/domain/models/client_record.dart';

void main() {
  group('clientToContact', () {
    test('maps a person client to name, phone, email and address', () {
      const client = ClientRecord(
        id: '1',
        name: 'Jane Doe',
        phone: '555-1234',
        email: 'jane@example.com',
        address: '123 Main St',
        city: 'Springfield',
        province: 'IL',
        postalCode: '62704',
        country: 'USA',
      );

      final contact = clientToContact(client);

      expect(contact.name?.first, 'Jane Doe');
      expect(contact.phones.single.number, '555-1234');
      expect(contact.emails.single.address, 'jane@example.com');
      expect(contact.organizations, isEmpty);

      final address = contact.addresses.single;
      expect(address.street, '123 Main St');
      expect(address.city, 'Springfield');
      expect(address.state, 'IL');
      expect(address.postalCode, '62704');
      expect(address.country, 'USA');
      expect(address.formatted, '123 Main St, Springfield, IL, 62704, USA');
    });

    test('business client lands on the organization, not the person name', () {
      const client = ClientRecord(
        id: '2',
        businessName: 'Acme Co',
        phone: '555-0000',
      );

      final contact = clientToContact(client);

      expect(contact.name, isNull);
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
      expect(contact.organizations, isEmpty);
    });
  });
}
