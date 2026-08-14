import 'package:flutter_test/flutter_test.dart';

import 'package:scheduling/features/clients/domain/models/client_type.dart';
import 'package:scheduling/features/clients/domain/policies/client_name_policy.dart';

/// The worked examples here are DELIBERATELY shared with
/// `functions/__tests__/client_name_utils.test.js`, which hand-mirrors this
/// policy for `propagateClientEdits` and the backfill script. A divergence
/// between the two implementations has to fail a test rather than ship — the
/// same discipline `appointment_day_slice` / `day_slice_utils` already uses.
void main() {
  group('stripPhone', () {
    test('removes the number this app appended', () {
      expect(
        ClientNamePolicy.stripPhone(
          'Marc Tremblay (514) 555-1234',
          phone: '(514) 555-1234',
        ),
        'Marc Tremblay',
      );
    });

    test('removes a legacy number typed in another shape', () {
      // The doc's stored phone is the masked form; the name was typed years
      // earlier with dashes. An exact-suffix test alone misses this.
      expect(
        ClientNamePolicy.stripPhone(
          'Marc Tremblay 514-555-1234',
          phone: '(514) 555-1234',
        ),
        'Marc Tremblay',
      );
    });

    test('matches an 11-digit form against the stored 10-digit one', () {
      expect(
        ClientNamePolicy.stripPhone(
          'Marc Tremblay 1-514-555-1234',
          phone: '(514) 555-1234',
        ),
        'Marc Tremblay',
      );
    });

    test('falls back to mobile when phone is empty', () {
      expect(
        ClientNamePolicy.stripPhone(
          'Marc Tremblay (514) 555-1234',
          mobile: '(514) 555-1234',
        ),
        'Marc Tremblay',
      );
    });

    test('leaves a trailing number that is NOT this client’s', () {
      // The whole reason the digits are compared rather than the shape: a
      // business genuinely named with a number must survive.
      expect(
        ClientNamePolicy.stripPhone(
          'Depanneur 5148889999',
          phone: '(514) 555-1234',
        ),
        'Depanneur 5148889999',
      );
    });

    test('leaves the name alone when the doc has no number at all', () {
      expect(
        ClientNamePolicy.stripPhone('Marc Tremblay 514-555-1234'),
        'Marc Tremblay 514-555-1234',
      );
    });

    test('returns empty when the name is nothing but the number', () {
      // Load-bearing: this is what lets displayFor fall through to the halves
      // rather than rendering a phone number as somebody's name.
      expect(
        ClientNamePolicy.stripPhone(
          '(514) 555-1234',
          phone: '(514) 555-1234',
        ),
        '',
      );
    });

    test('is idempotent', () {
      const stored = 'Marc Tremblay (514) 555-1234';
      final once = ClientNamePolicy.stripPhone(stored, phone: '(514) 555-1234');
      expect(
        ClientNamePolicy.stripPhone(once, phone: '(514) 555-1234'),
        once,
      );
    });
  });

  group('composeStored', () {
    test('appends the phone for Wave', () {
      expect(
        ClientNamePolicy.composeStored(
          baseName: 'Marc Tremblay',
          phone: '(514) 555-1234',
        ),
        'Marc Tremblay (514) 555-1234',
      );
    });

    test('never appends twice', () {
      // Every ordinary save runs through this, so a second pass over an
      // already-composed name must be a no-op.
      expect(
        ClientNamePolicy.composeStored(
          baseName: 'Marc Tremblay (514) 555-1234',
          phone: '(514) 555-1234',
        ),
        'Marc Tremblay (514) 555-1234',
      );
    });

    test('replaces the old number when the phone was edited', () {
      expect(
        ClientNamePolicy.composeStored(
          baseName: 'Marc Tremblay 514-555-1234',
          phone: '(438) 222-3333',
        ),
        // The old number is not this client's any more, so it stays in the
        // name — the strip only removes the number the doc currently stores.
        'Marc Tremblay 514-555-1234 (438) 222-3333',
      );
    });

    test('leaves the name bare when there is no phone', () {
      expect(
        ClientNamePolicy.composeStored(baseName: 'Marc Tremblay', phone: ''),
        'Marc Tremblay',
      );
    });

    test('a nameless client is stored as its number, not as blank', () {
      // A blank name floats the doc to the top of the name-ordered client list
      // and leaves its avatar with no initial.
      expect(
        ClientNamePolicy.composeStored(
          baseName: '',
          phone: '(514) 555-1234',
        ),
        '(514) 555-1234',
      );
    });
  });

  group('displayFor — a PERSON shows their halves', () {
    test('prefers the first/last halves over the stored name', () {
      expect(
        ClientNamePolicy.displayFor(
          name: 'Marc Tremblay (514) 555-1234',
          phone: '(514) 555-1234',
          firstName: 'Marc',
          lastName: 'Tremblay',
          type: ClientType.residential,
        ),
        'Marc Tremblay',
      );
    });

    test('takes a single half on its own', () {
      expect(
        ClientNamePolicy.displayFor(
          name: 'Marc (514) 555-1234',
          phone: '(514) 555-1234',
          firstName: 'Marc',
        ),
        'Marc',
      );
    });

    test('falls back to the stored name with the number stripped', () {
      expect(
        ClientNamePolicy.displayFor(
          name: 'Marc Tremblay (514) 555-1234',
          phone: '(514) 555-1234',
        ),
        'Marc Tremblay',
      );
    });

    test('a bare number beats an empty display name', () {
      expect(
        ClientNamePolicy.displayFor(
          name: '(514) 555-1234',
          phone: '(514) 555-1234',
        ),
        '(514) 555-1234',
      );
    });
  });

  group('displayFor — a BUSINESS shows its business name', () {
    test('a commercial client keeps its business name', () {
      // The load-bearing case: first/last is the CONTACT PERSON here, not the
      // client, so preferring the halves would render the company as a person.
      expect(
        ClientNamePolicy.displayFor(
          name: 'Vogas Plumbing (514) 555-1234',
          phone: '(514) 555-1234',
          firstName: 'Marc',
          lastName: 'Tremblay',
          type: ClientType.commercial,
        ),
        'Vogas Plumbing',
      );
    });

    test('property management counts as a business', () {
      expect(
        ClientNamePolicy.displayFor(
          name: 'Gestion Immobiliere ABC',
          firstName: 'Marc',
          lastName: 'Tremblay',
          type: ClientType.propertyManagement,
        ),
        'Gestion Immobiliere ABC',
      );
    });

    test('a legacy businessName doc is a business even with no type', () {
      // Pre-Wave-reshape docs predate `type`, so they arrive `unset` and would
      // otherwise be read as people.
      expect(
        ClientNamePolicy.displayFor(
          name: 'Acme Industries',
          businessName: 'Acme Industries',
          firstName: 'Marc',
          lastName: 'Tremblay',
        ),
        'Acme Industries',
      );
    });

    test('falls back to the legacy businessName when name is blank', () {
      expect(
        ClientNamePolicy.displayFor(name: '', businessName: 'Acme Inc'),
        'Acme Inc',
      );
    });

    test('falls back to the contact person when no company name is on file', () {
      // Better than rendering the phone number as the client's name.
      expect(
        ClientNamePolicy.displayFor(
          name: '(514) 555-1234',
          phone: '(514) 555-1234',
          firstName: 'Marc',
          lastName: 'Tremblay',
          type: ClientType.commercial,
        ),
        'Marc Tremblay',
      );
    });
  });

  group('isBusiness', () {
    test('the two organization types', () {
      expect(ClientNamePolicy.isBusiness(type: ClientType.commercial), isTrue);
      expect(
        ClientNamePolicy.isBusiness(type: ClientType.propertyManagement),
        isTrue,
      );
    });

    test('a residential or untyped client is a person', () {
      expect(
        ClientNamePolicy.isBusiness(type: ClientType.residential),
        isFalse,
      );
      expect(ClientNamePolicy.isBusiness(), isFalse);
    });

    test('a legacy businessName makes it a business regardless of type', () {
      expect(ClientNamePolicy.isBusiness(businessName: 'Acme Inc'), isTrue);
    });
  });

  group('liftPhoneFromName', () {
    test('moves a pasted number into the phone field', () {
      final lifted = ClientNamePolicy.liftPhoneFromName(
        name: 'Marc Tremblay 514-555-1234',
        phone: '',
      );
      expect(lifted?.name, 'Marc Tremblay');
      expect(lifted?.phone, '(514) 555-1234');
    });

    test('handles a number at the front', () {
      final lifted = ClientNamePolicy.liftPhoneFromName(
        name: '514-555-1234 - Marc Tremblay',
        phone: '',
      );
      expect(lifted?.name, 'Marc Tremblay');
      expect(lifted?.phone, '(514) 555-1234');
    });

    test('a typed phone always wins', () {
      expect(
        ClientNamePolicy.liftPhoneFromName(
          name: 'Marc Tremblay 514-555-1234',
          phone: '(438) 222-3333',
        ),
        isNull,
      );
    });

    test('keeps the name when it is nothing but the number', () {
      // The name is a required field — emptying it would read as the paste
      // having vanished.
      final lifted = ClientNamePolicy.liftPhoneFromName(
        name: '5145551234',
        phone: '',
      );
      expect(lifted?.name, '5145551234');
      expect(lifted?.phone, '(514) 555-1234');
    });

    test('leaves an ambiguous number for a human', () {
      // Not a clean 10 digits, so a rewrite would be guessing.
      expect(
        ClientNamePolicy.liftPhoneFromName(name: 'Suite 12345', phone: ''),
        isNull,
      );
      expect(
        ClientNamePolicy.liftPhoneFromName(
          name: 'Marc +33 6 12 34 56 78',
          phone: '',
        ),
        isNull,
      );
    });

    test('does nothing to an ordinary name', () {
      expect(
        ClientNamePolicy.liftPhoneFromName(name: 'Marc Tremblay', phone: ''),
        isNull,
      );
    });
  });
}
