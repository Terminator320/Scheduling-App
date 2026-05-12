import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/clients/domain/models/client_record.dart';
import 'package:scheduling/features/clients/domain/policies/client_form_validator.dart';
import 'package:scheduling/l10n/l10n.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  Map<String, String?> validate({
    String businessName = '',
    String name = '',
    String phone = '',
    String email = '',
    String address = '',
    List<ClientContact> additionalContacts = const [],
  }) {
    return ClientFormValidator.validate(
      l10n: l10n,
      businessName: businessName,
      name: name,
      phone: phone,
      email: email,
      address: address,
      additionalContacts: additionalContacts,
    );
  }

  group('ClientFormValidator', () {
    test('a name, phone, and address produce no errors', () {
      final errors = validate(
        name: 'Jane',
        phone: '555-1234',
        address: '1 Main St',
      );
      expect(errors.values.where((e) => e != null), isEmpty);
    });

    test('missing both business name and contact name flags both fields', () {
      final errors = validate(phone: '555-1234', address: '1 Main St');
      expect(errors['businessName'], isNotNull);
      expect(errors['name'], isNotNull);
    });

    test('missing both phone and email flags phone', () {
      final errors = validate(name: 'Jane', address: '1 Main St');
      expect(errors['phone'], isNotNull);
    });

    test('a malformed email is rejected', () {
      final errors = validate(
        name: 'Jane',
        phone: '555-1234',
        email: 'not-an-email',
        address: '1 Main St',
      );
      expect(errors['email'], isNotNull);
    });

    test('address is required only without a business name', () {
      expect(validate(name: 'Jane', phone: '555-1234')['address'], isNotNull);
      expect(
        validate(businessName: 'Acme', phone: '555-1234')['address'],
        isNull,
      );
    });

    test('additional contacts are ignored without a business name', () {
      final errors = validate(
        name: 'Jane',
        phone: '555-1234',
        address: '1 Main St',
        additionalContacts: const [ClientContact()],
      );
      expect(errors.keys.where((k) => k.startsWith('contact_')), isEmpty);
    });

    test('an all-empty contact card is skipped but keeps its index', () {
      final errors = validate(
        businessName: 'Acme',
        phone: '555-1234',
        additionalContacts: const [
          ClientContact(),
          ClientContact(phone: '555-9876'),
        ],
      );
      expect(errors.containsKey('contact_0_name'), isFalse);
      expect(errors['contact_1_name'], isNotNull);
    });

    test('a contact needs a phone or email', () {
      final errors = validate(
        businessName: 'Acme',
        phone: '555-1234',
        additionalContacts: const [ClientContact(name: 'Bob')],
      );
      expect(errors['contact_0_phone'], isNotNull);
    });
  });
}
